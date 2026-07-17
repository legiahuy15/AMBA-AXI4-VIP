# ==============================================================================
# File        : Makefile
# Project     : AXI4 Full VIP-to-VIP
# Base author : Huy Le
# Extension   : Hoang Ho
# Description : Simplified QuestaSim flow for single tests, GUI debug,
#               one-width regression, all-width regression, cleanup, and coverage.
# ==============================================================================

# Huy Le: the original project provides the UVM environment, test list, compile
# order, regression concept, and coverage flow.
# Hoang Ho: Release R3 exposes only six user-facing command groups. Internal
# helper targets begin with '_' and are not part of the normal user workflow.

.DEFAULT_GOAL := help

# ==============================================================================
# 1. Project paths and source order
# ==============================================================================
SRC_DIR     := ../src
RESULT_ROOT ?= ./results

SV_SOURCES := \
    $(SRC_DIR)/axi4_if.sv \
    $(SRC_DIR)/axi4_pkg.sv \
    $(SRC_DIR)/axi4_test_pkg.sv \
    $(SRC_DIR)/sva/axi4_sva.sv \
    $(SRC_DIR)/tb_top.sv

# ==============================================================================
# 2. User configuration
# ==============================================================================
TESTNAME      ?= axi4_sanity_test
SEED          ?= random
UVM_VERBOSITY ?= UVM_LOW
NUM_RUNS      ?= 5
JOBS          ?= 8
USE_COVERAGE  ?= 1

ADDR_WIDTH    ?= 32
DATA_WIDTH    ?= 32
ID_WIDTH      ?= 4
WIDTH_LIST    ?= 32 64 128 256 512 1024
FAIL_FAST     ?= 0

# Hoang Ho: DATA_WIDTH=256 is valid. DATA_WIDTH=264 is not an AXI4 data width
# supported by this project and is rejected with a clear error message.

# Huy Le: baseline executable tests inherited from the original repository.
# Keeping this list separate makes ownership and regression composition easy
# for a new learner to understand.
HUY_LE_TEST_LIST ?= axi4_sanity_test axi4_random_test \
                    axi4_outstanding_test axi4_out_of_order_test \
                    axi4_exclusive_test axi4_illegal_exclusive_test \
                    axi4_exclusive_fail_test axi4_reset_mid_burst_test \
                    axi4_unaligned_test axi4_cache_prot_test \
                    axi4_strobe_test axi4_burst_sweep_test \
                    axi4_wr_order_demo_test axi4_wlast_before_aw_test \
                    axi4_narrow_burst_test axi4_error_response_test \
                    axi4_all_burst_type_test axi4_back_to_back_test \
                    axi4_data_integrity_test axi4_addr_integrity_test \
                    axi4_backpressure_test axi4_exclusive_demo_test \
                    axi4_ooo_demo_test

# Hoang Ho: extension tests added for corrected helpers, exact 4KB behavior,
# response backpressure, protocol corners, read interleaving, and width scaling.
HOANG_HO_TEST_LIST ?= axi4_4kb_boundary_test \
                      axi4_response_backpressure_test \
                      axi4_spec_corner_test \
                      axi4_helper_unit_test \
                      axi4_read_interleaving_test \
                      axi4_width_scaling_test

# Hoang Ho: regress and regress_all use the complete 29-test list by default.
# Users can still override TEST_LIST from the command line for a smaller run.
TEST_LIST ?= $(HUY_LE_TEST_LIST) $(HOANG_HO_TEST_LIST)

# Result locations. Users normally select only DATA_WIDTH; the Makefile places
# every campaign in a predictable width-specific directory.
RUN_REPORT_DIR      ?= $(RESULT_ROOT)/run/w$(DATA_WIDTH)
GUI_REPORT_DIR      ?= $(RESULT_ROOT)/gui/w$(DATA_WIDTH)
REGRESS_REPORT_DIR  ?= $(RESULT_ROOT)/regress/w$(DATA_WIDTH)
REGRESS_ALL_ROOT    ?= $(RESULT_ROOT)/regress_all

# Coverage commands use the selected one-width regression directory by default.
# Override REPORT_DIR to inspect an all-width profile, for example:
# make cov_report REPORT_DIR=./results/regress_all/w64
REPORT_DIR ?= $(REGRESS_REPORT_DIR)

