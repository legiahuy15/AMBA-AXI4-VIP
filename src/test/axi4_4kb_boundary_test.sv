//Hoang Ho: New file: 4KB boundary directed test
//==============================================================================
// File        : axi4_4kb_boundary_test.sv
// Project     : AXI4 VIP
// Contributor : Hoang Ho
// Based on    : Huy Le / legiahuy15 axi4_base_test infrastructure
// Description : Positive directed test for legal near-4KB-boundary bursts.
//==============================================================================

`ifndef AXI4_4KB_BOUNDARY_TEST_INCLUDED_
`define AXI4_4KB_BOUNDARY_TEST_INCLUDED_

class axi4_4kb_boundary_test extends axi4_base_test;

    `uvm_component_utils(axi4_4kb_boundary_test)

    function new(string name = "axi4_4kb_boundary_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    task run_phase(uvm_phase phase);
        axi4_4kb_boundary_seq seq;

        phase.raise_objection(this, "axi4_4kb_boundary_test: starting");
        `uvm_info(get_type_name(), "Starting legal 4KB-boundary directed test", UVM_LOW)

        seq = axi4_4kb_boundary_seq::type_id::create("seq");
        if (seq == null) begin
            `uvm_fatal(get_type_name(), "Failed to create axi4_4kb_boundary_seq")
        end

        seq.start(env.master_agent.sqr);

        repeat (100) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(), "4KB-boundary directed test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_4kb_boundary_test: complete");
    endtask : run_phase

endclass : axi4_4kb_boundary_test

`endif // AXI4_4KB_BOUNDARY_TEST_INCLUDED_
