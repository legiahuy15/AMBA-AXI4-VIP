# AMBA AXI4 Full UVM VIP-to-VIP

A self-contained AXI4 Full learning and verification environment derived from Huy Le's original repository. The current release connects one active master VIP directly to one active slave VIP through `axi4_if`; no DUT or protocol bridge is included.

This is a protocol-oriented learning VIP, not an Arm-certified commercial VIP.

## Scope

- Topology: active AXI4 master VIP ↔ active AXI4 slave VIP.
- Address width: 32 bits.
- ID width: 4 bits.
- Data widths: 32/64/128/256/512/1024 bits.
- Later versions: AXI4 DUT integration, AXI4-to-AXI4-Lite, and AXI4-to-AHB5 verification.

`DATA_WIDTH=256` is valid. `DATA_WIDTH=264` is not supported.

## Ownership

- **Huy Le:** original interface, UVM architecture, agents, drivers, monitors, scoreboard, coverage, SVA, memory model, sequences, tests, and regression foundation.
- **Hoang Ho:** AXI4 protocol corrections, read interleaving, width scaling, generic data patterns, stronger checking, reproducible seeds, and the simplified release flow.

Original headers remain attributed to Huy Le. New or substantially changed teaching code uses concise `// Hoang Ho:` comments. Important retained behavior is marked with `// Huy Le:` where useful.

## Main features

- All five AXI4 channels and independent VALID/READY handshakes.
- FIXED, INCR, and WRAP bursts.
- Narrow and unaligned transfers.
- Exact 4KB boundary checking.
- Legal `WSTRB` byte lanes.
- Outstanding transactions and different-ID out-of-order completion.
- Same-ID FIFO ordering.
- Beat-level read interleaving across different RIDs.
- Response backpressure and stalled-payload stability.
- OKAY, EXOKAY, SLVERR, and DECERR.
- Simplified exclusive-access learning model.
- Compile-time data width from 32 to 1024 bits.

## Test inventory

- 30 UVM test classes.
- 24 Huy Le baseline classes, including `axi4_base_test`.
- 6 Hoang Ho extension classes.
- 29 executable tests in the default regression.

Full inventory: [`README_FULL_TESTCASES.md`](README_FULL_TESTCASES.md)

## Simplified Makefile

The public workflow has six command groups. Internal compile and helper targets are hidden behind them.

### 1. Run one test

```bash
cd sim
make run TESTNAME=axi4_sanity_test DATA_WIDTH=32 SEED=random
```

Other valid widths:

```bash
make run TESTNAME=axi4_sanity_test DATA_WIDTH=64
make run TESTNAME=axi4_width_scaling_test DATA_WIDTH=128 SEED=1
make run TESTNAME=axi4_read_interleaving_test DATA_WIDTH=1024 SEED=1
```

A random seed is generated once and reused in the console, Questa command, log name, UCDB name, waveform name, and PASS/FAIL message.

### 2. Open GUI

```bash
make gui TESTNAME=axi4_read_interleaving_test DATA_WIDTH=64 SEED=1
```

### 3. Run regression

One selected width:

```bash
make regress DATA_WIDTH=32 NUM_RUNS=5 JOBS=8
make regress DATA_WIDTH=256 NUM_RUNS=1 JOBS=8
```

All six widths:

```bash
make regress DATA_WIDTH=ALL NUM_RUNS=1 JOBS=8
```

Equivalent alias:

```bash
make regress_all NUM_RUNS=1 JOBS=8
```

The all-width campaign runs:

```text
29 tests × 6 widths × NUM_RUNS
```

With `NUM_RUNS=1`, the expected result is 174 successful simulations. Widths elaborate sequentially; tests within one width run in parallel. Results from every width are retained even when a previous width fails, unless `FAIL_FAST=1` is selected.

### 4. Clean

Selected width only:

```bash
make clean DATA_WIDTH=64
```

All generated results:

```bash
make clean_all
```

### 5. Merge coverage

Default one-width regression directory:

```bash
make merge_cov DATA_WIDTH=64
```

Selected all-width result:

```bash
make merge_cov REPORT_DIR=./results/regress_all/w64
```

Do not merge UCDB files from different data widths.

### 6. Generate coverage report

```bash
make cov_report DATA_WIDTH=64
```

Or:

```bash
make cov_report REPORT_DIR=./results/regress_all/w64
```

Generated HTML:

```text
<REPORT_DIR>/cov_html/index.html
```

Detailed command guide: [`doc/MAKEFILE_GUIDE.md`](doc/MAKEFILE_GUIDE.md)

## Result directories

```text
sim/results/
├── run/w<width>/
├── gui/w<width>/
├── regress/w<width>/
└── regress_all/
    ├── w32/
    ├── w64/
    ├── w128/
    ├── w256/
    ├── w512/
    ├── w1024/
    └── summary.txt
```

## Release verification

The R2 source completed the full 29-test regression independently at 32, 64, 128, 256, 512, and 1024 bits:

```text
174/174 simulations passed
```

Release R3 keeps the same verified protocol code and simplifies only the public Makefile workflow, result paths, and documentation. Re-run the following after copying R3 to the server:

```bash
cd sim
make clean_all
make regress DATA_WIDTH=ALL NUM_RUNS=1 JOBS=8
```

For a stronger baseline campaign:

```bash
make regress DATA_WIDTH=32 NUM_RUNS=5 JOBS=8
make cov_report DATA_WIDTH=32
```

## Documentation

- [`doc/MAKEFILE_GUIDE.md`](doc/MAKEFILE_GUIDE.md)
- [`doc/AXI4_FULL_VPLAN.md`](doc/AXI4_FULL_VPLAN.md)
- [`doc/AXI4_FULL_TESTPLAN.md`](doc/AXI4_FULL_TESTPLAN.md)
- [`doc/RELEASE_NOTES_R2.md`](doc/RELEASE_NOTES_R2.md)
- [`doc/RELEASE_NOTES_R3.md`](doc/RELEASE_NOTES_R3.md)
- `doc/axi4_vip_vplan_HOANG_HO.xlsx`

## References

- Original repository: https://github.com/legiahuy15/AMBA-AXI4-VIP
- Arm AMBA AXI and ACE Protocol Specification, IHI 0022H.c
- Original MIT License and attribution are preserved.
