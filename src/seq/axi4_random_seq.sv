//==============================================================================
// File        : axi4_random_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Random mixed-traffic sequence.
//               Generates a configurable number of random write and read
//               transactions with fully randomised parameters. Useful for
//               stress testing, corner-case discovery, and coverage closure.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_RANDOM_SEQ_INCLUDED_
`define AXI4_RANDOM_SEQ_INCLUDED_

class axi4_random_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_random_seq)

    // =========================================================================
    // Configurable knobs
    // =========================================================================
    int unsigned num_txns = 20;     // Total number of transactions to generate

    //Hoang Ho
    // Optional controls used by directed stress tests. Defaults preserve the
    // original mixed, fire-and-forget random-sequence behavior.
    bit        force_dir          = 1'b0;
    axi4_dir_e fixed_dir          = AXI4_WRITE;
    bit        wait_each_txn_done = 1'b0;
    //Hoang Ho

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_random_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // body - generate num_txns random write/read transactions
    // =========================================================================
    virtual task body();
        `uvm_info(get_type_name(),
                  $sformatf("Starting random sequence: %0d transactions", num_txns),
                  UVM_MEDIUM)

        for (int i = 0; i < num_txns; i++) begin
            axi4_transaction tr;

            tr = axi4_transaction::type_id::create($sformatf("rand_tr_%0d", i));
            start_item(tr);

            //Hoang Ho
            // A response-backpressure test can force a write-only or read-only
            // phase so writes cannot modify memory while read responses are
            // stalled. This prevents a false scoreboard mismatch caused by
            // comparing an AR-time read snapshot against a later memory state.
            if (force_dir) begin
                if (!tr.randomize() with {
                    dir  == local::fixed_dir;
                    addr inside {[addr_lo : addr_hi]};
                    id   inside {[id_lo   : id_hi]};
                }) `uvm_fatal(get_type_name(),
                              $sformatf("Randomization failed for transaction #%0d", i))
            end else begin
                if (!tr.randomize() with {
                    addr inside {[addr_lo : addr_hi]};
                    id   inside {[id_lo   : id_hi]};
                }) `uvm_fatal(get_type_name(),
                              $sformatf("Randomization failed for transaction #%0d", i))
            end

            finish_item(tr);

            // Optional serialization knob for tests that need one transaction
            // to finish on the bus before issuing the next transaction.
            if (wait_each_txn_done)
                wait (tr.completed); //Hoang Ho - persistent completion wait
            //Hoang Ho

            `uvm_info(get_type_name(),
                      $sformatf("[%0d/%0d] %s: ID=0x%0h ADDR=0x%08h LEN=%0d BURST=%s",
                                i + 1, num_txns,
                                tr.dir.name(), tr.id, tr.addr, tr.len,
                                tr.burst.name()),
                      UVM_HIGH)
        end

        `uvm_info(get_type_name(),
                  $sformatf("Random sequence complete: %0d transactions sent", num_txns),
                  UVM_MEDIUM)
    endtask : body

endclass : axi4_random_seq

`endif // AXI4_RANDOM_SEQ_INCLUDED_