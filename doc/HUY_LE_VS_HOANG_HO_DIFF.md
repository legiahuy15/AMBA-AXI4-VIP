# Huy Le Original Project vs Hoang Ho Functional Fix

## Compatibility strategy

The contribution is intentionally incremental. It does not rename Huy Le's public classes, interface signals, package names, test base classes, or normal Make targets. New behavior is default-off when it could alter original waveform timing.

| Topic | Original Huy Le project behavior | Hoang Ho contribution |
|---|---|---|
| Architecture | self-contained active master VIP connected to active slave VIP | preserved |
| File/API compatibility | existing package, agents, environment, tests | preserved; new includes appended |
| Unaligned WSTRB | lane calculation could wrap modulo the bus width | exact first-transfer lower/upper lane equations |
| Narrow transfer | shared modulo behavior could select an illegal lane | legal mask shared by transaction, slave, scoreboard, SVA, coverage |
| 4KB rule | `start_offset + total_bytes` approximation | FIXED/INCR/WRAP container-based check |
| Page-edge WRAP | legal WRAP could be rejected | accepted; directed `0x0FFC` vector added |
| Master W channel | extra cycle could repeat a beat when WREADY stayed HIGH | payload advances immediately after each handshake |
| Read receiving | assumed one RID until RLAST | every beat dispatched by RID; cross-ID interleaving accepted |
| Default read generation | one complete R burst at a time | preserved for simple waveforms |
| Same-ID read order | concurrent preparation could let a later request acquire the R channel first | AR-order sequence counters prevent overtaking |
| B dependency | coarse total counters | paired AW/W completion and BID eligibility |
| R dependency | same-cycle AR could incorrectly justify RVALID | R checked against pre-existing AR state |
| EXOKAY | partial checking | EXOKAY restricted to outstanding exclusive requests |
| Scoreboard matching | weaker key and common lane arithmetic | full functional key and legal-lane byte memory |
| End-of-test pending traffic | warnings possible | functional error |
| Sequence completion | event-only wait could miss a pulse | persistent `completed` state plus original event retained |
| Regression result | report could retain old UCDB and shell status was weak | stale merge excluded, HTML regenerated, non-zero fail status |
| VPlan | limited feature mapping | current feature/test/assertion/coverage traceability |

## Important correction to the original README

The original README states that read-data interleaving is unsupported because it was removed from AXI3. AXI4 removed write-data interleaving and therefore has no WID, but read-data transfers can still be interleaved between different IDs when the subordinate supports that behavior. The updated receivers accept such traffic. The default learning subordinate remains non-interleaving by declaration.

## Remaining learning-profile limits

This contribution does not turn the project into a commercial protocol-compliance product. It does not model USER signals, coherent protocols, real cache/QoS/security behavior, full interconnect routing, mixed-endian conversion, or every optional AXI property. Same-address concurrent read/write ordering is intentionally not assigned a universal memory-system policy.
