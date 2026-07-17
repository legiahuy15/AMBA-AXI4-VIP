//==============================================================================
// File        : axi4_exclusive_demo_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Exclusive access demo sequence for waveform capture.
//               Three transactions, all to a fixed address/ID, each run to
//               FULL completion before the next starts (wait on done_event),
//               so the phases never overlap on the waveform:
//                 1. Exclusive READ   -> RRESP = EXOKAY, records reservation
//                 2. Exclusive WRITE  -> BRESP = EXOKAY, commits (0x11111111)
//                 3. Exclusive WRITE  -> BRESP = OKAY,  reservation gone,
//                                        no commit (0x22222222 discarded)
//               Huy Le's known low-word data + sequential phasing make the
//               EXOKAY/OKAY story easy to read. Hoang Ho expands the data
//               across the compiled bus width. This file is `included inside axi4_pkg.sv.
//==============================================================================

// Huy Le: original three-phase exclusive-access teaching scenario.
// Hoang Ho: full-width data patterns and legal WSTRB scale with DATA_WIDTH.

`ifndef AXI4_EXCLUSIVE_DEMO_SEQ_INCLUDED_
`define AXI4_EXCLUSIVE_DEMO_SEQ_INCLUDED_

class axi4_exclusive_demo_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_exclusive_demo_seq)

    function new(string name = "axi4_exclusive_demo_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        axi4_transaction rd, wr1, wr2;

        `uvm_info(get_type_name(),
                  "Starting exclusive demo (READ EXOKAY -> WRITE EXOKAY -> WRITE OKAY)",
                  UVM_MEDIUM)

        // -----------------------------------------------------------------
        // Phase 1: Exclusive READ -> EXOKAY, records the reservation.
        //   Wait for full completion so the reservation is set BEFORE the
        //   write begins - READ and WRITE#1 never overlap on the waveform.
        // -----------------------------------------------------------------
        rd = axi4_transaction::type_id::create("excl_rd");
        start_item(rd);
        if (!rd.randomize() with {
            dir   == AXI4_READ;
            addr  == 32'h0000_1000;
            id    == 4'h5;
            len   == 0;
            size  == axi4_size_e'(AXI4_MAX_SIZE);
            burst == AXI4_BURST_INCR;
            lock  == AXI4_LOCK_EXCLUSIVE;
        }) `uvm_fatal(get_type_name(), "Randomization failed for exclusive read")
        finish_item(rd);
        wait (rd.completed); // Hoang Ho: persistent completion state
        `uvm_info(get_type_name(),
                  $sformatf("Phase 1 [EXCL READ] done: RRESP=%s (expect EXOKAY)",
                            rd.rresp[0].name()), UVM_MEDIUM)

        // -----------------------------------------------------------------
        // Phase 2: Exclusive WRITE matching the reservation -> EXOKAY, commits.
        // -----------------------------------------------------------------
        wr1 = axi4_transaction::type_id::create("excl_wr_ok");
        start_item(wr1);
        if (!wr1.randomize() with {
            dir   == AXI4_WRITE;
            addr  == 32'h0000_1000;
            id    == 4'h5;
            len   == 0;
            size  == axi4_size_e'(AXI4_MAX_SIZE);
            burst == AXI4_BURST_INCR;
            lock  == AXI4_LOCK_EXCLUSIVE;
        }) `uvm_fatal(get_type_name(), "Randomization failed for exclusive write #1")
        // Hoang Ho: expand the original 0x11111111 waveform marker across all
        // lanes, then enable exactly the bytes selected by AxSIZE/AxADDR.
        wr1.data[0] = axi4_expand_legacy_word(32'h1111_1111, 0);
        wr1.strb[0] = axi4_calc_legal_lane_mask(wr1.addr, 0, wr1.size,
                                                wr1.burst, wr1.len);
        finish_item(wr1);
        wait (wr1.completed); // Hoang Ho: persistent completion state
        `uvm_info(get_type_name(),
                  $sformatf("Phase 2 [EXCL WRITE] done: BRESP=%s (expect EXOKAY)",
                            wr1.resp.name()), UVM_MEDIUM)

        // -----------------------------------------------------------------
        // Phase 3: Exclusive WRITE with no reservation -> OKAY, no commit.
        // -----------------------------------------------------------------
        wr2 = axi4_transaction::type_id::create("excl_wr_fail");
        start_item(wr2);
        if (!wr2.randomize() with {
            dir   == AXI4_WRITE;
            addr  == 32'h0000_1000;
            id    == 4'h5;
            len   == 0;
            size  == axi4_size_e'(AXI4_MAX_SIZE);
            burst == AXI4_BURST_INCR;
            lock  == AXI4_LOCK_EXCLUSIVE;
        }) `uvm_fatal(get_type_name(), "Randomization failed for exclusive write #2")
        // Hoang Ho: this second recognizable pattern must not commit because
        // the successful exclusive write consumed the reservation.
        wr2.data[0] = axi4_expand_legacy_word(32'h2222_2222, 0);
        wr2.strb[0] = axi4_calc_legal_lane_mask(wr2.addr, 0, wr2.size,
                                                wr2.burst, wr2.len);
        finish_item(wr2);
        wait (wr2.completed); // Hoang Ho: persistent completion state
        `uvm_info(get_type_name(),
                  $sformatf("Phase 3 [EXCL WRITE] done: BRESP=%s (expect OKAY, no commit)",
                            wr2.resp.name()), UVM_MEDIUM)

        `uvm_info(get_type_name(),
                  "Exclusive demo complete (3/3 transactions)", UVM_MEDIUM)
    endtask : body

endclass : axi4_exclusive_demo_seq

`endif // AXI4_EXCLUSIVE_DEMO_SEQ_INCLUDED_
