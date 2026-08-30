# command to view the simulation output is make clean && make run

# ---------- CONFIG -----------

TOP      ?= mkSpeculaCore
SRC_DIR  ?= src
OUT_DIR  ?= build
EXE      ?= sim

BSC      := bsc
BSC_PATH := +:src:src/common:src/frontend:src/backend:sw
BSC_FLAGS := +RTS -K512M -RTS -sim -p $(BSC_PATH) -bdir $(OUT_DIR) -info-dir $(OUT_DIR)

# ---------- TEST PROGRAM / INSTRUCTION IMAGE (M1/M2/M3) -----------
#
# sw/start.S + sw/test.c  --(gcc, sw/link.ld)-->  build/test.elf
#   --(objcopy)--> build/test.bin
#   --(od/awk)---> program.hex           one 32-bit word per line, program order,
#                                        NOP-padded to IMEM_WORDS entries
#   --(printf)---> sw/ProgramImage.bsv   progWords / imemWords for the core
#
# program.hex is read at run time by mkRegFileLoad, relative to the directory
# the simulator is launched from (the repo root), so it lives there.
#
# M2: the program terminates by storing to the tohost MMIO address; the NOP
#     padding is only a safety runway so fetch never reads past the image.
# M3: sw/start.S sets sp then `jal main`; sw/link.ld puts _start at 0x0.

IMEM_WORDS ?= 256
NOP        := 00000013

RV_PREFIX  ?= riscv32-unknown-elf-
RV_CC      := $(RV_PREFIX)gcc
RV_OBJCOPY := $(RV_PREFIX)objcopy
RV_OBJDUMP := $(RV_PREFIX)objdump

RV_CFLAGS  := -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -ffreestanding -O1
RV_LDFLAGS := -Wl,-T,sw/link.ld

SW_SRCS  := sw/start.S sw/test.c
SW_LD    := sw/link.ld
ELF      := $(OUT_DIR)/test.elf
BIN      := $(OUT_DIR)/test.bin
HEX      := program.hex
IMG_BSV  := sw/ProgramImage.bsv

# ---------- TARGETS -----------

.PHONY: all run image disasm clean

all: $(OUT_DIR)/$(EXE)

image: $(HEX) $(IMG_BSV)

$(ELF): $(SW_SRCS) $(SW_LD) | $(OUT_DIR)
	@echo "[img] compiling $(SW_SRCS)"
	$(RV_CC) $(RV_CFLAGS) $(RV_LDFLAGS) -o $@ $(SW_SRCS)

$(BIN): $(ELF)
	$(RV_OBJCOPY) -O binary $< $@

$(HEX): $(BIN)
	@echo "[img] $@ <- $< (NOP-padded to $(IMEM_WORDS) words)"
	@od -An -v -tx4 -w4 $< | awk '{print $$1}' > $@
	@real=$$(wc -l < $@); \
	if [ $$real -gt $(IMEM_WORDS) ]; then \
	  echo "ERROR: program is $$real words, exceeds IMEM_WORDS=$(IMEM_WORDS)"; exit 1; fi; \
	for i in $$(seq $$real $$(( $(IMEM_WORDS) - 1 ))); do echo $(NOP) >> $@; done

$(IMG_BSV): $(BIN)
	@bytes=$$(wc -c < $<); words=$$(( bytes / 4 )); \
	printf '// GENERATED from %s by the Makefile. Do not edit; not tracked.\npackage ProgramImage;\n  Integer progWords = %s;  // real compiled instructions\n  Integer imemWords = %s;  // program.hex size incl. NOP padding\nendpackage\n' "$(SW_SRCS)" "$$words" "$(IMEM_WORDS)" > $@; \
	echo "[img] $@ : progWords=$$words imemWords=$(IMEM_WORDS)"

disasm: $(ELF)
	$(RV_OBJDUMP) -d $<

$(OUT_DIR)/$(EXE): $(SRC_DIR)/SpeculaCore.bsv $(HEX) $(IMG_BSV) | $(OUT_DIR)
	@echo "[1/3] Compiling $(TOP)"
	$(BSC) $(BSC_FLAGS) -u -g $(TOP) $(SRC_DIR)/SpeculaCore.bsv
	@echo "[2/3] Elaborating"
	$(BSC) $(BSC_FLAGS) -e $(TOP) -o $(OUT_DIR)/$(EXE)

run: all
	@echo "[3/3] Running simulation"
	./$(OUT_DIR)/$(EXE) | tee output.txt

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

clean:
	rm -rf $(OUT_DIR)
	rm -f $(HEX) $(IMG_BSV) output.txt