# Single CLI runs keep a unique waveform. Parallel regression disables VCD by
# default so multiple simulations never write the same file.
RUN_PLUSARGS     ?= +DUMP_VCD
REGRESS_PLUSARGS ?=

# ==============================================================================
# 3. Internal simulator configuration
# ==============================================================================
LOG_DIR      = $(REPORT_DIR)/logs
COV_DIR      = $(REPORT_DIR)/coverage
COV_HTML_DIR = $(REPORT_DIR)/cov_html
STATUS_DIR   = $(REPORT_DIR)/status
WAVE_DIR     = $(REPORT_DIR)/waveforms

VLOG_FLAGS = -sv -work work -timescale 1ns/1ps +incdir+$(SRC_DIR) \
             -l $(LOG_DIR)/compile.log \
             +define+AXI4_ADDR_WIDTH_CFG=$(ADDR_WIDTH) \
             +define+AXI4_DATA_WIDTH_CFG=$(DATA_WIDTH) \
             +define+AXI4_ID_WIDTH_CFG=$(ID_WIDTH)
VOPT_FLAGS = +acc -work work -l $(LOG_DIR)/optimize.log
VSIM_FLAGS = -c -work work

ifeq ($(USE_COVERAGE),1)
VLOG_FLAGS += -cover sbcet
VOPT_FLAGS += -cover sbcet
VSIM_FLAGS += -coverage
endif

# Generate one private make target for every test/run pair.
REGRESS_TARGETS = $(foreach test,$(TEST_LIST),\
                  $(foreach idx,$(shell seq 1 $(NUM_RUNS)),$(test)_run_$(idx)))

# ==============================================================================
# 4. Six user-facing command groups
# ==============================================================================
.PHONY: help run gui regress regress_all REGRESS_ALL clean clean_all CLEAN_ALL \
        merge_cov merge_cov_all cov_report cov_report_all \
        _check_width _static_check _clean_work _compile _optimize _run_cli \
        _regress_width $(REGRESS_TARGETS)

help:
	@echo "========================================================================"
	@echo "             AXI4 FULL VIP-TO-VIP - SIMPLIFIED MAKEFILE"
	@echo "========================================================================"
	@echo "1) RUN ONE TEST"
	@echo "   make run TESTNAME=<test> DATA_WIDTH=<32|64|128|256|512|1024> SEED=<n|random>"
	@echo ""
	@echo "2) OPEN GUI"
	@echo "   make gui TESTNAME=<test> DATA_WIDTH=<width> SEED=<n|random>"
	@echo ""
	@echo "3) REGRESSION"
	@echo "   make regress DATA_WIDTH=<width> NUM_RUNS=<n> JOBS=<n>"
	@echo "   make regress DATA_WIDTH=ALL NUM_RUNS=<n> JOBS=<n>"
	@echo "   make regress_all NUM_RUNS=<n> JOBS=<n>       # same as DATA_WIDTH=ALL"
	@echo ""
	@echo "4) CLEAN"
	@echo "   make clean DATA_WIDTH=<width>                 # selected width only"
	@echo "   make clean_all                                # all generated results"
	@echo ""
	@echo "5) MERGE COVERAGE"
	@echo "   make merge_cov DATA_WIDTH=<width>             # one-width regression"
	@echo "   make merge_cov REPORT_DIR=<result-directory>  # custom directory"
	@echo "   make merge_cov_all                            # all 6 regress_all widths"
	@echo ""
	@echo "6) COVERAGE REPORT"
	@echo "   make cov_report DATA_WIDTH=<width>             # one-width regression"
	@echo "   make cov_report REPORT_DIR=<result-directory>  # custom directory"
	@echo "   make cov_report_all                            # all 6 regress_all widths"
	@echo "------------------------------------------------------------------------"
	@echo "AVAILABLE TESTCASES"
	@echo ""
	@echo "Huy Le baseline tests:"
	@n=1; for test_name in $(HUY_LE_TEST_LIST); do \
		printf "   %2d) %s\n" $$n "$$test_name"; \
		n=$$((n + 1)); \
	done
	@echo ""
	@echo "Hoang Ho extension tests:"
	@n=1; for test_name in $(HOANG_HO_TEST_LIST); do \
		printf "   %2d) %s\n" $$n "$$test_name"; \
		n=$$((n + 1)); \
	done
	@echo ""
	@test_count=$$(printf '%s\n' $(TEST_LIST) | wc -l); \
	 echo "Current regression TEST_LIST: $$test_count executable tests"
	@echo "Example:"
	@echo "   make run TESTNAME=axi4_data_integrity_test DATA_WIDTH=128 SEED=231"
	@echo "Important: do not place a space after TESTNAME=, DATA_WIDTH=, or SEED=."
	@echo "------------------------------------------------------------------------"
	@echo "Defaults: TESTNAME=$(TESTNAME), DATA_WIDTH=32, NUM_RUNS=$(NUM_RUNS), JOBS=$(JOBS), FAIL_FAST=$(FAIL_FAST)"
	@echo "Supported widths: $(WIDTH_LIST)"
	@echo "Note: use 256, not 264."
	@echo "========================================================================"

