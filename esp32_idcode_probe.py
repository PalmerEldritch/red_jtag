#!/usr/bin/env python3
"""Minimal FTDI FIFO host tool for split-top and monolith bring-up.

Known-good ESP32 IDCODE test:
    1. Put the ESP32 into manual boot/programming mode by holding BOOT and pressing RST.
    2. Run:
           python esp32_idcode_probe.py --profile split --index 1

Expected result:
    Raw IDCODE bytes: e5340012
    IDCODE candidate: 0x120034E5
"""

from __future__ import annotations

import argparse
import sys
import time
from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class ProtocolProfile:
    name: str
    has_ping: bool
    cmd_ping: int
    ping_reply: bytes
    cmd_reset: int
    reset_reply: bytes
    cmd_load_ir: Optional[int]
    cmd_read_idcode: Optional[int]
    idcode_prefix: bytes
    cmd_shift_dr: Optional[int]


PROFILE_SPLIT = ProtocolProfile(
    name="split",
    has_ping=True,
    cmd_ping=0xFF,
    ping_reply=b"\x55",
    cmd_reset=0x10,
    reset_reply=b"\x00",
    cmd_load_ir=0x12,
    cmd_read_idcode=None,
    idcode_prefix=b"",
    cmd_shift_dr=0x13,
)

PROFILE_MONOLITH = ProtocolProfile(
    name="monolith",
    has_ping=False,
    cmd_ping=0x00,
    ping_reply=b"",
    cmd_reset=0x01,
    reset_reply=b"\x81",
    cmd_load_ir=None,
    cmd_read_idcode=0x02,
    idcode_prefix=b"\x82",
    cmd_shift_dr=None,
)


class FtdiAsyncFifo:
    @staticmethod
    def _import_ftd2xx():
        try:
            import ftd2xx  # type: ignore
        except ImportError as exc:  # pragma: no cover
            raise SystemExit(
                "Missing Python package 'ftd2xx'. Install it first, for example: pip install ftd2xx"
            ) from exc
        except OSError as exc:  # pragma: no cover
            raise SystemExit(
                "Failed to load FTDI D2XX runtime library 'libftd2xx.so'. "
                "Install the system D2XX library for your distro and ensure the dynamic loader can find it."
            ) from exc
        return ftd2xx

    def __init__(self, index: int, timeout_ms: int, settle_ms: int) -> None:
        ftd2xx = self._import_ftd2xx()

        self.dev = ftd2xx.open(index)
        self.dev.resetDevice()
        self.dev.setLatencyTimer(2)
        self.dev.setUSBParameters(65536, 65536)
        self.dev.setTimeouts(timeout_ms, timeout_ms)
        self.dev.purge()

        # Match the known-working C# application: async bitbang pulse, then reset to async 245 FIFO.
        self.dev.setBitMode(0xFF, 0x01)
        time.sleep(0.01)
        self.dev.setBitMode(0x00, 0x00)
        time.sleep(max(settle_ms, 0) / 1000.0)
        self.dev.purge()

    @staticmethod
    def list_devices() -> None:
        ftd2xx = FtdiAsyncFifo._import_ftd2xx()

        devices = ftd2xx.listDevices()
        if not devices:
            print("No FTDI devices found.")
            return

        for idx, dev in enumerate(devices):
            text = dev.decode(errors="replace") if isinstance(dev, bytes) else str(dev)
            print(f"[{idx}] {text}")

    def close(self) -> None:
        self.dev.close()

    def write(self, payload: bytes) -> None:
        written = self.dev.write(payload)
        if written != len(payload):
            raise RuntimeError(f"Short write: wrote {written} of {len(payload)} bytes")

    def read_exact(self, size: int, timeout_s: float) -> bytes:
        deadline = time.monotonic() + timeout_s
        chunks = bytearray()
        while len(chunks) < size:
            remaining = size - len(chunks)
            queued = self.dev.getQueueStatus()
            if queued:
                chunks.extend(self.dev.read(min(queued, remaining)))
                continue
            if time.monotonic() >= deadline:
                raise TimeoutError(f"Timed out waiting for {size} response bytes, got {len(chunks)}")
            time.sleep(0.005)
        return bytes(chunks)

    def read_available(self) -> bytes:
        queued = self.dev.getQueueStatus()
        if queued <= 0:
            return b""
        return self.dev.read(queued)

    def drain_input(self, quiet_ms: int) -> bytes:
        drained = bytearray()
        deadline = time.monotonic() + max(quiet_ms, 0) / 1000.0
        while True:
            chunk = self.read_available()
            if chunk:
                drained.extend(chunk)
                deadline = time.monotonic() + max(quiet_ms, 0) / 1000.0
            if time.monotonic() >= deadline:
                break
            time.sleep(0.001)
        return bytes(drained)


