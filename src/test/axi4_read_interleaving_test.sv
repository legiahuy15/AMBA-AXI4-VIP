//Hoang Ho: end-to-end read-data interleaving and same-ID ordering test.
`ifndef AXI4_READ_INTERLEAVING_TEST_INCLUDED_
`define AXI4_READ_INTERLEAVING_TEST_INCLUDED_

class axi4_read_interleaving_test extends axi4_base_test;
    `uvm_component_utils(axi4_read_interleaving_test)

    bit capture_enable;
    bit stop_capture;
    int unsigned interleave_switches;
    int unsigned r_stall_cycles;
    int unsigned unique_rids;
    bit have_previous;
    axi4_id_t previous_rid;
    bit previous_last;
    bit rid_seen[axi4_id_t];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env_cfg.slave_agent_cfg.r_interleave_enable      = 1;
        env_cfg.slave_agent_cfg.r_reorder_enable         = 0;
        env_cfg.slave_agent_cfg.r_interleave_start_depth = 3;
        env_cfg.slave_agent_cfg.r_interleave_start_wait  = 24;
        env_cfg.slave_agent_cfg.r_outstanding_max        = 8;
        env_cfg.master_agent_cfg.rready_delay_min        = 1;
        env_cfg.master_agent_cfg.rready_delay_max        = 3;
    endfunction

    task capture_r_channel();
        forever begin
            @(env_cfg.master_vif.monitor_cb);
            if (stop_capture)
                return;
            if (!capture_enable)
                continue;

            if (env_cfg.master_vif.monitor_cb.RVALID &&
                !env_cfg.master_vif.monitor_cb.RREADY)
                r_stall_cycles++;

            if (env_cfg.master_vif.monitor_cb.RVALID &&
                env_cfg.master_vif.monitor_cb.RREADY) begin
                if (!rid_seen.exists(env_cfg.master_vif.monitor_cb.RID)) begin
                    rid_seen[env_cfg.master_vif.monitor_cb.RID] = 1'b1;
                    unique_rids++;
                end
                if (have_previous && !previous_last &&
                    env_cfg.master_vif.monitor_cb.RID != previous_rid)
                    interleave_switches++;
                have_previous = 1;
                previous_rid  = env_cfg.master_vif.monitor_cb.RID;
                previous_last = env_cfg.master_vif.monitor_cb.RLAST;
            end
        end
    endtask : capture_r_channel

    task reset_capture();
        interleave_switches = 0;
        r_stall_cycles      = 0;
        unique_rids         = 0;
        have_previous       = 0;
        previous_rid        = '0;
        previous_last       = 1;
        rid_seen.delete();
    endtask

    task run_phase(uvm_phase phase);
        axi4_read_interleaving_seq seq_cross_id;
        axi4_read_interleaving_seq seq_same_id;

        phase.raise_objection(this, "read interleaving test");
        stop_capture   = 0;
        capture_enable = 0;
        fork
            capture_r_channel();
        join_none

        // Phase A: three different IDs, mixed lengths and deterministic stalls.
        reset_capture();
        capture_enable = 1;
        seq_cross_id = axi4_read_interleaving_seq::type_id::create("seq_cross_id");
        seq_cross_id.same_id_mode = 0;
        seq_cross_id.num_beats_a  = 8;
        seq_cross_id.num_beats_b  = 4;
        seq_cross_id.num_beats_c  = 2;
        seq_cross_id.start(env.master_agent.sqr);
        capture_enable = 0;

        if (seq_cross_id.errors != 0)
            `uvm_error(get_type_name(), $sformatf("Cross-ID sequence errors=%0d", seq_cross_id.errors))
        if (unique_rids < 3)
            `uvm_error(get_type_name(), $sformatf("Expected 3 active RIDs, observed %0d", unique_rids))
        if (interleave_switches < 2)
            `uvm_error(get_type_name(),
                       $sformatf("Insufficient cross-ID interleaving: switches=%0d", interleave_switches))
        if (r_stall_cycles == 0)
            `uvm_error(get_type_name(), "RREADY backpressure was not exercised")

        // Phase B: the same RID is used twice. Distinct data patterns make any
        // response mixing or overtaking visible to the sequence checker.
        env.slave_agent.drv.r_interleave_start_depth = 1;
        seq_same_id = axi4_read_interleaving_seq::type_id::create("seq_same_id");
        seq_same_id.same_id_mode = 1;
        seq_same_id.num_beats_a  = 4;
        seq_same_id.num_beats_b  = 4;
        seq_same_id.start(env.master_agent.sqr);
        if (seq_same_id.errors != 0)
            `uvm_error(get_type_name(), $sformatf("Same-ID sequence errors=%0d", seq_same_id.errors))

        repeat (20) @(env_cfg.master_vif.monitor_cb);
        stop_capture = 1;
        @(env_cfg.master_vif.monitor_cb);
        disable fork;

        `uvm_info(get_type_name(),
                  $sformatf("Read interleaving checked: RIDs=%0d switches=%0d stall_cycles=%0d",
                            unique_rids, interleave_switches, r_stall_cycles), UVM_LOW)
        phase.drop_objection(this, "read interleaving test complete");
    endtask : run_phase
endclass : axi4_read_interleaving_test

`endif
