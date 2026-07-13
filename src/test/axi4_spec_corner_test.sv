//Hoang Ho - New file: functional AXI4 corner regression test
//==============================================================================
// File        : axi4_spec_corner_test.sv
// Project     : AXI4 VIP
// Contributor : Hoang Ho
// Description : Runs the directed spec-corner sequence while the subordinate
//               keeps WREADY continuously HIGH and allows different-ID read
//               completion reordering. Optional AXI attributes stay at default.
//==============================================================================

`ifndef AXI4_SPEC_CORNER_TEST_INCLUDED_
`define AXI4_SPEC_CORNER_TEST_INCLUDED_

class axi4_spec_corner_test extends axi4_base_test;

    `uvm_component_utils(axi4_spec_corner_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        //Hoang Ho - These knobs default to zero in all original Huy Le tests.
        env_cfg.slave_agent_cfg.wready_always_high = 1'b1;
        env_cfg.slave_agent_cfg.r_reorder_enable   = 1'b1;
        env_cfg.slave_agent_cfg.r_outstanding_max  = 4;
    endfunction : build_phase

    task run_phase(uvm_phase phase);
        axi4_spec_corner_seq seq;
        int unsigned timeout_cycles;

        phase.raise_objection(this, "axi4_spec_corner_test starting");
        seq = axi4_spec_corner_seq::type_id::create("seq");

        fork
            begin
                seq.start(env.master_agent.sqr);
            end
            begin
                timeout_cycles = 100000;
                repeat (timeout_cycles) @(posedge env_cfg.master_vif.clk);
                `uvm_fatal(get_type_name(), "Timeout waiting for AXI4 spec-corner sequence")
            end
        join_any
        disable fork;

        //Hoang Ho - drain monitor/scoreboard analysis FIFOs deterministically.
        repeat (20) @(posedge env_cfg.master_vif.clk);
        phase.drop_objection(this, "axi4_spec_corner_test complete");
    endtask : run_phase

endclass : axi4_spec_corner_test

`endif // AXI4_SPEC_CORNER_TEST_INCLUDED_
