//==============================================================================
// File        : axi4_outstanding_seq_test.sv (axi4_outstanding_test.sv)
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Outstanding transactions test.
//               Executes a sequence generating concurrent read and write
//               bursts to stress-test the VIP's tracking of outstanding
//               transactions and response matching.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_OUTSTANDING_TEST_INCLUDED_
`define AXI4_OUTSTANDING_TEST_INCLUDED_

class axi4_outstanding_test extends axi4_base_test;

    `uvm_component_utils(axi4_outstanding_test)

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Run phase — execute outstanding sequence
    // =========================================================================
    task run_phase(uvm_phase phase);
        axi4_outstanding_seq outstanding_seq;
        int unsigned num_writes = 15;
        int unsigned num_reads  = 15;
        int unsigned depth      = 4;

        phase.raise_objection(this, "axi4_outstanding_test: starting");

        // Allow command-line overrides
        void'($value$plusargs("NUM_WRITES=%d", num_writes));
        void'($value$plusargs("NUM_READS=%d", num_reads));
        void'($value$plusargs("OUTSTANDING_DEPTH=%d", depth));

        `uvm_info(get_type_name(),
                  $sformatf("Starting outstanding test with %0d writes, %0d reads, depth=%0d",
                            num_writes, num_reads, depth),
                  UVM_LOW)

        // Create outstanding sequence
        outstanding_seq = axi4_outstanding_seq::type_id::create("outstanding_seq");
        outstanding_seq.num_writes        = num_writes;
        outstanding_seq.num_reads         = num_reads;
        outstanding_seq.outstanding_depth = depth;

        // Start sequence on master sequencer
        outstanding_seq.start(env.master_agent.sqr);

        // Drain time — wait for outstanding responses to complete
        repeat (100) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(), "Outstanding test completed successfully", UVM_LOW)

        phase.drop_objection(this, "axi4_outstanding_test: complete");
    endtask : run_phase

endclass : axi4_outstanding_test

`endif // AXI4_OUTSTANDING_TEST_INCLUDED_