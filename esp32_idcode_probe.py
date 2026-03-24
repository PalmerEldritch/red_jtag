#!/usr/bin/env python3
"""Minimal FTDI FIFO host tool for split-top and monolith bring-up."""

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
    cmd_read_idcode=0x02,
    idcode_prefix=b"\x82",
    cmd_shift_dr=None,
)


class FtdiAsyncFifo:
    def __init__(self, index: int, timeout_ms: int, settle_ms: int) -> None:
        try:
            import ftd2xx  # type: ignore
        except ImportError as exc:  # pragma: no cover
            raise SystemExit(
                "Missing Python package 'ftd2xx'. Install it first, for example: pip install ftd2xx"
            ) from exc

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
        try:
            import ftd2xx  # type: ignore
        except ImportError as exc:  # pragma: no cover
            raise SystemExit(
                "Missing Python package 'ftd2xx'. Install it first, for example: pip install ftd2xx"
            ) from exc

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


def read_idcode(link: FtdiAsyncFifo, profile: ProtocolProfile, timeout_s: float) -> bytes:
    if profile.cmd_read_idcode is not None:
        link.write(bytes([profile.cmd_read_idcode]))
        rsp = link.read_exact(len(profile.idcode_prefix) + 4, timeout_s)
        if profile.idcode_prefix and rsp[: len(profile.idcode_prefix)] != profile.idcode_prefix:
            raise RuntimeError(
                f"IDCODE read failed, expected prefix {profile.idcode_prefix.hex()} and got {rsp.hex()}"
            )
        return rsp[len(profile.idcode_prefix) :]

    if profile.cmd_shift_dr is None:
        raise RuntimeError("Profile does not support an IDCODE read method")

    payload = bytes([profile.cmd_shift_dr, 32, 0, 0, 0, 0, 0])
    link.write(payload)
    return link.read_exact(4, timeout_s)


def format_idcode(raw: bytes) -> str:
    value = int.from_bytes(raw, byteorder="little", signed=False)
    return f"0x{value:08X}"


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
    parser.add_argument("--retries", type=int, default=3, help="Retry count for the initial command")
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

        jtag_reset(link, profile, timeout_s)
        print("JTAG reset ok")

        raw = read_idcode(link, profile, timeout_s)
        print(f"Raw IDCODE bytes: {raw.hex()}")
        print(f"IDCODE candidate: {format_idcode(raw)}")
        return 0
    finally:
        link.close()


if __name__ == "__main__":
    sys.exit(main())
