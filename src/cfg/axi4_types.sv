//==============================================================================
// OWNERSHIP NOTE
//   Original unmarked code in this file : Huy Le / original AXI4-VIP repo
//   Blocks marked //Hoang Ho            : Hoang Ho functional/spec fixes
//==============================================================================
//==============================================================================
// File        : axi4_types.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 protocol parameters, enums, and typedefs.
//               All values follow ARM AMBA AXI4 specification (IHI0022H.c).
//               This file is `included inside axi4_pkg.sv - do NOT add
//               package/endpackage here.
//==============================================================================

// Huy Le: original architecture and baseline implementation.

    // Hoang Ho: compile-time widths are shared with axi4_if, axi4_sva and tb_top.
    `include "cfg/axi4_compile_cfg.svh"

    //-------------------------------------------------------------------------
    // 1. Bus-width parameters
    //-------------------------------------------------------------------------
    parameter AXI4_ADDR_WIDTH = `AXI4_ADDR_WIDTH_CFG;
    parameter AXI4_DATA_WIDTH = `AXI4_DATA_WIDTH_CFG;
    parameter AXI4_STRB_WIDTH = AXI4_DATA_WIDTH / 8;
    parameter AXI4_ID_WIDTH   = `AXI4_ID_WIDTH_CFG;
    parameter AXI4_LEN_WIDTH  = 8;
    localparam int unsigned AXI4_MAX_SIZE = $clog2(AXI4_STRB_WIDTH);

    //-------------------------------------------------------------------------
    // 2. Burst type
    //    Defines how the address is calculated for each transfer in a burst.
    //        FIXED - same address for every transfer  (e.g. FIFO access)
    //        INCR  - incrementing address             (most common)
    //        WRAP  - wrapping burst                   (cache-line fills)
    //-------------------------------------------------------------------------
    typedef enum bit [1:0] {
        AXI4_BURST_FIXED = 2'b00,
        AXI4_BURST_INCR  = 2'b01,
        AXI4_BURST_WRAP  = 2'b10
        // 2'b11 is reserved
    } axi4_burst_type_e;

    //-------------------------------------------------------------------------
    // 3. Response type
    //    Indicates the status of a read/write transaction.
    //        OKAY   - normal access success
    //        EXOKAY - exclusive access success
    //        SLVERR - slave error (valid address, slave-side failure)
    //        DECERR - decode error (no slave at that address)
    //-------------------------------------------------------------------------
    typedef enum bit [1:0] {
        AXI4_RESP_OKAY   = 2'b00,
        AXI4_RESP_EXOKAY = 2'b01,
        AXI4_RESP_SLVERR = 2'b10,
        AXI4_RESP_DECERR = 2'b11
    } axi4_resp_e;

    //-------------------------------------------------------------------------
    // 4. Burst size
    //      Number of bytes per transfer = 2^SIZE.
    //      Must not exceed the data bus width (DATA_WIDTH / 8 bytes).
    //-------------------------------------------------------------------------
    typedef enum bit [2:0] {
        AXI4_SIZE_1B   = 3'b000,   //   1 byte  per transfer
        AXI4_SIZE_2B   = 3'b001,   //   2 bytes per transfer
        AXI4_SIZE_4B   = 3'b010,   //   4 bytes per transfer
        AXI4_SIZE_8B   = 3'b011,   //   8 bytes per transfer
        AXI4_SIZE_16B  = 3'b100,   //  16 bytes per transfer
        AXI4_SIZE_32B  = 3'b101,   //  32 bytes per transfer
        AXI4_SIZE_64B  = 3'b110,   //  64 bytes per transfer
        AXI4_SIZE_128B = 3'b111    // 128 bytes per transfer
    } axi4_size_e;

    //-------------------------------------------------------------------------
    // 5. Lock type
    //        NORMAL    - normal access
    //        EXCLUSIVE - exclusive access (for atomic read-modify-write)
    //-------------------------------------------------------------------------
    typedef enum bit {
        AXI4_LOCK_NORMAL    = 1'b0,
        AXI4_LOCK_EXCLUSIVE = 1'b1
    } axi4_lock_e;

    //-------------------------------------------------------------------------
    // 6. Transaction direction (VIP-internal, not in AXI spec)
    //      Used inside the sequence item to distinguish write vs read.
    //-------------------------------------------------------------------------
    typedef enum bit {
        AXI4_READ  = 1'b0,
        AXI4_WRITE = 1'b1
    } axi4_dir_e;

    //-------------------------------------------------------------------------
    // 7. Write channel ordering (VIP-internal, not in AXI spec)
    //      Controls the relative timing of AW and W channels.
    //        PARALLEL   - AW and W start simultaneously (default, most common)
    //        AW_BEFORE_W - AW handshake completes before W data begins
    //        W_BEFORE_AW - W data begins before AW address is sent
    //-------------------------------------------------------------------------
    typedef enum bit [1:0] {
        AXI4_WR_PARALLEL    = 2'b00,
        AXI4_WR_AW_BEFORE_W = 2'b01,
        AXI4_WR_W_BEFORE_AW = 2'b10
    } axi4_wr_order_e;

    //-------------------------------------------------------------------------
    // 8. Event wrapper class
    //    Used to wrap SystemVerilog built-in event type, because event is not a
    //    class and cannot be dynamically instantiated with 'new'.
    //-------------------------------------------------------------------------
    class axi4_event_wrapper;
        event ev;
    endclass

    // Hoang Ho: shared AXI4 address, lane, and 4KB helper functions
    // These helpers centralize the functional rules used by the transaction,
    // slave model, scoreboard, and coverage. Keeping one implementation avoids
    // common-mode drift between components.
    typedef bit [AXI4_ADDR_WIDTH-1:0] axi4_addr_t;
    typedef bit [AXI4_DATA_WIDTH-1:0] axi4_data_t;
    typedef bit [AXI4_STRB_WIDTH-1:0] axi4_strb_t;
    typedef bit [AXI4_ID_WIDTH-1:0]   axi4_id_t;

    function automatic bit axi4_supported_data_width();
        return AXI4_DATA_WIDTH inside {32, 64, 128, 256, 512, 1024};
    endfunction : axi4_supported_data_width

    function automatic axi4_size_e axi4_full_bus_size();
        return axi4_size_e'(AXI4_MAX_SIZE);
    endfunction : axi4_full_bus_size

    // Hoang Ho: deterministic byte pattern that exercises every lane at every width.
    function automatic axi4_data_t axi4_make_data_pattern(
        int unsigned tag,
        int unsigned beat_idx
    );
        axi4_data_t value;
        value = '0;
        for (int lane = 0; lane < AXI4_STRB_WIDTH; lane++)
            value[lane*8 +: 8] = byte'((tag + beat_idx*AXI4_STRB_WIDTH + lane) & 8'hFF);
        return value;
    endfunction : axi4_make_data_pattern

    // Huy Le: several directed demos used recognizable 32-bit constants.
    // Hoang Ho: retain the original value in bits [31:0], then fill every
    // additional 32-bit chunk with a deterministic variant. At DATA_WIDTH=32
    // the waveform is unchanged; wider profiles no longer leave upper lanes 0.
    function automatic axi4_data_t axi4_expand_legacy_word(
        bit [31:0]    legacy_word,
        int unsigned beat_idx
    );
        axi4_data_t value;
        value = '0;
        for (int chunk = 0; chunk < AXI4_DATA_WIDTH/32; chunk++) begin
            value[chunk*32 +: 32] = legacy_word
                                   + beat_idx
                                   + (32'h0101_0101 * chunk);
        end
        return value;
    endfunction : axi4_expand_legacy_word

    function automatic int unsigned axi4_num_bytes(bit [2:0] size_i);
        return (1 << size_i);
    endfunction : axi4_num_bytes

    function automatic axi4_addr_t axi4_aligned_addr(
        axi4_addr_t start_addr,
        bit [2:0]   size_i
    );
        int unsigned nbytes;
        nbytes = axi4_num_bytes(size_i);
        return (start_addr / nbytes) * nbytes;
    endfunction : axi4_aligned_addr

    function automatic axi4_addr_t axi4_calc_beat_addr(
        axi4_addr_t          start_addr,
        int unsigned         beat_idx,
        bit [2:0]            size_i,
        axi4_burst_type_e    burst_i,
        bit [7:0]            len_i
    );
        int unsigned nbytes;
        int unsigned beats;
        int unsigned total_bytes;
        axi4_addr_t aligned_start;
        axi4_addr_t wrap_boundary;
        axi4_addr_t addr_i;

        nbytes       = axi4_num_bytes(size_i);
        beats        = len_i + 1;
        aligned_start = axi4_aligned_addr(start_addr, size_i);

        case (burst_i)
            AXI4_BURST_FIXED: addr_i = start_addr;

            AXI4_BURST_INCR: begin
                if (beat_idx == 0)
                    addr_i = start_addr;
                else
                    addr_i = aligned_start + beat_idx * nbytes;
            end

            AXI4_BURST_WRAP: begin
                total_bytes  = nbytes * beats;
                wrap_boundary = (start_addr / total_bytes) * total_bytes;
                if (beat_idx == 0) begin
                    addr_i = start_addr;
                end else begin
                    addr_i = aligned_start + beat_idx * nbytes;
                    while (addr_i >= wrap_boundary + total_bytes)
                        addr_i = addr_i - total_bytes;
                end
            end

            default: addr_i = start_addr;
        endcase

        return addr_i;
    endfunction : axi4_calc_beat_addr

    function automatic axi4_addr_t axi4_bus_word_base(axi4_addr_t beat_addr);
        return (beat_addr / AXI4_STRB_WIDTH) * AXI4_STRB_WIDTH;
    endfunction : axi4_bus_word_base

    function automatic axi4_strb_t axi4_calc_legal_lane_mask(
        axi4_addr_t          start_addr,
        int unsigned         beat_idx,
        bit [2:0]            size_i,
        axi4_burst_type_e    burst_i,
        bit [7:0]            len_i
    );
        axi4_addr_t beat_addr;
        axi4_addr_t bus_base;
        axi4_addr_t aligned_start;
        axi4_strb_t mask;
        int unsigned nbytes;
        int unsigned lower_lane;
        int unsigned upper_lane;
        bit first_transfer_rules;

        beat_addr            = axi4_calc_beat_addr(start_addr, beat_idx, size_i, burst_i, len_i);
        bus_base             = axi4_bus_word_base(beat_addr);
        aligned_start        = axi4_aligned_addr(start_addr, size_i);
        nbytes               = axi4_num_bytes(size_i);
        lower_lane           = beat_addr - bus_base;
        first_transfer_rules = (beat_idx == 0) || (burst_i == AXI4_BURST_FIXED);

        // For an unaligned first transfer, bytes below AxADDR are not part of
        // the transfer. The lane range must not wrap around within one beat.
        if (first_transfer_rules && ((start_addr % nbytes) != 0))
            upper_lane = (aligned_start + nbytes - 1) - bus_base;
        else
            upper_lane = lower_lane + nbytes - 1;

        mask = '0;
        for (int lane = lower_lane; lane <= upper_lane; lane++) begin
            if (lane < AXI4_STRB_WIDTH)
                mask[lane] = 1'b1;
        end
        return mask;
    endfunction : axi4_calc_legal_lane_mask

    function automatic bit axi4_burst_crosses_4kb(
        axi4_addr_t          start_addr,
        bit [2:0]            size_i,
        axi4_burst_type_e    burst_i,
        bit [7:0]            len_i
    );
        longint unsigned first_byte;
        longint unsigned last_byte;
        longint unsigned aligned_start;
        longint unsigned wrap_boundary;
        longint unsigned nbytes;
        longint unsigned beats;
        longint unsigned total_bytes;

        nbytes        = axi4_num_bytes(size_i);
        beats         = len_i + 1;
        total_bytes   = nbytes * beats;
        aligned_start = (start_addr / nbytes) * nbytes;

        case (burst_i)
            AXI4_BURST_FIXED: begin
                first_byte = start_addr;
                last_byte  = aligned_start + nbytes - 1;
            end
            AXI4_BURST_INCR: begin
                first_byte = start_addr;
                last_byte  = aligned_start + total_bytes - 1;
            end
            AXI4_BURST_WRAP: begin
                wrap_boundary = (start_addr / total_bytes) * total_bytes;
                first_byte = wrap_boundary;
                last_byte  = wrap_boundary + total_bytes - 1;
            end
            default: return 1'b1;
        endcase

        return ((first_byte >> 12) != (last_byte >> 12));
    endfunction : axi4_burst_crosses_4kb
