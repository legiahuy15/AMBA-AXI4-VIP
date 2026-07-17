# AXI4 VIP-to-VIP — Full Testcase List

This project contains **30 UVM test classes**:

- **24 Huy Le baseline tests**: 1 base/infrastructure class + 23 executable tests.
- **6 Hoang Ho extension tests**: all executable.
- **Default regression**: 29 executable tests. `axi4_base_test` is inherited by the other tests and is not run directly.

## 1. Huy Le baseline — 24 test classes

| ID | Testcase | Category | Main objective |
|---|---|---|---|
| TC-00 | `axi4_base_test` | Infrastructure | Builds the UVM environment, agents, scoreboard, coverage, configuration, and common pass/fail reporting. Not run directly in the default regression. |
| TC-01 | `axi4_sanity_test` | Sanity | Basic write-then-read-back connectivity across AW/W/B/AR/R; sequence knobs obey transaction size/burst/4KB legality. |
| TC-02 | `axi4_data_integrity_test` | Directed | Writes known data patterns and checks exact read-back data. |
| TC-03 | `axi4_addr_integrity_test` | Directed / Checker | Checks burst-address progression and byte-lane mapping with an independent reference model. |
| TC-04 | `axi4_all_burst_type_test` | Directed | Exercises FIXED, INCR, and WRAP bursts. |
| TC-05 | `axi4_burst_sweep_test` | Sweep | Sweeps legal burst type, length, and transfer-size combinations. |
| TC-06 | `axi4_narrow_burst_test` | Directed | Verifies narrow transfers where `AxSIZE` is smaller than the data-bus width. |
| TC-07 | `axi4_unaligned_test` | Directed | Verifies read/write transfers starting at unaligned addresses. |
| TC-08 | `axi4_strobe_test` | Directed | Checks full, sparse, partial, and zero-subset `WSTRB` behavior. |
| TC-09 | `axi4_cache_prot_test` | Sweep | Sweeps `AxCACHE` and `AxPROT` encodings and checks transport/stability. |
| TC-10 | `axi4_back_to_back_test` | Directed | Issues consecutive writes and reads without unnecessary idle gaps. |
| TC-11 | `axi4_outstanding_test` | Stress | Keeps multiple read/write transactions outstanding and checks completion tracking. |
| TC-12 | `axi4_out_of_order_test` | Directed | Verifies different-ID out-of-order completion and ID-based response matching. |
| TC-13 | `axi4_ooo_demo_test` | Demo | Produces a short deterministic waveform showing different-ID out-of-order completion. |
| TC-14 | `axi4_exclusive_test` | Directed | Verifies successful and failed exclusive accesses with EXOKAY/OKAY behavior. |
| TC-15 | `axi4_exclusive_demo_test` | Demo | Produces a compact exclusive-access waveform for learning and documentation. |
| TC-16 | `axi4_exclusive_fail_test` | Corner | Checks reservation invalidation by an intervening normal store. |
| TC-17 | `axi4_illegal_exclusive_test` | Negative | Injects illegal exclusive attributes and checks protocol-error detection. |
| TC-18 | `axi4_error_response_test` | Directed | Exercises OKAY, SLVERR, and DECERR response regions. |
| TC-19 | `axi4_random_test` | Random | Generates mixed constrained-random read/write traffic for stress and coverage. |
| TC-20 | `axi4_backpressure_test` | Stress | Applies slave-side READY/response delays and checks VALID/payload stability. |
| TC-21 | `axi4_reset_mid_burst_test` | Corner | Asserts reset while traffic is active and verifies clean post-reset recovery. |
| TC-22 | `axi4_wr_order_demo_test` | Demo | Demonstrates PARALLEL, AW-before-W, and W-before-AW write-channel ordering. |
| TC-23 | `axi4_wlast_before_aw_test` | Corner / Checker | Exercises legal W-before-AW overlap and the WLAST-before-AW checker path. |

## 2. Hoang Ho extension — 6 new executable tests

