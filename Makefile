# command to view the simulation output is make clean && make run

# ---------- CONFIG -----------

TOP      ?= mkSpeculaCore
SRC_DIR  ?= src
OUT_DIR  ?= build
EXE      ?= sim

BSC      := bsc
BSC_PATH := +:src:src/common:src/frontend:src/backend:sw
BSC_FLAGS := +RTS -K512M -RTS -sim -p $(BSC_PATH) -bdir $(OUT_DIR) -info-dir $(OUT_DIR)

MEM_WORDS ?= 33554432
IMAGE_PAD_WORDS ?= 262144
SIM_MAX_CYCLES ?= 100000000
ZERO      := 00000000

# ---- M20: interactive-UART build (live host terminal instead of uart_rx.in script) ----
EXE_INTERACTIVE         ?= sim_interactive
BDIR_INTERACTIVE        := $(OUT_DIR)/interactive
# Simulated cycles stall while $fgetc() blocks on human input, so this only
# needs to cover *active* execution between keystrokes; kept generous.
INTERACTIVE_MAX_CYCLES  ?= 2000000000

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

# M19: fs.img backing store for the VirtIO-blk model. Generated from the xv6
# fs.img when present; a 1-word placeholder otherwise (non-xv6 tests never DMA).
FS_IMG   ?= ../xv6-rv32/fs.img
FS_HEX   := fs.hex
FS_PAD_WORDS ?= 262144

# ---------- TARGETS -----------

.PHONY: all run image disasm clean rvctest csrtest uarttest mmutest m18test virtiotest interactive

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

# M9: standalone UART / SystemBus bench (no program image needed).
uarttest: | $(OUT_DIR)
	$(BSC) $(BSC_FLAGS) -u -g mkUartTest $(SRC_DIR)/backend/UartTest.bsv
	$(BSC) $(BSC_FLAGS) -e mkUartTest -o $(OUT_DIR)/uarttest
	./$(OUT_DIR)/uarttest

# M17: standalone Sv32 page-table-walk bench (no program image needed).
mmutest: | $(OUT_DIR)
	$(BSC) $(BSC_FLAGS) -u -g mkMMUTest $(SRC_DIR)/backend/MMUTest.bsv
	$(BSC) $(BSC_FLAGS) -e mkMMUTest -o $(OUT_DIR)/mmutest
	./$(OUT_DIR)/mmutest

m18test:
	$(MAKE) TEST=sw/tests/m18_trap.S RV_ARCH=rv32i_zicsr run

# M19: standalone VirtIO-blk + PLIC bench (descriptor walk, used ring, IRQ).
virtiotest: $(FS_HEX) | $(OUT_DIR)
	$(BSC) $(BSC_FLAGS) -u -g mkVirtioBlkTest $(SRC_DIR)/backend/VirtioBlkTest.bsv
	$(BSC) $(BSC_FLAGS) -e mkVirtioBlkTest -o $(OUT_DIR)/virtiotest
	./$(OUT_DIR)/virtiotest

$(FS_HEX): $(wildcard $(FS_IMG))
	@if [ -f "$(FS_IMG)" ]; then \
	  od -An -v -tx4 -w4 "$(FS_IMG)" | awk '{print $$1}' > $@; \
	  real=$$(wc -l < $@); pad=$$(( $(FS_PAD_WORDS) - real )); \
	  if [ $$pad -gt 0 ]; then yes $(ZERO) | head -n $$pad >> $@; fi; \
	  echo "[img] $@ <- $(FS_IMG) ($$real words + $$pad zero)"; \
	else printf '%s\n' $(ZERO) > $@; echo "[img] $@ : placeholder (no $(FS_IMG))"; fi

$(ELF): $(SW_SRCS) $(SW_LD) | $(OUT_DIR)
	@echo "[img] compiling $(SW_SRCS)"
	$(RV_CC) $(RV_CFLAGS) $(RV_LDFLAGS) -o $@ $(SW_SRCS)

$(BIN): $(ELF)
	$(RV_OBJCOPY) -O binary $< $@
	@sz=$$(wc -c < $@); r=$$(( (4 - sz % 4) % 4 )); \
	if [ $$r -gt 0 ]; then head -c $$r /dev/zero >> $@; fi

