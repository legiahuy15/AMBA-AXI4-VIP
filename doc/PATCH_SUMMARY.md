# Hoang Ho AXI4 Functional Patch Summary

This patch keeps the original learning-oriented VIP-to-VIP architecture and focuses on mandatory/core AXI4 behavior.

## Functional corrections

- exact Arm burst address calculation for FIXED, INCR, and WRAP;
- correct first-beat byte lanes for unaligned and narrow transfers;
- exact 4KB burst-container checking, including legal page-edge WRAP;
- continuous-WREADY-safe master write-data loop;
- RID-based read reception and monitor reconstruction;
- same-ID read response order preservation;
- paired AW/W completion and BID eligibility checks;
- AR-before-R checking using pre-existing outstanding state;
- legal WSTRB enforcement in constraints, SVA, slave, scoreboard, and coverage;
- stronger EXOKAY/exclusive attribute checking;
- completed transaction flag to eliminate missed event waits;
- unmatched monitor/scoreboard traffic promoted to errors.

## Regression and documentation

- new helper unit test and functional corner test;
- page-edge 4KB/WRAP vectors;
- fixed response-backpressure seeds retained as directed gates;
- `make spec_smoke` target;
- non-zero Make exit on UVM errors/fatals;
- safe UCDB merge/report regeneration;
- updated VPlan, test plan, ownership map, and contribution guide.
