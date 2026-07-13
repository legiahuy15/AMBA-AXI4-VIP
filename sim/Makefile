# Hoang Ho: unmarked baseline recipes remain from Huy Le's original project.
# Hoang Ho: lines explicitly marked below add functional/spec regression safety.
# ==============================================================================
# File        : Makefile
# Project     : AXI4 VIP
# Author      : Huy Le
# Description : QuestaSim simulation Makefile for Linux.
#               Supports parallel regressions, random seeding, code/functional 
#               coverage collection, and merging results into HTML reports.
# ==============================================================================

# ==============================================================================
# 1. Path Definitions & File List
# ==============================================================================
SRC_DIR      = ../src
REPORT_DIR   = ./report
LOG_DIR      = $(REPORT_DIR)/logs
COV_DIR      = $(REPORT_DIR)/coverage
COV_HTML_DIR = $(REPORT_DIR)/cov_html
# Hoang Ho - per-run pass/fail markers for complete regression accounting
STATUS_DIR    = $(REPORT_DIR)/status

# Compilation Source Files (in correct compile order)
SV_SOURCES = \
    $(SRC_DIR)/axi4_if.sv \
    $(SRC_DIR)/axi4_pkg.sv \
    $(SRC_DIR)/axi4_test_pkg.sv \
    $(SRC_DIR)/sva/axi4_sva.sv \
    $(SRC_DIR)/tb_top.sv

# ==============================================================================
# 2. Configurable Variables (Can be overridden via command line)
# ==============================================================================
TESTNAME      ?= axi4_sanity_test
# Set to 'random' or a specific integer (e.g., 42)
SEED          ?= random
UVM_VERBOSITY ?= UVM_LOW
# Number of iterations per test in regression
NUM_RUNS      ?= 5
# 1: Enable coverage collection, 0: Disable for speed
USE_COVERAGE  ?= 1

# Additional user-defined simulator arguments
PLUSARGS      += +DUMP_VCD

# List of tests to run during a regression
TEST_LIST     ?= axi4_sanity_test axi4_random_test axi4_outstanding_test \
                 axi4_out_of_order_test \
                 axi4_exclusive_test axi4_illegal_exclusive_test \
                 axi4_exclusive_fail_test axi4_reset_mid_burst_test \
                 axi4_unaligned_test axi4_cache_prot_test \
                 axi4_strobe_test axi4_burst_sweep_test \
                 axi4_wr_order_demo_test axi4_wlast_before_aw_test \
                 axi4_narrow_burst_test \
                 axi4_error_response_test axi4_all_burst_type_test \
                 axi4_back_to_back_test \
                 axi4_data_integrity_test \
                 axi4_addr_integrity_test axi4_backpressure_test \
                 axi4_4kb_boundary_test axi4_response_backpressure_test \
                 axi4_spec_corner_test axi4_helper_unit_test \
                 axi4_exclusive_demo_test axi4_ooo_demo_test

# ==============================================================================
# 3. Simulator Flags & Conditional Options
# ==============================================================================
VLOG_FLAGS = -sv -work work -timescale 1ns/1ps +incdir+$(SRC_DIR) -l $(LOG_DIR)/compile.log
VOPT_FLAGS = +acc -work work -l $(LOG_DIR)/optimize.log
VSIM_BASE_FLAGS = -c -work work
VSIM_FLAGS = $(VSIM_BASE_FLAGS) -l $(LOG_DIR)/run.log

# Coverage collection settings
ifeq ($(USE_COVERAGE),1)
    VLOG_FLAGS += -cover sbcet
    VOPT_FLAGS += -cover sbcet
    VSIM_BASE_FLAGS += -coverage
endif

# Dynamic Seed Generation
ifeq ($(SEED),random)
    GEN_SEED = $(shell shuf -i 1-99999999 -n 1)
else
    GEN_SEED = $(SEED)
endif

# ==============================================================================
# 4. Main Targets
# ==============================================================================
.PHONY: help compile optimize run regress merge_cov cov_report gui clean sva_unit spec_smoke

