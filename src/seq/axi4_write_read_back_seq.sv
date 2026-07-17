//==============================================================================
// File        : axi4_write_read_back_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Write-then-read-back sequence.
//               Writes data to a given address, then reads back from the
//               same address with matching burst parameters. Useful for
//               verifying data integrity through the slave memory model.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

//Huy Le: original write/read-back sequence.
//Hoang Ho: default transfer size follows the compiled data-bus width.

class axi4_write_read_back_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_write_read_back_seq)

    // =========================================================================
    // Configurable fields
    // =========================================================================
    rand bit [AXI4_ADDR_WIDTH-1:0] addr;
    rand bit [AXI4_LEN_WIDTH-1:0]  len;
    rand axi4_size_e               size;
    rand axi4_burst_type_e         burst;

    constraint c_addr_range { addr inside {[addr_lo : addr_hi]}; }
    constraint c_len_default { soft len inside {[0:15]}; }
    constraint c_size_default { soft size == axi4_size_e'(AXI4_MAX_SIZE); }
    constraint c_burst_default { soft burst == AXI4_BURST_INCR; }

    // Hoang Ho: staged sequence randomization must obey the same protocol
    // legality as axi4_transaction. These fields are randomized first and are
    // then copied into the transaction with inline equality constraints. If
    // the sequence chooses an illegal combination, transaction randomization
    // correctly rejects it before any bus traffic is generated.
    //
    // The equations below are deliberately solver-native. QuestaSim 10.6b can
    // fail to backtrack reliably when a user function is called from a
    // constraint, so no helper function is used here.
    constraint c_size_legal {
        size <= AXI4_MAX_SIZE;
    }

    // Hoang Ho: choose transfer attributes before the address. The address is
    // the field that must move to keep the complete burst inside one 4KB page.
    constraint c_protocol_solve_order {
        solve size before addr;
        solve len before addr;
        solve burst before addr;
    }

    // Hoang Ho: FIXED and INCR use the aligned transfer container when checking
    // the 4KB rule. For an unaligned first INCR beat, bytes below AxADDR are not
    // transferred, but the burst still occupies the aligned beat container.
    constraint c_4kb_boundary {
        if (burst == AXI4_BURST_FIXED) {
            (((addr[11:0] >> size) << size) + (1 << size)) <= 4096;
        }
        else if (burst == AXI4_BURST_INCR) {
            (((addr[11:0] >> size) << size) +
             ((len + 1) << size)) <= 4096;
        }
    }

    // Hoang Ho: AXI4 WRAP bursts contain exactly 2, 4, 8, or 16 transfers and
    // the start address is aligned to the transfer size. Since the total WRAP
    // container is a power of two no larger than 2048 bytes, a legal WRAP
    // container cannot cross a 4KB boundary.
    constraint c_wrap_len {
        (burst == AXI4_BURST_WRAP) -> len inside {1, 3, 7, 15};
    }

    constraint c_wrap_align {
        (burst == AXI4_BURST_WRAP) ->
            (addr % (1 << size)) == 0;
    }

    // Hoang Ho: FIXED bursts are limited to 16 transfers in AXI4.
    constraint c_fixed_len {
        (burst == AXI4_BURST_FIXED) -> len <= 15;
    }

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_write_read_back_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // body - write then read-back with matching parameters
    // =========================================================================
    virtual task body();
        axi4_transaction wr_tr, rd_tr;

        // Phase 1: Write
        wr_tr = axi4_transaction::type_id::create("wr_tr");
        start_item(wr_tr);

        if (!wr_tr.randomize() with {
            dir   == AXI4_WRITE;
            addr  == local::addr;
            len   == local::len;
            size  == local::size;
            burst == local::burst;
            id    inside {[id_lo : id_hi]};
        }) `uvm_fatal(get_type_name(), "Randomization failed for write transaction")

        finish_item(wr_tr);
        wait (wr_tr.completed); //Hoang Ho: persistent completion wait

        `uvm_info(get_type_name(),
                  $sformatf("Write phase: ADDR=0x%08h LEN=%0d SIZE=%s BURST=%s",
                             wr_tr.addr, wr_tr.len, wr_tr.size.name(), wr_tr.burst.name()),
                  UVM_MEDIUM)

        // Phase 2: Read-back (same addr, len, size, burst)
        rd_tr = axi4_transaction::type_id::create("rd_tr");
        start_item(rd_tr);

        if (!rd_tr.randomize() with {
            dir   == AXI4_READ;
            addr  == wr_tr.addr;
            len   == wr_tr.len;
            size  == wr_tr.size;
            burst == wr_tr.burst;
            id    inside {[id_lo : id_hi]};
        }) `uvm_fatal(get_type_name(), "Randomization failed for read-back transaction")

        finish_item(rd_tr);
        wait (rd_tr.completed); //Hoang Ho: persistent completion wait

        `uvm_info(get_type_name(),
                  $sformatf("Read-back phase: ADDR=0x%08h LEN=%0d - data integrity check via scoreboard",
                            rd_tr.addr, rd_tr.len),
                  UVM_MEDIUM)
    endtask : body

endclass : axi4_write_read_back_seq
