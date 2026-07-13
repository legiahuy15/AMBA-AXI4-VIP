//=============================================================================
// OWNERSHIP NOTE
//   Original unmarked code in this file : Huy Le / original AXI4-VIP repo
//   Blocks marked //Hoang Ho            : Hoang Ho functional/spec fixes
//=============================================================================
//==============================================================================
// File        : axi4_scoreboard.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 scoreboard.
//               Receives completed transactions from both master and slave
//               monitors, matches them by a robust AXI4 transaction key, and compares all
//               fields using axi4_transaction::compare() (which includes
//               the manual rresp[] comparison via do_compare).
//
//               Matching strategy:
//                 When a transaction arrives from one side, search the other
//                 side's queue for a match by (id, addr). If found, compare
//                 immediately. If not, queue for later matching.
//                 This handles out-of-order and timing-skewed arrivals.
//
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

// Analysis port suffix declarations (must be outside class)
`uvm_analysis_imp_decl(_master)
`uvm_analysis_imp_decl(_slave)

class axi4_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(axi4_scoreboard)

    // =========================================================================
    // Analysis imports - one per monitor side
    // =========================================================================
    uvm_analysis_imp_master #(axi4_transaction, axi4_scoreboard) master_export;
    uvm_analysis_imp_slave  #(axi4_transaction, axi4_scoreboard) slave_export;

    // =========================================================================
    // Unmatched transaction queues
    //   Separated by direction for efficient matching.
    //   When a transaction arrives from one side and no match exists on the
    //   other side, it is queued here until the counterpart arrives.
    // =========================================================================
    axi4_transaction master_wr_q[$];
    axi4_transaction master_rd_q[$];
    axi4_transaction slave_wr_q[$];
    axi4_transaction slave_rd_q[$];

    // =========================================================================
    // Reference Memory Model for checking read-after-write data integrity
    // =========================================================================
    bit [7:0] ref_mem [bit [AXI4_ADDR_WIDTH-1:0]];

    // =========================================================================
    // Statistics
    // =========================================================================
    int unsigned match_count    = 0;
    int unsigned mismatch_count = 0;
    int unsigned total_master   = 0;
    int unsigned total_slave    = 0;

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Build phase - create analysis imports
    // =========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        master_export = new("master_export", this);
        slave_export  = new("slave_export",  this);
    endfunction : build_phase

    // =========================================================================
    // write_master - called when master monitor broadcasts a completed txn
    // =========================================================================
    function void write_master(axi4_transaction t);
        axi4_transaction tr;
        total_master++;

        // Deep copy - the monitor may reuse the object
        tr = axi4_transaction::type_id::create("master_tr");
        tr.copy(t);

        `uvm_info(get_type_name(),
                  $sformatf("Master %s received: ID=0x%0h ADDR=0x%08h LEN=%0d",
                            tr.dir.name(), tr.id, tr.addr, tr.len), UVM_HIGH)

        if (tr.dir == AXI4_WRITE)
            try_match(tr, master_wr_q, slave_wr_q, "WRITE");
        else
            try_match(tr, master_rd_q, slave_rd_q, "READ");
    endfunction : write_master

    // =========================================================================
    // write_slave - called when slave monitor broadcasts a completed txn
    // =========================================================================
    function void write_slave(axi4_transaction t);
        axi4_transaction tr;
        total_slave++;

        // Deep copy
        tr = axi4_transaction::type_id::create("slave_tr");
        tr.copy(t);

        `uvm_info(get_type_name(),
                  $sformatf("Slave %s received: ID=0x%0h ADDR=0x%08h LEN=%0d",
                            tr.dir.name(), tr.id, tr.addr, tr.len), UVM_HIGH)

        if (tr.dir == AXI4_WRITE)
            try_match(tr, slave_wr_q, master_wr_q, "WRITE");
        else
            try_match(tr, slave_rd_q, master_rd_q, "READ");
    endfunction : write_slave

    //Hoang Ho - BEGIN: Robust AXI4 Full transaction matching key
    // =========================================================================
    // is_same_txn_key - AXI4 transaction-level matching key
    //   Do not match only by (id, addr). AXI4 can have multiple outstanding
    //   transactions with the same ID/address but different length, size, burst,
    //   lock, or attributes. This key is still lightweight, but much safer for
    //   AXI4 Full than the old (id, addr) match.
    // =========================================================================
    function bit is_same_txn_key(axi4_transaction a, axi4_transaction b);
        return (a.dir    == b.dir)    &&
               (a.id     == b.id)     &&
               (a.addr   == b.addr)   &&
               (a.len    == b.len)    &&
               (a.size   == b.size)   &&
               (a.burst  == b.burst)  &&
               (a.lock   == b.lock)   &&
               (a.cache  == b.cache)  &&
               (a.prot   == b.prot)   &&
               (a.region == b.region);
    endfunction : is_same_txn_key
    //Hoang Ho - END: Robust AXI4 Full transaction matching key

    // =========================================================================
    // try_match - search for matching transaction on the other side
    //   If found:  compare and consume both.
    //   If not:    push to own queue for future matching.
    // =========================================================================
    function void try_match(
        axi4_transaction     new_tr,
        ref axi4_transaction own_q[$],
        ref axi4_transaction other_q[$],
        input string         dir_str
    );
        for (int i = 0; i < other_q.size(); i++) begin
            //Hoang Ho - BEGIN: replace old id+addr matching with full transaction key
            if (is_same_txn_key(other_q[i], new_tr)) begin
                axi4_transaction ref_tr = other_q[i];
                other_q.delete(i);
                compare_transactions(ref_tr, new_tr, dir_str);
                return;
            end
            //Hoang Ho - END: replace old id+addr matching with full transaction key
        end

        own_q.push_back(new_tr);
    endfunction : try_match

    //Hoang Ho - BEGIN: shared, spec-correct address and lane wrappers
    function bit [AXI4_ADDR_WIDTH-1:0] calc_beat_addr(
        bit [AXI4_ADDR_WIDTH-1:0] start_addr,
        int unsigned              beat_idx,
        bit [2:0]                 size,
        bit [1:0]                 burst_type,
        bit [7:0]                 len
    );
        return axi4_calc_beat_addr(start_addr, beat_idx, size,
                                   axi4_burst_type_e'(burst_type), len);
    endfunction : calc_beat_addr

    function bit [AXI4_STRB_WIDTH-1:0] calc_legal_wstrb_mask(
        bit [AXI4_ADDR_WIDTH-1:0] start_addr,
        int unsigned              beat_idx,
        bit [2:0]                 size,
        bit [1:0]                 burst_type,
        bit [7:0]                 len
    );
        return axi4_calc_legal_lane_mask(start_addr, beat_idx, size,
                                         axi4_burst_type_e'(burst_type), len);
    endfunction : calc_legal_wstrb_mask
    //Hoang Ho - END: shared, spec-correct address and lane wrappers

    // =========================================================================
    // update_ref_mem - update scoreboard's reference memory on WRITES
    // =========================================================================
    function void update_ref_mem(axi4_transaction tr);
        bit do_write;

        //Hoang Ho - BEGIN: response-driven reference-memory commit policy
        // Normal successful writes and successful exclusive writes commit data.
        // SLVERR/DECERR and failed exclusive writes never modify memory.
        do_write = ((tr.lock == AXI4_LOCK_NORMAL)    &&
                    (tr.resp == AXI4_RESP_OKAY))     ||
                   ((tr.lock == AXI4_LOCK_EXCLUSIVE) &&
                    (tr.resp == AXI4_RESP_EXOKAY));

        if (do_write) begin
            for (int beat = 0; beat <= tr.len; beat++) begin
                bit [AXI4_ADDR_WIDTH-1:0] beat_addr;
                bit [AXI4_ADDR_WIDTH-1:0] bus_base;
                bit [AXI4_STRB_WIDTH-1:0] legal_mask;

                beat_addr  = axi4_calc_beat_addr(tr.addr, beat, tr.size,
                                                 tr.burst, tr.len);
                bus_base   = axi4_bus_word_base(beat_addr);
                legal_mask = axi4_calc_legal_lane_mask(tr.addr, beat, tr.size,
                                                       tr.burst, tr.len);

                if ((tr.strb[beat] & ~legal_mask) != '0) begin
                    mismatch_count++;
                    `uvm_error(get_type_name(),
                               $sformatf("[WSTRB_LEGALITY_FAIL] ADDR=0x%08h beat=%0d STRB=0b%0b legal=0b%0b",
                                         tr.addr, beat, tr.strb[beat], legal_mask))
                end

                for (int lane = 0; lane < AXI4_STRB_WIDTH; lane++) begin
                    if (legal_mask[lane] && tr.strb[beat][lane]) begin
                        ref_mem[bus_base + lane] = tr.data[beat][lane*8 +: 8];
                        `uvm_info(get_type_name(),
                                  $sformatf("[REF_MEM_WRITE] Addr=0x%08h Data=0x%02h",
                                            bus_base + lane, tr.data[beat][lane*8 +: 8]),
                                  UVM_HIGH)
                    end
                end
            end
        end else begin
            `uvm_info(get_type_name(),
                      $sformatf("[REF_MEM_WRITE_IGNORED] ADDR=0x%08h LOCK=%s RESP=%s",
                                tr.addr, tr.lock.name(), tr.resp.name()), UVM_MEDIUM)
        end
        //Hoang Ho - END: response-driven reference-memory commit policy
    endfunction : update_ref_mem

    // =========================================================================
    // check_ref_mem - verify READ transaction against reference memory
    // =========================================================================
    function void check_ref_mem(axi4_transaction tr);
        //Hoang Ho - BEGIN: compare only bytes that belong to each AXI4 transfer
        // Inactive lanes are not protocol data and are therefore ignored. Read
        // beats carrying SLVERR/DECERR are checked for response only, not RDATA.
        for (int beat = 0; beat <= tr.len; beat++) begin
            bit [AXI4_ADDR_WIDTH-1:0] beat_addr;
            bit [AXI4_ADDR_WIDTH-1:0] bus_base;
            bit [AXI4_STRB_WIDTH-1:0] legal_mask;

            if (tr.rresp[beat] inside {AXI4_RESP_SLVERR, AXI4_RESP_DECERR})
                continue;

            beat_addr  = axi4_calc_beat_addr(tr.addr, beat, tr.size,
                                             tr.burst, tr.len);
            bus_base   = axi4_bus_word_base(beat_addr);
            legal_mask = axi4_calc_legal_lane_mask(tr.addr, beat, tr.size,
                                                   tr.burst, tr.len);

            for (int lane = 0; lane < AXI4_STRB_WIDTH; lane++) begin
                bit [AXI4_ADDR_WIDTH-1:0] byte_addr;
                bit [7:0] exp_byte;
                bit [7:0] act_byte;

                if (!legal_mask[lane])
                    continue;

                byte_addr = bus_base + lane;
                exp_byte  = ref_mem.exists(byte_addr) ? ref_mem[byte_addr] : 8'h00;
                act_byte  = tr.data[beat][lane*8 +: 8];

                if (exp_byte !== act_byte) begin
                    mismatch_count++;
                    `uvm_error(get_type_name(),
                               $sformatf("[DATA_INTEGRITY_FAIL] Beat=%0d Lane=%0d Addr=0x%08h Expected=0x%02h Actual=0x%02h",
                                         beat, lane, byte_addr, exp_byte, act_byte))
                end
            end
        end
        //Hoang Ho - END: compare only bytes that belong to each AXI4 transfer
    endfunction : check_ref_mem

    // =========================================================================
    // compare_transactions - detailed comparison using do_compare
    //   Uses axi4_transaction::compare() which internally calls do_compare
    //   for all fields including the manually-handled rresp[] array.
    // =========================================================================
    function void compare_transactions(
        axi4_transaction expected,
        axi4_transaction actual,
        string           dir_str
    );
        if (expected.compare(actual)) begin
            match_count++;
            `uvm_info(get_type_name(),
                      $sformatf("[%s] MATCH #%0d: ID=0x%0h ADDR=0x%08h LEN=%0d",
                                dir_str, match_count,
                                actual.id, actual.addr, actual.len), UVM_MEDIUM)
            if (actual.dir == AXI4_WRITE) begin
                update_ref_mem(actual);
            end else begin
                check_ref_mem(actual);
            end
        end else begin
            mismatch_count++;
            `uvm_error(get_type_name(),
                       $sformatf("[%s] MISMATCH #%0d: ID=0x%0h ADDR=0x%08h LEN=%0d",
                                 dir_str, mismatch_count,
                                 actual.id, actual.addr, actual.len))
            `uvm_info(get_type_name(),
                      {"Expected:\n", expected.sprint()}, UVM_LOW)
            `uvm_info(get_type_name(),
                      {"Actual:\n", actual.sprint()}, UVM_LOW)
        end
    endfunction : compare_transactions


    //Hoang Ho - BEGIN: completion helper used by drain-aware tests
    function int unsigned pending_count();
        return master_wr_q.size() + master_rd_q.size() +
               slave_wr_q.size()  + slave_rd_q.size();
    endfunction : pending_count
    //Hoang Ho - END: completion helper used by drain-aware tests

    // =========================================================================
    // check_phase - flag errors for unmatched/mismatched transactions
    // =========================================================================
    function void check_phase(uvm_phase phase);
        int unsigned unmatched;
        unmatched = master_wr_q.size() + master_rd_q.size()
                  + slave_wr_q.size()  + slave_rd_q.size();

        if (mismatch_count > 0)
            `uvm_error(get_type_name(),
                       $sformatf("%0d transaction MISMATCHES detected", mismatch_count))

        //Hoang Ho - unmatched traffic is a functional failure, not a warning.
        if (unmatched > 0)
            `uvm_error(get_type_name(),
                       $sformatf("%0d unmatched transactions at end of simulation",
                                 unmatched))
    endfunction : check_phase

    // =========================================================================
    // report_phase - print summary statistics
    // =========================================================================
    function void report_phase(uvm_phase phase);
        int unsigned unmatched;
        string result_str;

        unmatched = master_wr_q.size() + master_rd_q.size()
                  + slave_wr_q.size()  + slave_rd_q.size();

        result_str = (mismatch_count == 0 && unmatched == 0) ? "PASS" : "FAIL";

        `uvm_info(get_type_name(), $sformatf({
            "\n",
            "========================================\n",
            "         SCOREBOARD SUMMARY\n",
            "========================================\n",
            "  Master transactions : %0d\n",
            "  Slave transactions  : %0d\n",
            "  Matches             : %0d\n",
            "  Mismatches          : %0d\n",
            "  Unmatched master WR : %0d\n",
            "  Unmatched master RD : %0d\n",
            "  Unmatched slave  WR : %0d\n",
            "  Unmatched slave  RD : %0d\n",
            "========================================\n",
            "  RESULT : %s\n",
            "========================================"},
            total_master, total_slave,
            match_count, mismatch_count,
            master_wr_q.size(), master_rd_q.size(),
            slave_wr_q.size(), slave_rd_q.size(),
            result_str), UVM_NONE)
    endfunction : report_phase

endclass : axi4_scoreboard