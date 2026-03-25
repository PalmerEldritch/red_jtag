# PC Application Planned Implementation

## Purpose

This document describes the planned PC-side application architecture for controlling the FPGA JTAG engine.

The PC application is intended to become the source of truth for:
- target-device knowledge
- JTAG chain composition
- boundary-scan metadata
- BSDL parsing
- higher-level operations such as pin manipulation and I2C-over-boundary-scan

## Core Principle

The PC application should be smart.

The FPGA should be generic.

That means:
- the PC should understand devices, instructions, pins, and chain order
- the FPGA should mainly execute host-provided scan requests

## Planned Responsibilities

### Device and chain knowledge

The PC application should:
- import BSDL files
- extract IR length per device
- extract supported instructions per device
- extract boundary-scan register length
- extract boundary cell names and bit indices
- allow the user to define chain order
- build a chain model covering all devices in the daisy chain

### Request composition

The PC application should:
- compose full-chain IR payloads
- compose full-chain DR payloads
- insert BYPASS or other padding data for non-target devices
- choose the correct instruction for each target operation
- translate logical operations into FPGA request frames

### User-facing workflows

The PC application should support:
- read IDCODE
- sample boundary register
- load boundary register
- set/read logical boundary pin
- future I2C-over-boundary-scan operations

## Intended User Workflow

1. Connect FPGA and target chain.
2. Load one or more BSDL files into the application.
3. Define or confirm chain order.
4. Select the active target device.
5. Let the application infer:
   - total chain IR length
   - expected DR lengths
   - instruction values
   - logical boundary pin map
6. Choose a user action such as:
   - read IDCODE
   - sample pins
   - drive a boundary pin
   - run a higher-level bus transaction
7. The application composes the exact raw FPGA command frames.
8. The FPGA executes them and returns raw data.
9. The application interprets the results back into device/pin-level meaning.

## Recommended Internal Software Architecture

### Layer 1: Transport

Responsibilities:
- open FTDI channel
- configure async 245 FIFO
- send request bytes
- receive reply bytes

Notes:
- this should be reusable and well-isolated
- it should not know target-specific JTAG details

### Layer 2: FPGA Protocol

Responsibilities:
- pack and unpack FPGA command frames
- support both:
  - stable generic protocol commands
  - any temporary compatibility commands if still needed

Examples:
- raw JTAG reset
- raw shift IR
- raw shift DR
- raw shift IR+DR
- generic boundary-scan helper requests

### Layer 3: Chain Model

Responsibilities:
- hold chain order
- hold per-device IR length
- hold instruction dictionary
- hold BSR length and boundary pin map

Suggested objects:
- `ChainDescription`
- `DeviceDescription`
- `InstructionDefinition`
- `BoundaryPinDefinition`

### Layer 4: Operation Builder

Responsibilities:
- convert a logical action into composed chain IR/DR payloads
- manage active target and BYPASS padding
- generate the FPGA requests needed for a user action

Examples:
- build IR payload for one target device while all others are in BYPASS
- build DR payload for reading one target IDCODE in a multi-device chain
- build EXTEST/SAMPLE operations for one target while others remain harmless

### Layer 5: High-Level Features

Responsibilities:
- user-facing operations
- target-level workflows
- future scripted bus protocols

Examples:
- `read_idcode(target)`
- `sample_bsr(target)`
- `set_boundary_pin(target, pin_name, value)`
- `i2c_write_via_boundary(target, sda_pin, scl_pin, ...)`

## BSDL Integration Plan

The application should parse BSDL and extract at minimum:
- entity name
- instruction length
- instruction opcodes
- boundary register length
- boundary register cell table
- pin names and cell mappings

The application should then allow the user to:
- resolve ambiguous pins
- label pins by logical function
- save a project profile for reuse

## Chain and Multi-Device Strategy

The PC application should explicitly support daisy chains.

This affects:
- IR composition
- DR composition
- IDCODE discovery
- boundary-scan operations

### Example

If only one device in a chain should execute `EXTEST`, the PC application must:
- place the target instruction in that device’s IR slot
- place `BYPASS` or another safe instruction in the other devices’ IR slots
- pad DR payloads to account for non-target devices

This should happen automatically in software.

## Minimal First Version

The first useful PC application does not need a full GUI.

A good staged plan is:

1. command-line utility for:
   - open FTDI
   - ping FPGA
   - reset JTAG
   - read IDCODE
   - raw IR/DR commands
2. add chain description from a config file
3. add BSDL import
4. add a small GUI for chain/device/pin actions

## GUI Direction

The eventual GUI should make the workflow mostly automatic.

Suggested UI capabilities:
- device discovery / FTDI selection
- chain configuration
- BSDL import
- target selection
- logical pin browsing
- raw JTAG expert view
- decoded result display

The GUI should also allow saving and loading project profiles containing:
- device set
- chain order
- chosen target
- pin aliases
- known-safe instruction selections

## Communication Contract With FPGA

Preferred long-term FPGA protocol characteristics:
- explicit lengths
- explicit payloads
- no hidden target assumptions
- stable binary framing
- deterministic reply formatting

The PC application should treat the FPGA as an execution backend, not as a source of target metadata.

## Current Status

At the time of writing:
- there is a working Python probe script for hardware validation
- the split FPGA design has been validated by reading ESP32 IDCODE
- the full planned PC application has not yet been implemented

Known-good validation example:
- `python esp32_idcode_probe.py --profile split --index 1`

with the operational note that the ESP32 had to be placed into manual boot/programming mode first using `BOOT + RST`.

## Recommended Next PC-Side Steps

1. Preserve the current probe script as a low-level validation tool.
2. Define a stable generic FPGA command framing document.
3. Build a reusable transport/protocol library around FTDI FIFO access.
4. Add a chain description model in software.
5. Add BSDL parsing and instruction/pin extraction.
6. Add higher-level operations only after the chain model is working.
