<!-- Hoang Ho - Updated test plan for the AXI4 functional-compliance extension -->
# AXI4 Full Learning VIP Test Plan

## Positive regression

| Test | Primary purpose | Key checks |
|---|---|---|
| `axi4_sanity_test` | basic write/read | five-channel flow and read-back |
| `axi4_random_test` | random mixed traffic | general constraints and transaction matching |
| `axi4_all_burst_type_test` | burst types | FIXED, INCR, WRAP |
| `axi4_burst_sweep_test` | length/size sweep | beat count, LAST, address progression |
| `axi4_narrow_burst_test` | narrow transfers | legal byte lanes for `AxSIZE < bus width` |
| `axi4_unaligned_test` | unaligned first transfer | first-beat lane masking and address progression |
| `axi4_strobe_test` | WSTRB patterns | full, partial, sparse, zero-subset behavior |
| `axi4_4kb_boundary_test` | legal page-edge bursts | INCR/FIXED/WRAP exact 4KB rule |
| `axi4_helper_unit_test` | pure helper vectors | unaligned masks, WRAP addresses, legal/illegal 4KB classification |
| `axi4_spec_corner_test` | Hoang Ho directed functional gate | continuous WREADY, unaligned/narrow/FIXED/WRAP edge, same-ID order |
| `axi4_outstanding_test` | multiple in-flight requests | pending queues and completion |
| `axi4_out_of_order_test` | different-ID OOO | whole-burst OOO and ID matching |
| `axi4_ooo_demo_test` | deterministic OOO waveform | AR order differs from RID completion order |
| `axi4_back_to_back_test` | pipelined issue | adjacent handshakes without artificial gaps |
| `axi4_backpressure_test` | subordinate backpressure | AWREADY/WREADY/ARREADY and response latency |
| `axi4_response_backpressure_test` | manager backpressure | BREADY/RREADY stalls and response stability |
| `axi4_wr_order_demo_test` | AW/W independence | parallel, AW-before-W, W-before-AW |
| `axi4_wlast_before_aw_test` | leading W data | W burst buffered before AW |
| `axi4_error_response_test` | error responses | SLVERR/DECERR and no failed-write commit |
| `axi4_exclusive_test` | exclusive success | reservation and EXOKAY |
| `axi4_exclusive_fail_test` | exclusive failure | invalidation and failed store |
| `axi4_illegal_exclusive_test` | illegal exclusive attributes | checker errors/response policy |
| `axi4_cache_prot_test` | optional attribute transport | stable/pass-through/cache-prot coverage |
| `axi4_reset_mid_burst_test` | reset recovery | VALID reset, queue cleanup, no stale completion |
| `axi4_data_integrity_test` | known data | byte-level write/read comparison |
| `axi4_addr_integrity_test` | known address map | address-to-data mapping |
| `axi4_exclusive_demo_test` | deterministic exclusive waveform | successful exclusive pair |

## Directed vectors added by Hoang Ho

`axi4_helper_unit_test` checks these exact equations without depending on bus timing:

- `ADDR=0x1`, `SIZE=4B`, first INCR beat -> legal lane mask `1110`.
- `ADDR=0x3`, `SIZE=2B`, first INCR beat -> legal lane mask `1000`.
- WRAP start `0x0FFC`, 4 beats x 4 bytes -> `0x0FFC, 0x0FF0, 0x0FF4, 0x0FF8`.
- The page-edge WRAP above is legal and does not cross 4KB.
- INCR start `0x0FF4`, 4 beats x 4 bytes crosses 4KB and is illegal.

`axi4_spec_corner_test` adds bus-level read-back for the same lane/address cases, keeps WREADY continuously HIGH to detect duplicated W beats, and issues two same-ID reads concurrently to prove response order.

## Negative/SVA lane

Negative runs must be reported separately from the all-pass positive regression.

| Negative scenario | Current mechanism | Pass criterion |
|---|---|---|
| missing/late WLAST with W-before-AW | `make sva_unit` | expected assertion fires only in the intentional violation phase |
| reserved AxBURST | SVA | `AWBURST_VALID`/`ARBURST_VALID` fires |
| invalid size | SVA | `AWSIZE_VALID`/`ARSIZE_VALID` fires |
| illegal WRAP length/alignment | SVA | WRAP assertions fire |
| 4KB crossing | SVA/helper | boundary checker fires |
| WSTRB outside legal lanes | SVA/slave/scoreboard | checker reports error, memory not committed |
| premature BVALID/BID | transaction-aware SVA | no eligible completed write assertion fires |
| premature RVALID/RID | per-ID SVA | no prior AR assertion fires |
| EXOKAY on normal access | SVA | EXOKAY legality assertion fires |

## Required commands

```bash
cd sim
make clean
make spec_smoke
make -j8 regress NUM_RUNS=5
make cov_report
```

For focused debug:

```bash
make run TESTNAME=axi4_spec_corner_test SEED=1
make run TESTNAME=axi4_helper_unit_test SEED=1
make run TESTNAME=axi4_response_backpressure_test SEED=22883092
make run TESTNAME=axi4_response_backpressure_test SEED=68865829
```

The Makefile returns non-zero when the simulator fails or the UVM summary contains any non-zero UVM_ERROR/UVM_FATAL count.
