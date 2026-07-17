# Simplified Makefile Guide

The Makefile exposes six command groups. Compile, optimize, static source checking, seed handling, result checking, and parallel-run helpers are internal.

## Supported widths

```text
32 64 128 256 512 1024
```

Use `256`, not `264`.

## 1. `make run`

Runs one UVM testcase at one selected width.

```bash
make run TESTNAME=axi4_sanity_test DATA_WIDTH=64 SEED=random
```

Important variables:

| Variable | Meaning | Default |
|---|---|---:|
| `TESTNAME` | UVM test class | `axi4_sanity_test` |
| `DATA_WIDTH` | Compiled AXI4 data width | `32` |
| `SEED` | Fixed integer or `random` | `random` |
| `USE_COVERAGE` | Enable UCDB collection | `1` |
| `UVM_VERBOSITY` | UVM log level | `UVM_LOW` |

Output:

```text
results/run/w<width>/
```

## 2. `make gui`

Compiles the selected width and opens Questa GUI with `wave.do`.

```bash
make gui TESTNAME=axi4_read_interleaving_test DATA_WIDTH=128 SEED=1
```

Output log:

```text
results/gui/w<width>/logs/
```

## 3. `make regress`

Runs all 29 executable tests at one selected width.

```bash
make regress DATA_WIDTH=64 NUM_RUNS=5 JOBS=8
```

Expected run count:

```text
29 × NUM_RUNS
```

Result:

```text
results/regress/w64/
```

### All widths

```bash
make regress DATA_WIDTH=ALL NUM_RUNS=1 JOBS=8
```

Equivalent:

```bash
make regress_all NUM_RUNS=1 JOBS=8
```

Expected run count with one seed:

```text
29 × 6 = 174
```

Result:

```text
results/regress_all/w32/
...
results/regress_all/w1024/
results/regress_all/summary.txt
```

`FAIL_FAST=0` continues through every width and returns failure at the end when any profile failed. `FAIL_FAST=1` stops at the first failed width.

## 4. `make clean`

Selected width:

```bash
make clean DATA_WIDTH=64
```

Removes work files plus run, GUI, one-width regression, and all-width regression results for width 64.

All generated outputs:

```bash
make clean_all
```

## 5. `make merge_cov`

Merges UCDB files from one elaborated width.

```bash
make merge_cov DATA_WIDTH=64
```

This defaults to:

```text
results/regress/w64/coverage/
```

For an all-width campaign profile:

```bash
make merge_cov REPORT_DIR=./results/regress_all/w64
```

Never merge different widths into one UCDB.

## 6. `make cov_report`

Merges coverage and creates HTML.

```bash
make cov_report DATA_WIDTH=64
```

Or:

```bash
make cov_report REPORT_DIR=./results/regress_all/w64
```

Output:

```text
<REPORT_DIR>/cov_html/index.html
```

## Recommended release command

```bash
make clean_all && \
make regress DATA_WIDTH=ALL NUM_RUNS=1 JOBS=8
```

Stronger 32-bit randomized baseline:

```bash
make regress DATA_WIDTH=32 NUM_RUNS=5 JOBS=8
make cov_report DATA_WIDTH=32
```