def ping(link: FtdiAsyncFifo, profile: ProtocolProfile, timeout_s: float) -> None:
    if not profile.has_ping:
        return
    link.write(bytes([profile.cmd_ping]))
    rsp = link.read_exact(len(profile.ping_reply), timeout_s)
    if rsp != profile.ping_reply:
        raise RuntimeError(f"PING failed, expected {profile.ping_reply.hex()} and got {rsp.hex()}")


def jtag_reset(link: FtdiAsyncFifo, profile: ProtocolProfile, timeout_s: float) -> None:
    link.write(bytes([profile.cmd_reset]))
    rsp = link.read_exact(len(profile.reset_reply), timeout_s)
    if rsp != profile.reset_reply:
        raise RuntimeError(
            f"JTAG reset failed, expected {profile.reset_reply.hex()} and got {rsp.hex()}"
        )


def jtag_reset_with_resync(
    link: FtdiAsyncFifo,
    profile: ProtocolProfile,
    timeout_s: float,
    quiet_ms: int,
    verbose: bool,
) -> None:
    try:
        jtag_reset(link, profile, timeout_s)
        return
    except RuntimeError as exc:
        msg = str(exc)
        if profile.ping_reply and f"got {profile.ping_reply.hex()}" in msg:
            drained = link.drain_input(quiet_ms)
            if verbose:
                extra = drained.hex() if drained else "<none>"
                print(f"Reset saw stale ping reply; drained: {extra}; retrying once")
            jtag_reset(link, profile, timeout_s)
            return
        raise


def read_idcode(
    link: FtdiAsyncFifo,
    profile: ProtocolProfile,
    timeout_s: float,
    nbits: int,
) -> bytes:
    if profile.cmd_read_idcode is not None:
        if nbits != 32:
            raise RuntimeError("This profile only supports 32-bit IDCODE reads")
        link.write(bytes([profile.cmd_read_idcode]))
        rsp = link.read_exact(len(profile.idcode_prefix) + 4, timeout_s)
        if profile.idcode_prefix and rsp[: len(profile.idcode_prefix)] != profile.idcode_prefix:
            raise RuntimeError(
                f"IDCODE read failed, expected prefix {profile.idcode_prefix.hex()} and got {rsp.hex()}"
            )
        return rsp[len(profile.idcode_prefix) :]

    if profile.cmd_shift_dr is None:
        raise RuntimeError("Profile does not support an IDCODE read method")

    if nbits <= 0:
        raise RuntimeError("IDCODE bit count must be positive")
    if nbits % 8 != 0:
        raise RuntimeError("IDCODE bit count must be a multiple of 8")

    nbytes = nbits // 8
    return shift_dr(link, profile, b"\x00" * nbytes, nbits, timeout_s)


def format_idcode(raw: bytes) -> str:
    value = int.from_bytes(raw, byteorder="little", signed=False)
    return f"0x{value:08X}"


def format_words(raw: bytes) -> list[str]:
    if len(raw) % 4 != 0:
        return [raw.hex()]
    return [f"0x{int.from_bytes(raw[i:i + 4], byteorder='little', signed=False):08X}" for i in range(0, len(raw), 4)]


def parse_hex_bytes(text: str) -> bytes:
    normalized = text.strip().lower().replace("_", "").replace(" ", "")
    if normalized.startswith("0x"):
        normalized = normalized[2:]
    if not normalized:
        return b""
    if len(normalized) % 2 != 0:
        normalized = "0" + normalized
    return bytes.fromhex(normalized)


def load_ir(link: FtdiAsyncFifo, profile: ProtocolProfile, ir_value: bytes) -> None:
    if profile.cmd_load_ir is None:
        raise RuntimeError("Profile does not support raw IR loads")
    if len(ir_value) != 1:
        raise RuntimeError("Current raw IR helper expects exactly one IR payload byte")
    link.write(bytes([profile.cmd_load_ir]) + ir_value)


def shift_dr(link: FtdiAsyncFifo, profile: ProtocolProfile, payload: bytes, nbits: int, timeout_s: float) -> bytes:
    if profile.cmd_shift_dr is None:
        raise RuntimeError("Profile does not support raw DR shifts")
    if nbits <= 0:
        raise RuntimeError("DR bit count must be positive")
    if nbits % 8 != 0:
        raise RuntimeError("DR bit count must be a multiple of 8")
    if len(payload) != nbits // 8:
        raise RuntimeError("DR payload length does not match requested bit count")
    frame = bytes([profile.cmd_shift_dr, nbits & 0xFF, (nbits >> 8) & 0xFF]) + payload
    link.write(frame)
    return link.read_exact(len(payload), timeout_s)


