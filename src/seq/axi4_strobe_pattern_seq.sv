//==============================================================================
// File        : axi4_strobe_pattern_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 write-strobe pattern sequence.
//               Exercises full, zero, walking-one, and half-bus WSTRB values.
//               Hoang Ho generalized the original 4-lane test so every byte
//               lane is covered at DATA_WIDTH=32..1024.
//==============================================================================

`ifndef AXI4_STROBE_PATTERN_SEQ_INCLUDED_
`define AXI4_STROBE_PATTERN_SEQ_INCLUDED_

class axi4_strobe_pattern_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_strobe_pattern_seq)

    function new(string name = "axi4_strobe_pattern_seq");
        super.new(name);
    endfunction : new

    //Hoang Ho: send one aligned, full-width write with an explicit strobe.
    protected task send_pattern(string name_i, axi4_strb_t pattern_i, int unsigned offset_i);
        axi4_transaction tr;
        axi4_addr_t aligned_addr;

        aligned_addr = axi4_addr_t'(32'h0000_5000 + offset_i * AXI4_STRB_WIDTH);
        tr = axi4_transaction::type_id::create(name_i);
        start_item(tr);
        if (!tr.randomize() with {
            dir   == AXI4_WRITE;
            addr  == aligned_addr;
            id    inside {[id_lo : id_hi]};
            size  == axi4_size_e'(AXI4_MAX_SIZE);
            burst == AXI4_BURST_INCR;
            len   == 0;
            strb[0] == pattern_i;
        }) `uvm_fatal(get_type_name(), $sformatf("Randomization failed for %s", name_i))
        finish_item(tr);
        wait (tr.completed);
    endtask : send_pattern

    virtual task body();
        axi4_strb_t pattern;
        int unsigned pattern_idx;

        `uvm_info(get_type_name(),
                  $sformatf("Starting width-scalable WSTRB test (%0d lanes)", AXI4_STRB_WIDTH),
                  UVM_MEDIUM)

        pattern_idx = 0;

        //Huy Le baseline intent: all bytes and no bytes enabled.
        send_pattern("strb_all_tr",  '1, pattern_idx++);
        send_pattern("strb_none_tr", '0, pattern_idx++);

        //Hoang Ho: walking one covers each byte lane on 32..1024-bit buses.
        for (int lane = 0; lane < AXI4_STRB_WIDTH; lane++) begin
            pattern = '0;
            pattern[lane] = 1'b1;
            send_pattern($sformatf("strb_lane_%0d", lane), pattern, pattern_idx++);
        end

        //Hoang Ho: contiguous lower and upper halves exercise wide partial writes.
        pattern = '0;
        for (int lane = 0; lane < AXI4_STRB_WIDTH/2; lane++)
            pattern[lane] = 1'b1;
        send_pattern("strb_lower_half", pattern, pattern_idx++);

        pattern = '0;
        for (int lane = AXI4_STRB_WIDTH/2; lane < AXI4_STRB_WIDTH; lane++)
            pattern[lane] = 1'b1;
        send_pattern("strb_upper_half", pattern, pattern_idx++);

        `uvm_info(get_type_name(),
                  $sformatf("WSTRB test complete: %0d patterns", pattern_idx),
                  UVM_MEDIUM)
    endtask : body

endclass : axi4_strobe_pattern_seq

`endif // AXI4_STROBE_PATTERN_SEQ_INCLUDED_
