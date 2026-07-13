# Hoang Ho AXI4 Functional Patch — Static Review

Date: 2026-07-12

## Target

This review targets the core functional behavior of an AXI4 Full memory-mapped learning VIP-to-VIP environment. It does not claim commercial VIP certification. Optional AxCACHE, AxPROT, AxQOS, and AxREGION fields remain pass-through/default behavior.

## Reference and baseline

- Arm AMBA AXI and ACE Protocol Specification, IHI 0022H.c.
- Public repository: `legiahuy15/AXI4-VIP`.
- Unified patch baseline: the previously tested local tree `AXI4-VIP-main_HOANG_HO_FIXED`, which already contains the response-backpressure seed repair.
- The artifact environment could inspect the public GitHub repository page but could not obtain a clean network clone. See `BASELINE_NOTE.txt`.

## Static checks completed

- Inventoried the complete `src/` tree and the positive/negative test libraries.
- Confirmed every materially changed or new SystemVerilog file contains an exact `//Hoang Ho` contribution marker.
- Confirmed entirely new SystemVerilog files begin with `//Hoang Ho - New file`.
- Confirmed package include lists contain the new sequences/tests.
- Confirmed `sim/Makefile` maps the new test names into the regression and provides `spec_smoke`.
- Confirmed the obsolete claim that AXI4 forbids read-data interleaving is removed from the contributed project.
- Confirmed event-only completion waits were replaced with persistent transaction completion state where needed.
- Confirmed common modulo byte-lane code was replaced by shared Arm-style address/lane helpers.
- Confirmed coverage merge excludes stale `merged.ucdb` and recreates the HTML directory.
- Confirmed Make dry-run expansion for help, focused smoke, regression, and coverage targets.
- Inspected the generated VPlan XLSX and PDF for formula errors and visual clipping.

## Principal functional corrections

1. Correct first-beat byte lanes for narrow and unaligned transfers.
2. Shared FIXED/INCR/WRAP address calculation.
3. Exact burst-container 4KB checking, including legal page-edge WRAP bursts.
4. Master W channel made safe when WREADY remains continuously asserted.
5. Master and monitors dispatch every accepted R beat by RID.
6. Same-ID read ordering preserved while different IDs may complete out of order.
7. BVALID/BID and RVALID/RID dependency checking strengthened.
8. WSTRB legality enforced consistently in transaction constraints, slave model, scoreboard, SVA, and coverage.
9. Failed writes do not update memory; EXOKAY is restricted to successful exclusive accesses.
10. Pending/unmatched traffic is treated as a functional failure.
11. New deterministic helper, corner, and 4KB tests added.
12. Regression shell status and coverage regeneration made fail-safe.

## Runtime validation already known

The earlier response-backpressure correction was run by the user on QuestaSim 10.6b for seeds:

- `22883092`
- `68865829`

Both runs completed with 30 master transactions, 30 slave transactions, 30 matches, zero mismatches, and zero UVM errors/fatals.

## Runtime validation not performed here

The artifact environment does not contain QuestaSim, ModelSim, VCS, Verilator, or another usable SystemVerilog/UVM simulator. Consequently, the larger Arm-functional patch has not been compiled or simulated in this environment.

Before publication, run:

```bash
cd sim
make clean
make spec_smoke
make -j8 regress NUM_RUNS=5
make cov_report
```

Expected contribution gate:

- compile/optimize: zero errors;
- focused smoke: all tests pass;
- positive regression: all runs pass;
- no unexpected `UVM_ERROR` or `UVM_FATAL`;
- no unmatched/pending transactions;
- core functional coverage at least 90%, with every remaining core miss reviewed;
- assertion/directive coverage reviewed separately from UVM macro-generated code coverage.

## Declared limitations

- USER signals, ACE/coherency, AXI5, AXI-Stream, and full interconnect routing are outside scope.
- No real cache, security, QoS arbitration, or region-decode semantics.
- Default subordinate emits one complete read burst at a time for deterministic waveforms, although receivers are RID-aware and accept legal cross-ID interleaving.
- Mixed-endian conversion is not modeled.
- Same-address concurrent read/write visibility uses a simplified declared policy; conflicting integrity tests are serialized.
- This package is suitable for learning-level functional contribution review, not commercial compliance certification.
