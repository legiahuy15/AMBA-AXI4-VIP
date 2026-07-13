//Hoang Ho - New file: directed AXI4 functional corner sequence
//==============================================================================
// File        : axi4_spec_corner_seq.sv
// Project     : AXI4 VIP
// Contributor : Hoang Ho
// Description : Directed positive tests for the functional fixes added on top
//               of Huy Le's original learning VIP:
//                 - unaligned full-width and narrow byte lanes
//                 - unaligned FIXED byte lanes
//                 - legal WRAP burst at the end of a 4KB page
//                 - same-ID read response ordering
//                 - multi-beat transfer with continuously asserted WREADY
//==============================================================================

`ifndef AXI4_SPEC_CORNER_SEQ_INCLUDED_
`define AXI4_SPEC_CORNER_SEQ_INCLUDED_

class axi4_spec_corner_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_spec_corner_seq)

    function new(string name = "axi4_spec_corner_seq");
        super.new(name);
    endfunction : new

    //Hoang Ho - Populate fields explicitly so the corner vectors stay stable
    // across random seeds and old simulators.
    protected function void init_common(
        axi4_transaction         tr,
        axi4_dir_e               dir_i,
        bit [AXI4_ID_WIDTH-1:0]  id_i,
        bit [AXI4_ADDR_WIDTH-1:0] addr_i,
        bit [7:0]                len_i,
        axi4_size_e              size_i,
        axi4_burst_type_e        burst_i
    );
        tr.dir      = dir_i;
        tr.wr_order = AXI4_WR_PARALLEL;
        tr.id       = id_i;
        tr.addr     = addr_i;
        tr.len      = len_i;
        tr.size     = size_i;
        tr.burst    = burst_i;
        tr.lock     = AXI4_LOCK_NORMAL;
        tr.cache    = 4'h0;
        tr.prot     = 3'b000;
        tr.qos      = 4'h0;
        tr.region   = 4'h0;
        tr.resp     = AXI4_RESP_OKAY;
        tr.completed = 1'b0;
        tr.completion_time = 0;
    endfunction : init_common

    //Hoang Ho - Questa 10.6b compatibility: explicitly declare every
    // argument direction. In an ANSI task declaration, an omitted direction
    // inherits the previous formal direction. Because the first argument is
    // output, the old declaration accidentally made name_i..wait_done output.
    protected task issue_write(
        output axi4_transaction    tr,
        input  string              name_i,
        input  bit [AXI4_ID_WIDTH-1:0]    id_i,
        input  bit [AXI4_ADDR_WIDTH-1:0]  addr_i,
        input  bit [7:0]           len_i,
        input  axi4_size_e         size_i,
        input  axi4_burst_type_e   burst_i,
        input  bit [31:0]          data_seed,
        input  bit                 wait_done = 1'b1
    );
        tr = axi4_transaction::type_id::create(name_i);
        init_common(tr, AXI4_WRITE, id_i, addr_i, len_i, size_i, burst_i);
        tr.data  = new[len_i + 1];
        tr.strb  = new[len_i + 1];
        tr.rresp = new[0];

        for (int beat = 0; beat <= len_i; beat++) begin
            tr.data[beat] = data_seed + (32'h0101_0101 * beat);
            tr.strb[beat] = axi4_calc_legal_lane_mask(addr_i, beat, size_i,
                                                      burst_i, len_i);
        end

        start_item(tr);
        finish_item(tr);
        if (wait_done)
            wait (tr.completed);
    endtask : issue_write

    //Hoang Ho - Explicit input directions prevent the output direction of tr
    // from propagating to the remaining formals on older Questa versions.
    protected task issue_read(
        output axi4_transaction    tr,
        input  string              name_i,
        input  bit [AXI4_ID_WIDTH-1:0]    id_i,
        input  bit [AXI4_ADDR_WIDTH-1:0]  addr_i,
        input  bit [7:0]           len_i,
        input  axi4_size_e         size_i,
        input  axi4_burst_type_e   burst_i,
        input  bit                 wait_done = 1'b1
    );
        tr = axi4_transaction::type_id::create(name_i);
        init_common(tr, AXI4_READ, id_i, addr_i, len_i, size_i, burst_i);
        tr.data  = new[len_i + 1];
        tr.strb  = new[0];
        tr.rresp = new[len_i + 1];
        foreach (tr.rresp[i])
            tr.rresp[i] = AXI4_RESP_OKAY;

        start_item(tr);
        finish_item(tr);
        if (wait_done)
            wait (tr.completed);
    endtask : issue_read

    protected task write_then_read(
        string                    tag,
        bit [AXI4_ID_WIDTH-1:0]   id_i,
        bit [AXI4_ADDR_WIDTH-1:0] addr_i,
        bit [7:0]                 len_i,
        axi4_size_e               size_i,
        axi4_burst_type_e         burst_i,
        bit [31:0]                data_seed
    );
        axi4_transaction wr;
        axi4_transaction rd;
        issue_write(wr, {tag, "_wr"}, id_i, addr_i, len_i,
                    size_i, burst_i, data_seed, 1'b1);
        issue_read(rd, {tag, "_rd"}, id_i, addr_i, len_i,
                   size_i, burst_i, 1'b1);
    endtask : write_then_read

    virtual task body();
        axi4_transaction wr_a;
        axi4_transaction wr_b;
        axi4_transaction rd_first;
        axi4_transaction rd_second;

        `uvm_info(get_type_name(), "Starting Hoang Ho AXI4 spec-corner sequence", UVM_LOW)

        // Full-width 4-byte transfer starting at byte lane 1. First-beat legal
        // mask is 4'b1110, not 4'b1111 and never wraps to lane 0.
        write_then_read("unaligned_full", 4'h1, 32'h0000_1001,
                        8'd3, AXI4_SIZE_4B, AXI4_BURST_INCR, 32'h1100_0000);

        // Narrow 2-byte transfer starting at byte lane 3. First beat uses only
        // lane 3; later beats progress using the aligned address rule.
        write_then_read("unaligned_narrow", 4'h2, 32'h0000_1103,
                        8'd3, AXI4_SIZE_2B, AXI4_BURST_INCR, 32'h2200_0000);

        // FIXED keeps the same legal byte lanes on every beat.
        write_then_read("unaligned_fixed", 4'h3, 32'h0000_1201,
                        8'd3, AXI4_SIZE_2B, AXI4_BURST_FIXED, 32'h3300_0000);

        // Legal WRAP container [0x0FF0:0x0FFF]. The start address is 0x0FFC,
        // so the sequence is FFC, FF0, FF4, FF8 without crossing 4KB.
        write_then_read("wrap_page_edge", 4'h4, 32'h0000_0FFC,
                        8'd3, AXI4_SIZE_4B, AXI4_BURST_WRAP, 32'h4400_0000);

        // Preload two locations used for same-ID ordering.
        issue_write(wr_a, "same_id_preload_a", 4'hA, 32'h0000_2000,
                    8'd15, AXI4_SIZE_4B, AXI4_BURST_INCR, 32'hA100_0000, 1'b1);
        issue_write(wr_b, "same_id_preload_b", 4'hA, 32'h0000_3000,
                    8'd0, AXI4_SIZE_4B, AXI4_BURST_INCR, 32'hA200_0000, 1'b1);

        // Issue two same-ID reads without waiting between requests. Even when
        // different-ID reordering is enabled, the second same-ID response must
        // not complete before the first accepted request.
        issue_read(rd_first,  "same_id_read_first",  4'hA, 32'h0000_2000,
                   8'd15, AXI4_SIZE_4B, AXI4_BURST_INCR, 1'b0);
        issue_read(rd_second, "same_id_read_second", 4'hA, 32'h0000_3000,
                   8'd0, AXI4_SIZE_4B, AXI4_BURST_INCR, 1'b0);
        wait (rd_first.completed && rd_second.completed);

        if (rd_second.completion_time < rd_first.completion_time)
            `uvm_error(get_type_name(),
                       $sformatf("Same-ID ordering failure: second completed at %0t before first at %0t",
                                 rd_second.completion_time, rd_first.completion_time))

        `uvm_info(get_type_name(), "Completed Hoang Ho AXI4 spec-corner sequence", UVM_LOW)
    endtask : body

endclass : axi4_spec_corner_seq

`endif // AXI4_SPEC_CORNER_SEQ_INCLUDED_
