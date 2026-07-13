//Hoang Ho - New file: pure helper-function unit test
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
        bit [AXI4_STRB_WIDTH-1:0] mask;
        bit [AXI4_ADDR_WIDTH-1:0] addr_i;

        phase.raise_objection(this, "axi4_helper_unit_test starting");

        //Hoang Ho - Unaligned 4-byte first transfer at address 1 uses lanes 1-3.
        mask = axi4_calc_legal_lane_mask(32'h1, 0, AXI4_SIZE_4B,
                                         AXI4_BURST_INCR, 8'd3);
        if (mask !== 4'b1110)
            `uvm_error(get_type_name(), $sformatf("Expected mask 1110, got %0b", mask))

        mask = axi4_calc_legal_lane_mask(32'h1, 1, AXI4_SIZE_4B,
                                         AXI4_BURST_INCR, 8'd3);
        if (mask !== 4'b1111)
            `uvm_error(get_type_name(), $sformatf("Expected beat1 mask 1111, got %0b", mask))

        //Hoang Ho - Unaligned narrow first transfer at lane 3 must not wrap.
        mask = axi4_calc_legal_lane_mask(32'h3, 0, AXI4_SIZE_2B,
                                         AXI4_BURST_INCR, 8'd3);
        if (mask !== 4'b1000)
            `uvm_error(get_type_name(), $sformatf("Expected mask 1000, got %0b", mask))

        //Hoang Ho - WRAP page-edge addresses: FFC, FF0, FF4, FF8.
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

        repeat (5) @(posedge env_cfg.master_vif.clk);
        phase.drop_objection(this, "axi4_helper_unit_test complete");
    endtask : run_phase

endclass : axi4_helper_unit_test

`endif // AXI4_HELPER_UNIT_TEST_INCLUDED_
