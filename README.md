# Specula

Specula is an experimental 1-wide out-of-order RISC-V processor core written in
Bluespec SystemVerilog. It fetches a small program, renames registers, issues
instructions out of order through a reservation station, and commits them in
program order using a reorder buffer. It runs in the Bluespec simulator.

## How to run

```sh
git clone https://github.com/pranav0x2212/Specula.git
cd Specula
make clean
make
./build/sim
```

`make` builds the simulator at `build/sim`. `./build/sim` runs it and prints a
cycle-by-cycle trace, ending with:

```
[Specula] Simulation complete - all instructions retired
```

### The example program

The simulation runs a fixed, hard-coded RISC-V instruction sequence defined in
`src/common/Common.bsv`. It does not load an external program or binary.

```asm
addi x1,  x0, 1      # x1 = 1
add  x2,  x1, x1     # needs x1
add  x3,  x2, x2     # needs x2
add  x4,  x3, x3     # needs x3
addi x10, x0, 10     # independent
addi x11, x0, 11     # independent
addi x12, x0, 12     # independent
addi x13, x0, 13     # independent
```

The first four instructions form a dependency chain, so each instruction
depends on the result of the previous one. The last four instructions are
independent and can execute as soon as they are ready. Specula lets these
younger independent instructions execute before the older dependency chain
finishes, while the reorder buffer still commits all instructions in program
order.

## Repository layout

```
Makefile                        build rules
src/
  SpeculaCore.bsv               top-level core, wires the pipeline together
  common/Common.bsv             shared types, instruction decode, and the test program
  frontend/
    FetchUnit.bsv               instruction fetch
    DecodeUnit.bsv              instruction decode
    BranchPredictor.bsv         branch predictor module
    InOrderCore.bsv             older standalone in-order core
  backend/
    RenameStage.bsv             register renaming and architectural map
    FreeList.bsv                physical-register free list
    PRF.bsv                     physical register file
    ReservationStation.bsv      out-of-order issue queue
    ROB.bsv                     reorder buffer (in-order commit)
    ALU.bsv                     integer ALU
    LSU.bsv                     load/store unit and data memory
    RAT.bsv                     register-alias table module
docs/                           design notes and the pipeline diagram
```
