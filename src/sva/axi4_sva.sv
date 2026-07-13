//=============================================================================
// OWNERSHIP NOTE
//   Original unmarked code in this file : Huy Le / original AXI4-VIP repo
//   Blocks marked //Hoang Ho            : Hoang Ho functional/spec fixes
//=============================================================================
//=============================================================================
// File        : axi4_sva.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 protocol assertions (SVA) module.
//               Checks compliance with ARM AMBA AXI4 specification.
//               Designed to be bound to axi4_if via SystemVerilog `bind`.
//=============================================================================

`timescale 1ns/1ps

module axi4_sva #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input logic                     clk,
    input logic                     rst_n,

    // AW Channel
    input logic [ID_WIDTH-1:0]      AWID,
    input logic [ADDR_WIDTH-1:0]    AWADDR,
    input logic [7:0]               AWLEN,
    input logic [2:0]               AWSIZE,
    input logic [1:0]               AWBURST,
    input logic                     AWLOCK,
    input logic [3:0]               AWCACHE,
    input logic [2:0]               AWPROT,
    input logic [3:0]               AWQOS,
    input logic [3:0]               AWREGION,
    input logic                     AWVALID,
    input logic                     AWREADY,

    // W Channel
    input logic [DATA_WIDTH-1:0]    WDATA,
    input logic [DATA_WIDTH/8-1:0]  WSTRB,
    input logic                     WLAST,
    input logic                     WVALID,
    input logic                     WREADY,

    // B Channel
    input logic [ID_WIDTH-1:0]      BID,
    input logic [1:0]               BRESP,
    input logic                     BVALID,
    input logic                     BREADY,

    // AR Channel
    input logic [ID_WIDTH-1:0]      ARID,
    input logic [ADDR_WIDTH-1:0]    ARADDR,
    input logic [7:0]               ARLEN,
    input logic [2:0]               ARSIZE,
    input logic [1:0]               ARBURST,
    input logic                     ARLOCK,
    input logic [3:0]               ARCACHE,
    input logic [2:0]               ARPROT,
    input logic [3:0]               ARQOS,
    input logic [3:0]               ARREGION,
    input logic                     ARVALID,
    input logic                     ARREADY,

    // R Channel
    input logic [ID_WIDTH-1:0]      RID,
    input logic [DATA_WIDTH-1:0]    RDATA,
    input logic [1:0]               RRESP,
    input logic                     RLAST,
    input logic                     RVALID,
    input logic                     RREADY
);

    //-------------------------------------------------------------------------
    // Local parameters
    //-------------------------------------------------------------------------
    localparam STRB_WIDTH = DATA_WIDTH / 8;


    //Hoang Ho - BEGIN: local AXI4 helper functions used by protocol assertions
    function automatic longint unsigned f_num_bytes(logic [2:0] size_i);
        return (64'd1 << size_i);
    endfunction : f_num_bytes

    function automatic bit f_burst_crosses_4kb(
        logic [ADDR_WIDTH-1:0] addr_i,
        logic [2:0]            size_i,
        logic [1:0]            burst_i,
        logic [7:0]            len_i
    );
        longint unsigned nbytes;
        longint unsigned beats;
        longint unsigned total_bytes;
        longint unsigned aligned_addr;
        longint unsigned first_byte;
        longint unsigned last_byte;
        longint unsigned wrap_boundary;

        nbytes      = f_num_bytes(size_i);
        beats       = len_i + 1;
        total_bytes = nbytes * beats;
        aligned_addr = (addr_i / nbytes) * nbytes;

        case (burst_i)
            2'b00: begin // FIXED
                first_byte = addr_i;
                last_byte  = aligned_addr + nbytes - 1;
            end
            2'b01: begin // INCR
                first_byte = addr_i;
                last_byte  = aligned_addr + total_bytes - 1;
            end
            2'b10: begin // WRAP
                wrap_boundary = (addr_i / total_bytes) * total_bytes;
                first_byte = wrap_boundary;
                last_byte  = wrap_boundary + total_bytes - 1;
            end
            default: return 1'b1;
        endcase

        return ((first_byte >> 12) != (last_byte >> 12));
    endfunction : f_burst_crosses_4kb

    function automatic logic [STRB_WIDTH-1:0] f_legal_wstrb_mask(
        logic [ADDR_WIDTH-1:0] addr_i,
        int unsigned           beat_idx,
        logic [2:0]            size_i,
        logic [1:0]            burst_i,
        logic [7:0]            len_i
    );
        longint unsigned nbytes;
        longint unsigned beats;
        longint unsigned total_bytes;
        longint unsigned aligned_start;
        longint unsigned wrap_boundary;
        longint unsigned beat_addr;
        longint unsigned bus_base;
        int unsigned lower_lane;
        int unsigned upper_lane;
        logic [STRB_WIDTH-1:0] mask;

        nbytes       = f_num_bytes(size_i);
        beats        = len_i + 1;
        total_bytes  = nbytes * beats;
        aligned_start = (addr_i / nbytes) * nbytes;

        case (burst_i)
            2'b00: beat_addr = addr_i;
            2'b01: beat_addr = (beat_idx == 0) ? addr_i
                                               : aligned_start + beat_idx*nbytes;
            2'b10: begin
                wrap_boundary = (addr_i / total_bytes) * total_bytes;
                beat_addr = (beat_idx == 0) ? addr_i
                                            : aligned_start + beat_idx*nbytes;
                while (beat_addr >= wrap_boundary + total_bytes)
                    beat_addr = beat_addr - total_bytes;
            end
            default: beat_addr = addr_i;
        endcase

        bus_base  = (beat_addr / STRB_WIDTH) * STRB_WIDTH;
        lower_lane = beat_addr - bus_base;
        if (((beat_idx == 0) || (burst_i == 2'b00)) && ((addr_i % nbytes) != 0))
            upper_lane = (aligned_start + nbytes - 1) - bus_base;
        else
            upper_lane = lower_lane + nbytes - 1;

        mask = '0;
        for (int lane = lower_lane; lane <= upper_lane; lane++)
            if (lane < STRB_WIDTH)
                mask[lane] = 1'b1;
        return mask;
    endfunction : f_legal_wstrb_mask
    //Hoang Ho - END: local AXI4 helper functions used by protocol assertions

    //-------------------------------------------------------------------------
    // Internal state tracking
    //-------------------------------------------------------------------------
    bit          rst_seen;       // True after first posedge clk during reset

    // Track reset assertion - set at posedge clk when rst_n is low.
    // (Cannot use negedge rst_n because rst_n starts at 0 as a `bit`,
    // so there is no falling edge to trigger on.)
    always @(posedge clk) begin
        if (!rst_n)
            rst_seen <= 1'b1;
    end

    //-------------------------------------------------------------------------
    // RESET CHECKS
    //    All VALID signals must be de-asserted during reset
    //    Only checked after reset has been asserted at least once (rst_seen)
    //    to avoid false positives from initial bit=0 state.
    //-------------------------------------------------------------------------

    property p_reset_awvalid;
        @(posedge clk) (rst_seen && !rst_n) |-> !AWVALID;
    endproperty

    property p_reset_wvalid;
        @(posedge clk) (rst_seen && !rst_n) |-> !WVALID;
    endproperty

    property p_reset_bvalid;
        @(posedge clk) (rst_seen && !rst_n) |-> !BVALID;
    endproperty

    property p_reset_arvalid;
        @(posedge clk) (rst_seen && !rst_n) |-> !ARVALID;
    endproperty

    property p_reset_rvalid;
        @(posedge clk) (rst_seen && !rst_n) |-> !RVALID;
    endproperty

    RESET_AWVALID : assert property (p_reset_awvalid)
        else $error("[SVA] AWVALID asserted during reset");

    RESET_WVALID  : assert property (p_reset_wvalid)
        else $error("[SVA] WVALID asserted during reset");

    RESET_BVALID  : assert property (p_reset_bvalid)
        else $error("[SVA] BVALID asserted during reset");

    RESET_ARVALID : assert property (p_reset_arvalid)
        else $error("[SVA] ARVALID asserted during reset");

    RESET_RVALID  : assert property (p_reset_rvalid)
        else $error("[SVA] RVALID asserted during reset");

    //-------------------------------------------------------------------------
    // HANDSHAKE STABILITY
    //    VALID must remain asserted until READY
    //-------------------------------------------------------------------------

    // AW Channel
    property p_awvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        AWVALID && !AWREADY |=> AWVALID;
    endproperty

    // W Channel
    property p_wvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        WVALID && !WREADY |=> WVALID;
    endproperty

    // B Channel
    property p_bvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        BVALID && !BREADY |=> BVALID;
    endproperty

    // AR Channel
    property p_arvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        ARVALID && !ARREADY |=> ARVALID;
    endproperty

    // R Channel
    property p_rvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        RVALID && !RREADY |=> RVALID;
    endproperty

    AWVALID_STABLE : assert property (p_awvalid_stable)
        else $error("[SVA] AWVALID de-asserted before AWREADY handshake");

    WVALID_STABLE  : assert property (p_wvalid_stable)
        else $error("[SVA] WVALID de-asserted before WREADY handshake");

    BVALID_STABLE  : assert property (p_bvalid_stable)
        else $error("[SVA] BVALID de-asserted before BREADY handshake");

    ARVALID_STABLE : assert property (p_arvalid_stable)
        else $error("[SVA] ARVALID de-asserted before ARREADY handshake");

    RVALID_STABLE  : assert property (p_rvalid_stable)
        else $error("[SVA] RVALID de-asserted before RREADY handshake");

    //-------------------------------------------------------------------------
    // PAYLOAD STABILITY - signals must be stable while VALID && !READY
    //    The source must not change the information it is signaling
    //    while VALID is asserted 
    //-------------------------------------------------------------------------

    // AW Channel payload
    property p_aw_payload_stable;
        @(posedge clk) disable iff (!rst_n)
        AWVALID && !AWREADY |=>
            $stable(AWID)     && $stable(AWADDR) && $stable(AWLEN) &&
            $stable(AWSIZE)   && $stable(AWBURST) &&
            $stable(AWLOCK)   && $stable(AWCACHE) && $stable(AWPROT) &&
            $stable(AWQOS)    && $stable(AWREGION);
    endproperty

    //Hoang Ho - BEGIN: first-stall-cycle-safe W payload stability check
    // If a W beat is stalled, the same beat and WVALID must still be present at
    // the next clock edge. A payload change is legal only after a handshake.
    property p_w_payload_stable;
        @(posedge clk) disable iff (!rst_n)
        WVALID && !WREADY |=>
            WVALID && $stable(WDATA) && $stable(WSTRB) && $stable(WLAST);
    endproperty
    //Hoang Ho - END: first-stall-cycle-safe W payload stability check

    // B Channel payload
    property p_b_payload_stable;
        @(posedge clk) disable iff (!rst_n)
        BVALID && !BREADY |=>
            $stable(BID) && $stable(BRESP);
    endproperty

    // AR Channel payload
    property p_ar_payload_stable;
        @(posedge clk) disable iff (!rst_n)
        ARVALID && !ARREADY |=>
            $stable(ARID)     && $stable(ARADDR) && $stable(ARLEN) &&
            $stable(ARSIZE)   && $stable(ARBURST) &&
            $stable(ARLOCK)   && $stable(ARCACHE) && $stable(ARPROT) &&
            $stable(ARQOS)    && $stable(ARREGION);
    endproperty

    // R Channel payload
    property p_r_payload_stable;
        @(posedge clk) disable iff (!rst_n)
        RVALID && !RREADY |=>
            $stable(RID) && $stable(RDATA) && $stable(RRESP) && $stable(RLAST);
    endproperty

    AW_PAYLOAD_STABLE : assert property (p_aw_payload_stable)
        else $error("[SVA] AW channel payload changed while AWVALID && !AWREADY");

    W_PAYLOAD_STABLE  : assert property (p_w_payload_stable)
        else $error("[SVA] W channel payload changed while WVALID && !WREADY");

    B_PAYLOAD_STABLE  : assert property (p_b_payload_stable)
        else $error("[SVA] B channel payload changed while BVALID && !BREADY");

    AR_PAYLOAD_STABLE : assert property (p_ar_payload_stable)
        else $error("[SVA] AR channel payload changed while ARVALID && !ARREADY");

    R_PAYLOAD_STABLE  : assert property (p_r_payload_stable)
        else $error("[SVA] R channel payload changed while RVALID && !RREADY");

    //-------------------------------------------------------------------------
    // X/Z CHECKS - Control signals must not be unknown when active
    //-------------------------------------------------------------------------

    property p_awvalid_known;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(AWVALID);
    endproperty

    property p_wvalid_known;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(WVALID);
    endproperty

    property p_bvalid_known;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(BVALID);
    endproperty

    property p_arvalid_known;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(ARVALID);
    endproperty

    property p_rvalid_known;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(RVALID);
    endproperty

    property p_awready_known;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(AWREADY);
    endproperty

    property p_wready_known;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(WREADY);
    endproperty

    property p_bready_known;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(BREADY);
    endproperty

    property p_arready_known;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(ARREADY);
    endproperty

    property p_rready_known;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(RREADY);
    endproperty

    AWVALID_KNOWN : assert property (p_awvalid_known)
        else $error("[SVA] AWVALID is X or Z");

    WVALID_KNOWN  : assert property (p_wvalid_known)
        else $error("[SVA] WVALID is X or Z");

    BVALID_KNOWN  : assert property (p_bvalid_known)
        else $error("[SVA] BVALID is X or Z");

    ARVALID_KNOWN : assert property (p_arvalid_known)
        else $error("[SVA] ARVALID is X or Z");

    RVALID_KNOWN  : assert property (p_rvalid_known)
        else $error("[SVA] RVALID is X or Z");

    AWREADY_KNOWN : assert property (p_awready_known)
        else $error("[SVA] AWREADY is X or Z");

    WREADY_KNOWN  : assert property (p_wready_known)
        else $error("[SVA] WREADY is X or Z");

    BREADY_KNOWN  : assert property (p_bready_known)
        else $error("[SVA] BREADY is X or Z");

    ARREADY_KNOWN : assert property (p_arready_known)
        else $error("[SVA] ARREADY is X or Z");

    RREADY_KNOWN  : assert property (p_rready_known)
        else $error("[SVA] RREADY is X or Z");

    //-------------------------------------------------------------------------
    // BURST PROTOCOL - WLAST / RLAST correctness (Queue-based)
    //    Checks correct beat count and WLAST/RLAST positioning using FIFOs
    //    to support out-of-order handshakes and pipelined transactions.
    //-------------------------------------------------------------------------

    // Queues and beat counters
    int unsigned w_beat_cnt;     // Counts W beats within a burst
    int unsigned aw_len_fifo[$]; // FIFO storing AWLEN values from AW handshakes
    int unsigned w_len_fifo[$];  // FIFO storing actual W burst lengths (completed before AW)

    // Queues and beat counters per ID to support out-of-order read responses
    int unsigned ar_len_fifo[logic [ID_WIDTH-1:0]][$];
    int unsigned r_beat_cnt[logic [ID_WIDTH-1:0]];

    //Hoang Ho - BEGIN: transaction-aware BVALID/BID dependency tracker
    // W data has no ID in AXI4, so completed W bursts pair with accepted AW
    // requests in AW order. A B response becomes legal only after one such
    // address/data pair existed before the current clock edge. Different BID
    // values may complete out of order; each BID must still name an eligible
    // outstanding write transaction.
    int unsigned aw_done_for_b;
    int unsigned wlast_done_for_b;
    logic [ID_WIDTH-1:0] aw_id_unpaired_q[$];
    int unsigned         w_bursts_unpaired;
    int unsigned         b_eligible_by_id[logic [ID_WIDTH-1:0]];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_done_for_b    = 0;
            wlast_done_for_b = 0;
            aw_id_unpaired_q.delete();
            w_bursts_unpaired = 0;
            b_eligible_by_id.delete();
        end else begin
            // BVALID is checked against state created on an earlier edge. This
            // intentionally rejects BVALID asserted on the same edge as the
            // AW or final-W handshake that completes the transaction.
            if (BVALID) begin
                BVALID_AFTER_COMPLETE_WRITE : assert (
                    b_eligible_by_id.exists(BID) &&
                    b_eligible_by_id[BID] > 0)
                    else $error("[SVA] BVALID/BID=0x%0h has no completed AW+WLAST transaction", BID);
            end

            if (BVALID && BREADY &&
                b_eligible_by_id.exists(BID) &&
                b_eligible_by_id[BID] > 0) begin
                b_eligible_by_id[BID] = b_eligible_by_id[BID] - 1;
                if (b_eligible_by_id[BID] == 0)
                    b_eligible_by_id.delete(BID);
            end

            if (AWVALID && AWREADY) begin
                aw_id_unpaired_q.push_back(AWID);
                aw_done_for_b = aw_done_for_b + 1;
            end

            if (WVALID && WREADY && WLAST) begin
                w_bursts_unpaired = w_bursts_unpaired + 1;
                wlast_done_for_b   = wlast_done_for_b + 1;
            end

            // Pair W bursts and AW requests in protocol order for future BVALID.
            while ((aw_id_unpaired_q.size() > 0) && (w_bursts_unpaired > 0)) begin
                logic [ID_WIDTH-1:0] paired_id;
                paired_id = aw_id_unpaired_q.pop_front();
                if (!b_eligible_by_id.exists(paired_id))
                    b_eligible_by_id[paired_id] = 0;
                b_eligible_by_id[paired_id] = b_eligible_by_id[paired_id] + 1;
                w_bursts_unpaired = w_bursts_unpaired - 1;
            end

            if (BVALID && BREADY) begin
                if (aw_done_for_b > 0)
                    aw_done_for_b = aw_done_for_b - 1;
                if (wlast_done_for_b > 0)
                    wlast_done_for_b = wlast_done_for_b - 1;
            end
        end
    end
    //Hoang Ho - END: transaction-aware BVALID/BID dependency tracker

    // Track AW/W handshakes and check WLAST positioning. AW is captured before
    // the W check, so an AW handshaking on the same edge is reflected when that
    // W beat is judged.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_len_fifo.delete();
            w_len_fifo.delete();
        end else begin
            // Capture AWLEN when AW handshakes
            if (AWVALID && AWREADY) begin
                if (w_len_fifo.size() > 0) begin
                    int unsigned actual_w_len;
                    actual_w_len = w_len_fifo.pop_front();
                    WLAST_CORRECT_W_BEFORE_AW : assert (AWLEN == actual_w_len)
                        else $error("[SVA] WLAST asserted on beat %0d but AWLEN is %0d (W before AW)",
                                    actual_w_len, AWLEN);
                end else begin
                    // W started before AW: the beats already accepted must fit,
                    // i.e. AWLEN >= w_beat_cnt, else a beat that should have
                    // carried WLAST already passed.
                    if (aw_len_fifo.size() == 0 && w_beat_cnt > 0) begin
                        WLAST_MISSING_W_BEFORE_AW : assert (AWLEN >= w_beat_cnt)
                            else $error("[SVA] W accepted %0d beats without WLAST before AW arrived, but AWLEN=%0d (WLAST missing/late, W before AW)",
                                        w_beat_cnt, AWLEN);
                    end
                    aw_len_fifo.push_back(AWLEN);
                end
            end

            // Check WLAST positioning on each W beat (AWLEN known from above).
            if (WVALID && WREADY) begin
                if (aw_len_fifo.size() > 0) begin
                    if (w_beat_cnt == aw_len_fifo[0]) begin
                        WLAST_CORRECT_CHECK : assert (WLAST)
                            else $error("[SVA] WLAST not asserted on final W beat (beat=%0d, expected AWLEN=%0d)",
                                        w_beat_cnt, aw_len_fifo[0]);
                    end else begin
                        WLAST_NOT_EARLY_CHECK : assert (!WLAST)
                            else $error("[SVA] WLAST asserted too early (beat=%0d, expected AWLEN=%0d)",
                                        w_beat_cnt, aw_len_fifo[0]);
                    end
                end

                if (WLAST) begin
                    if (aw_len_fifo.size() > 0) begin
                        void'(aw_len_fifo.pop_front());
                    end else begin
                        w_len_fifo.push_back(w_beat_cnt);
                    end
                end
            end
        end
    end

    // W beat counter, reset on WLAST. Nonblocking so the block above reads the
    // pre-edge beat index.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_beat_cnt <= 0;
        end else if (WVALID && WREADY) begin
            if (WLAST)
                w_beat_cnt <= 0;
            else
                w_beat_cnt <= w_beat_cnt + 1;
        end
    end

    // Track AR handshakes and check RLAST on R burst completion
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_len_fifo.delete();
            r_beat_cnt.delete();
        end else begin
            //Hoang Ho - BEGIN: enforce AR-before-R using pre-edge outstanding state
            // A newly handshaken AR on this same edge cannot justify RVALID that
            // was already HIGH before the edge. Therefore R is checked before
            // the current AR request is appended.
            if (RVALID) begin
                RVALID_AFTER_AR : assert (ar_len_fifo.exists(RID) && ar_len_fifo[RID].size() > 0)
                    else $error("[SVA] RVALID asserted without a previously outstanding AR for RID=0x%0h", RID);
            end

            if (RVALID && RREADY) begin
                logic [ID_WIDTH-1:0] cur_rid;
                cur_rid = RID;
                if (!r_beat_cnt.exists(cur_rid))
                    r_beat_cnt[cur_rid] = 0;

                if (ar_len_fifo.exists(cur_rid) && ar_len_fifo[cur_rid].size() > 0) begin
                    if (r_beat_cnt[cur_rid] == ar_len_fifo[cur_rid][0]) begin
                        RLAST_CORRECT_CHECK : assert (RLAST)
                            else $error("[SVA] RLAST not asserted on final R beat (beat=%0d, expected ARLEN=%0d)",
                                        r_beat_cnt[cur_rid], ar_len_fifo[cur_rid][0]);
                    end else begin
                        RLAST_NOT_EARLY_CHECK : assert (!RLAST)
                            else $error("[SVA] RLAST asserted too early (beat=%0d, expected ARLEN=%0d)",
                                        r_beat_cnt[cur_rid], ar_len_fifo[cur_rid][0]);
                    end
                end else begin
                    RLAST_WITHOUT_AR : assert (1'b0)
                        else $error("[SVA] R handshake occurred without outstanding AR handshake for RID=0x%0h", cur_rid);
                end

                if (RLAST) begin
                    if (ar_len_fifo.exists(cur_rid) && ar_len_fifo[cur_rid].size() > 0) begin
                        void'(ar_len_fifo[cur_rid].pop_front());
                        if (ar_len_fifo[cur_rid].size() == 0)
                            ar_len_fifo.delete(cur_rid);
                    end
                    r_beat_cnt[cur_rid] = 0;
                end else begin
                    r_beat_cnt[cur_rid] = r_beat_cnt[cur_rid] + 1;
                end
            end

            // Capture this cycle's AR only after all R checks above.
            if (ARVALID && ARREADY)
                ar_len_fifo[ARID].push_back(ARLEN);
            //Hoang Ho - END: enforce AR-before-R using pre-edge outstanding state
        end
    end

    //-------------------------------------------------------------------------
    // BURST TYPE - AWBURST / ARBURST must not be reserved value (2'b11)
    //-------------------------------------------------------------------------

    property p_awburst_valid;
        @(posedge clk) disable iff (!rst_n)
        (AWVALID && AWREADY) |-> (AWBURST != 2'b11);
    endproperty

    property p_arburst_valid;
        @(posedge clk) disable iff (!rst_n)
        (ARVALID && ARREADY) |-> (ARBURST != 2'b11);
    endproperty

    AWBURST_VALID : assert property (p_awburst_valid)
        else $error("[SVA] AWBURST=2'b11 is reserved and illegal");

    ARBURST_VALID : assert property (p_arburst_valid)
        else $error("[SVA] ARBURST=2'b11 is reserved and illegal");

    //-------------------------------------------------------------------------
    // BURST SIZE - must not exceed data bus width
    //    2^AWSIZE <= DATA_WIDTH/8
    //-------------------------------------------------------------------------

    property p_awsize_valid;
        @(posedge clk) disable iff (!rst_n)
        (AWVALID && AWREADY) |-> ((1 << AWSIZE) <= (DATA_WIDTH / 8));
    endproperty

    property p_arsize_valid;
        @(posedge clk) disable iff (!rst_n)
        (ARVALID && ARREADY) |-> ((1 << ARSIZE) <= (DATA_WIDTH / 8));
    endproperty

    AWSIZE_VALID : assert property (p_awsize_valid)
        else $error("[SVA] AWSIZE exceeds data bus width (2^%0d > %0d bytes)",
                    AWSIZE, DATA_WIDTH / 8);

    ARSIZE_VALID : assert property (p_arsize_valid)
        else $error("[SVA] ARSIZE exceeds data bus width (2^%0d > %0d bytes)",
                    ARSIZE, DATA_WIDTH / 8);

    //Hoang Ho - BEGIN: exact 4KB boundary checks for FIXED/INCR/WRAP
    property p_aw_4kb_boundary;
        @(posedge clk) disable iff (!rst_n)
        (AWVALID && AWREADY) |->
            !f_burst_crosses_4kb(AWADDR, AWSIZE, AWBURST, AWLEN);
    endproperty

    property p_ar_4kb_boundary;
        @(posedge clk) disable iff (!rst_n)
        (ARVALID && ARREADY) |->
            !f_burst_crosses_4kb(ARADDR, ARSIZE, ARBURST, ARLEN);
    endproperty

    AW_4KB_BOUNDARY : assert property (p_aw_4kb_boundary)
        else $error("[SVA] AW burst crosses 4KB boundary: AWADDR=0x%08h AWLEN=%0d AWSIZE=%0d AWBURST=%0b",
                    AWADDR, AWLEN, AWSIZE, AWBURST);

    AR_4KB_BOUNDARY : assert property (p_ar_4kb_boundary)
        else $error("[SVA] AR burst crosses 4KB boundary: ARADDR=0x%08h ARLEN=%0d ARSIZE=%0d ARBURST=%0b",
                    ARADDR, ARLEN, ARSIZE, ARBURST);
    //Hoang Ho - END: exact 4KB boundary checks for FIXED/INCR/WRAP

    //-------------------------------------------------------------------------
    // WRAP BURST - length must be 2, 4, 8, or 16 (LEN = 1, 3, 7, 15)
    //-------------------------------------------------------------------------

    property p_wrap_aw_len;
        @(posedge clk) disable iff (!rst_n)
        (AWVALID && AWREADY && AWBURST == 2'b10) |->
            (AWLEN inside {8'd1, 8'd3, 8'd7, 8'd15});
    endproperty

    property p_wrap_ar_len;
        @(posedge clk) disable iff (!rst_n)
        (ARVALID && ARREADY && ARBURST == 2'b10) |->
            (ARLEN inside {8'd1, 8'd3, 8'd7, 8'd15});
    endproperty

    WRAP_AW_LEN : assert property (p_wrap_aw_len)
        else $error("[SVA] WRAP burst AWLEN=%0d is invalid (must be 1,3,7,15)", AWLEN);

    WRAP_AR_LEN : assert property (p_wrap_ar_len)
        else $error("[SVA] WRAP burst ARLEN=%0d is invalid (must be 1,3,7,15)", ARLEN);


    //Hoang Ho - BEGIN: AXI4 WRAP start-address alignment checks
    property p_wrap_aw_align;
        @(posedge clk) disable iff (!rst_n)
        (AWVALID && AWREADY && AWBURST == 2'b10) |->
            ((AWADDR % (1 << AWSIZE)) == 0);
    endproperty

    property p_wrap_ar_align;
        @(posedge clk) disable iff (!rst_n)
        (ARVALID && ARREADY && ARBURST == 2'b10) |->
            ((ARADDR % (1 << ARSIZE)) == 0);
    endproperty

    WRAP_AW_ALIGN : assert property (p_wrap_aw_align)
        else $error("[SVA] WRAP AWADDR=0x%08h is not aligned to AWSIZE=%0d", AWADDR, AWSIZE);

    WRAP_AR_ALIGN : assert property (p_wrap_ar_align)
        else $error("[SVA] WRAP ARADDR=0x%08h is not aligned to ARSIZE=%0d", ARADDR, ARSIZE);
    //Hoang Ho - END: AXI4 WRAP start-address alignment checks

    //-------------------------------------------------------------------------
    // FIXED BURST - length must not exceed 16 (LEN <= 15)
    //-------------------------------------------------------------------------

    property p_fixed_aw_len;
        @(posedge clk) disable iff (!rst_n)
        (AWVALID && AWREADY && AWBURST == 2'b00) |-> (AWLEN <= 8'd15);
    endproperty

    property p_fixed_ar_len;
        @(posedge clk) disable iff (!rst_n)
        (ARVALID && ARREADY && ARBURST == 2'b00) |-> (ARLEN <= 8'd15);
    endproperty

    FIXED_AW_LEN : assert property (p_fixed_aw_len)
        else $error("[SVA] FIXED burst AWLEN=%0d exceeds maximum of 15", AWLEN);

    FIXED_AR_LEN : assert property (p_fixed_ar_len)
        else $error("[SVA] FIXED burst ARLEN=%0d exceeds maximum of 15", ARLEN);

    //Hoang Ho - BEGIN: EXOKAY legality and WSTRB lane checks
    logic aw_exclusive_by_id[logic [ID_WIDTH-1:0]][$];
    logic ar_exclusive_by_id[logic [ID_WIDTH-1:0]][$];

    typedef struct packed {
        logic [ADDR_WIDTH-1:0] addr;
        logic [7:0]            len;
        logic [2:0]            size;
        logic [1:0]            burst;
    } aw_lane_ctrl_t;

    aw_lane_ctrl_t aw_lane_fifo[$];
    logic [STRB_WIDTH-1:0] w_before_aw_strb[$];
    logic                  w_before_aw_last[$];
    int unsigned           w_lane_beat_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_exclusive_by_id.delete();
            ar_exclusive_by_id.delete();
            aw_lane_fifo.delete();
            w_before_aw_strb.delete();
            w_before_aw_last.delete();
            w_lane_beat_idx <= 0;
        end else begin
            if (AWVALID && AWREADY) begin
                aw_lane_ctrl_t ctrl;
                ctrl = '{addr:AWADDR, len:AWLEN, size:AWSIZE, burst:AWBURST};
                aw_exclusive_by_id[AWID].push_back(AWLOCK);

                // W-before-AW beats are checked immediately when their address
                // control arrives. Otherwise retain the AW for future W beats.
                if (w_before_aw_strb.size() > 0) begin
                    int unsigned idx;
                    bit burst_done;
                    idx = 0;
                    burst_done = 0;
                    while ((w_before_aw_strb.size() > 0) && !burst_done) begin
                        logic [STRB_WIDTH-1:0] legal_mask;
                        logic [STRB_WIDTH-1:0] observed_strb;
                        observed_strb = w_before_aw_strb.pop_front();
                        burst_done    = w_before_aw_last.pop_front();
                        legal_mask    = f_legal_wstrb_mask(AWADDR, idx, AWSIZE, AWBURST, AWLEN);
                        WSTRB_LEGAL_W_BEFORE_AW : assert ((observed_strb & ~legal_mask) == '0)
                            else $error("[SVA] Illegal WSTRB on W-before-AW beat=%0d STRB=0b%0b legal=0b%0b",
                                        idx, observed_strb, legal_mask);
                        idx++;
                    end
                    // AW can legally arrive in the middle of a W burst. Keep
                    // its control fields and continue checking subsequent beats.
                    if (!burst_done) begin
                        aw_lane_fifo.push_back(ctrl);
                        w_lane_beat_idx = idx;
                    end
                end else begin
                    aw_lane_fifo.push_back(ctrl);
                end
            end

            if (ARVALID && ARREADY)
                ar_exclusive_by_id[ARID].push_back(ARLOCK);

            if (WVALID && WREADY) begin
                if (aw_lane_fifo.size() > 0) begin
                    logic [STRB_WIDTH-1:0] legal_mask;
                    legal_mask = f_legal_wstrb_mask(aw_lane_fifo[0].addr,
                                                    w_lane_beat_idx,
                                                    aw_lane_fifo[0].size,
                                                    aw_lane_fifo[0].burst,
                                                    aw_lane_fifo[0].len);
                    WSTRB_LEGAL_CHECK : assert ((WSTRB & ~legal_mask) == '0)
                        else $error("[SVA] Illegal WSTRB beat=%0d STRB=0b%0b legal=0b%0b",
                                    w_lane_beat_idx, WSTRB, legal_mask);
                    if (WLAST) begin
                        void'(aw_lane_fifo.pop_front());
                        w_lane_beat_idx <= 0;
                    end else begin
                        w_lane_beat_idx <= w_lane_beat_idx + 1;
                    end
                end else begin
                    w_before_aw_strb.push_back(WSTRB);
                    w_before_aw_last.push_back(WLAST);
                end
            end

            if (BVALID && BREADY) begin
                if (BRESP == 2'b01) begin
                    BRESP_EXOKAY_ONLY_EXCLUSIVE : assert (
                        aw_exclusive_by_id.exists(BID) &&
                        aw_exclusive_by_id[BID].size() > 0 &&
                        aw_exclusive_by_id[BID][0])
                        else $error("[SVA] BRESP=EXOKAY for non-exclusive BID=0x%0h", BID);
                end
                if (aw_exclusive_by_id.exists(BID) && aw_exclusive_by_id[BID].size() > 0) begin
                    void'(aw_exclusive_by_id[BID].pop_front());
                    if (aw_exclusive_by_id[BID].size() == 0)
                        aw_exclusive_by_id.delete(BID);
                end
            end

            if (RVALID && RREADY) begin
                if (RRESP == 2'b01) begin
                    RRESP_EXOKAY_ONLY_EXCLUSIVE : assert (
                        ar_exclusive_by_id.exists(RID) &&
                        ar_exclusive_by_id[RID].size() > 0 &&
                        ar_exclusive_by_id[RID][0])
                        else $error("[SVA] RRESP=EXOKAY for non-exclusive RID=0x%0h", RID);
                end
                if (RLAST && ar_exclusive_by_id.exists(RID) && ar_exclusive_by_id[RID].size() > 0) begin
                    void'(ar_exclusive_by_id[RID].pop_front());
                    if (ar_exclusive_by_id[RID].size() == 0)
                        ar_exclusive_by_id.delete(RID);
                end
            end
        end
    end
    //Hoang Ho - END: EXOKAY legality and WSTRB lane checks

    //-------------------------------------------------------------------------
    // RESPONSE VALUE - BRESP/RRESP must be valid
    //     0-3 is always valid, but EXOKAY is only valid for exclusive accesses
    //     Basic check: BRESP/RRESP must not be X/Z at handshake
    //-------------------------------------------------------------------------

    property p_bresp_known;
        @(posedge clk) disable iff (!rst_n)
        (BVALID && BREADY) |-> !$isunknown(BRESP);
    endproperty

    property p_rresp_known;
        @(posedge clk) disable iff (!rst_n)
        (RVALID && RREADY) |-> !$isunknown(RRESP);
    endproperty

    BRESP_KNOWN : assert property (p_bresp_known)
        else $error("[SVA] BRESP is X or Z at handshake");

    RRESP_KNOWN : assert property (p_rresp_known)
        else $error("[SVA] RRESP is X or Z at handshake");

    //Hoang Ho - BEGIN: legal read interleaving observation
    // AXI4 permits R beats from different IDs to interleave. Same-ID ordering
    // is checked by the AR/R per-ID FIFOs above, so RID changes are evidence to
    // cover rather than protocol violations.
    logic                    have_previous_r_beat;
    logic [ID_WIDTH-1:0]     previous_rid;
    logic                    previous_r_was_last;
    logic                    r_interleave_pulse;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            have_previous_r_beat <= 1'b0;
            previous_rid         <= '0;
            previous_r_was_last  <= 1'b1;
            r_interleave_pulse   <= 1'b0;
        end else begin
            r_interleave_pulse <= 1'b0;
            if (RVALID && RREADY) begin
                r_interleave_pulse <= have_previous_r_beat &&
                                      !previous_r_was_last &&
                                      (RID != previous_rid);
                have_previous_r_beat <= 1'b1;
                previous_rid         <= RID;
                previous_r_was_last  <= RLAST;
            end
        end
    end
    //Hoang Ho - END: legal read interleaving observation

    //-------------------------------------------------------------------------
    // COVER PROPERTIES - Track protocol scenarios for functional coverage
    //-------------------------------------------------------------------------

    // Handshake coverage
    AW_HANDSHAKE_COV : cover property (@(posedge clk) disable iff (!rst_n) AWVALID && AWREADY);
    W_HANDSHAKE_COV  : cover property (@(posedge clk) disable iff (!rst_n) WVALID  && WREADY);
    B_HANDSHAKE_COV  : cover property (@(posedge clk) disable iff (!rst_n) BVALID  && BREADY);
    AR_HANDSHAKE_COV : cover property (@(posedge clk) disable iff (!rst_n) ARVALID && ARREADY);
    R_HANDSHAKE_COV  : cover property (@(posedge clk) disable iff (!rst_n) RVALID  && RREADY);
    //Hoang Ho - legal cross-ID read-data interleaving evidence
    R_INTERLEAVE_DIFF_ID_COV : cover property (@(posedge clk) disable iff (!rst_n) r_interleave_pulse);

    // Back-pressure coverage (VALID && !READY - stall cycle)
    AW_BACKPRESSURE_COV : cover property (@(posedge clk) disable iff (!rst_n) AWVALID && !AWREADY);
    W_BACKPRESSURE_COV  : cover property (@(posedge clk) disable iff (!rst_n) WVALID  && !WREADY);
    B_BACKPRESSURE_COV  : cover property (@(posedge clk) disable iff (!rst_n) BVALID  && !BREADY);
    AR_BACKPRESSURE_COV : cover property (@(posedge clk) disable iff (!rst_n) ARVALID && !ARREADY);
    R_BACKPRESSURE_COV  : cover property (@(posedge clk) disable iff (!rst_n) RVALID  && !RREADY);

    // Burst type coverage
    WRITE_INCR_COV  : cover property (@(posedge clk) disable iff (!rst_n) AWVALID && AWREADY && AWBURST == 2'b01);
    WRITE_FIXED_COV : cover property (@(posedge clk) disable iff (!rst_n) AWVALID && AWREADY && AWBURST == 2'b00);
    WRITE_WRAP_COV  : cover property (@(posedge clk) disable iff (!rst_n) AWVALID && AWREADY && AWBURST == 2'b10);
    READ_INCR_COV   : cover property (@(posedge clk) disable iff (!rst_n) ARVALID && ARREADY && ARBURST == 2'b01);
    READ_FIXED_COV  : cover property (@(posedge clk) disable iff (!rst_n) ARVALID && ARREADY && ARBURST == 2'b00);
    READ_WRAP_COV   : cover property (@(posedge clk) disable iff (!rst_n) ARVALID && ARREADY && ARBURST == 2'b10);

    // Single-beat burst
    SINGLE_WRITE_COV : cover property (@(posedge clk) disable iff (!rst_n) AWVALID && AWREADY && AWLEN == 0);
    SINGLE_READ_COV  : cover property (@(posedge clk) disable iff (!rst_n) ARVALID && ARREADY && ARLEN == 0);

    // Max-length burst (256 beats)
    MAX_WRITE_COV : cover property (@(posedge clk) disable iff (!rst_n) AWVALID && AWREADY && AWLEN == 255);
    MAX_READ_COV  : cover property (@(posedge clk) disable iff (!rst_n) ARVALID && ARREADY && ARLEN == 255);



    //Hoang Ho - BEGIN: Additional SVA cover properties for 4KB and dependency hit evidence
    // 4KB boundary near-edge coverage
    AW_4KB_NEAR_COV : cover property (@(posedge clk) disable iff (!rst_n)
        AWVALID && AWREADY && AWADDR[11:0] >= 12'hF00);
    AR_4KB_NEAR_COV : cover property (@(posedge clk) disable iff (!rst_n)
        ARVALID && ARREADY && ARADDR[11:0] >= 12'hF00);

    // Dependency coverage
    B_AFTER_AW_WLAST_COV : cover property (@(posedge clk) disable iff (!rst_n)
        BVALID && (aw_done_for_b > 0) && (wlast_done_for_b > 0));
    RVALID_COV : cover property (@(posedge clk) disable iff (!rst_n) RVALID);
    //Hoang Ho - END: Additional SVA cover properties for 4KB and dependency hit evidence

endmodule : axi4_sva