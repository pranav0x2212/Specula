# Specula

Specula is an experimental 1-wide out-of-order RV32 RISC-V processor core
written in Bluespec SystemVerilog. It renames registers, issues instructions
out of order through a reservation station, executes speculatively with branch
prediction and recovery, and commits in program order using a reorder buffer.
It runs in the Bluespec simulator (Bluesim) and can now boot xv6-rv32 to an
interactive shell. It has not been synthesized or run on an FPGA.

## Status

- Out-of-order core: register renaming, free list, reservation station, ROB,
  speculative execution with misprediction recovery, gshare + BTB prediction.
- ISA: RV32I, the M subset used by xv6 (MUL, DIVU, REMU), AMOSWAP.W from A,
  the C compressed extension, and Zicsr.
- Machine and supervisor privilege: CSRs, ECALL, MRET, SRET, trap delivery.
- Sv32 virtual memory (two-level page-table walk).
- Memory-mapped devices: 16550-style UART, PLIC, and a VirtIO block device.
- Boots xv6-rv32 to an interactive `$` shell: host keystrokes reach the kernel
  through the modeled UART, and filesystem commands run against the
  VirtIO-backed xv6 filesystem image.

## How to run

```sh
git clone https://github.com/pranav0x2212/Specula.git
cd Specula
make clean
make
./build/sim
```

`make` builds the simulator at `build/sim`. `./build/sim` runs a small RV32
program from `sw/` and reports a `tohost` pass/fail result. Directed tests for
individual features live in `sw/tests/` and in the `*test` Makefile targets.

Younger independent instructions execute ahead of an older dependency chain,
while the reorder buffer still commits every instruction in program order.

## Repository layout

```
Makefile                        build rules
sw/                             RV32 test programs and directed tests
src/
  SpeculaCore.bsv               top-level core, wires the pipeline together
  common/Common.bsv             shared types and instruction decode
  frontend/
    FetchUnit.bsv               instruction fetch (Sv32-translated)
    DecodeUnit.bsv              instruction decode
    BranchPredictor.bsv         gshare + BTB predictor
    RVCExpand.bsv               compressed-instruction expander
    InOrderCore.bsv             older standalone in-order core
  backend/
    RenameStage.bsv             register renaming and architectural map
    RAT.bsv                     register-alias table module
    FreeList.bsv                physical-register free list
    PRF.bsv                     physical register file
    ReservationStation.bsv      out-of-order issue queue
    ROB.bsv                     reorder buffer (in-order commit)
    ALU.bsv                     integer ALU
    LSU.bsv                     load/store unit
    CSRFile.bsv                 machine/supervisor CSRs and traps
    MMU.bsv                     Sv32 address translation
    SystemBus.bsv               MMIO decode (RAM, UART, PLIC, VirtIO)
    Uart.bsv                    16550-style UART model
    Plic.bsv                    platform interrupt controller
    VirtioStub.bsv              VirtIO block device model
docs/                           design notes and the pipeline diagram
```