$(HEX): $(BIN)
	@echo "[img] $@ <- $< (zero-padded to $(IMAGE_PAD_WORDS) words)"
	@od -An -v -tx4 -w4 $< | awk '{print $$1}' > $@
	@real=$$(wc -l < $@); \
	if [ $$real -gt $(IMAGE_PAD_WORDS) ]; then \
	  echo "ERROR: image is $$real words, exceeds IMAGE_PAD_WORDS=$(IMAGE_PAD_WORDS)"; exit 1; fi; \
	pad=$$(( $(IMAGE_PAD_WORDS) - real )); \
	if [ $$pad -gt 0 ]; then yes $(ZERO) | head -n $$pad >> $@; fi; \
	echo "[img] $@ : $$(wc -l < $@) lines ($$real image + $$pad zero), memory is $(MEM_WORDS) words"

$(IMG_BSV): $(BIN)
	@bytes=$$(wc -c < $<); words=$$(( (bytes + 3) / 4 )); \
	printf '// GENERATED from %s by the Makefile. Do not edit; not tracked.\npackage MemImage;\n  typedef %s MemWords;                 // unified memory size in 32-bit words\n  Integer memBaseAddr = %sh80000000;    // physical base of the unified memory\n  Integer imageWords  = %s;               // real bytes/4 loaded from the ELF\n  Integer maxCycles   = %s;\nendpackage\n' "$(SW_SRCS)" "$(MEM_WORDS)" "'" "$$words" "$(SIM_MAX_CYCLES)" > $@; \
	echo "[img] $@ : MemWords=$(MEM_WORDS) imageWords=$$words maxCycles=$(SIM_MAX_CYCLES)"

disasm: $(ELF)
	$(RV_OBJDUMP) -d $<

$(OUT_DIR)/$(EXE): $(SRC_DIR)/SpeculaCore.bsv $(HEX) $(IMG_BSV) $(FS_HEX) | $(OUT_DIR)
	@echo "[1/3] Compiling $(TOP)"
	$(BSC) $(BSC_FLAGS) -u -g $(TOP) $(SRC_DIR)/SpeculaCore.bsv
	@echo "[2/3] Elaborating"
	$(BSC) $(BSC_FLAGS) -e $(TOP) -o $(OUT_DIR)/$(EXE)

run: all
	@echo "[3/3] Running simulation"
	./$(OUT_DIR)/$(EXE) | tee output.txt

# M20: live interactive xv6 shell over the existing UART RX/TX path.
# Built with -D INTERACTIVE_UART (see src/backend/Uart.bsv) into its own
# -bdir/-o so it never shares or clobbers the regression build's .bo cache
# or the default build/sim binary. Only the `maxCycles` line of $(IMG_BSV)
# is patched (in place, then restored via trap) rather than regenerating the
# whole file from $(BIN) - image.hex/$(IMG_BSV) here may have been produced
# out-of-band (e.g. from an xv6 ELF) rather than via the sw/test.c pipeline,
# and regenerating from $(BIN) would silently overwrite that image.
$(OUT_DIR)/$(EXE_INTERACTIVE): $(SRC_DIR)/SpeculaCore.bsv $(HEX) $(IMG_BSV) $(FS_HEX) | $(OUT_DIR)
	@mkdir -p $(BDIR_INTERACTIVE)
	@set -e; \
	cp $(IMG_BSV) $(IMG_BSV).interactive-saved; \
	trap 'mv -f $(IMG_BSV).interactive-saved $(IMG_BSV)' EXIT; \
	sed -i 's/^  Integer maxCycles.*/  Integer maxCycles   = $(INTERACTIVE_MAX_CYCLES);/' $(IMG_BSV); \
	echo "[1/2] Compiling $(TOP) (interactive UART, maxCycles=$(INTERACTIVE_MAX_CYCLES))"; \
	$(BSC) $(BSC_FLAGS) -D INTERACTIVE_UART -bdir $(BDIR_INTERACTIVE) -info-dir $(BDIR_INTERACTIVE) -u -g $(TOP) $(SRC_DIR)/SpeculaCore.bsv; \
	echo "[2/2] Elaborating (interactive UART)"; \
	$(BSC) $(BSC_FLAGS) -D INTERACTIVE_UART -bdir $(BDIR_INTERACTIVE) -info-dir $(BDIR_INTERACTIVE) -e $(TOP) -o $(OUT_DIR)/$(EXE_INTERACTIVE)

interactive: $(OUT_DIR)/$(EXE_INTERACTIVE)
	@scripts/interactive.sh $(OUT_DIR)/$(EXE_INTERACTIVE)

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

clean:
	rm -rf $(OUT_DIR)
	rm -f $(HEX) $(IMG_BSV) $(FS_HEX) output.txt
	rm -f uart_rx.in.regression-backup
