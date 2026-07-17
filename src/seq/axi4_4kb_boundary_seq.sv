// Hoang Ho: New file: 4KB boundary directed sequence
//==============================================================================
// File        : axi4_4kb_boundary_seq.sv
// Project     : AXI4 VIP
// Contributor : Hoang Ho
// Based on    : Huy Le / legiahuy15 AXI4-VIP public APIs and base sequence
// Description : Directed legal near-4KB-boundary sequence.
//               Exercises legal AXI4 bursts that end at or near a 4KB boundary.
//               No randomize() is used here, so the sequence is stable on older
//               simulators such as QuestaSim 10.6b.
//==============================================================================

`ifndef AXI4_4KB_BOUNDARY_SEQ_INCLUDED_
`define AXI4_4KB_BOUNDARY_SEQ_INCLUDED_

class axi4_4kb_boundary_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_4kb_boundary_seq)

    function new(string name = "axi4_4kb_boundary_seq");
        super.new(name);
    endfunction : new

    // -------------------------------------------------------------------------
    // Local helper: calculate beat address for FIXED/INCR/WRAP bursts.
    // This keeps the directed sequence independent from transaction helper
    // functions and avoids inline-randomize function-scope issues.
    // -------------------------------------------------------------------------
    // Hoang Ho: Shared helper wrappers keep this sequence aligned with the
    // transaction, slave, scoreboard, coverage, and SVA implementation.
    protected function bit [AXI4_ADDR_WIDTH-1:0] local_calc_beat_addr(
        bit [AXI4_ADDR_WIDTH-1:0] start_addr,
        int unsigned              beat_idx,
        axi4_size_e               size,
        axi4_burst_type_e         burst,
        bit [7:0]                 len
    );
        return axi4_calc_beat_addr(start_addr, beat_idx, size, burst, len);
    endfunction : local_calc_beat_addr

    protected function bit [AXI4_STRB_WIDTH-1:0] local_calc_legal_wstrb_mask(
        bit [AXI4_ADDR_WIDTH-1:0] start_addr,
        int unsigned              beat_idx,
        axi4_size_e               size,
        axi4_burst_type_e         burst,
        bit [7:0]                 len
    );
        return axi4_calc_legal_lane_mask(start_addr, beat_idx, size, burst, len);
    endfunction : local_calc_legal_wstrb_mask

    // -------------------------------------------------------------------------
    // Send a legal write burst near 4KB boundary.
    // -------------------------------------------------------------------------
    protected task send_write(
        string                   tr_name,
        bit [AXI4_ID_WIDTH-1:0]  id,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        bit [7:0]                len,
        axi4_size_e              size,
        axi4_burst_type_e        burst,
        bit [31:0]               legacy_word
    );
        axi4_transaction tr;
        int unsigned beats;

        beats = len + 1;
        tr = axi4_transaction::type_id::create(tr_name);

        tr.dir      = AXI4_WRITE;
        tr.wr_order = AXI4_WR_PARALLEL;
        tr.id       = id;
        tr.addr     = addr;
        tr.len      = len;
        tr.size     = size;
        tr.burst    = burst;
        tr.lock     = AXI4_LOCK_NORMAL;
        tr.cache    = 4'h0;
        tr.prot     = 3'b000;
        tr.qos      = 4'h0;
        tr.region   = 4'h0;
        tr.resp     = AXI4_RESP_OKAY;

        tr.data  = new[beats];
        tr.strb  = new[beats];
        tr.rresp = new[0];

        for (int i = 0; i < beats; i++) begin
            tr.data[i] = axi4_expand_legacy_word(legacy_word, i);
            tr.strb[i] = local_calc_legal_wstrb_mask(addr, i, size, burst, len);
        end

        start_item(tr);
        finish_item(tr);
        wait (tr.completed); // Hoang Ho: persistent completion wait
    endtask : send_write

    // -------------------------------------------------------------------------
    // Send a matching read burst for read-back.
    // -------------------------------------------------------------------------
    protected task send_read(
        string                   tr_name,
        bit [AXI4_ID_WIDTH-1:0]  id,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        bit [7:0]                len,
        axi4_size_e              size,
        axi4_burst_type_e        burst
    );
        axi4_transaction tr;
        int unsigned beats;

        beats = len + 1;
        tr = axi4_transaction::type_id::create(tr_name);

        tr.dir      = AXI4_READ;
        tr.wr_order = AXI4_WR_PARALLEL;
        tr.id       = id;
        tr.addr     = addr;
        tr.len      = len;
        tr.size     = size;
        tr.burst    = burst;
        tr.lock     = AXI4_LOCK_NORMAL;
        tr.cache    = 4'h0;
        tr.prot     = 3'b000;
        tr.qos      = 4'h0;
        tr.region   = 4'h0;
        tr.resp     = AXI4_RESP_OKAY;

        tr.data  = new[beats];
        tr.strb  = new[0];
        tr.rresp = new[beats];

        for (int i = 0; i < beats; i++) begin
            tr.data[i]  = '0;
            tr.rresp[i] = AXI4_RESP_OKAY;
        end

        start_item(tr);
        finish_item(tr);
        wait (tr.completed); // Hoang Ho: persistent completion wait
    endtask : send_read

    virtual task body();
        `uvm_info(get_type_name(), "Starting legal 4KB boundary sequence", UVM_LOW)

        // Case 0: INCR 4 beats x 4 bytes.
        // Start 0x0FF0, total 16 bytes, last byte 0x0FFF. Legal.
        send_write("wr_4kb_incr_4beat", 4'h1, 32'h0000_0FF0,
                   8'd3, AXI4_SIZE_4B, AXI4_BURST_INCR, 32'h4B00_0000);
        send_read ("rd_4kb_incr_4beat", 4'h1, 32'h0000_0FF0,
                   8'd3, AXI4_SIZE_4B, AXI4_BURST_INCR);

        // Case 1: INCR single 1-byte transfer at the last byte of a 4KB page.
        // Start 0x0FFF, size 1 byte, single beat. Legal.
        send_write("wr_4kb_last_byte", 4'h2, 32'h0000_0FFF,
                   8'd0, AXI4_SIZE_1B, AXI4_BURST_INCR, 32'h4B00_0100);
        send_read ("rd_4kb_last_byte", 4'h2, 32'h0000_0FFF,
                   8'd0, AXI4_SIZE_1B, AXI4_BURST_INCR);

        // Case 2: WRAP 4 beats x 4 bytes inside the same 4KB page.
        send_write("wr_4kb_wrap", 4'h3, 32'h0000_0FC0,
                   8'd3, AXI4_SIZE_4B, AXI4_BURST_WRAP, 32'h4B00_0200);
        send_read ("rd_4kb_wrap", 4'h3, 32'h0000_0FC0,
                   8'd3, AXI4_SIZE_4B, AXI4_BURST_WRAP);

        // Hoang Ho: Case 2b exposes the old false 4KB failure. The WRAP
        // container is [0x0FF0:0x0FFF], although the first address is 0x0FFC.
        send_write("wr_4kb_wrap_edge", 4'h5, 32'h0000_0FFC,
                   8'd3, AXI4_SIZE_4B, AXI4_BURST_WRAP, 32'h4B00_0250);
        send_read ("rd_4kb_wrap_edge", 4'h5, 32'h0000_0FFC,
                   8'd3, AXI4_SIZE_4B, AXI4_BURST_WRAP);

        // Case 3: FIXED burst near boundary.
        // FIXED repeatedly accesses same transfer address. Legal because the
        // addressed transfer itself fits in the page.
        send_write("wr_4kb_fixed", 4'h4, 32'h0000_0FFC,
                   8'd7, AXI4_SIZE_4B, AXI4_BURST_FIXED, 32'h4B00_0300);
        send_read ("rd_4kb_fixed", 4'h4, 32'h0000_0FFC,
                   8'd7, AXI4_SIZE_4B, AXI4_BURST_FIXED);

        `uvm_info(get_type_name(), "Completed legal 4KB boundary sequence", UVM_LOW)
    endtask : body

endclass : axi4_4kb_boundary_seq

`endif // AXI4_4KB_BOUNDARY_SEQ_INCLUDED_
