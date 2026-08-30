# command to view the simulation output is make clean && make run

# ---------- CONFIG -----------

TOP      ?= mkSpeculaCore
SRC_DIR  ?= src
OUT_DIR  ?= build
EXE      ?= sim

BSC      := bsc
BSC_PATH := +:src:src/common:src/frontend:src/backend
BSC_FLAGS := +RTS -K512M -RTS -sim -p $(BSC_PATH) -bdir $(OUT_DIR) -info-dir $(OUT_DIR)

# ---------- TARGETS -----------

.PHONY: all run clean

all: $(OUT_DIR)/$(EXE)

$(OUT_DIR)/$(EXE): $(SRC_DIR)/SpeculaCore.bsv | $(OUT_DIR)
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