help:
	@echo "========================================================================"
	@echo "                      AXI4 VIP Simulation Makefile                      "
	@echo "========================================================================"
	@echo "Usage:"
	@echo "  make run             - Run a single simulation (CLI mode)"
	@echo "  make gui             - Run a single simulation (GUI mode with wave window)"
	@echo "  make regress         - Run multiple simulation runs in parallel"
	@echo "  make merge_cov       - Merge all coverage databases (.ucdb)"
	@echo "  make cov_report      - Merge and generate HTML coverage report"
	@echo "  make spec_smoke      - Run Hoang Ho directed AXI4 functional fixes"
	@echo "  make clean           - Remove all generated files & simulation libraries"
	@echo ""
	@echo "Variables (Override via command line, e.g., 'make run TESTNAME=my_test'):"
	@echo "  TESTNAME=<name>      - Set UVM test name (default: $(TESTNAME))"
	@echo "  SEED=<int/random>    - Set simulation seed (default: $(SEED))"
	@echo "  UVM_VERBOSITY=<val>  - Set verbosity level (default: $(UVM_VERBOSITY))"
	@echo "  NUM_RUNS=<int>       - Iterations per test in regression (default: $(NUM_RUNS))"
	@echo "  USE_COVERAGE=<0/1>   - Enable/disable code coverage (default: $(USE_COVERAGE))"
	@echo "  TEST_LIST=\"t1 t2\"  - List of tests for regression (default: \"$(TEST_LIST)\")"
	@echo "========================================================================"

# Compile phase
compile:
	@mkdir -p $(LOG_DIR)
	@echo "[COMPILE] Creating library and compiling sources..."
	@# Hoang Ho - avoid harmless vlib-34 warning when work already exists.
	@if [ ! -d work ]; then vlib work; fi
	@vmap work work
	vlog $(VLOG_FLAGS) $(SV_SOURCES)

# Optimize phase (Standard industry Questa flow using vopt)
optimize: compile
	@echo "[OPTIMIZE] Generating optimized model 'opt_tb_top'..."
	vopt $(VOPT_FLAGS) tb_top -o opt_tb_top

# Run a single simulation batch
run: optimize
	@mkdir -p $(LOG_DIR) $(COV_DIR)
	@echo "[RUN] Executing: $(TESTNAME) | SEED=$(GEN_SEED)"
	@rm -f $(LOG_DIR)/run.log
	@vsim $(VSIM_FLAGS) -sv_seed $(GEN_SEED) \
		+UVM_TESTNAME=$(TESTNAME) \
		+UVM_VERBOSITY=$(UVM_VERBOSITY) \
		$(PLUSARGS) \
		-do "coverage save -onexit $(COV_DIR)/$(TESTNAME)_seed_$(GEN_SEED).ucdb; run -all; quit -f" \
		opt_tb_top; \
	status=$$?; \
	if [ $$status -ne 0 ] || \
	   grep -q -E "UVM_ERROR[[:space:]]*:[[:space:]]*[1-9]" $(LOG_DIR)/run.log || \
	   grep -q -E "UVM_FATAL[[:space:]]*:[[:space:]]*[1-9]" $(LOG_DIR)/run.log || \
	   grep -q "=== TEST FAILED ===" $(LOG_DIR)/run.log; then \
		echo "[RUN] FAILED: $(TESTNAME), seed=$(GEN_SEED)"; \
		exit 1; \
	fi; \
	echo "[RUN] PASSED: $(TESTNAME), seed=$(GEN_SEED)"

# Hoang Ho - compact directed gate for the functional fixes in this patch.
spec_smoke: optimize
	@$(MAKE) run TESTNAME=axi4_helper_unit_test SEED=1
	@$(MAKE) run TESTNAME=axi4_spec_corner_test SEED=1
	@$(MAKE) run TESTNAME=axi4_4kb_boundary_test SEED=1
	@$(MAKE) run TESTNAME=axi4_response_backpressure_test SEED=22883092
	@$(MAKE) run TESTNAME=axi4_response_backpressure_test SEED=68865829
	@echo "[SPEC-SMOKE] All directed functional-fix tests passed."

