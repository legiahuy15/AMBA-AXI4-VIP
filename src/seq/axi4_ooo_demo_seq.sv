//==============================================================================
// File        : axi4_ooo_demo_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Out-of-order demo sequence for waveform capture.
//               Fires exactly 6 SINGLE-BEAT reads with distinct IDs (0..5) to
//               fixed addresses, back-to-back (no wait between), so all six
//               are outstanding together. With a reorder-enabled slave the R
//               responses return out of order (RID order != ARID order), while
//               each burst stays non-interleaved. Six in-flight reads make an
//               accidental in-order return negligibly unlikely on any seed.
//               Minimal, deterministic, compact - ideal for report waveforms.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_OOO_DEMO_SEQ_INCLUDED_
`define AXI4_OOO_DEMO_SEQ_INCLUDED_

class axi4_ooo_demo_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_ooo_demo_seq)

    function new(string name = "axi4_ooo_demo_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        axi4_transaction rds[6];

        `uvm_info(get_type_name(),
                  "Starting OOO demo sequence (6 single-beat reads, IDs 0-5)",
                  UVM_MEDIUM)

        // Issue all 6 reads back-to-back WITHOUT waiting, so they are
        // outstanding together and the slave can reorder their responses.
        for (int i = 0; i < 6; i++) begin
            rds[i] = axi4_transaction::type_id::create($sformatf("ooo_rd_%0d", i));
            start_item(rds[i]);
            if (!rds[i].randomize() with {
                dir   == AXI4_READ;
                addr  == 32'h0000_1000 + (i * 32'h100);  // 0x1000..0x1500
                id    == i[3:0];                          // distinct IDs 0..5
                len   == 0;                               // single beat -> compact
                size  == AXI4_SIZE_4B;
                burst == AXI4_BURST_INCR;
                lock  == AXI4_LOCK_NORMAL;
            }) `uvm_fatal(get_type_name(),
                          $sformatf("Randomization failed for OOO demo read #%0d", i))
            finish_item(rds[i]);   // do NOT wait -> pipelined / outstanding
        end

        // Wait for all responses (they may arrive out of order)
        for (int i = 0; i < 6; i++)
            wait(rds[i].done_event.ev.triggered);

        `uvm_info(get_type_name(),
                  "OOO demo sequence complete (6/6 reads returned)", UVM_MEDIUM)
    endtask : body

endclass : axi4_ooo_demo_seq

`endif // AXI4_OOO_DEMO_SEQ_INCLUDED_
