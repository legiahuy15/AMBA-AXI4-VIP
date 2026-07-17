//==============================================================================
// File        : axi4_data_integrity_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Data Integrity Demo Sequence (Write-then-Read-back).
//               Writes KNOWN, FIXED data patterns to specific addresses,
//               then reads back from those exact addresses. On the waveform
//               you can visually confirm WDATA == RDATA beat-by-beat.
//
//               The low 32 bits preserve Huy Le's recognizable constants.
//               Hoang Ho expands them across every 32-bit chunk so all data
//               lanes are exercised when DATA_WIDTH is greater than 32.
//
//               Total: 4 transactions (2 write + 2 read-back).
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

// Huy Le: original known-pattern data-integrity scenario.
// Hoang Ho: full-width transfers and strobes scale with DATA_WIDTH.

`ifndef AXI4_DATA_INTEGRITY_SEQ_INCLUDED_
`define AXI4_DATA_INTEGRITY_SEQ_INCLUDED_

class axi4_data_integrity_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_data_integrity_seq)

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_data_integrity_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // body - write known data, then read-back and compare on waveform
    // =========================================================================
    virtual task body();
        axi4_transaction wr_tr, rd_tr;

        `uvm_info(get_type_name(),
                  "Starting data integrity demo (write known data -> read-back -> compare on waveform)",
                  UVM_MEDIUM)

        // =================================================================
        // Pair 1: 4-beat INCR burst with recognisable data
        //   Address: 0x0000_C000 (aligned, OKAY region)
        //   On waveform, look at:
        //     W channel: WDATA = DEADBEEF, CAFEBABE, 12345678, A5A5A5A5
        //     R channel: RDATA = DEADBEEF, CAFEBABE, 12345678, A5A5A5A5
        //   They MUST match beat-for-beat.
        // =================================================================

        // --- Write Phase ---
        wr_tr = axi4_transaction::type_id::create("integrity_wr1");
        start_item(wr_tr);
        if (!wr_tr.randomize() with {
            dir   == AXI4_WRITE;
            addr  == 32'h0000_C000;
            len   == 3;                      // 4 beats
            size  == axi4_size_e'(AXI4_MAX_SIZE);
            burst == AXI4_BURST_INCR;
            id    == 4'hC;
            lock  == AXI4_LOCK_NORMAL;        // Normal write so ref-mem commits it
        }) `uvm_fatal(get_type_name(), "Randomization failed for integrity write #1")

        // Hoang Ho: assign known data after randomization. This avoids asking
        // older constraint solvers to evaluate wide helper functions.
        wr_tr.data[0] = axi4_expand_legacy_word(32'hDEAD_BEEF, 0);
        wr_tr.data[1] = axi4_expand_legacy_word(32'hCAFE_BABE, 1);
        wr_tr.data[2] = axi4_expand_legacy_word(32'h1234_5678, 2);
        wr_tr.data[3] = axi4_expand_legacy_word(32'hA5A5_A5A5, 3);
        foreach (wr_tr.strb[i])
            wr_tr.strb[i] = axi4_calc_legal_lane_mask(wr_tr.addr, i,
                                                       wr_tr.size, wr_tr.burst,
                                                       wr_tr.len);
        finish_item(wr_tr);
        wait (wr_tr.completed); // Hoang Ho: persistent completion wait

        `uvm_info(get_type_name(),
                  $sformatf("WRITE #1 done: ADDR=0x%08h DATA={0x%0h, 0x%0h, 0x%0h, 0x%0h} RESP=%s",
                            wr_tr.addr, wr_tr.data[0], wr_tr.data[1],
                            wr_tr.data[2], wr_tr.data[3], wr_tr.resp.name()),
                  UVM_MEDIUM)

        // --- Read-back Phase ---
        rd_tr = axi4_transaction::type_id::create("integrity_rd1");
        start_item(rd_tr);
        if (!rd_tr.randomize() with {
            dir   == AXI4_READ;
            addr  == 32'h0000_C000;          // Same address
            len   == 3;                      // Same burst length
            size  == axi4_size_e'(AXI4_MAX_SIZE);
            burst == AXI4_BURST_INCR;
            id    == 4'hC;
            lock  == AXI4_LOCK_NORMAL;        // Normal read-back
        }) `uvm_fatal(get_type_name(), "Randomization failed for integrity read #1")
        finish_item(rd_tr);
        wait (rd_tr.completed); // Hoang Ho: persistent completion wait

        `uvm_info(get_type_name(),
                  $sformatf("READ  #1 done: ADDR=0x%08h DATA={0x%0h, 0x%0h, 0x%0h, 0x%0h}",
                            rd_tr.addr, rd_tr.data[0], rd_tr.data[1],
                            rd_tr.data[2], rd_tr.data[3]),
                  UVM_MEDIUM)

        // In-sequence sanity check (scoreboard also checks, but log it explicitly)
        begin
            bit pass = 1;
            foreach (wr_tr.data[i]) begin
                if (wr_tr.data[i] !== rd_tr.data[i]) begin
                    `uvm_error(get_type_name(),
                               $sformatf("DATA MISMATCH beat[%0d]: wrote 0x%0h, read 0x%0h",
                                         i, wr_tr.data[i], rd_tr.data[i]))
                    pass = 0;
                end
            end
            if (pass)
                `uvm_info(get_type_name(),
                          "Pair #1 data integrity PASSED -- all 4 beats match",
                          UVM_LOW)
        end

        // =================================================================
        // Pair 2: Single-beat write + read (simplest case)
        //   Address: 0x0000_D000
        //   Data:    0x5555_AAAA
        //   On waveform: one WDATA beat = one RDATA beat, easy to spot.
        // =================================================================

        // --- Write Phase ---
        wr_tr = axi4_transaction::type_id::create("integrity_wr2");
        start_item(wr_tr);
        if (!wr_tr.randomize() with {
            dir   == AXI4_WRITE;
            addr  == 32'h0000_D000;
            len   == 0;                      // Single beat
            size  == axi4_size_e'(AXI4_MAX_SIZE);
            burst == AXI4_BURST_INCR;
            id    == 4'hD;
            lock  == AXI4_LOCK_NORMAL;        // Normal write so ref-mem commits it
        }) `uvm_fatal(get_type_name(), "Randomization failed for integrity write #2")
        // Hoang Ho: preserve 0x5555_AAAA in the low word and exercise all
        // additional chunks on wide data buses.
        wr_tr.data[0] = axi4_expand_legacy_word(32'h5555_AAAA, 0);
        wr_tr.strb[0] = axi4_calc_legal_lane_mask(wr_tr.addr, 0,
                                                  wr_tr.size, wr_tr.burst,
                                                  wr_tr.len);
        finish_item(wr_tr);
        wait (wr_tr.completed); // Hoang Ho: persistent completion wait

        `uvm_info(get_type_name(),
                  $sformatf("WRITE #2 done: ADDR=0x%08h DATA=0x%0h RESP=%s",
                            wr_tr.addr, wr_tr.data[0], wr_tr.resp.name()),
                  UVM_MEDIUM)

        // --- Read-back Phase ---
        rd_tr = axi4_transaction::type_id::create("integrity_rd2");
        start_item(rd_tr);
        if (!rd_tr.randomize() with {
            dir   == AXI4_READ;
            addr  == 32'h0000_D000;
            len   == 0;
            size  == axi4_size_e'(AXI4_MAX_SIZE);
            burst == AXI4_BURST_INCR;
            id    == 4'hD;
            lock  == AXI4_LOCK_NORMAL;        // Normal read-back
        }) `uvm_fatal(get_type_name(), "Randomization failed for integrity read #2")
        finish_item(rd_tr);
        wait (rd_tr.completed); // Hoang Ho: persistent completion wait

        `uvm_info(get_type_name(),
                  $sformatf("READ  #2 done: ADDR=0x%08h DATA=0x%0h",
                            rd_tr.addr, rd_tr.data[0]),
                  UVM_MEDIUM)

        // In-sequence sanity check
        if (wr_tr.data[0] === rd_tr.data[0])
            `uvm_info(get_type_name(),
                      "Pair #2 data integrity PASSED -- single beat matches",
                      UVM_LOW)
        else
            `uvm_error(get_type_name(),
                       $sformatf("DATA MISMATCH: wrote 0x%0h, read 0x%0h",
                                 wr_tr.data[0], rd_tr.data[0]))

        `uvm_info(get_type_name(),
                  "Data integrity demo complete (4/4 transactions sent)",
                  UVM_MEDIUM)
    endtask : body

endclass : axi4_data_integrity_seq

`endif // AXI4_DATA_INTEGRITY_SEQ_INCLUDED_