# Launch Questa GUI with full AXI4 waveform view
gui: optimize
	@mkdir -p $(LOG_DIR)
	@echo "[GUI] Launching QuestaSim GUI for: $(TESTNAME)"
	vsim -gui -work work \
		+UVM_TESTNAME=$(TESTNAME) \
		+UVM_VERBOSITY=$(UVM_VERBOSITY) \
		$(PLUSARGS) \
		-do "\
			add wave -divider {System}; \
			add wave -color Yellow sim:/tb_top/intf/clk; \
			add wave -color Yellow sim:/tb_top/intf/rst_n; \
			add wave -divider {AW Channel}; \
			add wave -hex sim:/tb_top/intf/AWID sim:/tb_top/intf/AWADDR sim:/tb_top/intf/AWLEN; \
			add wave -hex sim:/tb_top/intf/AWSIZE sim:/tb_top/intf/AWBURST; \
			add wave sim:/tb_top/intf/AWVALID sim:/tb_top/intf/AWREADY; \
			add wave -divider {W Channel}; \
			add wave -hex sim:/tb_top/intf/WDATA sim:/tb_top/intf/WSTRB; \
			add wave sim:/tb_top/intf/WLAST sim:/tb_top/intf/WVALID sim:/tb_top/intf/WREADY; \
			add wave -divider {B Channel}; \
			add wave -hex sim:/tb_top/intf/BID sim:/tb_top/intf/BRESP; \
			add wave sim:/tb_top/intf/BVALID sim:/tb_top/intf/BREADY; \
			add wave -divider {AR Channel}; \
			add wave -hex sim:/tb_top/intf/ARID sim:/tb_top/intf/ARADDR sim:/tb_top/intf/ARLEN; \
			add wave -hex sim:/tb_top/intf/ARSIZE sim:/tb_top/intf/ARBURST; \
			add wave sim:/tb_top/intf/ARVALID sim:/tb_top/intf/ARREADY; \
			add wave -divider {R Channel}; \
			add wave -hex sim:/tb_top/intf/RID sim:/tb_top/intf/RDATA sim:/tb_top/intf/RRESP; \
			add wave sim:/tb_top/intf/RLAST sim:/tb_top/intf/RVALID sim:/tb_top/intf/RREADY; \
			run -all" \
		opt_tb_top &

# ==============================================================================
# 4b. Standalone SVA unit test (no UVM) - proves WLAST_MISSING_W_BEFORE_AW fires
# ==============================================================================
sva_unit:
	@mkdir -p $(LOG_DIR)
	@echo "[SVA-UNIT] Compiling axi4_sva + directed unit testbench..."
	@# Hoang Ho - avoid vlib-34 warning.
	@if [ ! -d work ]; then vlib work; fi
	@vmap work work
	vlog -sv -work work -timescale 1ns/1ps +incdir+$(SRC_DIR) \
		$(SRC_DIR)/sva/axi4_sva.sv $(SRC_DIR)/sva/tb_sva_wlast_before_aw.sv \
		-l $(LOG_DIR)/sva_unit_compile.log
	@echo "[SVA-UNIT] Running (expect: 0 SVA errors in PHASE A/B, 1 in PHASE C)..."
	vsim -c -work work tb_sva_wlast_before_aw \
		-l $(LOG_DIR)/sva_unit_run.log \
		-do "run -all; quit -f"

# ==============================================================================
# 5. Regression Harness (Supports parallel execution, e.g., 'make -j8 regress')
# ==============================================================================
# Generate a list of execution targets: e.g., axi4_wr_rd_test_run_1, axi4_wr_rd_test_run_2
REGRESS_TARGETS = $(foreach test,$(TEST_LIST),$(foreach idx,$(shell seq 1 $(NUM_RUNS)),$(test)_run_$(idx)))

