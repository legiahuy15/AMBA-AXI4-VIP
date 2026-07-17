# AXI4 Full VIP-to-VIP Verification Plan

## Scope

- Active AXI4 master VIP connected directly to active AXI4 slave VIP.
- Core AXI4 memory-mapped functional rules from Arm IHI 0022H.c.
- Address width 32, ID width 4, data widths 32/64/128/256/512/1024.
- Optional system semantics are default/pass-through or out of scope.

## Huy Le baseline

| Area | Existing implementation | Main verification |
|---|---|---|
| Environment | interface, agents, monitors, scoreboard, SVA, coverage | sanity test |
| Channels | AW/W/B/AR/R VALID/READY | sanity, backpressure |
| Bursts | FIXED/INCR/WRAP | burst tests |
| Concurrency | outstanding and different-ID OOO | outstanding, OOO |
| Responses | OKAY/EXOKAY/SLVERR/DECERR | error, exclusive |
| Data/recovery | memory, WSTRB, reset, delays | integrity, strobe, reset |

## Hoang Ho additions and corrections

| Requirement | Implementation | Verification |
|---|---|---|
| Correct beat address and 4KB boundary | shared FIXED/INCR/WRAP helpers | helper, 4KB, SVA |
| Correct unaligned/narrow lanes | legal lane mask without modulo wrap | helper, unaligned, address integrity |
| Legal WSTRB | post-randomize mask plus runtime checks | strobe, random, SVA |
| Continuous WREADY | advance W payload after each handshake | specification corner |
| Same-ID ordering | only head request of one ID can respond | outstanding, interleaving |
| Beat-level read interleaving | round-robin R scheduler across active RIDs | read-interleaving test |
| R-channel stall stability | selected beat held until handshake | SVA, interleaving |
| Width scaling | shared compile configuration and lane-complete patterns | width-scaling test |
| Legacy known patterns | 32-bit marker expanded across full bus | data integrity, exclusive, corner |
| Reproducible seed | one resolved seed per simulation | Makefile log/name check |
| Staged sequence legality | sequence knobs mirror transaction size/burst/4KB rules | helper and sanity |
| Simplified release flow | six public Makefile command groups | one-width and all-width regression |

## Verification campaigns

### One selected testcase

`make run` verifies one test at one selected data width. It is used for debug, fixed-seed reproduction, and targeted waveform collection.

### One-width full regression

For one selected width:

- compile one elaborated model;
- run all 29 executable tests;
- run `NUM_RUNS` seeds per test;
- require exactly one PASS or FAIL marker per expected run;
- retain logs, status, UCDB, and summary under `results/regress/w<width>/`.

### All-width full regression

`make regress DATA_WIDTH=ALL` or `make regress_all` repeats the complete regression independently at 32, 64, 128, 256, 512, and 1024 bits.

Default count with one seed:

```text
29 tests × 6 widths = 174 simulations
```

Widths elaborate sequentially. Tests inside one width run in parallel. Every width result is retained. With `FAIL_FAST=0`, later widths continue after a failure and the command returns failure after the final summary.

## Acceptance criteria

### Protocol

- zero unexpected `UVM_ERROR` and `UVM_FATAL`;
- zero scoreboard mismatch and zero unmatched transaction;
- VALID payload stable through stalls;
- exact beat count and WLAST/RLAST behavior;
- no legal burst crosses a 4KB boundary;
- no WSTRB bit selects an illegal byte lane;
- same-ID responses remain ordered;
- different-ID read data can interleave legally;
- EXOKAY only for successful exclusive accesses.

### Width matrix

For 32/64/128/256/512/1024 bits:

- `WSTRB_WIDTH = DATA_WIDTH/8`;
- maximum legal `AxSIZE = log2(DATA_WIDTH/8)`;
- full-width data exercises every byte lane;
- intentionally narrow transfers remain legal and correctly placed;
- recognizable fixed patterns populate the complete data bus;
- all 29 executable tests pass independently.

### Regression infrastructure

- one printed seed identifies one simulation everywhere;
- every expected run produces exactly one `.pass` or `.fail` marker;
- one width never overwrites another width's result;
- coverage databases from different widths are never merged together;
- sequence-level randomization cannot select a size/burst/4KB tuple rejected by the transaction.

## Release commands

One-width baseline:

```bash
cd sim
make clean DATA_WIDTH=32
make regress DATA_WIDTH=32 NUM_RUNS=5 JOBS=8
make cov_report DATA_WIDTH=32
```

Complete width matrix:

```bash
make clean_all
make regress DATA_WIDTH=ALL NUM_RUNS=1 JOBS=8
```

## Limits

- VIP-to-VIP only; no DUT or bridge topology in this release.
- No Arm certification claim.
- USER, ACE/coherency, AXI5 atomics, AXI-Stream, and full interconnect behavior are out of scope.
- Cache/protection/QoS/region fields are transported and checked without system-level semantics.
