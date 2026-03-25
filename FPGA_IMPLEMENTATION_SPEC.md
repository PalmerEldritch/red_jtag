# FPGA Implementation Specification

## Purpose

This document describes the current FPGA-side implementation in this repository, the architectural intent behind it, and the planned direction toward a generic multi-device JTAG and boundary-scan engine.

The FPGA target is a Lattice Certus-NX design that interfaces to a host PC over an FT245-style async FIFO channel and drives an external JTAG chain.

## Design Goals

### Current goals

- Replace the original monolithic VHDL design with a structured implementation.
- Preserve a working raw JTAG path over FT245.
- Support initial target validation by reading JTAG IDCODE from an attached device.
- Isolate transport, parsing, execution, and boundary-scan concerns into separate modules.

### End goals

- Make the FPGA design target-agnostic.
- Support arbitrary daisy-chained JTAG devices.
- Accept host-supplied chain-composed IR and DR payloads at runtime.
- Support generic boundary-scan operations without hardcoded target knowledge in FPGA logic.
- Serve as a stable execution engine underneath a smarter PC application that parses BSDL files and composes chain data.

## Current Top-Level Modules

### `ft245_sync_if.vhd`

Purpose:
- Owns the FT245-style async FIFO timing and byte transport.

Current implementation:
- Handles one byte at a time.
- Synchronizes `ft_rxf_n` and `ft_txe_n`.
- Generates `rx_valid` and `tx_ready`.
- Drives `ft_rd_n`, `ft_wr_n`, and the bidirectional data bus.

Notes:
- This is the host transport layer only.
- No command semantics belong here.

### `host_cmd_parser.vhd`

Purpose:
- Converts host byte streams into normalized internal requests.

Current implementation:
- Supports both:
  - legacy-compatible commands
  - newer generic/raw commands for explicit IR/DR control
- Outputs decoded fields such as:
  - request kind
  - IR length
  - IR payload
  - DR length
  - DR payload
  - pin number and pin value for boundary-scan helpers

Current generic command support:
- raw IR shift
- raw DR shift
- raw IR+DR shift
- generic boundary-scan sample/load/set-pin/read-pin requests

Notes:
- This is now the beginning of the target-agnostic host protocol layer.
- Some legacy commands remain as compatibility shims.

### `jtag_master.vhd`

Purpose:
- Execute raw JTAG requests.

Responsibilities:
- TAP state navigation
- TCK, TMS, and TDI driving
- TDO sampling
- IR and DR shift sequencing
- `busy` / `done` handshake

Current implementation:
- Supports:
  - reset
  - set TMS
  - toggle TCK
  - shift IR
  - shift DR
  - combined shift IR + shift DR
- Accepts:
  - explicit IR bit length
  - explicit IR payload
  - explicit DR bit length
  - explicit DR payload

Behavior status:
- Updated to move closer to the proven `i2c_jtag_full_v4_slow.vhd` semantics.
- IR handling supports widths greater than 8 bits.
- DR capture behavior has been updated away from the old left-shift-only model.

Open items:
- Final hardware-level equivalence to the monolith is not yet formally proven for all commands and corner cases.
- The implementation should eventually support per-request timing control if needed.

### `bscan_controller.vhd`

Purpose:
- Provide boundary-scan helper operations on top of `jtag_master`.

Current implementation:
- Supports generic operations:
  - sample
  - load
  - set pin
  - read pin
- No longer owns fixed target opcode meanings internally.
- Accepts host-supplied instruction payloads and DR lengths.
- Maintains a local DR shadow for set/load style operations.

Notes:
- This is a helper layer, not the long-term source of target truth.
- The PC application is expected to provide the device-specific instruction values and pin indices.

### `jtag_boundary_scan_top.vhd`

Purpose:
- Integrate all FPGA-side modules.

Responsibilities:
- instantiate clock source
- generate reset
- instantiate FT245 interface
- instantiate parser
- instantiate raw JTAG engine
- instantiate boundary-scan helper
- dispatch parsed commands
- serialize responses back to the PC
- expose simple LED/debug behavior

Current implementation:
- Supports:
  - FT245 host link
  - raw JTAG reset / IR / DR / IR+DR requests
  - boundary-scan helper requests
  - debug commands
  - limited legacy compatibility
- I2C-over-boundary-scan is not yet implemented in the structured design.

## Current Hardware Validation Status

The split design has passed:
- compile checks
- module-level simulations
- top-level smoke simulation
- real hardware IDCODE read from an ESP32 target over the full chain:
  - PC script
  - FT245 FIFO
  - FPGA split design
  - JTAG connection
  - ESP32 target

Known-good hardware result:
- ESP32 IDCODE read returned `0x120034E5`

Operational note:
- In the validated setup, the ESP32 had to be placed into manual boot/programming mode using `BOOT + RST` before the IDCODE read.

## Current Host Protocol Status

### Implemented style

The protocol is byte-oriented over FT245 and currently mixes:
- legacy monolith-compatible commands
- newer generic/raw commands

### Direction

The long-term protocol should favor explicit payloads over symbolic target-specific commands.

Preferred host request style:
- raw chain reset
- raw IR shift with explicit length and payload
- raw DR shift with explicit length and payload
- raw IR+DR shift with explicit lengths and payloads
- generic boundary-scan helper requests using host-supplied instruction values and pin indices

## Planned Architecture Direction

### Guiding principle

Target and chain knowledge should live on the PC side, not in the FPGA bitstream.

### FPGA-side target state

The FPGA should eventually be:
- a transport engine
- a request parser
- a raw JTAG executor
- an optional generic boundary-scan helper

The FPGA should not be responsible for:
- parsing BSDL
- knowing device-specific opcodes by default
- owning a fixed chain topology
- owning target-specific pin maps

### Daisy-chain support

The FPGA implementation should support:
- single-device chains
- multi-device daisy chains
- mixed IR lengths
- host-composed full-chain IR values
- host-composed full-chain DR values

The PC application should decide:
- chain order
- which TAP is being targeted
- which devices are in BYPASS
- what padding must be added around the active device

## Not Yet Implemented

- Full BSDL-driven workflow
- Real I2C-over-boundary-scan engine in the structured implementation
- Fully generic downloaded chain metadata cache in FPGA
- Final polished host protocol specification
- Exhaustive hardware validation across multiple target devices

## Recommended Next FPGA Steps

1. Add more real-hardware tests beyond IDCODE.
2. Expand top-level smoke coverage for the newer generic commands.
3. Tighten the raw JTAG semantics against the proven monolith where needed.
4. Decide whether chain metadata should remain purely per-request or whether a downloaded chain context should be supported.
5. Implement the future I2C-over-boundary-scan layer only after the generic raw and boundary-scan layers are stable.