# ------------------------------------------------------------------------------
# Group 1: run one selected testcase at one selected width
# ------------------------------------------------------------------------------
run:
	@$(MAKE) _check_width DATA_WIDTH=$(DATA_WIDTH)
	@rm -rf "$(RUN_REPORT_DIR)"
	@$(MAKE) _clean_work
	@$(MAKE) _optimize REPORT_DIR="$(RUN_REPORT_DIR)" \
		DATA_WIDTH=$(DATA_WIDTH) ADDR_WIDTH=$(ADDR_WIDTH) ID_WIDTH=$(ID_WIDTH) \
		USE_COVERAGE=$(USE_COVERAGE)
	@$(MAKE) _run_cli REPORT_DIR="$(RUN_REPORT_DIR)" \
		TESTNAME=$(TESTNAME) SEED=$(SEED) DATA_WIDTH=$(DATA_WIDTH) \
		ADDR_WIDTH=$(ADDR_WIDTH) ID_WIDTH=$(ID_WIDTH) \
		USE_COVERAGE=$(USE_COVERAGE)

# ------------------------------------------------------------------------------
# Group 2: compile one width and open Questa GUI
# ------------------------------------------------------------------------------
gui:
	@$(MAKE) _check_width DATA_WIDTH=$(DATA_WIDTH)
	@rm -rf "$(GUI_REPORT_DIR)"
	@$(MAKE) _clean_work
	@$(MAKE) _optimize REPORT_DIR="$(GUI_REPORT_DIR)" \
		DATA_WIDTH=$(DATA_WIDTH) ADDR_WIDTH=$(ADDR_WIDTH) ID_WIDTH=$(ID_WIDTH) \
		USE_COVERAGE=$(USE_COVERAGE)
	@mkdir -p "$(GUI_REPORT_DIR)/logs"
	@set -e; \
	if [ "$(SEED)" = "random" ]; then \
		run_seed=$$(shuf -i 1-99999999 -n 1); \
	else \
		run_seed="$(SEED)"; \
	fi; \
	echo "[GUI] TEST=$(TESTNAME) DATA_WIDTH=$(DATA_WIDTH) SEED=$$run_seed"; \
	vsim -gui -work work -sv_seed $$run_seed \
		+UVM_TESTNAME=$(TESTNAME) \
		+UVM_VERBOSITY=$(UVM_VERBOSITY) \
		-l "$(GUI_REPORT_DIR)/logs/$(TESTNAME)_seed_$${run_seed}.log" \
		-do wave.do opt_tb_top &

