# AXI4 Learning VIP – Concise Verification Plan

## Scope
- Environment: Huy Le's self-contained master-VIP to slave-VIP UVM project.
- Goal: core AXI4 memory-mapped functional correctness for learning and project verification.
- Reference: Arm AMBA AXI and ACE Protocol Specification, IHI 0022H.c.

## Huy Le baseline

| Area | Existing implementation | Main tests |
|---|---|---|
| Architecture | master agent, slave agent, interface, monitors, scoreboard, coverage, SVA | `axi4_sanity_test` |
| Channels | AW, W, B, AR, R VALID/READY handling | sanity, backpressure |
| Bursts | FIXED, INCR, WRAP and burst sweep | all-burst, burst-sweep |
| Outstanding/OOO | multiple requests and different-ID response matching | outstanding, OOO |
| Responses | OKAY, EXOKAY, SLVERR, DECERR | error, exclusive |
| Data checks | WSTRB, memory model, read-back | strobe, data-integrity |
| Recovery | reset and configurable delays | reset-mid-burst, backpressure |

## Hoang Ho additions

| Area | Addition or correction | Main test/check | Status |
|---|---|---|---|
| Byte lanes | correct narrow and unaligned first-beat lane mask | helper, unaligned, spec-corner | Done |
| Burst address | shared FIXED/INCR/WRAP beat-address helpers | helper, all-burst | Done |
| 4KB boundary | exact burst-container check, including page-edge WRAP | 4KB, helper | Done |
| W channel | prevent repeated beat when `WREADY` remains HIGH | spec-corner | Done |
| Read receive | dispatch each R beat by `RID` | driver/monitor checks | Done |
| Same-ID order | preserve request order for one ID | spec-corner | Done |
| Different-ID OOO | retain legal whole-burst reordering | OOO tests | Done |
| B/R dependency | require eligible AW+WLAST before B and prior AR before R | SVA | Done |
| WSTRB | reject strobes outside legal lanes | SVA, slave, scoreboard | Done |
| Exclusive | strengthen EXOKAY and reservation checks | exclusive tests | Done |
| Backpressure | directed BREADY/RREADY stalls | response-backpressure | Done |
| Regression | `spec_smoke`, non-zero fail status, clean UCDB merge | Makefile | Done |
| Read interleaving | receiver accepts cross-ID beat interleaving | per-RID tracking | Receive only |

## Sign-off gate

```bash
cd sim
make clean
make spec_smoke
make -j8 regress NUM_RUNS=5
make cov_report
```

Accept the learning profile only when:

- compile and optimize complete without errors;
- `spec_smoke` and the positive regression pass;
- no unexpected `UVM_ERROR` or `UVM_FATAL` remains;
- scoreboard and monitors have no pending transactions;
- functional coverage is reviewed against the implemented scope.

## Declared limits

- Default slave does not generate beat-level R interleaving.
- USER, ACE/coherency, AXI5 atomic features, and full interconnect behavior are out of scope.
- Optional cache/protection/QoS/region fields are pass-through only.
- This is a learning VIP, not a commercial compliance certificate.
