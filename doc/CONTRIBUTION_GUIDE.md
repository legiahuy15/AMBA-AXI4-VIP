# Contribution Guide

## Applying the patch

1. Start from a clean clone of `legiahuy15/AXI4-VIP`.
2. Apply the supplied unified diff or copy the complete project tree.
3. Keep all original Huy Le author headers.
4. Keep `//Hoang Ho` markers around contributed SystemVerilog blocks.
5. Run the directed gate, then the full regression.

```bash
git checkout -b fix/axi4-functional-corners
patch -p1 < HOANG_HO_ARM_FUNCTIONAL_FIX.patch
cd sim
make clean
make spec_smoke
make -j8 regress NUM_RUNS=5
make cov_report
```

## Suggested pull request split

For easier review, the work can be contributed as four commits:

1. Shared Arm address/lane/4KB helpers and transaction constraints.
2. Driver/monitor/slave/scoreboard/SVA functional fixes.
3. Directed sequences/tests and Makefile fail-safe regression.
4. VPlan, test plan, ownership map, and comparison notes.

## Evidence to attach to the pull request

- compile and optimize logs with zero errors;
- `make spec_smoke` log;
- complete positive regression summary;
- coverage HTML summary;
- focused waveforms for continuous WREADY, page-edge WRAP, same-ID reads, BREADY/RREADY stalls;
- a note that optional attributes remain pass-through/default behavior.

## Review warning

This package was statically reviewed in the artifact-generation environment, which does not contain QuestaSim. The contributor must rerun compilation and regression on the project server before opening the pull request.