# ------------------------------------------------------------------------------
# Group 3: full regression at one width or at all six widths
# ------------------------------------------------------------------------------
regress:
	@if [ "$(DATA_WIDTH)" = "ALL" ] || [ "$(DATA_WIDTH)" = "all" ]; then \
		$(MAKE) regress_all NUM_RUNS=$(NUM_RUNS) JOBS=$(JOBS) \
			USE_COVERAGE=$(USE_COVERAGE) FAIL_FAST=$(FAIL_FAST) \
			ADDR_WIDTH=$(ADDR_WIDTH) ID_WIDTH=$(ID_WIDTH) \
			TEST_LIST="$(TEST_LIST)"; \
	else \
		$(MAKE) _check_width DATA_WIDTH=$(DATA_WIDTH); \
		rm -rf "$(REGRESS_REPORT_DIR)"; \
		$(MAKE) _clean_work; \
		$(MAKE) _regress_width REPORT_DIR="$(REGRESS_REPORT_DIR)" \
			DATA_WIDTH=$(DATA_WIDTH) ADDR_WIDTH=$(ADDR_WIDTH) ID_WIDTH=$(ID_WIDTH) \
			NUM_RUNS=$(NUM_RUNS) JOBS=$(JOBS) USE_COVERAGE=$(USE_COVERAGE) \
			TEST_LIST="$(TEST_LIST)"; \
	fi

# Hoang Ho: widths elaborate sequentially because the interface and package
# types change with DATA_WIDTH. Tests inside one width still run in parallel.
# Every width result is retained. FAIL_FAST=0 collects the complete diagnosis.
regress_all:
	@rm -rf "$(REGRESS_ALL_ROOT)"
	@mkdir -p "$(REGRESS_ALL_ROOT)"
	@set +e; \
	summary="$(REGRESS_ALL_ROOT)/summary.txt"; \
	overall=0; \
	{ echo "AXI4 FULL REGRESSION SUMMARY"; \
	  echo "WIDTHS=$(WIDTH_LIST)"; \
	  echo "TESTS=$$(printf '%s\n' $(TEST_LIST) | wc -l)"; \
	  echo "RUNS_PER_TEST=$(NUM_RUNS)"; } > "$$summary"; \
	for width in $(WIDTH_LIST); do \
		report_dir="$(REGRESS_ALL_ROOT)/w$$width"; \
		echo "============================================================"; \
		echo "[REGRESS-ALL] DATA_WIDTH=$$width | REPORT=$$report_dir"; \
		echo "============================================================"; \
		$(MAKE) _clean_work; \
		$(MAKE) _regress_width REPORT_DIR="$$report_dir" \
			DATA_WIDTH=$$width ADDR_WIDTH=$(ADDR_WIDTH) ID_WIDTH=$(ID_WIDTH) \
			NUM_RUNS=$(NUM_RUNS) JOBS=$(JOBS) USE_COVERAGE=$(USE_COVERAGE) \
			TEST_LIST="$(TEST_LIST)"; \
		status=$$?; \
		if [ $$status -eq 0 ]; then \
			echo "DATA_WIDTH=$$width PASS" | tee "$$report_dir/REGRESSION_PASS.txt" >> "$$summary"; \
		else \
			overall=1; \
			echo "DATA_WIDTH=$$width FAIL" | tee "$$report_dir/REGRESSION_FAIL.txt" >> "$$summary"; \
			if [ "$(FAIL_FAST)" = "1" ]; then \
				cat "$$summary"; \
				exit 1; \
			fi; \
		fi; \
	done; \
	cat "$$summary"; \
	if [ $$overall -ne 0 ]; then \
		echo "[REGRESS-ALL] FAILED. Evidence is preserved under $(REGRESS_ALL_ROOT)."; \
		exit 1; \
	fi; \
	echo "[REGRESS-ALL] PASSED. Results are under $(REGRESS_ALL_ROOT)."

# Uppercase alias for users who prefer the name REGRESS_ALL.
REGRESS_ALL: regress_all

# ------------------------------------------------------------------------------
# Group 4: clean one width or all generated data
# ------------------------------------------------------------------------------
clean:
	@if [ "$(DATA_WIDTH)" = "ALL" ] || [ "$(DATA_WIDTH)" = "all" ]; then \
		$(MAKE) clean_all; \
	else \
		$(MAKE) _check_width DATA_WIDTH=$(DATA_WIDTH); \
		$(MAKE) _clean_work; \
		rm -rf "$(RESULT_ROOT)/run/w$(DATA_WIDTH)" \
		       "$(RESULT_ROOT)/gui/w$(DATA_WIDTH)" \
		       "$(RESULT_ROOT)/regress/w$(DATA_WIDTH)" \
		       "$(RESULT_ROOT)/regress_all/w$(DATA_WIDTH)"; \
		echo "[CLEAN] Removed generated results for DATA_WIDTH=$(DATA_WIDTH)."; \
	fi