| ID | Testcase | Category | Main objective |
|---|---|---|---|
| HH-TC-01 | `axi4_helper_unit_test` | Directed / Helper | Checks FIXED/INCR/WRAP address, legal byte lanes, exact 4KB equations, and staged sequence legality at the page edge. |
| HH-TC-02 | `axi4_spec_corner_test` | Directed / Corner | Verifies continuous `WREADY`, corrected unaligned lanes, page-edge WRAP behavior, and same-ID ordering. |
| HH-TC-03 | `axi4_4kb_boundary_test` | Directed / Boundary | Exercises legal bursts near a 4KB edge and detects illegal boundary crossing. |
| HH-TC-04 | `axi4_response_backpressure_test` | Stress | Applies master-side `BREADY`/`RREADY` stalls and checks response payload stability and completion. |
| HH-TC-05 | `axi4_read_interleaving_test` | Directed / Stress | Verifies beat-level read-data interleaving across three different RIDs, `RREADY` stalls, and FIFO ordering for transactions with the same ID. |
| HH-TC-06 | `axi4_width_scaling_test` | Width Matrix | Verifies full-width data and every byte lane for 32/64/128/256/512/1024-bit data buses. |

## 3. Huy Le tests strengthened by Hoang Ho

These remain Huy Le baseline testcases; Hoang Ho corrected or extended their implementation/checking:

| Testcase(s) | Improvement |
|---|---|
| `axi4_addr_integrity_test` | Independent expected model now handles the first unaligned beat without modulo-wrapping bytes into the same data word. |
| `axi4_random_test`, `axi4_burst_sweep_test` | Solver-native legality constraints avoid false randomization failures on QuestaSim 10.6b. |
| `axi4_outstanding_test`, `axi4_out_of_order_test` | Per-RID reconstruction and same-ID FIFO ordering are checked more strictly. |
| `axi4_unaligned_test`, `axi4_strobe_test` | Legal byte lanes and `WSTRB` masks use the corrected AXI4 lane equations. |
| `axi4_backpressure_test` | Payload-stability and response-dependency checks were strengthened. |
| `axi4_reset_mid_burst_test` | Reset cleanup includes the new read scheduler and pending per-ID state. |
| `axi4_data_integrity_test`, `axi4_exclusive_demo_test` | Recognizable 32-bit constants are expanded across all data lanes at wider bus widths. |

## 4. Simplified regression composition

| Command | Runs |
|---|---:|
| `make run TESTNAME=<test> DATA_WIDTH=<width> SEED=<seed>` | 1 selected executable test |
| `make regress DATA_WIDTH=<width> NUM_RUNS=1` | 29 runs at one selected width |
| `make regress DATA_WIDTH=<width> NUM_RUNS=5 JOBS=8` | 145 runs at one selected width |
| `make regress DATA_WIDTH=ALL NUM_RUNS=1 JOBS=8` | 174 runs — 29 tests × 6 widths |
| `make regress_all NUM_RUNS=5 JOBS=8` | 870 runs — 29 tests × 6 widths × 5 seeds |

The supported width list is:

```text
32, 64, 128, 256, 512, 1024 bits
```

Use `256`, not `264`.

All directed corner tests, helper tests, response-backpressure tests, read-interleaving tests, and width-scaling tests are already included in the default 29-test `TEST_LIST`. Separate smoke and release targets are therefore unnecessary in R3.

## 5. Recommended verification order

One selected test:

```bash
cd sim
make run TESTNAME=axi4_sanity_test DATA_WIDTH=64 SEED=random
```

Full baseline regression:

```bash
make regress DATA_WIDTH=32 NUM_RUNS=5 JOBS=8
make cov_report DATA_WIDTH=32
```

Full release matrix:

```bash
make clean_all
make regress DATA_WIDTH=ALL NUM_RUNS=1 JOBS=8
```

A publishable result must show zero unexpected `UVM_ERROR`/`UVM_FATAL`, zero scoreboard mismatch, zero pending transaction, exactly 29 PASS markers per width for `NUM_RUNS=1`, and reviewed coverage for each elaborated width used for coverage sign-off.
