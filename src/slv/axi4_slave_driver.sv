//=============================================================================
// OWNERSHIP NOTE
//   Original unmarked code in this file : Huy Le / original AXI4-VIP repo
//   Blocks marked //Hoang Ho            : Hoang Ho functional/spec fixes
//=============================================================================
//==============================================================================
// File        : axi4_slave_driver.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 reactive slave driver.
//               Listens on the bus for incoming master requests and generates
//               responses automatically. Contains a built-in byte-addressable
//               memory model for data storage and retrieval.
//               Write flow : wait AW -> collect W beats -> store to mem -> send B
//               Read flow  : wait AR -> read from mem -> send R beats
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

//Huy Le: original architecture and baseline implementation.
class axi4_slave_driver extends uvm_driver #(axi4_transaction);

    `uvm_component_utils(axi4_slave_driver)

    // Virtual interface handle
    virtual axi4_if vif;

    // =========================================================================
    // Built-in memory model (byte-addressable)
    // =========================================================================
    bit [7:0] mem [bit [AXI4_ADDR_WIDTH-1:0]];

    //Hoang Ho: Extended exclusive reservation attributes for AXI4 Full
    // Exclusive reservation table per AXI4 spec (Key: transaction ID).
    //   The reservation records the exclusive-read attributes. The paired
    //   exclusive write succeeds only if ID, address, size, length, burst and
    //   key attributes match and no conflicting write invalidated the region.
    typedef struct {
        bit                       valid;
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        bit [2:0]                 size;
        bit [7:0]                 len;
        bit [1:0]                 burst;
        bit [3:0]                 cache;
        bit [2:0]                 prot;
        bit [3:0]                 region;
    } excl_res_t;
    protected excl_res_t excl_res [bit [AXI4_ID_WIDTH-1:0]];

    // Internal FIFO structs and queues to support outstanding transactions
    typedef struct {
        bit [AXI4_ID_WIDTH-1:0]   id;
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        bit [7:0]                 len;
        bit [2:0]                 size;
        bit [1:0]                 burst;
        axi4_lock_e               lock;
        //Hoang Ho: Capture extra AW attributes for exclusive/access policy
        bit [3:0]                 cache;
        bit [2:0]                 prot;
        bit [3:0]                 region;
    } aw_info_t;

    typedef struct {
        bit [AXI4_DATA_WIDTH-1:0] data_q[$];
        bit [AXI4_STRB_WIDTH-1:0] strb_q[$];
    } w_burst_t;

    typedef struct {
        bit [AXI4_ID_WIDTH-1:0] id;
        axi4_resp_e             resp;
    } b_resp_t;

    typedef struct {
        bit [AXI4_ID_WIDTH-1:0]   id;
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        bit [7:0]                 len;
        bit [2:0]                 size;
        bit [1:0]                 burst;
        axi4_lock_e               lock;
        //Hoang Ho: Capture extra AR attributes for exclusive/access policy
        bit [3:0]                 cache;
        bit [2:0]                 prot;
        bit [3:0]                 region;
        //Hoang Ho: request sequence number within one RID; used to preserve
        // same-ID response ordering while still allowing different-ID OOO.
        int unsigned              order_idx;
    } ar_info_t;

    protected aw_info_t aw_fifo[$];
    protected w_burst_t w_fifo[$];
    protected b_resp_t  b_fifo[$];
    protected ar_info_t ar_fifo[$];

    // =========================================================================
    // Configurable delays - set via config_db or directly for back-pressure
    //   ready_delay : cycles before asserting xREADY (simulates slow slave)
    //   resp_delay  : cycles before driving B/R response
    //   When max = 0, no delay is inserted.
    // =========================================================================
    int unsigned ready_delay_min = 0;
    int unsigned ready_delay_max = 0;
    int unsigned resp_delay_min  = 0;
    int unsigned resp_delay_max  = 0;

    //Hoang Ho: subordinate can keep WREADY continuously HIGH for a corner test.
    bit wready_always_high = 0;

    //Hoang Ho: read-response scheduling modes.
    // r_reorder_enable selects a different RID at burst boundaries.
    // r_interleave_enable selects a different eligible RID after every R beat.
    // Only the front context of one RID is ever eligible, so same-ID order holds.
    bit          r_reorder_enable         = 0;
    bit          r_interleave_enable      = 0;
    int unsigned r_interleave_start_depth = 2;
    int unsigned r_interleave_start_wait  = 8;
    int unsigned r_outstanding_max        = 4;

    protected int unsigned ar_issue_seq[axi4_id_t];
    protected longint unsigned r_arrival_seq;
    protected axi4_read_context r_pending[axi4_id_t][$];
    protected axi4_read_context r_arrival_q[$];
    protected axi4_id_t          r_active_ids[$];
    protected axi4_read_context  r_locked_ctx;
    protected int unsigned       r_rr_cursor;
    protected int unsigned       r_context_count;
    protected bit                r_interleave_window_open;

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Build phase - get virtual interface from config_db
    // =========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi4_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_type_name(), "Virtual interface not found in config_db")
        // Optional delay configuration - tests can set these via config_db
        void'(uvm_config_db#(int unsigned)::get(this, "", "ready_delay_min", ready_delay_min));
        void'(uvm_config_db#(int unsigned)::get(this, "", "ready_delay_max", ready_delay_max));
        void'(uvm_config_db#(int unsigned)::get(this, "", "resp_delay_min",  resp_delay_min));
        void'(uvm_config_db#(int unsigned)::get(this, "", "resp_delay_max",  resp_delay_max));
        //Hoang Ho: optional continuous-WREADY mode.
        void'(uvm_config_db#(bit)::get(this, "", "wready_always_high", wready_always_high));
        //Hoang Ho: read scheduling configuration.
        void'(uvm_config_db#(bit)::get(this, "", "r_reorder_enable", r_reorder_enable));
        void'(uvm_config_db#(bit)::get(this, "", "r_interleave_enable", r_interleave_enable));
        void'(uvm_config_db#(int unsigned)::get(this, "", "r_interleave_start_depth", r_interleave_start_depth));
        void'(uvm_config_db#(int unsigned)::get(this, "", "r_interleave_start_wait", r_interleave_start_wait));
        void'(uvm_config_db#(int unsigned)::get(this, "", "r_outstanding_max", r_outstanding_max));
        if (r_outstanding_max == 0)
            r_outstanding_max = 1;
        if (r_interleave_start_depth == 0)
            r_interleave_start_depth = 1;
    endfunction : build_phase

    // =========================================================================
    // Run phase - reactive slave: fork write & read handlers
    // =========================================================================
    task run_phase(uvm_phase phase);
        // Outer loop: recover from reset at any time during operation
        forever begin
            reset_signals();
            @(posedge vif.rst_n);
            `uvm_info(get_type_name(), "Reset deasserted - slave driver active", UVM_MEDIUM)

            fork
                begin : slave_loop
                    fork
                        handle_writes();
                        handle_reads();
                    join
                end
                begin : rst_watch
                    @(negedge vif.rst_n);
                    `uvm_info(get_type_name(), "Reset asserted - aborting", UVM_MEDIUM)
                end
            join_any
            disable fork;
        end
    endtask : run_phase

    // =========================================================================
    // Reset - deassert all slave-driven READY / VALID signals
    // =========================================================================
    task reset_signals();
        @(vif.slave_cb);
        vif.slave_cb.AWREADY <= 1'b0;
        vif.slave_cb.WREADY  <= 1'b0;
        vif.slave_cb.BVALID  <= 1'b0;
        vif.slave_cb.ARREADY <= 1'b0;
        vif.slave_cb.RVALID  <= 1'b0;
        vif.slave_cb.RLAST   <= 1'b0;

        aw_fifo.delete();
        w_fifo.delete();
        b_fifo.delete();
        ar_fifo.delete();
        //Hoang Ho: discard every outstanding read context on reset.
        ar_issue_seq.delete();
        r_pending.delete();
        r_arrival_q.delete();
        r_active_ids.delete();
        r_locked_ctx = null;
        r_rr_cursor = 0;
        r_context_count = 0;
        r_arrival_seq = 0;
        r_interleave_window_open = 0;
        excl_res.delete();      // drop all exclusive reservations on reset
    endtask : reset_signals

    // =========================================================================
    // Delay helpers - insert random back-pressure / response latency
    // =========================================================================
    task rand_ready_delay();
        int unsigned delay;
        if (ready_delay_max > 0) begin
            delay = $urandom_range(ready_delay_max, ready_delay_min);
            repeat (delay) @(vif.slave_cb);
        end
    endtask : rand_ready_delay

    task rand_resp_delay();
        int unsigned delay;
        if (resp_delay_max > 0) begin
            delay = $urandom_range(resp_delay_max, resp_delay_min);
            repeat (delay) @(vif.slave_cb);
        end
    endtask : rand_resp_delay

    // =========================================================================
    // Handle Writes - forks collector tasks and executor tasks to handle
    // pipelined/outstanding write requests.
    // =========================================================================
    task handle_writes();
        fork
            collect_aw();
            collect_w();
            process_writes();
            drive_b();
        join
    endtask : handle_writes

    // ----- AW Collector: listens and handshakes AW address phases -----
    task collect_aw();
        forever begin
            aw_info_t info;

            do @(vif.slave_cb);
            while (!vif.slave_cb.AWVALID);

            rand_ready_delay();
            vif.slave_cb.AWREADY <= 1'b1;

            //Hoang Ho: sample AW payload only at real handshake, not before READY
            //Hoang Ho
            // AWREADY is a clocking-block output and must not be read back in
            // Questa. The driver already holds AWREADY high, so AWVALID sampled
            // at the next clocking event is exactly the AW handshake condition.
            do @(vif.slave_cb);
            while (!vif.slave_cb.AWVALID);
            //Hoang Ho

            info.id     = vif.slave_cb.AWID;
            info.addr   = vif.slave_cb.AWADDR;
            info.len    = vif.slave_cb.AWLEN;
            info.size   = vif.slave_cb.AWSIZE;
            info.burst  = vif.slave_cb.AWBURST;
            info.lock   = axi4_lock_e'(vif.slave_cb.AWLOCK);
            info.cache  = vif.slave_cb.AWCACHE;
            info.prot   = vif.slave_cb.AWPROT;
            info.region = vif.slave_cb.AWREGION;

            vif.slave_cb.AWREADY <= 1'b0;

            `uvm_info(get_type_name(),
                      $sformatf("AW received: ID=0x%0h ADDR=0x%08h LEN=%0d LOCK=%s",
                                info.id, info.addr, info.len, info.lock.name()), UVM_HIGH)
            aw_fifo.push_back(info);
        end
    endtask : collect_aw

    // ----- W Collector: collects W bursts from master -----
    task collect_w();
        //Hoang Ho: support both pulsed and continuously-high WREADY
        if (wready_always_high) begin
            vif.slave_cb.WREADY <= 1'b1;
            forever begin
                w_burst_t burst;
                bit wlast_seen;
                wlast_seen = 0;
                while (!wlast_seen) begin
                    do @(vif.slave_cb);
                    while (!vif.slave_cb.WVALID);

                    burst.data_q.push_back(vif.slave_cb.WDATA);
                    burst.strb_q.push_back(vif.slave_cb.WSTRB);
                    wlast_seen = vif.slave_cb.WLAST;
                end
                w_fifo.push_back(burst);
            end
        end else begin
            // Original Huy Le behavior: pulse WREADY once for each accepted beat.
            forever begin
                w_burst_t burst;
                bit wlast_seen;
                wlast_seen = 0;
                while (!wlast_seen) begin
                    rand_ready_delay();
                    vif.slave_cb.WREADY <= 1'b1;

                    do @(vif.slave_cb);
                    while (!vif.slave_cb.WVALID);

                    burst.data_q.push_back(vif.slave_cb.WDATA);
                    burst.strb_q.push_back(vif.slave_cb.WSTRB);
                    wlast_seen = vif.slave_cb.WLAST;

                    vif.slave_cb.WREADY <= 1'b0;
                    @(vif.slave_cb);
                end
                w_fifo.push_back(burst);
            end
        end
    endtask : collect_w

    // ----- Write Executor: matches AW and W, writes to memory -----
    task process_writes();
        forever begin
            aw_info_t aw;
            w_burst_t w;
            axi4_resp_e wr_resp;
            bit do_write = 1;

            wait (aw_fifo.size() > 0 && w_fifo.size() > 0);
            aw = aw_fifo.pop_front();
            w  = w_fifo.pop_front();

            if (w.data_q.size() != aw.len + 1)
                `uvm_error(get_type_name(),
                           $sformatf("W beat count mismatch: expected %0d, got %0d",
                                     aw.len + 1, w.data_q.size()))

            if (aw.addr >= 32'hF000_0000) begin
                wr_resp = AXI4_RESP_DECERR;
                do_write = 0;
            end else if (aw.addr >= 32'hE000_0000) begin
                wr_resp = AXI4_RESP_SLVERR;
                do_write = 0;
            end else if (aw.lock == AXI4_LOCK_EXCLUSIVE) begin
                // Exclusive write: must be a legal exclusive access AND match an
                // outstanding reservation (same ID, addr, size, len) that is
                // still valid. Otherwise the exclusive access fails (OKAY, no write).
                if (!is_legal_exclusive(aw.addr, aw.size, aw.len)) begin
                    `uvm_error(get_type_name(),
                               $sformatf("Illegal exclusive WRITE: ID=0x%0h ADDR=0x%08h SIZE=%0d LEN=%0d violates AXI4 exclusive constraints (pow2 bytes<=128, len<=16, aligned)",
                                         aw.id, aw.addr, aw.size, aw.len))
                    wr_resp = AXI4_RESP_OKAY;
                    do_write = 0;
                end else if (excl_res.exists(aw.id) && excl_res[aw.id].valid &&
                             //Hoang Ho: match extra exclusive attributes
                             excl_res[aw.id].addr   == aw.addr   &&
                             excl_res[aw.id].size   == aw.size   &&
                             excl_res[aw.id].len    == aw.len    &&
                             excl_res[aw.id].burst  == aw.burst  &&
                             excl_res[aw.id].cache  == aw.cache  &&
                             excl_res[aw.id].prot   == aw.prot   &&
                             excl_res[aw.id].region == aw.region) begin
                    wr_resp = AXI4_RESP_EXOKAY;
                    excl_res[aw.id].valid = 0;   // reservation consumed
                    // do_write stays 1 -> the store is committed below
                end else begin
                    wr_resp = AXI4_RESP_OKAY;
                    do_write = 0;                // exclusive write failed
                end
            end else begin
                wr_resp = AXI4_RESP_OKAY;
            end

            //Hoang Ho: reject byte strobes outside the legal transfer lanes
            if (do_write) begin
                for (int beat = 0; beat < w.data_q.size(); beat++) begin
                    bit [AXI4_STRB_WIDTH-1:0] legal_mask;
                    legal_mask = calc_legal_wstrb_mask(aw.addr, beat, aw.size, aw.burst, aw.len);
                    if ((w.strb_q[beat] & ~legal_mask) != '0) begin
                        `uvm_error(get_type_name(),
                                   $sformatf("Illegal WSTRB: ID=0x%0h ADDR=0x%08h beat=%0d STRB=0b%0b legal=0b%0b",
                                             aw.id, aw.addr, beat, w.strb_q[beat], legal_mask))
                        wr_resp = AXI4_RESP_SLVERR;
                        do_write = 0;
                    end
                end
            end

            if (do_write) begin
                for (int beat = 0; beat < w.data_q.size(); beat++) begin
                    bit [AXI4_ADDR_WIDTH-1:0] beat_addr;
                    bit [AXI4_ADDR_WIDTH-1:0] aligned_beat_addr;
                    beat_addr = calc_beat_addr(aw.addr, beat, aw.size, aw.burst, aw.len);
                    aligned_beat_addr = (beat_addr / AXI4_STRB_WIDTH) * AXI4_STRB_WIDTH;


                    for (int b = 0; b < AXI4_STRB_WIDTH; b++) begin
                        if (w.strb_q[beat][b]) begin
                            mem[aligned_beat_addr + b] = w.data_q[beat][b*8 +: 8];
                            // Any committed store cancels reservations covering
                            // this byte (including those held by other IDs).
                            invalidate_reservations_at(aligned_beat_addr + b);
                        end
                    end
                end
            end

            begin
                b_resp_t b;
                b.id = aw.id;
                b.resp = wr_resp;
                b_fifo.push_back(b);
            end
        end
    endtask : process_writes

    // ----- B Driver: drives BID and BRESP on the B channel -----
    task drive_b();
        forever begin
            b_resp_t b;
            wait (b_fifo.size() > 0);
            b = b_fifo.pop_front();

            rand_resp_delay();
            @(vif.slave_cb);
            vif.slave_cb.BID    <= b.id;
            vif.slave_cb.BRESP  <= b.resp;
            vif.slave_cb.BVALID <= 1'b1;

            do @(vif.slave_cb);
            while (!vif.slave_cb.BREADY);

            vif.slave_cb.BVALID <= 1'b0;
            `uvm_info(get_type_name(),
                      $sformatf("Write complete: ID=0x%0h RESP=%s", b.id, b.resp.name()), UVM_MEDIUM)
        end
    endtask : drive_b

    // =========================================================================
    // Handle Reads
    //Huy Le: AR collection and reactive memory response model.
    //Hoang Ho: one scheduler owns the physical R channel and can switch RID
    // after each accepted beat. This is legal only across different IDs.
    // =========================================================================
    task handle_reads();
        fork
            collect_ar();
            prepare_r_contexts();
            drive_r_scheduler();
        join
    endtask : handle_reads

    //Huy Le: AR collector. Hoang Ho: order_idx records acceptance order per RID.
    task collect_ar();
        forever begin
            ar_info_t info;

            do @(vif.slave_cb);
            while (!vif.slave_cb.ARVALID);

            rand_ready_delay();
            vif.slave_cb.ARREADY <= 1'b1;

            // ARREADY is already HIGH. Sample only when ARVALID is observed at
            // the following clocking event, which is the actual handshake.
            do @(vif.slave_cb);
            while (!vif.slave_cb.ARVALID);

            info.id     = vif.slave_cb.ARID;
            info.addr   = vif.slave_cb.ARADDR;
            info.len    = vif.slave_cb.ARLEN;
            info.size   = vif.slave_cb.ARSIZE;
            info.burst  = vif.slave_cb.ARBURST;
            info.lock   = axi4_lock_e'(vif.slave_cb.ARLOCK);
            info.cache  = vif.slave_cb.ARCACHE;
            info.prot   = vif.slave_cb.ARPROT;
            info.region = vif.slave_cb.ARREGION;
            if (!ar_issue_seq.exists(info.id))
                ar_issue_seq[info.id] = 0;
            info.order_idx = ar_issue_seq[info.id];
            ar_issue_seq[info.id]++;

            vif.slave_cb.ARREADY <= 1'b0;
            ar_fifo.push_back(info);

            `uvm_info(get_type_name(),
                      $sformatf("AR received: ID=0x%0h ADDR=0x%08h LEN=%0d ORDER=%0d",
                                info.id, info.addr, info.len, info.order_idx), UVM_HIGH)
        end
    endtask : collect_ar

    //Hoang Ho: prepare response/data without driving the shared R channel.
    // The bounded context count models finite subordinate buffering; AR requests
    // already accepted by collect_ar remain queued until space is available.
    task prepare_r_contexts();
        forever begin
            ar_info_t ar;
            axi4_read_context ctx;

            wait (ar_fifo.size() > 0 && r_context_count < r_outstanding_max);
            ar = ar_fifo.pop_front();
            build_read_context(ar, ctx);
            enqueue_read_context(ctx);
        end
    endtask : prepare_r_contexts

    task build_read_context(ar_info_t ar, output axi4_read_context ctx);
        ctx = new();
        ctx.id          = ar.id;
        ctx.addr        = ar.addr;
        ctx.len         = ar.len;
        ctx.size        = ar.size;
        ctx.burst       = axi4_burst_type_e'(ar.burst);
        ctx.lock        = ar.lock;
        ctx.cache       = ar.cache;
        ctx.prot        = ar.prot;
        ctx.region      = ar.region;
        ctx.order_idx   = ar.order_idx;
        ctx.arrival_idx = r_arrival_seq++;

        if (ar.addr >= 32'hF000_0000) begin
            ctx.resp = AXI4_RESP_DECERR;
        end else if (ar.addr >= 32'hE000_0000) begin
            ctx.resp = AXI4_RESP_SLVERR;
        end else if (ar.lock == AXI4_LOCK_EXCLUSIVE) begin
            if (!is_legal_exclusive(ar.addr, ar.size, ar.len)) begin
                `uvm_error(get_type_name(),
                           $sformatf("Illegal exclusive READ: ID=0x%0h ADDR=0x%08h SIZE=%0d LEN=%0d",
                                     ar.id, ar.addr, ar.size, ar.len))
                ctx.resp = AXI4_RESP_OKAY;
            end else begin
                ctx.resp = AXI4_RESP_EXOKAY;
                excl_res[ar.id] = '{valid:1'b1, addr:ar.addr, size:ar.size, len:ar.len,
                                    burst:ar.burst, cache:ar.cache, prot:ar.prot, region:ar.region};
            end
        end else begin
            ctx.resp = AXI4_RESP_OKAY;
        end

        // Build one bus-width RDATA value for every transfer. Inactive lanes are
        // zero and an unaligned first beat never wraps into lower lanes.
        for (int beat = 0; beat <= ar.len; beat++) begin
            axi4_addr_t beat_addr;
            axi4_addr_t bus_base;
            axi4_strb_t lane_mask;
            axi4_data_t rdata;

            beat_addr = axi4_calc_beat_addr(ar.addr, beat, ar.size,
                                             axi4_burst_type_e'(ar.burst), ar.len);
            bus_base  = axi4_bus_word_base(beat_addr);
            lane_mask = axi4_calc_legal_lane_mask(ar.addr, beat, ar.size,
                                                   axi4_burst_type_e'(ar.burst), ar.len);
            rdata = '0;
            for (int lane = 0; lane < AXI4_STRB_WIDTH; lane++) begin
                axi4_addr_t byte_addr;
                byte_addr = bus_base + lane;
                if (lane_mask[lane] && mem.exists(byte_addr))
                    rdata[lane*8 +: 8] = mem[byte_addr];
            end
            ctx.data_q.push_back(rdata);
        end
    endtask : build_read_context

    function void enqueue_read_context(axi4_read_context ctx);
        bit new_rid;
        new_rid = !r_pending.exists(ctx.id) || (r_pending[ctx.id].size() == 0);
        r_pending[ctx.id].push_back(ctx);
        r_arrival_q.push_back(ctx);
        r_context_count++;
        if (new_rid)
            r_active_ids.push_back(ctx.id);
    endfunction : enqueue_read_context

    function axi4_read_context choose_interleaved_context();
        axi4_read_context ctx;
        if (r_active_ids.size() == 0)
            return null;
        if (r_rr_cursor >= r_active_ids.size())
            r_rr_cursor = 0;

        for (int offset = 0; offset < r_active_ids.size(); offset++) begin
            int idx;
            axi4_id_t id;
            idx = (r_rr_cursor + offset) % r_active_ids.size();
            id  = r_active_ids[idx];
            if (r_pending.exists(id) && r_pending[id].size() > 0) begin
                ctx = r_pending[id][0];
                r_rr_cursor = (idx + 1) % r_active_ids.size();
                return ctx;
            end
        end
        return null;
    endfunction : choose_interleaved_context

    function axi4_read_context choose_burst_context();
        axi4_read_context ctx;
        if (r_locked_ctx != null)
            return r_locked_ctx;

        if (r_reorder_enable && r_active_ids.size() > 0) begin
            int idx;
            axi4_id_t id;
            idx = $urandom_range(r_active_ids.size()-1, 0);
            id  = r_active_ids[idx];
            if (r_pending.exists(id) && r_pending[id].size() > 0)
                ctx = r_pending[id][0];
        end else if (r_arrival_q.size() > 0) begin
            ctx = r_arrival_q[0];
        end
        r_locked_ctx = ctx;
        return ctx;
    endfunction : choose_burst_context

    function void remove_active_rid(axi4_id_t id);
        for (int i = 0; i < r_active_ids.size(); i++) begin
            if (r_active_ids[i] == id) begin
                r_active_ids.delete(i);
                if (r_rr_cursor > i)
                    r_rr_cursor--;
                if (r_rr_cursor >= r_active_ids.size())
                    r_rr_cursor = 0;
                return;
            end
        end
    endfunction : remove_active_rid

    function void remove_arrival_context(axi4_read_context ctx);
        for (int i = 0; i < r_arrival_q.size(); i++) begin
            if (r_arrival_q[i] == ctx) begin
                r_arrival_q.delete(i);
                return;
            end
        end
    endfunction : remove_arrival_context

    function void complete_read_context(axi4_read_context ctx);
        if (!r_pending.exists(ctx.id) || r_pending[ctx.id].size() == 0 ||
            r_pending[ctx.id][0] != ctx) begin
            `uvm_error(get_type_name(),
                       $sformatf("Internal read-order error for RID=0x%0h", ctx.id))
            return;
        end

        void'(r_pending[ctx.id].pop_front());
        if (r_pending[ctx.id].size() == 0) begin
            r_pending.delete(ctx.id);
            remove_active_rid(ctx.id);
        end
        remove_arrival_context(ctx);
        if (r_context_count > 0)
            r_context_count--;
        if (r_locked_ctx == ctx)
            r_locked_ctx = null;
        if (r_context_count == 0)
            r_interleave_window_open = 0;
    endfunction : complete_read_context

    task drive_r_scheduler();
        forever begin
            axi4_read_context ctx;
            wait (r_context_count > 0);

            // Give a second RID a bounded opportunity to arrive. This makes the
            // directed interleaving test deterministic without deadlocking a
            // legal single-read transaction.
            if (r_interleave_enable && !r_interleave_window_open) begin
                int waited;
                waited = 0;
                while (r_active_ids.size() < r_interleave_start_depth &&
                       waited < r_interleave_start_wait) begin
                    @(vif.slave_cb);
                    waited++;
                end
                r_interleave_window_open = 1;
            end

            if (r_interleave_enable)
                ctx = choose_interleaved_context();
            else
                ctx = choose_burst_context();

            if (ctx == null) begin
                @(vif.slave_cb);
                continue;
            end

            drive_one_r_beat(ctx);
            if (ctx.beat_idx > ctx.len) begin
                `uvm_info(get_type_name(),
                          $sformatf("Read complete: RID=0x%0h ADDR=0x%08h RESP=%s beats=%0d",
                                    ctx.id, ctx.addr, ctx.resp.name(), ctx.len+1), UVM_MEDIUM)
                complete_read_context(ctx);
            end
        end
    endtask : drive_r_scheduler

    task drive_one_r_beat(axi4_read_context ctx);
        int unsigned beat;
        beat = ctx.beat_idx;
        if (beat > ctx.len || beat >= ctx.data_q.size()) begin
            `uvm_error(get_type_name(),
                       $sformatf("Read context beat overflow RID=0x%0h beat=%0d LEN=%0d",
                                 ctx.id, beat, ctx.len))
            ctx.beat_idx = ctx.len + 1;
            return;
        end

        rand_resp_delay();
        @(vif.slave_cb);
        vif.slave_cb.RID    <= ctx.id;
        vif.slave_cb.RDATA  <= ctx.data_q[beat];
        vif.slave_cb.RRESP  <= ctx.resp;
        vif.slave_cb.RLAST  <= (beat == ctx.len);
        vif.slave_cb.RVALID <= 1'b1;

        // The selected beat remains unchanged for every stall cycle. A new RID
        // can be selected only after RVALID && RREADY accepts this beat.
        do @(vif.slave_cb);
        while (!vif.slave_cb.RREADY);

        vif.slave_cb.RVALID <= 1'b0;
        vif.slave_cb.RLAST  <= 1'b0;
        ctx.beat_idx++;
    endtask : drive_one_r_beat

    // =========================================================================
    // is_legal_exclusive - validate exclusive access constraints (AXI4 spec A7.2)
    //   An exclusive access is only legal when ALL of the following hold:
    //     1. Burst length <= 16 beats.
    //     2. Total bytes (bytes/beat * beats) <= 128.
    //     3. Total bytes is a power of two.
    //     4. Start address is aligned to the total number of bytes.
    //   A master that violates these is issuing an illegal exclusive access.
    // =========================================================================
    function bit is_legal_exclusive(bit [AXI4_ADDR_WIDTH-1:0] addr,
                                    bit [2:0]                 size,
                                    bit [7:0]                 len);
        int unsigned num_bytes   = 1 << size;
        int unsigned burst_len   = len + 1;
        int unsigned total_bytes = num_bytes * burst_len;

        if (burst_len > 16)                              return 1'b0; // rule 1
        if (total_bytes > 128)                           return 1'b0; // rule 2
        if ((total_bytes & (total_bytes - 1)) != 0)      return 1'b0; // rule 3 (pow2)
        if ((addr % total_bytes) != 0)                   return 1'b0; // rule 4 (align)
        return 1'b1;
    endfunction : is_legal_exclusive

    // =========================================================================
    // invalidate_reservations_at - clear any exclusive reservation whose
    //   monitored region contains byte_addr. Called for every byte actually
    //   committed to memory (any write, exclusive or normal), so a store that
    //   touches a monitored location cancels the pending exclusive access as
    //   required by the AXI4 spec.
    // =========================================================================
    function void invalidate_reservations_at(bit [AXI4_ADDR_WIDTH-1:0] byte_addr);
        foreach (excl_res[id]) begin
            if (excl_res[id].valid) begin
                int unsigned res_bytes;
                res_bytes = (1 << excl_res[id].size) * (excl_res[id].len + 1);
                if (byte_addr >= excl_res[id].addr &&
                    byte_addr <  (excl_res[id].addr + res_bytes))
                    excl_res[id].valid = 1'b0;
            end
        end
    endfunction : invalidate_reservations_at

    // =========================================================================
    // calc_beat_addr - Calculate address for each beat in a burst
    //   Supports FIXED, INCR, and WRAP burst types per AXI4 spec.
    // =========================================================================
    function bit [AXI4_ADDR_WIDTH-1:0] calc_beat_addr(
        bit [AXI4_ADDR_WIDTH-1:0] start_addr,
        int unsigned              beat_idx,
        bit [2:0]                 size,
        bit [1:0]                 burst_type,
        bit [7:0]                 len
    );
        //Hoang Ho: use the shared, spec-correct burst address helper.
        return axi4_calc_beat_addr(start_addr, beat_idx, size,
                                   axi4_burst_type_e'(burst_type), len);
    endfunction : calc_beat_addr


    //Hoang Ho: legal WSTRB mask helper for AXI4 Full narrow/unaligned writes
    // =========================================================================
    // calc_legal_wstrb_mask
    //   Calculates the legal byte-lane mask for a write beat according to:
    //     - start address
    //     - beat index
    //     - transfer size
    //     - burst type
    //     - burst length
    // =========================================================================
    function bit [AXI4_STRB_WIDTH-1:0] calc_legal_wstrb_mask(
        bit [AXI4_ADDR_WIDTH-1:0] start_addr,
        int unsigned              beat_idx,
        bit [2:0]                 size,
        bit [1:0]                 burst_type,
        bit [7:0]                 len
    );
        //Hoang Ho: use the shared, spec-correct byte-lane helper.
        return axi4_calc_legal_lane_mask(start_addr, beat_idx, size,
                                          axi4_burst_type_e'(burst_type), len);
    endfunction : calc_legal_wstrb_mask

endclass : axi4_slave_driver