clean_all:
	@$(MAKE) _clean_work
	@rm -rf "$(RESULT_ROOT)"
	@echo "[CLEAN-ALL] Removed every generated result directory."

CLEAN_ALL: clean_all

# ------------------------------------------------------------------------------
# Group 5: merge UCDB files from one elaborated width only
# ------------------------------------------------------------------------------
merge_cov:
	@echo "[COV] Selected result directory: $(REPORT_DIR)"
	@mkdir -p "$(REPORT_DIR)/coverage"
	@rm -f "$(REPORT_DIR)/coverage/merged.ucdb"
	@ucdb_files=$$(find "$(REPORT_DIR)/coverage" -maxdepth 1 -type f \
		-name '*.ucdb' ! -name 'merged.ucdb' -print); \
	if [ -z "$$ucdb_files" ]; then \
		echo "[COV] ERROR: no UCDB files found."; \
		echo "[COV] Run regression with USE_COVERAGE=1 first."; \
		exit 1; \
	fi; \
	vcover merge "$(REPORT_DIR)/coverage/merged.ucdb" $$ucdb_files
	@echo "[COV] Merge completed. Do not merge different DATA_WIDTH profiles together."

# Hoang Ho: merge all six profiles from a completed regress_all campaign.
# Each DATA_WIDTH is merged into its own UCDB because the elaborated types differ.
merge_cov_all:
	@set +e; \
	overall=0; \
	for width in $(WIDTH_LIST); do \
		report_dir="$(REGRESS_ALL_ROOT)/w$$width"; \
		echo "============================================================"; \
		echo "[COV-ALL] MERGE DATA_WIDTH=$$width"; \
		echo "[COV-ALL] REPORT=$$report_dir"; \
		echo "============================================================"; \
		$(MAKE) merge_cov DATA_WIDTH=$$width REPORT_DIR="$$report_dir"; \
		status=$$?; \
		if [ $$status -ne 0 ]; then overall=1; fi; \
	done; \
	if [ $$overall -ne 0 ]; then \
		echo "[COV-ALL] FAILED: one or more width profiles could not be merged."; \
		exit 1; \
	fi; \
	echo "[COV-ALL] PASSED: all six width-specific UCDB databases were merged."

# ------------------------------------------------------------------------------
# Group 6: generate the HTML coverage report
# ------------------------------------------------------------------------------
cov_report: merge_cov
	@rm -rf "$(REPORT_DIR)/cov_html"
	@mkdir -p "$(REPORT_DIR)/cov_html"
	vcover report -html -htmldir "$(REPORT_DIR)/cov_html" -verbose \
		"$(REPORT_DIR)/coverage/merged.ucdb"
	@echo "[COV] HTML report: $(REPORT_DIR)/cov_html/index.html"

# Hoang Ho: generate six independent HTML reports from regress_all results.
# cov_report already invokes merge_cov for the selected width.
cov_report_all:
	@set +e; \
	overall=0; \
	for width in $(WIDTH_LIST); do \
		report_dir="$(REGRESS_ALL_ROOT)/w$$width"; \
		echo "============================================================"; \
		echo "[COV-ALL] REPORT DATA_WIDTH=$$width"; \
		echo "[COV-ALL] REPORT=$$report_dir"; \
		echo "============================================================"; \
		$(MAKE) cov_report DATA_WIDTH=$$width REPORT_DIR="$$report_dir"; \
		status=$$?; \
		if [ $$status -ne 0 ]; then overall=1; fi; \
	done; \
	if [ $$overall -ne 0 ]; then \
		echo "[COV-ALL] FAILED: one or more HTML reports could not be generated."; \
		exit 1; \
	fi; \
	echo "[COV-ALL] PASSED: HTML reports were generated for all six widths."

