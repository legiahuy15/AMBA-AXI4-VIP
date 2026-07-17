//Hoang Ho: New file: pure helper-function unit test
//==============================================================================
// File        : axi4_helper_unit_test.sv
// Project     : AXI4 VIP
// Contributor : Hoang Ho
// Description : Checks address, WSTRB lane, and 4KB helper functions against
//               directed values from the Arm AXI4 equations. No bus injection.
//==============================================================================

`ifndef AXI4_HELPER_UNIT_TEST_INCLUDED_
`define AXI4_HELPER_UNIT_TEST_INCLUDED_

class axi4_helper_unit_test extends axi4_base_test;

    `uvm_component_utils(axi4_helper_unit_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    task run_phase(uvm_phase phase);
        axi4_strb_t mask;
        axi4_strb_t expected_mask;
        axi4_addr_t addr_i;
        axi4_addr_t legal_page_edge_addr;
        axi4_addr_t illegal_page_edge_addr;
        int unsigned full_burst_bytes;
        axi4_write_read_back_seq wr_rd_seq;
        axi4_single_write_seq single_wr_seq;
        axi4_single_read_seq single_rd_seq;

        phase.raise_objection(this, "axi4_helper_unit_test starting");

        //Hoang Ho: Unaligned 4-byte first transfer at address 1 uses lanes 1-3.
        expected_mask = '0;
        expected_mask[1] = 1'b1;
        expected_mask[2] = 1'b1;
        expected_mask[3] = 1'b1;
        mask = axi4_calc_legal_lane_mask(axi4_addr_t'(1), 0, AXI4_SIZE_4B,
                                         AXI4_BURST_INCR, 8'd3);
        if (mask !== expected_mask)
            `uvm_error(get_type_name(), $sformatf("First-beat mask mismatch expected=%0b got=%0b", expected_mask, mask))

        expected_mask = '0;
        for (int lane = 4; lane < 8 && lane < AXI4_STRB_WIDTH; lane++)
            expected_mask[lane] = 1'b1;
        if (AXI4_STRB_WIDTH == 4)
            expected_mask = '1;
        mask = axi4_calc_legal_lane_mask(axi4_addr_t'(1), 1, AXI4_SIZE_4B,
                                         AXI4_BURST_INCR, 8'd3);
        if (mask !== expected_mask)
            `uvm_error(get_type_name(), $sformatf("Beat1 mask mismatch expected=%0b got=%0b", expected_mask, mask))

        //Hoang Ho: Unaligned narrow first transfer at lane 3 must not wrap.
        expected_mask = '0;
        expected_mask[3] = 1'b1;
        mask = axi4_calc_legal_lane_mask(axi4_addr_t'(3), 0, AXI4_SIZE_2B,
                                         AXI4_BURST_INCR, 8'd3);
        if (mask !== expected_mask)
            `uvm_error(get_type_name(), $sformatf("Narrow first-beat mask mismatch expected=%0b got=%0b", expected_mask, mask))

        //Hoang Ho: WRAP page-edge addresses: FFC, FF0, FF4, FF8.
        addr_i = axi4_calc_beat_addr(32'h0000_0FFC, 0, AXI4_SIZE_4B,
                                     AXI4_BURST_WRAP, 8'd3);
        if (addr_i !== 32'h0000_0FFC) `uvm_error(get_type_name(), "WRAP beat0 mismatch")
        addr_i = axi4_calc_beat_addr(32'h0000_0FFC, 1, AXI4_SIZE_4B,
                                     AXI4_BURST_WRAP, 8'd3);
        if (addr_i !== 32'h0000_0FF0) `uvm_error(get_type_name(), "WRAP beat1 mismatch")
        addr_i = axi4_calc_beat_addr(32'h0000_0FFC, 2, AXI4_SIZE_4B,
                                     AXI4_BURST_WRAP, 8'd3);
        if (addr_i !== 32'h0000_0FF4) `uvm_error(get_type_name(), "WRAP beat2 mismatch")
        addr_i = axi4_calc_beat_addr(32'h0000_0FFC, 3, AXI4_SIZE_4B,
                                     AXI4_BURST_WRAP, 8'd3);
        if (addr_i !== 32'h0000_0FF8) `uvm_error(get_type_name(), "WRAP beat3 mismatch")

        if (axi4_burst_crosses_4kb(32'h0000_0FFC, AXI4_SIZE_4B,
                                    AXI4_BURST_WRAP, 8'd3))
            `uvm_error(get_type_name(), "Legal page-edge WRAP incorrectly classified as crossing 4KB")

        if (!axi4_burst_crosses_4kb(32'h0000_0FF4, AXI4_SIZE_4B,
                                     AXI4_BURST_INCR, 8'd3))
            `uvm_error(get_type_name(), "Illegal INCR crossing was not detected")

        // Hoang Ho: regression for staged sequence randomization.
        //
        // A sequence object randomizes addr/len/size/burst before its body
        // randomizes axi4_transaction with equality constraints. The sequence
        // must therefore reject the same illegal 4KB tuple as the transaction.
        // Sixteen full-width beats are used so the check automatically scales
        // from DATA_WIDTH=32 through DATA_WIDTH=1024.
        full_burst_bytes      = AXI4_STRB_WIDTH * 16;
        legal_page_edge_addr  = axi4_addr_t'(4096 - full_burst_bytes);
        illegal_page_edge_addr = axi4_addr_t'(legal_page_edge_addr + AXI4_STRB_WIDTH);

        wr_rd_seq = axi4_write_read_back_seq::type_id::create("wr_rd_seq");
        if (!wr_rd_seq.randomize() with {
            addr  == local::legal_page_edge_addr;
            len   == 8'd15;
            size  == axi4_size_e'(AXI4_MAX_SIZE);
            burst == AXI4_BURST_INCR;
        })
            `uvm_error(get_type_name(),
                       "write_read_back sequence rejected a legal page-edge INCR burst")

        if (wr_rd_seq.randomize() with {
            addr  == local::illegal_page_edge_addr;
            len   == 8'd15;
            size  == axi4_size_e'(AXI4_MAX_SIZE);
            burst == AXI4_BURST_INCR;
        })
            `uvm_error(get_type_name(),
                       "write_read_back sequence accepted an INCR burst that crosses 4KB")

        single_wr_seq = axi4_single_write_seq::type_id::create("single_wr_seq");
        if (!single_wr_seq.randomize() with {
            addr  == local::legal_page_edge_addr;
            len   == 8'd15;
            size  == axi4_size_e'(AXI4_MAX_SIZE);
            burst == AXI4_BURST_INCR;
        })
            `uvm_error(get_type_name(),
                       "single_write sequence rejected a legal page-edge INCR burst")

        if (single_wr_seq.randomize() with {
            addr  == local::illegal_page_edge_addr;
            len   == 8'd15;
            size  == axi4_size_e'(AXI4_MAX_SIZE);
            burst == AXI4_BURST_INCR;
        })
            `uvm_error(get_type_name(),
                       "single_write sequence accepted an INCR burst that crosses 4KB")

        single_rd_seq = axi4_single_read_seq::type_id::create("single_rd_seq");
        if (!single_rd_seq.randomize() with {
            addr  == local::legal_page_edge_addr;
            len   == 8'd15;
            size  == axi4_size_e'(AXI4_MAX_SIZE);
            burst == AXI4_BURST_INCR;
        })
            `uvm_error(get_type_name(),
                       "single_read sequence rejected a legal page-edge INCR burst")

        if (single_rd_seq.randomize() with {
            addr  == local::illegal_page_edge_addr;
            len   == 8'd15;
            size  == axi4_size_e'(AXI4_MAX_SIZE);
            burst == AXI4_BURST_INCR;
        })
            `uvm_error(get_type_name(),
                       "single_read sequence accepted an INCR burst that crosses 4KB")

        `uvm_info(get_type_name(),
                  $sformatf("Sequence-level 4KB legality checked: DATA=%0d legal=0x%08h illegal=0x%08h",
                            AXI4_DATA_WIDTH, legal_page_edge_addr,
                            illegal_page_edge_addr),
                  UVM_LOW)

        repeat (5) @(posedge env_cfg.master_vif.clk);
        phase.drop_objection(this, "axi4_helper_unit_test complete");
    endtask : run_phase

endclass : axi4_helper_unit_test

`endif // AXI4_HELPER_UNIT_TEST_INCLUDED_
