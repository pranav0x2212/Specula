# command to view the simulation output is make clean && make run

# ---------- CONFIG -----------

TOP      ?= mkSpeculaCore
SRC_DIR  ?= src
OUT_DIR  ?= build
EXE      ?= sim

BSC      := bsc
BSC_PATH := +:src:src/common:src/frontend:src/backend:sw
BSC_FLAGS := +RTS -K512M -RTS -sim -p $(BSC_PATH) -bdir $(OUT_DIR) -info-dir $(OUT_DIR)

MEM_WORDS ?= 65536
ZERO      := 00000000

RV_PREFIX  ?= riscv32-unknown-elf-
RV_CC      := $(RV_PREFIX)gcc
RV_OBJCOPY := $(RV_PREFIX)objcopy
RV_OBJDUMP := $(RV_PREFIX)objdump

# RV_ARCH = target ISA string. Default rv32i (M1-M7a). Use rv32ic for M7b tests.
RV_ARCH    ?= rv32i
RV_CFLAGS  := -march=$(RV_ARCH) -mabi=ilp32 -nostdlib -nostartfiles -ffreestanding -O1
RV_LDFLAGS := -Wl,-T,sw/link.ld

# TEST: source under test. Override e.g.  make TEST=sw/tests/m5.c run
TEST     ?= sw/test.c
SW_SRCS  := sw/start.S $(TEST)
SW_LD    := sw/link.ld
ELF      := $(OUT_DIR)/test.elf
BIN      := $(OUT_DIR)/test.bin
HEX      := image.hex
IMG_BSV  := sw/MemImage.bsv

# ---------- TARGETS -----------

.PHONY: all run image disasm clean rvctest csrtest

all: $(OUT_DIR)/$(EXE)

image: $(HEX) $(IMG_BSV)

# M7b: standalone RV32C expander bench (no program image needed).
rvctest: | $(OUT_DIR)
	$(BSC) $(BSC_FLAGS) -u -g mkRVCExpandTest $(SRC_DIR)/frontend/RVCExpandTest.bsv
	$(BSC) $(BSC_FLAGS) -e mkRVCExpandTest -o $(OUT_DIR)/rvctest
	./$(OUT_DIR)/rvctest

# M8: standalone machine-mode CSR-file bench (no program image needed).
csrtest: | $(OUT_DIR)
	$(BSC) $(BSC_FLAGS) -u -g mkCSRFileTest $(SRC_DIR)/backend/CSRFileTest.bsv
	$(BSC) $(BSC_FLAGS) -e mkCSRFileTest -o $(OUT_DIR)/csrtest
	./$(OUT_DIR)/csrtest

$(ELF): $(SW_SRCS) $(SW_LD) | $(OUT_DIR)
	@echo "[img] compiling $(SW_SRCS)"
	$(RV_CC) $(RV_CFLAGS) $(RV_LDFLAGS) -o $@ $(SW_SRCS)

$(BIN): $(ELF)
	$(RV_OBJCOPY) -O binary $< $@
	@sz=$$(wc -c < $@); r=$$(( (4 - sz % 4) % 4 )); \
	if [ $$r -gt 0 ]; then head -c $$r /dev/zero >> $@; fi

$(HEX): $(BIN)
	@echo "[img] $@ <- $< (zero-padded to exactly $(MEM_WORDS) words)"
	@od -An -v -tx4 -w4 $< | awk '{print $$1}' > $@
	@real=$$(wc -l < $@); \
	if [ $$real -gt $(MEM_WORDS) ]; then \
	  echo "ERROR: image is $$real words, exceeds MEM_WORDS=$(MEM_WORDS)"; exit 1; fi; \
	pad=$$(( $(MEM_WORDS) - real )); \
	if [ $$pad -gt 0 ]; then yes $(ZERO) | head -n $$pad >> $@; fi; \
	final=$$(wc -l < $@); \
	if [ $$final -ne $(MEM_WORDS) ]; then \
	  echo "ERROR: $@ has $$final lines, expected exactly $(MEM_WORDS)"; exit 1; fi; \
	echo "[img] $@ : $$final lines ($$real image + $$pad zero)"

$(IMG_BSV): $(BIN)
	@bytes=$$(wc -c < $<); words=$$(( (bytes + 3) / 4 )); \
	printf '// GENERATED from %s by the Makefile. Do not edit; not tracked.\npackage MemImage;\n  typedef %s MemWords;                 // unified memory size in 32-bit words\n  Integer memBaseAddr = %sh80000000;    // physical base of the unified memory\n  Integer imageWords  = %s;               // real bytes/4 loaded from the ELF\nendpackage\n' "$(SW_SRCS)" "$(MEM_WORDS)" "'" "$$words" > $@; \
	echo "[img] $@ : MemWords=$(MEM_WORDS) imageWords=$$words"

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
