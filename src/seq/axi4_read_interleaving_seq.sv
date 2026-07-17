//Hoang Ho: deterministic read-data interleaving stimulus for VIP-to-VIP mode.
// Different-ID mode launches three reads. Same-ID mode launches two reads and
// relies on distinct data patterns to detect any response-order violation.
`ifndef AXI4_READ_INTERLEAVING_SEQ_INCLUDED_
`define AXI4_READ_INTERLEAVING_SEQ_INCLUDED_

class axi4_read_interleaving_seq extends axi4_base_sequence;
    `uvm_object_utils(axi4_read_interleaving_seq)

    bit          same_id_mode = 0;
    int unsigned num_beats_a  = 8;
    int unsigned num_beats_b  = 4;
    int unsigned num_beats_c  = 2;
    int unsigned errors       = 0;

    localparam axi4_addr_t BUF_A = axi4_addr_t'(32'h0001_0000);
    localparam axi4_addr_t BUF_B = axi4_addr_t'(32'h0001_2000);
    localparam axi4_addr_t BUF_C = axi4_addr_t'(32'h0001_4000);

    function new(string name = "axi4_read_interleaving_seq");
        super.new(name);
    endfunction

    protected function axi4_id_t test_id(int unsigned value);
        return axi4_id_t'(value);
    endfunction

    protected task send_write(
        input string       name_i,
        input axi4_id_t    id_i,
        input axi4_addr_t  addr_i,
        input int unsigned tag_i,
        input int unsigned beats_i
    );
        axi4_transaction tr;
        tr = axi4_transaction::type_id::create(name_i);
        tr.dir      = AXI4_WRITE;
        tr.wr_order = AXI4_WR_PARALLEL;
        tr.id       = id_i;
        tr.addr     = addr_i;
        tr.len      = beats_i - 1;
        tr.size     = axi4_full_bus_size();
        tr.burst    = AXI4_BURST_INCR;
        tr.lock     = AXI4_LOCK_NORMAL;
        tr.cache    = '0;
        tr.prot     = '0;
        tr.qos      = '0;
        tr.region   = '0;
        tr.data     = new[beats_i];
        tr.strb     = new[beats_i];
        tr.rresp    = new[beats_i];
        foreach (tr.data[i]) begin
            tr.data[i]  = axi4_make_data_pattern(tag_i, i);
            tr.strb[i]  = '1;
            tr.rresp[i] = AXI4_RESP_OKAY;
        end
        start_item(tr);
        finish_item(tr);
        wait (tr.completed);
        if (tr.resp != AXI4_RESP_OKAY) begin
            errors++;
            `uvm_error(get_type_name(), $sformatf("%s BRESP=%s", name_i, tr.resp.name()))
        end
    endtask : send_write

    //Hoang Ho: finish_item returns after the driver queues the request, so the
    // next AR can become outstanding before the earlier R burst completes.
    protected task issue_read(
        output axi4_transaction tr,
        input  string           name_i,
        input  axi4_id_t        id_i,
        input  axi4_addr_t      addr_i,
        input  int unsigned     beats_i
    );
        tr = axi4_transaction::type_id::create(name_i);
        tr.dir      = AXI4_READ;
        tr.wr_order = AXI4_WR_PARALLEL;
        tr.id       = id_i;
        tr.addr     = addr_i;
        tr.len      = beats_i - 1;
        tr.size     = axi4_full_bus_size();
        tr.burst    = AXI4_BURST_INCR;
        tr.lock     = AXI4_LOCK_NORMAL;
        tr.cache    = '0;
        tr.prot     = '0;
        tr.qos      = '0;
        tr.region   = '0;
        tr.data     = new[beats_i];
        tr.strb     = new[beats_i];
        tr.rresp    = new[beats_i];
        foreach (tr.data[i]) begin
            tr.data[i]  = '0;
            tr.strb[i]  = '1;
            tr.rresp[i] = AXI4_RESP_OKAY;
        end
        start_item(tr);
        finish_item(tr);
    endtask : issue_read

    protected function void check_read(
        input string           name_i,
        input axi4_transaction tr,
        input int unsigned     tag_i
    );
        foreach (tr.data[i]) begin
            axi4_data_t expected;
            expected = axi4_make_data_pattern(tag_i, i);
            if (tr.data[i] !== expected) begin
                errors++;
                `uvm_error(get_type_name(),
                           $sformatf("%s beat[%0d] data mismatch", name_i, i))
            end
            if (tr.rresp[i] != AXI4_RESP_OKAY) begin
                errors++;
                `uvm_error(get_type_name(),
                           $sformatf("%s beat[%0d] RRESP=%s", name_i, i, tr.rresp[i].name()))
            end
        end
    endfunction : check_read

    virtual task body();
        axi4_id_t id_a;
        axi4_id_t id_b;
        axi4_id_t id_c;
        axi4_transaction rd_a;
        axi4_transaction rd_b;
        axi4_transaction rd_c;

        if (AXI4_ID_WIDTH < 2)
            `uvm_fatal(get_type_name(), "Read interleaving requires ID_WIDTH >= 2")
        if (num_beats_a < 2) num_beats_a = 2;
        if (num_beats_b < 2) num_beats_b = 2;
        if (num_beats_c < 2) num_beats_c = 2;

        id_a = same_id_mode ? test_id(3) : test_id(1);
        id_b = same_id_mode ? test_id(3) : test_id(2);
        id_c = test_id(3);

        send_write("interleave_wr_a", test_id(0), BUF_A, 8'h10, num_beats_a);
        send_write("interleave_wr_b", test_id(0), BUF_B, 8'h80, num_beats_b);
        if (!same_id_mode)
            send_write("interleave_wr_c", test_id(0), BUF_C, 8'hC0, num_beats_c);

        // AR acceptance order is explicit. The slave may alternate different
        // RIDs, but two requests using the same ID must remain FIFO ordered.
        issue_read(rd_a, "interleave_rd_a", id_a, BUF_A, num_beats_a);
        issue_read(rd_b, "interleave_rd_b", id_b, BUF_B, num_beats_b);
        if (!same_id_mode)
            issue_read(rd_c, "interleave_rd_c", id_c, BUF_C, num_beats_c);

        if (same_id_mode) begin
            wait (rd_a.completed && rd_b.completed);
        end else begin
            wait (rd_a.completed && rd_b.completed && rd_c.completed);
        end

        check_read("interleave_rd_a", rd_a, 8'h10);
        check_read("interleave_rd_b", rd_b, 8'h80);
        if (!same_id_mode)
            check_read("interleave_rd_c", rd_c, 8'hC0);
    endtask : body
endclass : axi4_read_interleaving_seq

`endif
