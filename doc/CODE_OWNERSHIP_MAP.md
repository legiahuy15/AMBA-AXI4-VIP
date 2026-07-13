# Code Ownership and Contribution Markers

This repository preserves Huy Le's original class names, file hierarchy, APIs, and default behavior wherever possible.

## Marker rule

- Existing unmarked SystemVerilog code and original file headers remain attributed to Huy Le.
- Every block added or materially changed for this contribution is marked with `//Hoang Ho`.
- Entirely new SystemVerilog files begin with `//Hoang Ho - New file`.
- Makefile changes use `# Hoang Ho` because `//` is not valid Make syntax.
- Markdown additions use `<!-- Hoang Ho -->`.

Do not remove Huy Le's author header when applying this contribution. The marker identifies a contributor patch without claiming ownership of the original project.

## New files by Hoang Ho

- `src/seq/axi4_4kb_boundary_seq.sv`
- `src/seq/axi4_spec_corner_seq.sv`
- `src/test/axi4_4kb_boundary_test.sv`
- `src/test/axi4_response_backpressure_test.sv`
- `src/test/axi4_spec_corner_test.sv`
- `src/test/axi4_helper_unit_test.sv`
- `doc/AXI4_FULL_VPLAN.md`
- `doc/AXI4_FULL_TESTPLAN.md`
- `doc/HUY_LE_VS_HOANG_HO_DIFF.md`
- `doc/CONTRIBUTION_GUIDE.md`

## Existing files extended with marked blocks

- `src/cfg/axi4_types.sv`: common address, byte-lane, and 4KB helpers.
- `src/cfg/axi4_transaction.sv`: exact constraints and persistent completion state.
- `src/cfg/axi4_agent_config.sv`: response backpressure, WREADY-high, and read reorder knobs.
- `src/mst/axi4_master_driver.sv`: continuous-WREADY-safe W channel and RID beat dispatcher.
- `src/mst/axi4_master_monitor.sv`: per-RID read reconstruction.
- `src/mst/axi4_master_agent.sv`: propagation of BREADY/RREADY delay knobs.
- `src/slv/axi4_slave_driver.sv`: legal lanes, same-ID response order, optional continuous WREADY, exclusive attribute matching.
- `src/slv/axi4_slave_monitor.sv`: per-RID read reconstruction.
- `src/slv/axi4_slave_agent.sv`: propagation of subordinate knobs.
- `src/env/axi4_scoreboard.sv`: robust matching, legal-lane memory model, response-driven commit, unmatched errors.
- `src/env/axi4_coverage.sv`: exact 4KB and narrow/unaligned lane coverage.
- `src/sva/axi4_sva.sv`: exact boundary/lane/dependency/order assertions.
- sequence/test/package/Makefile files containing inline `//Hoang Ho` or `# Hoang Ho` additions.
