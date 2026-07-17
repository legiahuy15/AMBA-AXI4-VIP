# AXI4 Full VIP-to-VIP Test Plan

## Test inventory

- 30 UVM test classes.
- 29 executable tests in the default regression.
- 24 Huy Le baseline classes, including the infrastructure base test.
- 6 Hoang Ho extension tests.

See [`../README_FULL_TESTCASES.md`](../README_FULL_TESTCASES.md) for the full list.

## Huy Le baseline tests

Sanity, random, burst, narrow, unaligned, strobe, outstanding, OOO, exclusive, error, reset, integrity, write-order, and backpressure tests remain in `TEST_LIST`.

## Hoang Ho tests

| Test | Purpose | Pass criteria |
|---|---|---|
| `axi4_helper_unit_test` | address/lane/4KB equations plus staged sequence legality | helpers match; legal edge tuple accepted; crossing tuple rejected |
| `axi4_4kb_boundary_test` | legal and crossing page-edge bursts | legal accepted; crossing detected |
| `axi4_spec_corner_test` | continuous WREADY and corrected corners | no duplicate beat or mismatch |
| `axi4_response_backpressure_test` | B/R stalls | stable payload and complete drain |
| `axi4_read_interleaving_test` | 3-RID interleaving and same-ID order | switches/stalls hit; data/RLAST correct |
| `axi4_width_scaling_test` | 32..1024-bit data bus | full-width and every-lane read-back correct |

## Width-generic improvements to baseline tests

| Huy Le scenario | Hoang Ho update |
|---|---|
| `axi4_data_integrity_test` | legacy low-word patterns expanded across every 32-bit chunk |
| `axi4_exclusive_demo_test` | full-width exclusive transfer and legal width-scaled WSTRB |
| `axi4_4kb_boundary_test` | deterministic seed data expanded across the full bus |
| `axi4_spec_corner_test` | deterministic corner data expanded across the full bus |
| narrow/unaligned tests | remain intentionally narrow; shared lane equations scale with bus width |
| random/burst/outstanding tests | randomized data vectors scale with `AXI4_DATA_WIDTH` |
| sanity/single read/single write sequences | sequence knobs mirror transaction size, FIXED/WRAP, and 4KB legality |

## Read-interleaving scenarios

1. Three different IDs use mixed 8-, 4-, and 2-beat INCR reads.
2. RID changes before the previous burst reaches RLAST.
3. `RREADY` stalls for 1–3 cycles; payload remains stable.
4. Two reads with the same ID remain FIFO ordered.
5. Scoreboard and monitors reconstruct each burst by RID with zero mismatch.

## Width scenarios

For every supported width:

1. Full-width INCR beats write/read unique data in every lane.
2. A 1-byte INCR burst visits every byte lane once.
3. Read interleaving is repeated at the compiled width.
4. All 29 executable tests are run by the all-width regression.

## Simplified campaigns

| Command | Scope | Default runs |
|---|---|---:|
| `make run TESTNAME=<t> DATA_WIDTH=<w> SEED=random` | one reproducible run | 1 |
| `make regress DATA_WIDTH=<w> NUM_RUNS=1` | all tests at one width | 29 |
| `make regress DATA_WIDTH=32 NUM_RUNS=5 JOBS=8` | baseline randomized regression | 145 |
| `make regress DATA_WIDTH=ALL NUM_RUNS=1 JOBS=8` | all tests at all widths | 174 |
| `make regress_all NUM_RUNS=5 JOBS=8` | five seeds at all widths | 870 |

## Result preservation

```text
results/regress/w<width>/
results/regress_all/w32/ ... w1024/
results/regress_all/summary.txt
```

Each regression directory contains compile/optimization logs, per-run logs, status markers, coverage when enabled, and a summary. Parallel regression does not dump VCD by default. Different widths use independent elaborated models and independent coverage directories.

## SVA and coverage targets

- address/control/data stability during stalls;
- B only after accepted AW and final W;
- R only after an outstanding AR for that RID;
- per-RID RLAST count;
- legal AxSIZE, burst type, WRAP length/alignment, and 4KB boundary;
- legal WSTRB lanes;
- EXOKAY only for exclusive accesses;
- different-RID interleaving and interleaving after an R stall;
- start-lane, full-width, and narrow-size coverage;
- legal/illegal page-edge randomization for write-read-back, single-write, and single-read wrappers.

## Publication gate

```bash
cd sim
make clean_all
make regress DATA_WIDTH=ALL NUM_RUNS=1 JOBS=8
make regress DATA_WIDTH=32 NUM_RUNS=5 JOBS=8
make cov_report DATA_WIDTH=32
```

The result must contain zero unexpected `UVM_ERROR`/`UVM_FATAL`, zero scoreboard mismatch, no pending transaction, and the exact expected PASS-marker count.
