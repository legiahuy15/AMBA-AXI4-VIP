//==============================================================================
// File        : axi4_exclusive_fail_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Exclusive-access reservation corner-case sequence.
//               Exercises how an exclusive reservation is invalidated by an
//               intervening store (AXI4 spec A7.2).
//
//               Cases:
//                 A. Excl read -> normal write SAME id/addr -> excl write FAILS
//                 B. Excl read -> normal write OTHER id/same addr -> excl write FAILS
//                 C. Excl read -> excl write uninterrupted -> SUCCEEDS
//                 D. Excl read -> normal write unrelated addr -> excl write SUCCEEDS
//
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_EXCLUSIVE_FAIL_SEQ_INCLUDED_
`define AXI4_EXCLUSIVE_FAIL_SEQ_INCLUDED_

class axi4_exclusive_fail_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_exclusive_fail_seq)

    int unsigned errors = 0;

    function new(string name = "axi4_exclusive_fail_seq");
        super.new(name);
    endfunction : new

    task send_txn(input  axi4_dir_e                 a_dir,
                  input  bit [AXI4_ID_WIDTH-1:0]    a_id,
                  input  bit [AXI4_ADDR_WIDTH-1:0]  a_addr,
                  input  axi4_lock_e                a_lock,
                  output axi4_transaction           tr_out);
        axi4_transaction tr;

        tr = axi4_transaction::type_id::create("excl_fail_tr");

        start_item(tr);

        if (!tr.randomize() with {
            dir   == a_dir;
            id    == a_id;
            addr  == a_addr;
            lock  == a_lock;

            burst == AXI4_BURST_INCR;
            size  == AXI4_SIZE_4B;
            len   == 0;

            //Hoang Ho - BEGIN: keep exclusive attributes deterministic
            // The enhanced slave model matches exclusive reservations using:
            // ID, address, size, length, burst, cache, prot and region.
            // Therefore these attributes must be fixed so the exclusive read
            // and the matching exclusive write use identical attributes.
            cache  == 4'h3;
            prot   == 3'b000;
            region == 4'h0;
            //Hoang Ho - END: keep exclusive attributes deterministic

            foreach (strb[i]) strb[i] == '1;
        }) begin
            `uvm_fatal(get_type_name(), "Randomization failed in exclusive-fail seq")
        end

        finish_item(tr);

        wait (tr.completed); //Hoang Ho - persistent completion wait

        tr_out = tr;
    endtask : send_txn

    function void expect_resp(axi4_resp_e actual, axi4_resp_e exp, string tag);
        if (actual != exp) begin
            errors++;
            `uvm_error(get_type_name(),
                       $sformatf("%s: expected %s, got %s",
                                 tag, exp.name(), actual.name()))
        end else begin
            `uvm_info(get_type_name(),
                      $sformatf("%s: OK (%s)", tag, actual.name()), UVM_LOW)
        end
    endfunction : expect_resp

    virtual task body();
        axi4_transaction rd, wr;

        `uvm_info(get_type_name(),
                  "Starting exclusive reservation corner-case sequence",
                  UVM_MEDIUM)

        // Case A: normal write with same ID/address clears reservation.
        send_txn(AXI4_READ,  4'h5, 32'h0000_A000, AXI4_LOCK_EXCLUSIVE, rd);
        expect_resp(rd.rresp[0], AXI4_RESP_EXOKAY, "A.excl_read");

        send_txn(AXI4_WRITE, 4'h5, 32'h0000_A000, AXI4_LOCK_NORMAL, wr);
        expect_resp(wr.resp, AXI4_RESP_OKAY, "A.normal_write");

        send_txn(AXI4_WRITE, 4'h5, 32'h0000_A000, AXI4_LOCK_EXCLUSIVE, wr);
        expect_resp(wr.resp, AXI4_RESP_OKAY, "A.excl_write_must_fail");

        // Case B: normal write from another ID to same address clears reservation.
        send_txn(AXI4_READ,  4'h6, 32'h0000_A100, AXI4_LOCK_EXCLUSIVE, rd);
        expect_resp(rd.rresp[0], AXI4_RESP_EXOKAY, "B.excl_read");

        send_txn(AXI4_WRITE, 4'h9, 32'h0000_A100, AXI4_LOCK_NORMAL, wr);
        expect_resp(wr.resp, AXI4_RESP_OKAY, "B.other_id_write");

        send_txn(AXI4_WRITE, 4'h6, 32'h0000_A100, AXI4_LOCK_EXCLUSIVE, wr);
        expect_resp(wr.resp, AXI4_RESP_OKAY, "B.excl_write_must_fail");

        // Case C: uninterrupted exclusive read/write pair must succeed.
        send_txn(AXI4_READ,  4'h7, 32'h0000_A200, AXI4_LOCK_EXCLUSIVE, rd);
        expect_resp(rd.rresp[0], AXI4_RESP_EXOKAY, "C.excl_read");

        send_txn(AXI4_WRITE, 4'h7, 32'h0000_A200, AXI4_LOCK_EXCLUSIVE, wr);
        expect_resp(wr.resp, AXI4_RESP_EXOKAY, "C.excl_write_must_succeed");

        // Case D: unrelated normal write must not clear the reservation.
        send_txn(AXI4_READ,  4'h8, 32'h0000_A300, AXI4_LOCK_EXCLUSIVE, rd);
        expect_resp(rd.rresp[0], AXI4_RESP_EXOKAY, "D.excl_read");

        send_txn(AXI4_WRITE, 4'h8, 32'h0000_B000, AXI4_LOCK_NORMAL, wr);
        expect_resp(wr.resp, AXI4_RESP_OKAY, "D.unrelated_write");

        send_txn(AXI4_WRITE, 4'h8, 32'h0000_A300, AXI4_LOCK_EXCLUSIVE, wr);
        expect_resp(wr.resp, AXI4_RESP_EXOKAY, "D.excl_write_must_succeed");

        `uvm_info(get_type_name(),
                  $sformatf("Exclusive reservation corner-case sequence complete (%0d response errors)",
                            errors),
                  UVM_MEDIUM)
    endtask : body

endclass : axi4_exclusive_fail_seq

`endif // AXI4_EXCLUSIVE_FAIL_SEQ_INCLUDED_