# ==============================================================================
# 5. Internal helper targets
# ==============================================================================
_check_width:
	@case " $(WIDTH_LIST) " in \
		*" $(DATA_WIDTH) "*) ;; \
		*) echo "[CONFIG] ERROR: DATA_WIDTH=$(DATA_WIDTH) is unsupported."; \
		   echo "[CONFIG] Supported widths: $(WIDTH_LIST). Use 256, not 264."; \
		   exit 2 ;; \
	esac

_static_check:
	@python3 ../tools/static_check.py

_clean_work:
	@rm -rf work transcript vsim.wlf vsim_stacktrace.vstf modelsim.ini
	@rm -f *.vcd *.ucdb

_compile: _check_width _static_check
	@mkdir -p "$(LOG_DIR)"
	@echo "[COMPILE] ADDR=$(ADDR_WIDTH) DATA=$(DATA_WIDTH) ID=$(ID_WIDTH)"
	@if [ ! -d work ]; then vlib work; fi
	@vmap work work
	vlog $(VLOG_FLAGS) $(SV_SOURCES)

_optimize: _compile
	@echo "[OPTIMIZE] Creating opt_tb_top..."
	vopt $(VOPT_FLAGS) tb_top -o opt_tb_top

# Hoang Ho: SEED=random is resolved exactly once. The same value appears in the
# console, Questa command, log name, UCDB name, VCD name, and PASS/FAIL line.
_run_cli:
	@mkdir -p "$(LOG_DIR)" "$(COV_DIR)" "$(WAVE_DIR)"
	@set -e; \
	if [ "$(SEED)" = "random" ]; then \
		run_seed=$$(shuf -i 1-99999999 -n 1); \
	else \
		run_seed="$(SEED)"; \
	fi; \
	log_file="$(LOG_DIR)/$(TESTNAME)_seed_$${run_seed}.log"; \
	ucdb_file="$(COV_DIR)/$(TESTNAME)_seed_$${run_seed}.ucdb"; \
	vcd_file="$(WAVE_DIR)/$(TESTNAME)_seed_$${run_seed}.vcd"; \
	if [ "$(USE_COVERAGE)" = "1" ]; then \
		do_cmd="coverage save -onexit $$ucdb_file; run -all; quit -f"; \
	else \
		do_cmd="run -all; quit -f"; \
	fi; \
	echo "[RUN] TEST=$(TESTNAME) DATA_WIDTH=$(DATA_WIDTH) SEED=$$run_seed"; \
	set +e; \
	vsim $(VSIM_FLAGS) -sv_seed $$run_seed \
		+UVM_TESTNAME=$(TESTNAME) \
		+UVM_VERBOSITY=$(UVM_VERBOSITY) \
		$(RUN_PLUSARGS) +VCD_FILE=$$vcd_file \
		-l "$$log_file" -do "$$do_cmd" opt_tb_top; \
	status=$$?; \
	set -e; \
	if [ $$status -ne 0 ] || [ ! -f "$$log_file" ] || \
	   grep -q -E "UVM_ERROR[[:space:]]*:[[:space:]]*[1-9]" "$$log_file" || \
	   grep -q -E "UVM_FATAL[[:space:]]*:[[:space:]]*[1-9]" "$$log_file" || \
	   grep -q "=== TEST FAILED ===" "$$log_file" || \
	   ! grep -q "=== TEST PASSED ===" "$$log_file"; then \
		echo "[RUN] FAILED: TEST=$(TESTNAME) DATA_WIDTH=$(DATA_WIDTH) SEED=$$run_seed"; \
		exit 1; \
	fi; \
	echo "[RUN] PASSED: TEST=$(TESTNAME) DATA_WIDTH=$(DATA_WIDTH) SEED=$$run_seed"

