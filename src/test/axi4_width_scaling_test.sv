//Hoang Ho: new test: validates every byte lane at the compiled AXI4 width.
`ifndef AXI4_WIDTH_SCALING_TEST_INCLUDED_
`define AXI4_WIDTH_SCALING_TEST_INCLUDED_

class axi4_width_scaling_test extends axi4_base_test;
    `uvm_component_utils(axi4_width_scaling_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axi4_width_scaling_seq seq;
        phase.raise_objection(this, "width scaling test");
        seq = axi4_width_scaling_seq::type_id::create("seq");
        seq.start(env.master_agent.sqr);
        if (seq.errors != 0)
            `uvm_error(get_type_name(), $sformatf("Width-scaling errors=%0d", seq.errors))
        repeat (10) @(env_cfg.master_vif.monitor_cb);
        phase.drop_objection(this, "width scaling test complete");
    endtask
endclass : axi4_width_scaling_test

`endif
