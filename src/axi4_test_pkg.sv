//==============================================================================
// File        : axi4_test_pkg.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Test package for AXI4 VIP.
//               Imports axi4_pkg (VIP core) and includes all test classes.
//==============================================================================

`ifndef AXI4_TEST_PKG_INCLUDED_
`define AXI4_TEST_PKG_INCLUDED_

package axi4_test_pkg;

    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import axi4_pkg::*;

    // =========================================================================
    // Tests  (src/test/)
    // =========================================================================
    `include "test/axi4_base_test.sv"
    `include "test/axi4_sanity_test.sv"
    `include "test/axi4_random_test.sv"
    `include "test/axi4_outstanding_test.sv"
    `include "test/axi4_out_of_order_test.sv"
    `include "test/axi4_exclusive_test.sv"
    `include "test/axi4_unaligned_test.sv"
    `include "test/axi4_cache_prot_test.sv"
    `include "test/axi4_strobe_test.sv"
    `include "test/axi4_burst_sweep_test.sv"

endpackage : axi4_test_pkg

`endif // AXI4_TEST_PKG_INCLUDED_