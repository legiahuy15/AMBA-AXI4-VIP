//==============================================================================
// File        : axi4_burst_sweep_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Burst type, size, and length sweep.
//               Hoang Ho generalized the size loop to every transfer size that
//               is legal for the compiled 32..1024-bit data bus. INCR vectors
//               that cannot fit inside one 4KB page are skipped as required by
//               AXI4 rather than treated as missing legal combinations.
//==============================================================================

`ifndef AXI4_BURST_SWEEP_SEQ_INCLUDED_
`define AXI4_BURST_SWEEP_SEQ_INCLUDED_

class axi4_burst_sweep_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_burst_sweep_seq)

    function new(string name = "axi4_burst_sweep_seq");
        super.new(name);
    endfunction : new

    protected task send_sweep_tx(
        input string             name_i,
        input axi4_dir_e         dir_i,
        input axi4_burst_type_e  burst_i,
        input axi4_size_e        size_i,
        input bit [7:0]          len_i,
        input bit                error_region,
        input bit                decode_error
    );
        axi4_transaction tr;
        axi4_addr_t forced_addr;

        if (error_region)
            forced_addr = decode_error ? axi4_addr_t'(32'hF000_0000)
                                       : axi4_addr_t'(32'hE000_0000);
        else
            forced_addr = '0;

        tr = axi4_transaction::type_id::create(name_i);
        start_item(tr);
        if (!tr.randomize() with {
            dir   == dir_i;
            id    inside {[id_lo : id_hi]};
            burst == burst_i;
            size  == size_i;
            len   == len_i;
            if (error_region)
                addr == forced_addr;
            else {
                addr inside {[addr_lo : addr_hi]};
                addr < 32'hE000_0000;
            }
        }) `uvm_fatal(get_type_name(), $sformatf("Randomization failed for %s", name_i))
        finish_item(tr);
    endtask : send_sweep_tx

    virtual task body();
        int unsigned count;
        bit [7:0] fixed_len_values[5] = '{0, 1, 3, 7, 15};
        bit [7:0] wrap_len_values[4]  = '{1, 3, 7, 15};
        bit [7:0] incr_len_values[6]  = '{0, 2, 10, 32, 100, 255};

        count = 0;
        `uvm_info(get_type_name(),
                  $sformatf("Starting burst sweep: SIZE=0..%0d for DATA_WIDTH=%0d",
                            AXI4_MAX_SIZE, AXI4_DATA_WIDTH), UVM_MEDIUM)

        // FIXED: every legal size, lengths up to 16 beats.
        foreach (fixed_len_values[l]) begin
            for (int unsigned s = 0; s <= AXI4_MAX_SIZE; s++) begin
                axi4_size_e size_val;
                size_val = axi4_size_e'(s);
                send_sweep_tx($sformatf("fixed_wr_%0d", count++), AXI4_WRITE,
                              AXI4_BURST_FIXED, size_val, fixed_len_values[l], 0, 0);
                send_sweep_tx($sformatf("fixed_rd_%0d", count++), AXI4_READ,
                              AXI4_BURST_FIXED, size_val, fixed_len_values[l], 0, 0);
            end
        end

        // WRAP: legal lengths are 2/4/8/16 beats; the maximum legal container
        // is 16*128=2048 bytes, so every supported size remains inside 4KB.
        foreach (wrap_len_values[l]) begin
            for (int unsigned s = 0; s <= AXI4_MAX_SIZE; s++) begin
                axi4_size_e size_val;
                size_val = axi4_size_e'(s);
                send_sweep_tx($sformatf("wrap_wr_%0d", count++), AXI4_WRITE,
                              AXI4_BURST_WRAP, size_val, wrap_len_values[l], 0, 0);
                send_sweep_tx($sformatf("wrap_rd_%0d", count++), AXI4_READ,
                              AXI4_BURST_WRAP, size_val, wrap_len_values[l], 0, 0);
            end
        end

        // INCR: include each length-bin representative only when its transfer
        // container fits in one 4KB page for the current size.
        foreach (incr_len_values[l]) begin
            for (int unsigned s = 0; s <= AXI4_MAX_SIZE; s++) begin
                int unsigned bytes_per_beat;
                int unsigned total_bytes;
                axi4_size_e size_val;
                size_val      = axi4_size_e'(s);
                bytes_per_beat = 1 << s;
                total_bytes    = bytes_per_beat * (incr_len_values[l] + 1);
                if (total_bytes <= 4096) begin
                    send_sweep_tx($sformatf("incr_wr_%0d", count++), AXI4_WRITE,
                                  AXI4_BURST_INCR, size_val, incr_len_values[l], 0, 0);
                    send_sweep_tx($sformatf("incr_rd_%0d", count++), AXI4_READ,
                                  AXI4_BURST_INCR, size_val, incr_len_values[l], 0, 0);
                end
            end
        end

        // Error responses are orthogonal to width. Use one full-width beat so
        // every configured profile also exercises SLVERR and DECERR paths.
        send_sweep_tx($sformatf("slverr_wr_%0d", count++), AXI4_WRITE,
                      AXI4_BURST_INCR, axi4_size_e'(AXI4_MAX_SIZE), 0, 1, 0);
        send_sweep_tx($sformatf("slverr_rd_%0d", count++), AXI4_READ,
                      AXI4_BURST_INCR, axi4_size_e'(AXI4_MAX_SIZE), 0, 1, 0);
        send_sweep_tx($sformatf("decerr_wr_%0d", count++), AXI4_WRITE,
                      AXI4_BURST_INCR, axi4_size_e'(AXI4_MAX_SIZE), 0, 1, 1);
        send_sweep_tx($sformatf("decerr_rd_%0d", count++), AXI4_READ,
                      AXI4_BURST_INCR, axi4_size_e'(AXI4_MAX_SIZE), 0, 1, 1);

        `uvm_info(get_type_name(),
                  $sformatf("Burst sweep complete: %0d transactions", count), UVM_MEDIUM)
    endtask : body

endclass : axi4_burst_sweep_seq

`endif // AXI4_BURST_SWEEP_SEQ_INCLUDED_
