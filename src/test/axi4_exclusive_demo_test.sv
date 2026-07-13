//==============================================================================
// File        : axi4_exclusive_demo_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Exclusive access demo test for waveform capture.
//               Runs the exclusive sequence for exactly ONE iteration at a
//               fixed address and ID, producing a clean three-transaction
//               window:
//                 1. Exclusive read   -> RRESP = EXOKAY
//                 2. Exclusive write  -> BRESP = EXOKAY (reservation held)
//                 3. Exclusive write  -> BRESP = OKAY   (no reservation)
//               Minimal, deterministic traffic - ideal for report/slide
//               waveform illustration of AWLOCK/ARLOCK and EXOKAY resolution.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_EXCLUSIVE_DEMO_TEST_INCLUDED_
`define AXI4_EXCLUSIVE_DEMO_TEST_INCLUDED_

class axi4_exclusive_demo_test extends axi4_base_test;

    `uvm_component_utils(axi4_exclusive_demo_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    task run_phase(uvm_phase phase);
        axi4_exclusive_seq excl_seq;
        phase.raise_objection(this, "axi4_exclusive_demo_test: starting");

        `uvm_info(get_type_name(),
                  "Starting exclusive demo test (1 iteration, fixed addr/ID)",
                  UVM_LOW)

        excl_seq = axi4_exclusive_seq::type_id::create("excl_seq");
        // Single iteration -> exactly 3 transactions for a clean waveform
        excl_seq.num_iterations = 1;
        // Pin address and ID: urandom_range(x,x) == x -> deterministic
        excl_seq.addr_lo = 32'h0000_1000;
        excl_seq.addr_hi = 32'h0000_1000;
        excl_seq.id_lo   = 4'h5;
        excl_seq.id_hi   = 4'h5;

        excl_seq.start(env.master_agent.sqr);

        // Drain time
        repeat (60) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(), "Exclusive demo test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_exclusive_demo_test: complete");
    endtask : run_phase

endclass : axi4_exclusive_demo_test

`endif // AXI4_EXCLUSIVE_DEMO_TEST_INCLUDED_