def get_profile(name: str) -> ProtocolProfile:
    if name == "split":
        return PROFILE_SPLIT
    if name == "monolith":
        return PROFILE_MONOLITH
    raise ValueError(f"Unknown profile: {name}")


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Probe the FPGA FTDI FIFO path and attempt an IDCODE read using either the split design "
            "protocol or the known monolith protocol."
        )
    )
    parser.add_argument("--list", action="store_true", help="List FTDI devices and exit")
    parser.add_argument("--index", type=int, default=1, help="FTDI device index to open")
    parser.add_argument("--timeout-ms", type=int, default=1000, help="FTDI read/write timeout")
    parser.add_argument("--settle-ms", type=int, default=50, help="Delay after FIFO reconfiguration")
    parser.add_argument(
        "--command-gap-ms",
        type=int,
        default=20,
        help="Quiet time between commands; drains any late/stale response bytes",
    )
    parser.add_argument("--retries", type=int, default=3, help="Retry count for the initial command")
    parser.add_argument(
        "--idcode-bits",
        type=int,
        default=32,
        help="Number of DR bits to shift when reading IDCODE via the split profile",
    )
    parser.add_argument(
        "--load-ir-hex",
        help="Load a raw IR value before an optional raw DR shift, for example 05",
    )
    parser.add_argument(
        "--shift-dr-hex",
        help="Shift a raw DR payload given as hex bytes, for example deadbeef",
    )
    parser.add_argument(
        "--shift-dr-bits",
        type=int,
        help="Bit count for --shift-dr-hex; defaults to payload length * 8",
    )
    parser.add_argument(
        "--profile",
        choices=["split", "monolith"],
        default="split",
        help="Protocol profile to use",
    )
    parser.add_argument(
        "--skip-ping",
        action="store_true",
        help="Skip PING even if the selected profile supports it",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print drained bytes and extra host-side diagnostics",
    )
    args = parser.parse_args(argv)

    if args.list:
        FtdiAsyncFifo.list_devices()
        return 0

    profile = get_profile(args.profile)
    link = FtdiAsyncFifo(index=args.index, timeout_ms=args.timeout_ms, settle_ms=args.settle_ms)
    timeout_s = max(args.timeout_ms / 1000.0, 0.1)

    try:
        if profile.has_ping and not args.skip_ping:
            last_exc: Optional[Exception] = None
            for _ in range(max(args.retries, 1)):
                try:
                    ping(link, profile, timeout_s)
                    last_exc = None
                    break
                except Exception as exc:
                    last_exc = exc
                    link.dev.purge()
                    time.sleep(0.01)
            if last_exc is not None:
                raise last_exc
            print("PING ok")
            drained = link.drain_input(args.command_gap_ms)
            if drained and args.verbose:
                print(f"Drained trailing bytes after PING: {drained.hex()}")

        if args.load_ir_hex is not None:
            ir_value = parse_hex_bytes(args.load_ir_hex)
            load_ir(link, profile, ir_value)
            drained = link.drain_input(args.command_gap_ms)
            if drained and args.verbose:
                print(f"Drained trailing bytes after IR load: {drained.hex()}")
            print(f"Loaded IR: {ir_value.hex()}")

        if args.shift_dr_hex is not None:
            dr_payload = parse_hex_bytes(args.shift_dr_hex)
            dr_bits = args.shift_dr_bits if args.shift_dr_bits is not None else len(dr_payload) * 8
            raw = shift_dr(link, profile, dr_payload, dr_bits, timeout_s)
            print(f"Raw DR response bytes: {raw.hex()}")
            if len(raw) == 4:
                print(f"DR response word: {format_idcode(raw)}")
            else:
                print("DR response words: " + ", ".join(format_words(raw)))
            return 0

        jtag_reset_with_resync(
            link,
            profile,
            timeout_s,
            quiet_ms=args.command_gap_ms,
            verbose=args.verbose,
        )
        print("JTAG reset ok")
        drained = link.drain_input(args.command_gap_ms)
        if drained and args.verbose:
            print(f"Drained trailing bytes after reset: {drained.hex()}")

        raw = read_idcode(link, profile, timeout_s, args.idcode_bits)
        print(f"Raw IDCODE bytes: {raw.hex()}")
        if len(raw) == 4:
            print(f"IDCODE candidate: {format_idcode(raw)}")
        else:
            print("IDCODE words: " + ", ".join(format_words(raw)))
        return 0
    finally:
        link.close()


if __name__ == "__main__":
    sys.exit(main())
