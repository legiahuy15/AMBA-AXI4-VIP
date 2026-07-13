//Hoang Ho - New file: BREADY/RREADY response-backpressure test
//==============================================================================
// File        : axi4_response_backpressure_test.sv
// Project     : AXI4 VIP
// Contributor : Hoang Ho
// Based on    : Huy Le / legiahuy15 axi4_base_test and axi4_random_seq APIs
// Description : Master-side BREADY/RREADY back-pressure test.
//               Complements subordinate request-channel backpressure by holding
//               BREADY/RREADY low while BVALID/RVALID payloads remain stable.
//==============================================================================

`ifndef AXI4_RESPONSE_BACKPRESSURE_TEST_INCLUDED_
`define AXI4_RESPONSE_BACKPRESSURE_TEST_INCLUDED_

class axi4_response_backpressure_test extends axi4_base_test;

    `uvm_component_utils(axi4_response_backpressure_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env_cfg.master_agent_cfg.bready_delay_min = 2;
        env_cfg.master_agent_cfg.bready_delay_max = 8;
        env_cfg.master_agent_cfg.rready_delay_min = 2;
        env_cfg.master_agent_cfg.rready_delay_max = 8;
        env_cfg.slave_agent_cfg.resp_delay_min   = 0;
        env_cfg.slave_agent_cfg.resp_delay_max   = 2;
    endfunction : build_phase

    //Hoang Ho
    // Wait for a real scoreboard completion target instead of using a fixed
    // drain delay. This catches a stuck response deterministically and avoids
    // ending the test while B/R transactions are still outstanding.
    task automatic wait_for_scoreboard_target(
        input int unsigned target_count,
        input int unsigned timeout_cycles = 200000
    );
        int unsigned cycles;

        if (env.scb == null)
            `uvm_fatal(get_type_name(),
                       "Response-backpressure test requires the scoreboard")

        cycles = 0;
        while ((env.scb.total_master < target_count) ||
               (env.scb.total_slave  < target_count) ||
               (env.scb.match_count  < target_count)) begin
            @(posedge env_cfg.master_vif.clk);
            cycles++;

            if (cycles >= timeout_cycles) begin
                `uvm_fatal(get_type_name(),
                           $sformatf({"Timeout waiting for %0d completed transactions: ",
                                      "master=%0d slave=%0d matches=%0d mismatches=%0d"},
                                     target_count,
                                     env.scb.total_master,
                                     env.scb.total_slave,
                                     env.scb.match_count,
                                     env.scb.mismatch_count))
            end
        end
    endtask : wait_for_scoreboard_target
    //Hoang Ho

    task run_phase(uvm_phase phase);
        //Hoang Ho
        axi4_random_seq wr_seq;
        axi4_random_seq rd_seq;

        phase.raise_objection(this, "axi4_response_backpressure_test: starting");
        `uvm_info(get_type_name(),
                  "Starting master-side BREADY/RREADY back-pressure test",
                  UVM_LOW)

        // Phase 1: issue 15 outstanding writes to stress BREADY backpressure.
        // Wait for every write response before starting reads. The slave commits
        // write data before B, so the scoreboard and slave memories are stable
        // and synchronized when the read phase begins.
        wr_seq = axi4_random_seq::type_id::create("resp_bp_wr_seq");
        wr_seq.num_txns = 15;
        wr_seq.addr_hi  = 32'h0000_FFFF; // avoid intentional error regions
        wr_seq.force_dir = 1'b1;
        wr_seq.fixed_dir = AXI4_WRITE;
        wr_seq.start(env.master_agent.sqr);

        wait_for_scoreboard_target(15);

        // Phase 2: issue 15 outstanding reads to stress RREADY backpressure.
        // No writes are active during this phase, so a long stalled read cannot
        // be checked against a newer, unrelated reference-memory state.
        rd_seq = axi4_random_seq::type_id::create("resp_bp_rd_seq");
        rd_seq.num_txns = 15;
        rd_seq.addr_hi  = 32'h0000_FFFF; // avoid intentional error regions
        rd_seq.force_dir = 1'b1;
        rd_seq.fixed_dir = AXI4_READ;
        rd_seq.start(env.master_agent.sqr);

        wait_for_scoreboard_target(30);

        // Small deterministic monitor/analysis drain after all 30 matches.
        repeat (10) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(),
                  "Response back-pressure test complete: 15 writes + 15 reads",
                  UVM_LOW)
        //Hoang Ho
        phase.drop_objection(this, "axi4_response_backpressure_test: complete");
    endtask : run_phase

endclass : axi4_response_backpressure_test

`endif // AXI4_RESPONSE_BACKPRESSURE_TEST_INCLUDED_
