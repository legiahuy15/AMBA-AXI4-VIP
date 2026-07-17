//Hoang Ho: width-profile sequence for AXI4 VIP-to-VIP verification.
// It checks full-width transfers and a 1-byte INCR burst that visits every
// byte lane of the compiled data bus.
`ifndef AXI4_WIDTH_SCALING_SEQ_INCLUDED_
`define AXI4_WIDTH_SCALING_SEQ_INCLUDED_

class axi4_width_scaling_seq extends axi4_base_sequence;
    `uvm_object_utils(axi4_width_scaling_seq)

    int unsigned errors = 0;
    localparam int unsigned FULL_BEATS = 4;
    localparam axi4_addr_t FULL_BASE   = axi4_addr_t'(32'h0002_0000);
    localparam axi4_addr_t LANE_BASE   = axi4_addr_t'(32'h0002_1000);

    function new(string name = "axi4_width_scaling_seq");
        super.new(name);
    endfunction

    protected task send_full_width_write();
        axi4_transaction wr;
        wr = axi4_transaction::type_id::create("width_full_wr");
        wr.dir      = AXI4_WRITE;
        wr.wr_order = AXI4_WR_PARALLEL;
        wr.id       = axi4_id_t'(0);
        wr.addr     = FULL_BASE;
        wr.len      = FULL_BEATS-1;
        wr.size     = axi4_full_bus_size();
        wr.burst    = AXI4_BURST_INCR;
        wr.lock     = AXI4_LOCK_NORMAL;
        wr.cache    = '0;
        wr.prot     = '0;
        wr.qos      = '0;
        wr.region   = '0;
        wr.data     = new[FULL_BEATS];
        wr.strb     = new[FULL_BEATS];
        wr.rresp    = new[FULL_BEATS];
        foreach (wr.data[i]) begin
            wr.data[i]  = axi4_make_data_pattern(8'h30, i);
            wr.strb[i]  = '1;
            wr.rresp[i] = AXI4_RESP_OKAY;
        end
        start_item(wr);
        finish_item(wr);
        wait (wr.completed);
        if (wr.resp != AXI4_RESP_OKAY) begin
            errors++;
            `uvm_error(get_type_name(), $sformatf("Full-width BRESP=%s", wr.resp.name()))
        end
    endtask

    protected task check_full_width_read();
        axi4_transaction rd;
        rd = axi4_transaction::type_id::create("width_full_rd");
        rd.dir      = AXI4_READ;
        rd.wr_order = AXI4_WR_PARALLEL;
        rd.id       = axi4_id_t'(1);
        rd.addr     = FULL_BASE;
        rd.len      = FULL_BEATS-1;
        rd.size     = axi4_full_bus_size();
        rd.burst    = AXI4_BURST_INCR;
        rd.lock     = AXI4_LOCK_NORMAL;
        rd.cache    = '0;
        rd.prot     = '0;
        rd.qos      = '0;
        rd.region   = '0;
        rd.data     = new[FULL_BEATS];
        rd.strb     = new[FULL_BEATS];
        rd.rresp    = new[FULL_BEATS];
        foreach (rd.data[i]) begin
            rd.data[i]  = '0;
            rd.strb[i]  = '1;
            rd.rresp[i] = AXI4_RESP_OKAY;
        end
        start_item(rd);
        finish_item(rd);
        wait (rd.completed);

        foreach (rd.data[i]) begin
            axi4_data_t expected;
            expected = axi4_make_data_pattern(8'h30, i);
            if (rd.data[i] !== expected) begin
                errors++;
                `uvm_error(get_type_name(),
                           $sformatf("Full-width DATA=%0d beat[%0d] mismatch", AXI4_DATA_WIDTH, i))
            end
            if (rd.rresp[i] != AXI4_RESP_OKAY) begin
                errors++;
                `uvm_error(get_type_name(),
                           $sformatf("Full-width beat[%0d] RRESP=%s", i, rd.rresp[i].name()))
            end
        end
    endtask

    //Hoang Ho: one 1-byte beat per bus lane. For a 1024-bit bus this is a
    // 128-beat burst, still within the AXI4 maximum length and one 4KB page.
    protected task send_lane_walk_write();
        axi4_transaction wr;
        int unsigned beats;
        beats = AXI4_STRB_WIDTH;
        wr = axi4_transaction::type_id::create("width_lane_wr");
        wr.dir      = AXI4_WRITE;
        wr.wr_order = AXI4_WR_PARALLEL;
        wr.id       = axi4_id_t'(2);
        wr.addr     = LANE_BASE;
        wr.len      = beats-1;
        wr.size     = AXI4_SIZE_1B;
        wr.burst    = AXI4_BURST_INCR;
        wr.lock     = AXI4_LOCK_NORMAL;
        wr.cache    = '0;
        wr.prot     = '0;
        wr.qos      = '0;
        wr.region   = '0;
        wr.data     = new[beats];
        wr.strb     = new[beats];
        wr.rresp    = new[beats];
        foreach (wr.data[i]) begin
            axi4_addr_t beat_addr;
            axi4_addr_t bus_base;
            int unsigned lane;
            beat_addr   = axi4_calc_beat_addr(wr.addr, i, wr.size, wr.burst, wr.len);
            bus_base    = axi4_bus_word_base(beat_addr);
            lane        = beat_addr - bus_base;
            wr.data[i]  = '0;
            wr.data[i][lane*8 +: 8] = byte'(8'h80 + i);
            wr.strb[i]  = '0;
            wr.strb[i][lane] = 1'b1;
            wr.rresp[i] = AXI4_RESP_OKAY;
        end
        start_item(wr);
        finish_item(wr);
        wait (wr.completed);
        if (wr.resp != AXI4_RESP_OKAY) begin
            errors++;
            `uvm_error(get_type_name(), $sformatf("Lane-walk BRESP=%s", wr.resp.name()))
        end
    endtask

    protected task check_lane_walk_read();
        axi4_transaction rd;
        int unsigned beats;
        beats = AXI4_STRB_WIDTH;
        rd = axi4_transaction::type_id::create("width_lane_rd");
        rd.dir      = AXI4_READ;
        rd.wr_order = AXI4_WR_PARALLEL;
        rd.id       = axi4_id_t'(3);
        rd.addr     = LANE_BASE;
        rd.len      = beats-1;
        rd.size     = AXI4_SIZE_1B;
        rd.burst    = AXI4_BURST_INCR;
        rd.lock     = AXI4_LOCK_NORMAL;
        rd.cache    = '0;
        rd.prot     = '0;
        rd.qos      = '0;
        rd.region   = '0;
        rd.data     = new[beats];
        rd.strb     = new[beats];
        rd.rresp    = new[beats];
        foreach (rd.data[i]) begin
            rd.data[i]  = '0;
            rd.strb[i]  = '1;
            rd.rresp[i] = AXI4_RESP_OKAY;
        end
        start_item(rd);
        finish_item(rd);
        wait (rd.completed);

        foreach (rd.data[i]) begin
            axi4_addr_t beat_addr;
            axi4_addr_t bus_base;
            axi4_data_t expected;
            int unsigned lane;
            beat_addr = axi4_calc_beat_addr(rd.addr, i, rd.size, rd.burst, rd.len);
            bus_base  = axi4_bus_word_base(beat_addr);
            lane      = beat_addr - bus_base;
            expected  = '0;
            expected[lane*8 +: 8] = byte'(8'h80 + i);
            if (rd.data[i] !== expected) begin
                errors++;
                `uvm_error(get_type_name(),
                           $sformatf("Lane-walk DATA=%0d lane=%0d beat=%0d mismatch",
                                     AXI4_DATA_WIDTH, lane, i))
            end
            if (rd.rresp[i] != AXI4_RESP_OKAY) begin
                errors++;
                `uvm_error(get_type_name(),
                           $sformatf("Lane-walk beat[%0d] RRESP=%s", i, rd.rresp[i].name()))
            end
        end
    endtask

    virtual task body();
        if (!axi4_supported_data_width())
            `uvm_fatal(get_type_name(), $sformatf("Unsupported DATA_WIDTH=%0d", AXI4_DATA_WIDTH))

        send_full_width_write();
        check_full_width_read();
        send_lane_walk_write();
        check_lane_walk_read();

        `uvm_info(get_type_name(),
                  $sformatf("Width profile checked: DATA=%0d STRB=%0d full SIZE=%0d lanes=%0d",
                            AXI4_DATA_WIDTH, AXI4_STRB_WIDTH, AXI4_MAX_SIZE, AXI4_STRB_WIDTH),
                  UVM_LOW)
    endtask : body
endclass : axi4_width_scaling_seq

`endif