# Regression runner entrypoint
regress: optimize
	@echo "[REGRESS] Starting parallel regression for tests: $(TEST_LIST)"
	@echo "          Running $(NUM_RUNS) iterations per test..."
	@mkdir -p $(LOG_DIR) $(COV_DIR) $(STATUS_DIR)
	@rm -f $(STATUS_DIR)/*.pass $(STATUS_DIR)/*.fail
	@$(MAKE) $(REGRESS_TARGETS)
	@fail_count=$$(find $(STATUS_DIR) -maxdepth 1 -name '*.fail' | wc -l); \
	pass_count=$$(find $(STATUS_DIR) -maxdepth 1 -name '*.pass' | wc -l); \
	echo "[REGRESS] Results: PASS=$$pass_count FAIL=$$fail_count"; \
	if [ $$fail_count -ne 0 ]; then \
		echo "[REGRESS] FAILED runs:"; \
		for f in $(STATUS_DIR)/*.fail; do [ -e "$$f" ] && cat "$$f"; done; \
		exit 1; \
	fi
	@echo "[REGRESS] Regression passed. Run 'make cov_report' to generate coverage."

# Individual run target handler
$(REGRESS_TARGETS):
	@test_name=$(word 1,$(subst _run_, ,$@)); \
	run_idx=$(word 2,$(subst _run_, ,$@)); \
	seed=$$(shuf -i 1-99999999 -n 1); \
	log_file=$(LOG_DIR)/$${test_name}_run_$${run_idx}_seed_$${seed}.log; \
	ucdb_file=$(COV_DIR)/$${test_name}_run_$${run_idx}_seed_$${seed}.ucdb; \
	status_base=$(STATUS_DIR)/$${test_name}_run_$${run_idx}_seed_$${seed}; \
	echo "[REGRESS-RUN] $$test_name | Iteration: $$run_idx | Seed: $$seed"; \
	vsim $(VSIM_BASE_FLAGS) -sv_seed $$seed \
		+UVM_TESTNAME=$$test_name \
		+UVM_VERBOSITY=$(UVM_VERBOSITY) \
		$(PLUSARGS) \
		-l $$log_file \
		-do "coverage save -onexit $$ucdb_file; run -all; quit -f" \
		opt_tb_top; \
	status=$$?; \
	if [ $$status -ne 0 ] || \
	   grep -q -E "UVM_ERROR[[:space:]]*:[[:space:]]*[1-9]" $$log_file || \
	   grep -q -E "UVM_FATAL[[:space:]]*:[[:space:]]*[1-9]" $$log_file || \
	   grep -q "=== TEST FAILED ===" $$log_file; then \
		echo "$$test_name run=$$run_idx seed=$$seed log=$$log_file" > $${status_base}.fail; \
		echo "              ==> $$test_name (Run $$run_idx) [FAILED] - Log: $$log_file"; \
	else \
		echo "$$test_name run=$$run_idx seed=$$seed log=$$log_file" > $${status_base}.pass; \
		echo "              ==> $$test_name (Run $$run_idx) [PASSED]"; \
	fi

# ==============================================================================
# 6. Coverage Post-Processing
# ==============================================================================
# Merge all generated UCDB databases
merge_cov:
	@echo "[COV] Merging coverage databases into $(COV_DIR)/merged.ucdb..."
	@mkdir -p $(COV_DIR)
	@rm -f $(COV_DIR)/merged.ucdb
	@ucdb_files=$$(find $(COV_DIR) -maxdepth 1 -type f -name '*.ucdb' ! -name 'merged.ucdb' -print); \
	if [ -n "$$ucdb_files" ]; then \
		vcover merge $(COV_DIR)/merged.ucdb $$ucdb_files; \
		echo "[COV] Coverage databases successfully merged."; \
	else \
		echo "[COV] ERROR: No .ucdb files found in $(COV_DIR)."; \
		exit 1; \
	fi

# Generate the HTML Report
cov_report: merge_cov
	@echo "[COV] Generating HTML coverage report in $(COV_HTML_DIR)..."
	@rm -rf $(COV_HTML_DIR)
	@mkdir -p $(COV_HTML_DIR)
	vcover report -html -htmldir $(COV_HTML_DIR) -verbose $(COV_DIR)/merged.ucdb
	@echo "========================================================================"
	@echo "[COV] HTML Report successfully generated!"
	@echo "      Open in browser: $(COV_HTML_DIR)/index.html"
	@echo "========================================================================"

# ==============================================================================
# 7. Clean up
# ==============================================================================
clean:
	@echo "[CLEAN] Removing all simulation outputs and libraries..."
	rm -rf work transcript vsim.wlf vsim_stacktrace.vstf modelsim.ini
	rm -rf $(REPORT_DIR)
	rm -rf *.vcd *.ucdb