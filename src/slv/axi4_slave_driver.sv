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

class axi4_slave_driver extends uvm_driver #(axi4_transaction);

    `uvm_component_utils(axi4_slave_driver)

    // Virtual interface handle
    virtual axi4_if vif;

    // =========================================================================
    // Built-in memory model (byte-addressable)
    // =========================================================================
    bit [7:0] mem [bit [AXI4_ADDR_WIDTH-1:0]];

    //Hoang Ho - BEGIN: Extended exclusive reservation attributes for AXI4 Full
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
    //Hoang Ho - END: Extended exclusive reservation attributes for AXI4 Full

    // Internal FIFO structs and queues to support outstanding transactions
    typedef struct {
        bit [AXI4_ID_WIDTH-1:0]   id;
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        bit [7:0]                 len;
        bit [2:0]                 size;
        bit [1:0]                 burst;
        axi4_lock_e               lock;
        //Hoang Ho - BEGIN: Capture extra AW attributes for exclusive/access policy
        bit [3:0]                 cache;
        bit [2:0]                 prot;
        bit [3:0]                 region;
        //Hoang Ho - END: Capture extra AW attributes for exclusive/access policy
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
        //Hoang Ho - BEGIN: Capture extra AR attributes for exclusive/access policy
        bit [3:0]                 cache;
        bit [2:0]                 prot;
        bit [3:0]                 region;
        //Hoang Ho - END: Capture extra AR attributes for exclusive/access policy
        //Hoang Ho - request sequence number within one RID; used to preserve
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

    //Hoang Ho - subordinate can keep WREADY continuously HIGH for a corner test.
    bit wready_always_high = 0;

    // Out-of-order read response control
    //   r_reorder_enable  : when 1, read responses may be reordered across IDs
    //   r_outstanding_max : max concurrent read responses being prepared
    bit          r_reorder_enable  = 0;
    int unsigned r_outstanding_max = 4;

    // R channel mutex - the default learning-profile subordinate emits one
    // complete burst at a time. AXI4 permits interleaving between different
    // RID values; the master and monitors accept it, but generation is optional.
    protected semaphore r_channel_mutex;

    //Hoang Ho - BEGIN: explicit same-ID read ordering counters
    // A mutex acquired after random preparation can allow a later same-ID
    // request to overtake an earlier one. Sequence counters make the order
    // deterministic from AR handshake order.
    protected int unsigned ar_issue_seq[bit [AXI4_ID_WIDTH-1:0]];
    protected int unsigned ar_next_rsp_seq[bit [AXI4_ID_WIDTH-1:0]];
    //Hoang Ho - END: explicit same-ID read ordering counters

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
        //Hoang Ho - optional continuous-WREADY mode.
        void'(uvm_config_db#(bit)::get(this, "", "wready_always_high", wready_always_high));
        // Out-of-order read response configuration
        void'(uvm_config_db#(bit)::get(this, "", "r_reorder_enable",  r_reorder_enable));
        void'(uvm_config_db#(int unsigned)::get(this, "", "r_outstanding_max", r_outstanding_max));
        //Hoang Ho - prevent a zero-sized semaphore from deadlocking the R path.
        if (r_outstanding_max == 0)
            r_outstanding_max = 1;
        // Create R channel mutex
        r_channel_mutex = new(1);
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
        //Hoang Ho - clear read ordering state on reset
        ar_issue_seq.delete();
        ar_next_rsp_seq.delete();
        excl_res.delete();      // drop all exclusive reservations on reset

        // Re-create the R-channel mutex. If reset aborts a drive_r_single thread
        // while it holds this mutex, the kill (disable fork) skips its put(1),
        // leaving the old semaphore locked forever. A fresh one guarantees the
        // R channel is usable again after reset.
        r_channel_mutex = new(1);
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

            //Hoang Ho - BEGIN: sample AW payload only at real handshake, not before READY
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
            //Hoang Ho - END: sample AW payload only at real handshake, not before READY

            `uvm_info(get_type_name(),
                      $sformatf("AW received: ID=0x%0h ADDR=0x%08h LEN=%0d LOCK=%s",
                                info.id, info.addr, info.len, info.lock.name()), UVM_HIGH)
            aw_fifo.push_back(info);
        end
    endtask : collect_aw

    // ----- W Collector: collects W bursts from master -----
    task collect_w();
        //Hoang Ho - BEGIN: support both pulsed and continuously-high WREADY
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
        //Hoang Ho - END: support both pulsed and continuously-high WREADY
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
                             //Hoang Ho - BEGIN: match extra exclusive attributes
                             excl_res[aw.id].addr   == aw.addr   &&
                             excl_res[aw.id].size   == aw.size   &&
                             excl_res[aw.id].len    == aw.len    &&
                             excl_res[aw.id].burst  == aw.burst  &&
                             excl_res[aw.id].cache  == aw.cache  &&
                             excl_res[aw.id].prot   == aw.prot   &&
                             excl_res[aw.id].region == aw.region) begin
                    //Hoang Ho - END: match extra exclusive attributes
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

            //Hoang Ho - BEGIN: reject byte strobes outside the legal transfer lanes
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
            //Hoang Ho - END: reject byte strobes outside the legal transfer lanes

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
    // Handle Reads - forks collector and driver to support outstanding reads.
    //   When r_reorder_enable is set, responses may arrive out-of-order
    //   across different IDs. The default learning subordinate emits each
    //   burst contiguously, while the receiving path remains RID-interleave capable.
    // =========================================================================
    task handle_reads();
        fork
            collect_ar();
            dispatch_r_responses();
        join
    endtask : handle_reads

    // ----- AR Collector: listens and handshakes AR address phases -----
    task collect_ar();
        forever begin
            ar_info_t info;

            do @(vif.slave_cb);
            while (!vif.slave_cb.ARVALID);

            rand_ready_delay();
            vif.slave_cb.ARREADY <= 1'b1;

            //Hoang Ho - BEGIN: sample AR payload only at real handshake, not before READY
            //Hoang Ho
            // ARREADY is a clocking-block output and must not be read back in
            // Questa. The driver already holds ARREADY high, so ARVALID sampled
            // at the next clocking event is exactly the AR handshake condition.
            do @(vif.slave_cb);
            while (!vif.slave_cb.ARVALID);
            //Hoang Ho

            info.id     = vif.slave_cb.ARID;
            info.addr   = vif.slave_cb.ARADDR;
            info.len    = vif.slave_cb.ARLEN;
            info.size   = vif.slave_cb.ARSIZE;
            info.burst  = vif.slave_cb.ARBURST;
            info.lock   = axi4_lock_e'(vif.slave_cb.ARLOCK);
            info.cache  = vif.slave_cb.ARCACHE;
            info.prot   = vif.slave_cb.ARPROT;
            info.region = vif.slave_cb.ARREGION;
            //Hoang Ho - assign a monotonically increasing sequence per RID at
            // the actual AR handshake.
            if (!ar_issue_seq.exists(info.id))
                ar_issue_seq[info.id] = 0;
            info.order_idx = ar_issue_seq[info.id];
            ar_issue_seq[info.id]++;

            vif.slave_cb.ARREADY <= 1'b0;
            //Hoang Ho - END: sample AR payload only at real handshake, not before READY

            `uvm_info(get_type_name(),
                      $sformatf("AR received: ID=0x%0h ADDR=0x%08h LEN=%0d LOCK=%s",
                                info.id, info.addr, info.len, info.lock.name()), UVM_HIGH)
            ar_fifo.push_back(info);
        end
    endtask : collect_ar

    // ----- R Dispatcher: forks a thread per AR request for OOO support -----
    //   A semaphore limits the number of concurrent read-response threads.
    //   Each thread prepares its data independently, then acquires the
    //   R channel mutex to drive beats atomically (no interleaving).
    task dispatch_r_responses();
        semaphore r_outstanding_sem = new(r_outstanding_max);
        forever begin
            ar_info_t ar;
            wait (ar_fifo.size() > 0);
            ar = ar_fifo.pop_front();

            //Hoang Ho - initialize the next expected response sequence for RID.
            if (!ar_next_rsp_seq.exists(ar.id))
                ar_next_rsp_seq[ar.id] = 0;

            r_outstanding_sem.get(1);
            fork
                automatic ar_info_t ar_local = ar;
                begin
                    drive_r_single(ar_local);
                    r_outstanding_sem.put(1);
                end
            join_none
        end
    endtask : dispatch_r_responses

    // ----- R Single: prepare data and drive R beats for one AR request -----
    task drive_r_single(ar_info_t ar);
        axi4_resp_e rd_resp;
        // Pre-read data from memory (can happen concurrently for different IDs)
        bit [AXI4_DATA_WIDTH-1:0] rdata_q[$];

        //Hoang Ho - BEGIN: preserve AR acceptance order for the same RID
        wait (ar_next_rsp_seq.exists(ar.id) &&
              ar.order_idx == ar_next_rsp_seq[ar.id]);
        //Hoang Ho - END: preserve AR acceptance order for the same RID

        if (ar.addr >= 32'hF000_0000) begin
            rd_resp = AXI4_RESP_DECERR;
        end else if (ar.addr >= 32'hE000_0000) begin
            rd_resp = AXI4_RESP_SLVERR;
        end else if (ar.lock == AXI4_LOCK_EXCLUSIVE) begin
            // Exclusive read: record the reservation only if the access is a
            // legal exclusive access. An illegal one is a master protocol
            // violation - flag it and respond OKAY (no reservation set).
            if (!is_legal_exclusive(ar.addr, ar.size, ar.len)) begin
                `uvm_error(get_type_name(),
                           $sformatf("Illegal exclusive READ: ID=0x%0h ADDR=0x%08h SIZE=%0d LEN=%0d violates AXI4 exclusive constraints (pow2 bytes<=128, len<=16, aligned)",
                                     ar.id, ar.addr, ar.size, ar.len))
                rd_resp = AXI4_RESP_OKAY;
            end else begin
                rd_resp = AXI4_RESP_EXOKAY;
                //Hoang Ho - BEGIN: store extra exclusive reservation attributes
                excl_res[ar.id] = '{valid:1'b1, addr:ar.addr, size:ar.size, len:ar.len,
                                    burst:ar.burst, cache:ar.cache, prot:ar.prot, region:ar.region};
                //Hoang Ho - END: store extra exclusive reservation attributes
            end
        end else begin
            rd_resp = AXI4_RESP_OKAY;
        end

        //Hoang Ho - BEGIN: correct AXI4 byte-lane mapping for read data
        // Only the legal lanes are populated. For an unaligned first beat the
        // lane range stops at the transfer boundary and never wraps to lane 0.
        for (int beat = 0; beat <= ar.len; beat++) begin
            bit [AXI4_ADDR_WIDTH-1:0] beat_addr;
            bit [AXI4_ADDR_WIDTH-1:0] bus_base;
            bit [AXI4_STRB_WIDTH-1:0] lane_mask;
            bit [AXI4_DATA_WIDTH-1:0] rdata;

            beat_addr = axi4_calc_beat_addr(ar.addr, beat, ar.size,
                                             axi4_burst_type_e'(ar.burst), ar.len);
            bus_base  = axi4_bus_word_base(beat_addr);
            lane_mask = axi4_calc_legal_lane_mask(ar.addr, beat, ar.size,
                                                   axi4_burst_type_e'(ar.burst), ar.len);
            rdata = '0;

            for (int lane = 0; lane < AXI4_STRB_WIDTH; lane++) begin
                bit [AXI4_ADDR_WIDTH-1:0] byte_addr;
                byte_addr = bus_base + lane;
                if (lane_mask[lane] && mem.exists(byte_addr))
                    rdata[lane*8 +: 8] = mem[byte_addr];
            end
            rdata_q.push_back(rdata);
        end
        //Hoang Ho - END: correct AXI4 byte-lane mapping for read data

        //Hoang Ho - same-ID ordering is already guaranteed by order_idx above.

        // When reordering is enabled, add a random delay before acquiring
        // the channel mutex.  This creates natural reordering: a later
        // request with a shorter delay will drive before an earlier one.
        if (r_reorder_enable) begin
            int unsigned reorder_delay;
            reorder_delay = $urandom_range(10, 0);
            repeat (reorder_delay) @(vif.slave_cb);
        end

        // Acquire R channel mutex - only one thread drives R beats at a time
        // This learning-profile subordinate emits one complete burst at a time.
        // AXI4 permits read-data interleaving across different IDs, and the
        // master receiver can accept it, but the default slave model keeps the
        // R channel non-interleaved for simpler deterministic stimulus.
        r_channel_mutex.get(1);

        for (int beat = 0; beat <= ar.len; beat++) begin
            rand_resp_delay();
            @(vif.slave_cb);
            vif.slave_cb.RID    <= ar.id;
            vif.slave_cb.RDATA  <= rdata_q[beat];
            vif.slave_cb.RRESP  <= rd_resp;
            vif.slave_cb.RLAST  <= (beat == ar.len) ? 1'b1 : 1'b0;
            vif.slave_cb.RVALID <= 1'b1;

            do @(vif.slave_cb);
            while (!vif.slave_cb.RREADY);

            vif.slave_cb.RVALID <= 1'b0;
            vif.slave_cb.RLAST  <= 1'b0;
        end

        r_channel_mutex.put(1);
        //Hoang Ho - release the next same-ID request only after this burst ends.
        ar_next_rsp_seq[ar.id]++;

        `uvm_info(get_type_name(),
                  $sformatf("Read complete: ID=0x%0h ADDR=0x%08h RESP=%s  %0d beats sent",
                            ar.id, ar.addr, rd_resp.name(), ar.len + 1), UVM_MEDIUM)
    endtask : drive_r_single

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
        //Hoang Ho - use the shared, spec-correct burst address helper.
        return axi4_calc_beat_addr(start_addr, beat_idx, size,
                                   axi4_burst_type_e'(burst_type), len);
    endfunction : calc_beat_addr


    //Hoang Ho - BEGIN: legal WSTRB mask helper for AXI4 Full narrow/unaligned writes
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
        //Hoang Ho - use the shared, spec-correct byte-lane helper.
        return axi4_calc_legal_lane_mask(start_addr, beat_idx, size,
                                          axi4_burst_type_e'(burst_type), len);
    endfunction : calc_legal_wstrb_mask
    //Hoang Ho - END: legal WSTRB mask helper for AXI4 Full narrow/unaligned writes

endclass : axi4_slave_driver