_regress_width: _check_width _optimize
	@echo "[REGRESS] DATA_WIDTH=$(DATA_WIDTH) TESTS=$$(printf '%s\n' $(TEST_LIST) | wc -l) RUNS=$(NUM_RUNS) JOBS=$(JOBS)"
	@mkdir -p "$(LOG_DIR)" "$(COV_DIR)" "$(STATUS_DIR)"
	@rm -f "$(STATUS_DIR)"/*.pass "$(STATUS_DIR)"/*.fail
	@$(MAKE) -j$(JOBS) $(REGRESS_TARGETS) \
		REPORT_DIR="$(REPORT_DIR)" DATA_WIDTH=$(DATA_WIDTH) \
		ADDR_WIDTH=$(ADDR_WIDTH) ID_WIDTH=$(ID_WIDTH) \
		NUM_RUNS=$(NUM_RUNS) USE_COVERAGE=$(USE_COVERAGE) \
		TEST_LIST="$(TEST_LIST)"
	@fail_count=$$(find "$(STATUS_DIR)" -maxdepth 1 -name '*.fail' | wc -l); \
	pass_count=$$(find "$(STATUS_DIR)" -maxdepth 1 -name '*.pass' | wc -l); \
	test_count=$$(printf '%s\n' $(TEST_LIST) | wc -l); \
	expected=$$((test_count * $(NUM_RUNS))); \
	actual=$$((pass_count + fail_count)); \
	printf "DATA_WIDTH=%s\nPASS=%s\nFAIL=%s\nEXPECTED=%s\n" \
		"$(DATA_WIDTH)" "$$pass_count" "$$fail_count" "$$expected" \
		> "$(REPORT_DIR)/summary.txt"; \
	echo "[REGRESS] PASS=$$pass_count FAIL=$$fail_count EXPECTED=$$expected"; \
	if [ $$actual -ne $$expected ]; then \
		echo "[REGRESS] ERROR: result marker count is incomplete."; \
		exit 1; \
	fi; \
	if [ $$fail_count -ne 0 ]; then \
		echo "[REGRESS] FAILED runs:"; \
		for file in "$(STATUS_DIR)"/*.fail; do [ -e "$$file" ] && cat "$$file"; done; \
		exit 1; \
	fi; \
	echo "[REGRESS] PASSED at DATA_WIDTH=$(DATA_WIDTH)."

# Hoang Ho: individual parallel runs never return failure directly. Each run
# writes one .pass or .fail marker; _regress_width checks the exact marker count
# after every parallel process has completed.
$(REGRESS_TARGETS):
	@test_name=$(word 1,$(subst _run_, ,$@)); \
	run_idx=$(word 2,$(subst _run_, ,$@)); \
	seed=$$(shuf -i 1-99999999 -n 1); \
	log_file="$(LOG_DIR)/$${test_name}_run_$${run_idx}_seed_$${seed}.log"; \
	ucdb_file="$(COV_DIR)/$${test_name}_run_$${run_idx}_seed_$${seed}.ucdb"; \
	status_base="$(STATUS_DIR)/$${test_name}_run_$${run_idx}_seed_$${seed}"; \
	if [ "$(USE_COVERAGE)" = "1" ]; then \
		do_cmd="coverage save -onexit $$ucdb_file; run -all; quit -f"; \
	else \
		do_cmd="run -all; quit -f"; \
	fi; \
	echo "[REGRESS-RUN] TEST=$$test_name RUN=$$run_idx SEED=$$seed DATA_WIDTH=$(DATA_WIDTH)"; \
	vsim $(VSIM_FLAGS) -sv_seed $$seed \
		+UVM_TESTNAME=$$test_name \
		+UVM_VERBOSITY=$(UVM_VERBOSITY) \
		$(REGRESS_PLUSARGS) -l "$$log_file" \
		-do "$$do_cmd" opt_tb_top; \
	status=$$?; \
	if [ $$status -ne 0 ] || [ ! -f "$$log_file" ] || \
	   grep -q -E "UVM_ERROR[[:space:]]*:[[:space:]]*[1-9]" "$$log_file" || \
	   grep -q -E "UVM_FATAL[[:space:]]*:[[:space:]]*[1-9]" "$$log_file" || \
	   grep -q "=== TEST FAILED ===" "$$log_file" || \
	   ! grep -q "=== TEST PASSED ===" "$$log_file"; then \
		echo "$$test_name run=$$run_idx seed=$$seed log=$$log_file" > "$${status_base}.fail"; \
		echo "              ==> $$test_name (Run $$run_idx) [FAILED]"; \
	else \
		echo "$$test_name run=$$run_idx seed=$$seed log=$$log_file" > "$${status_base}.pass"; \
		echo "              ==> $$test_name (Run $$run_idx) [PASSED]"; \
	fi
