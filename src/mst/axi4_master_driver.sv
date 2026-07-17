//=============================================================================
// OWNERSHIP NOTE
//   Original unmarked code in this file : Huy Le / original AXI4-VIP repo
//   Blocks marked //Hoang Ho            : Hoang Ho functional/spec fixes
//=============================================================================
//==============================================================================
// File        : axi4_master_driver.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 master driver.
//               Receives transactions from the sequencer and drives them
//               onto the AXI4 bus via the master clocking block.
//               Write flow : AW + W (parallel) -> wait B
//               Read flow  : AR -> wait R (all beats)
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

//Huy Le: original architecture and baseline implementation.
class axi4_master_driver extends uvm_driver #(axi4_transaction);

    `uvm_component_utils(axi4_master_driver)

    // Virtual interface handle
    virtual axi4_if vif;

    // Drive queues for channel ordering
    protected axi4_transaction aw_drive_queue[$];
    protected axi4_transaction w_drive_queue[$];
    protected axi4_transaction ar_drive_queue[$];

    // Queues and tables for tracking outstanding transactions
    protected axi4_transaction pending_b_tr[bit[AXI4_ID_WIDTH-1:0]][$];
    protected axi4_transaction pending_r_tr[bit[AXI4_ID_WIDTH-1:0]][$];

    //Hoang Ho: beat-level read response tracking by transaction
    // Allows legal R-channel interleaving between different RID values while
    // preserving request order for transactions that use the same ID.
    protected int unsigned pending_r_beat[axi4_transaction];

    // Inter-channel synchronization flags for wr_order constraints
    protected bit aw_done[axi4_transaction];
    protected bit w_started[axi4_transaction];

    // Phase handle for simulation objection control
    protected uvm_phase run_phase_handle;
    protected int unsigned active_objections_cnt = 0;

    // Master-side response back-pressure configuration. These fields control
    // how long the master waits before asserting BREADY/RREADY. They allow
    // response-channel payload stability checks and back-pressure coverage to
    // be exercised. When max = 0, the master responds with no extra delay.
    int unsigned bready_delay_min = 0;
    int unsigned bready_delay_max = 0;
    int unsigned rready_delay_min = 0;
    int unsigned rready_delay_max = 0;

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

        void'(uvm_config_db#(int unsigned)::get(this, "", "bready_delay_min", bready_delay_min));
        void'(uvm_config_db#(int unsigned)::get(this, "", "bready_delay_max", bready_delay_max));
        void'(uvm_config_db#(int unsigned)::get(this, "", "rready_delay_min", rready_delay_min));
        void'(uvm_config_db#(int unsigned)::get(this, "", "rready_delay_max", rready_delay_max));
    endfunction : build_phase

    // =========================================================================
    // Run phase - main driver loop (supports parallel/pipelined outstanding transactions)
    // =========================================================================
    task run_phase(uvm_phase phase);
        run_phase_handle = phase;
        // Outer loop: recover from reset at any time during operation.
        // If reset is asserted mid-transaction, the fork is killed and
        // the driver re-initialises cleanly.
        forever begin
            reset_signals();
            @(posedge vif.rst_n);
            `uvm_info(get_type_name(), "Reset deasserted - master driver active", UVM_MEDIUM)

            fork
                begin : drive_loop
                    forever begin
                        axi4_transaction tr;
                        seq_item_port.get_next_item(tr);
                        `uvm_info(get_type_name(),
                                  $sformatf("Driving %s  ID=0x%0h  ADDR=0x%08h  LEN=%0d",
                                            tr.dir.name(), tr.id, tr.addr, tr.len), UVM_MEDIUM)

                        if (tr.dir == AXI4_WRITE) begin
                            raise_driver_objection("Pending write transaction");
                            pending_b_tr[tr.id].push_back(tr);
                            aw_drive_queue.push_back(tr);
                            w_drive_queue.push_back(tr);
                        end else begin
                            raise_driver_objection("Pending read transaction");
                            pending_r_tr[tr.id].push_back(tr);
                            ar_drive_queue.push_back(tr);
                        end

                        seq_item_port.item_done();
                    end
                end
                aw_drive_loop();
                w_drive_loop();
                ar_drive_loop();
                receive_b_responses();
                receive_r_responses();
                begin : rst_watch
                    @(negedge vif.rst_n);
                    `uvm_info(get_type_name(), "Reset asserted - aborting", UVM_MEDIUM)
                end
            join_any
            disable fork;
        end
    endtask : run_phase

    // =========================================================================
    // Reset - deassert all master-driven VALID / READY signals
    // =========================================================================
    task reset_signals();
        @(vif.master_cb);
        vif.master_cb.AWVALID <= 1'b0;
        vif.master_cb.WVALID  <= 1'b0;
        vif.master_cb.BREADY  <= 1'b0;
        vif.master_cb.ARVALID <= 1'b0;
        vif.master_cb.RREADY  <= 1'b0;
        vif.master_cb.WLAST   <= 1'b0;

        aw_drive_queue.delete();
        w_drive_queue.delete();
        ar_drive_queue.delete();
        pending_b_tr.delete();
        pending_r_tr.delete();
        //Hoang Ho: reset read beat state together with outstanding requests
        pending_r_beat.delete();
        aw_done.delete();
        w_started.delete();
        clear_objections();
    endtask : reset_signals

    // =========================================================================
    // Objection helpers
    // =========================================================================
    function void raise_driver_objection(string desc = "");
        if (run_phase_handle != null) begin
            run_phase_handle.raise_objection(this, desc);
            active_objections_cnt++;
        end
    endfunction

    function void drop_driver_objection(string desc = "");
        if (run_phase_handle != null && active_objections_cnt > 0) begin
            run_phase_handle.drop_objection(this, desc);
            active_objections_cnt--;
        end
    endfunction

    function void clear_objections();
        if (run_phase_handle != null) begin
            repeat (active_objections_cnt) begin
                run_phase_handle.drop_objection(this, "Reset cleanup");
            end
        end
        active_objections_cnt = 0;
    endfunction

    // =========================================================================
    // Channel drive loops - process transactions in FIFO order from the queues
    // =========================================================================
    task aw_drive_loop();
        forever begin
            axi4_transaction tr;
            wait(aw_drive_queue.size() > 0);
            tr = aw_drive_queue[0];

            if (tr.wr_order == AXI4_WR_W_BEFORE_AW) begin
                wait(w_started.exists(tr) && w_started[tr] == 1);
                repeat ($urandom_range(5, 2)) @(vif.master_cb);
            end

            void'(aw_drive_queue.pop_front());
            drive_aw_channel(tr);
            aw_done[tr] = 1;
        end
    endtask : aw_drive_loop

    task w_drive_loop();
        forever begin
            axi4_transaction tr;
            wait(w_drive_queue.size() > 0);
            tr = w_drive_queue[0];

            if (tr.wr_order == AXI4_WR_AW_BEFORE_W) begin
                wait(aw_done.exists(tr) && aw_done[tr] == 1);
            end

            void'(w_drive_queue.pop_front());
            w_started[tr] = 1;
            drive_w_channel(tr);
        end
    endtask : w_drive_loop

    task ar_drive_loop();
        forever begin
            axi4_transaction tr;
            wait(ar_drive_queue.size() > 0);
            tr = ar_drive_queue.pop_front();
            drive_ar_channel(tr);
        end
    endtask : ar_drive_loop

    // =========================================================================
    // AW Channel - Write Address phase
    // =========================================================================
    task drive_aw_channel(axi4_transaction tr);
        @(vif.master_cb);
        vif.master_cb.AWVALID  <= 1'b1;
        vif.master_cb.AWID     <= tr.id;
        vif.master_cb.AWADDR   <= tr.addr;
        vif.master_cb.AWLEN    <= tr.len;
        vif.master_cb.AWSIZE   <= tr.size;
        vif.master_cb.AWBURST  <= tr.burst;
        vif.master_cb.AWLOCK   <= tr.lock;
        vif.master_cb.AWCACHE  <= tr.cache;
        vif.master_cb.AWPROT   <= tr.prot;
        vif.master_cb.AWQOS    <= tr.qos;
        vif.master_cb.AWREGION <= tr.region;

        // Wait for AWREADY handshake
        do @(vif.master_cb);
        while (!vif.master_cb.AWREADY);

        // Handshake complete - deassert VALID
        vif.master_cb.AWVALID <= 1'b0;
    endtask : drive_aw_channel

    // =========================================================================
    // W Channel - Write Data phase
    // =========================================================================
    task drive_w_channel(axi4_transaction tr);
        //Hoang Ho: continuous-WREADY-safe write-data driver
        // Present the first beat once, then update the payload immediately after
        // each handshake. There is no extra idle clock while WVALID remains high,
        // so a subordinate that keeps WREADY asserted cannot accept a beat twice.
        @(vif.master_cb);
        vif.master_cb.WVALID <= 1'b1;

        for (int i = 0; i <= tr.len; i++) begin
            vif.master_cb.WDATA <= tr.data[i];
            vif.master_cb.WSTRB <= tr.strb[i];
            vif.master_cb.WLAST <= (i == tr.len);

            do @(vif.master_cb);
            while (!vif.master_cb.WREADY);
        end

        vif.master_cb.WVALID <= 1'b0;
        vif.master_cb.WLAST  <= 1'b0;
    endtask : drive_w_channel

    // =========================================================================
    // AR Channel - Read Address phase
    // =========================================================================
    task drive_ar_channel(axi4_transaction tr);
        @(vif.master_cb);
        vif.master_cb.ARVALID  <= 1'b1;
        vif.master_cb.ARID     <= tr.id;
        vif.master_cb.ARADDR   <= tr.addr;
        vif.master_cb.ARLEN    <= tr.len;
        vif.master_cb.ARSIZE   <= tr.size;
        vif.master_cb.ARBURST  <= tr.burst;
        vif.master_cb.ARLOCK   <= tr.lock;
        vif.master_cb.ARCACHE  <= tr.cache;
        vif.master_cb.ARPROT   <= tr.prot;
        vif.master_cb.ARQOS    <= tr.qos;
        vif.master_cb.ARREGION <= tr.region;

        // Wait for ARREADY handshake
        do @(vif.master_cb);
        while (!vif.master_cb.ARREADY);

        // Handshake complete - deassert VALID
        vif.master_cb.ARVALID <= 1'b0;
    endtask : drive_ar_channel

    //Hoang Ho: Master-side B/R response backpressure helper tasks
    // =========================================================================
    // Response READY delay helpers
    // =========================================================================
    task rand_bready_delay();
        int unsigned delay;
        if (bready_delay_max > 0) begin
            delay = $urandom_range(bready_delay_max, bready_delay_min);
            vif.master_cb.BREADY <= 1'b0;
            repeat (delay) @(vif.master_cb);
        end
    endtask : rand_bready_delay

    task rand_rready_delay();
        int unsigned delay;
        if (rready_delay_max > 0) begin
            delay = $urandom_range(rready_delay_max, rready_delay_min);
            vif.master_cb.RREADY <= 1'b0;
            repeat (delay) @(vif.master_cb);
        end
    endtask : rand_rready_delay

    // Wait for one B handshake while optionally applying master-side
    // BREADY back-pressure.
    task wait_b_handshake(output bit [AXI4_ID_WIDTH-1:0] bid,
                          output axi4_resp_e             bresp);
        rand_bready_delay();
        vif.master_cb.BREADY <= 1'b1;
        do @(vif.master_cb);
        while (!vif.master_cb.BVALID);
        bid   = vif.master_cb.BID;
        bresp = axi4_resp_e'(vif.master_cb.BRESP);
        vif.master_cb.BREADY <= 1'b0;
    endtask : wait_b_handshake

    // Wait for one R handshake while optionally applying master-side
    // RREADY back-pressure.
    task wait_r_handshake(output bit [AXI4_ID_WIDTH-1:0]   rid,
                          output bit [AXI4_DATA_WIDTH-1:0] rdata,
                          output axi4_resp_e               rresp,
                          output bit                       rlast);
        rand_rready_delay();
        vif.master_cb.RREADY <= 1'b1;
        do @(vif.master_cb);
        while (!vif.master_cb.RVALID);
        rid   = vif.master_cb.RID;
        rdata = vif.master_cb.RDATA;
        rresp = axi4_resp_e'(vif.master_cb.RRESP);
        rlast = vif.master_cb.RLAST;
        vif.master_cb.RREADY <= 1'b0;
    endtask : wait_r_handshake

    // =========================================================================
    // B Channel response receiver (kept active in parallel)
    // =========================================================================
    task receive_b_responses();
        vif.master_cb.BREADY <= 1'b0;
        forever begin
            bit [AXI4_ID_WIDTH-1:0] bid;
            axi4_resp_e             bresp;

            //Hoang Ho: use backpressure-aware B handshake capture
            wait_b_handshake(bid, bresp);

            if (pending_b_tr.exists(bid) && pending_b_tr[bid].size() > 0) begin
                axi4_transaction tr;
                tr = pending_b_tr[bid].pop_front();
                tr.resp = bresp;

                w_started.delete(tr);
                aw_done.delete(tr);

                drop_driver_objection("Write response received");
                //Hoang Ho: persistent completion state is safe even if a
                // sequence starts waiting after the event pulse.
                tr.completed       = 1'b1;
                tr.completion_time = $time;
                ->tr.done_event.ev;
                `uvm_info(get_type_name(),
                          $sformatf("Master driver received B response: ID=0x%0h RESP=%s",
                                    tr.id, tr.resp.name()), UVM_HIGH)
            end else begin
                `uvm_error(get_type_name(),
                           $sformatf("Master driver received unexpected B response ID=0x%0h", bid))
            end
        end
    endtask : receive_b_responses

    // =========================================================================
    // R Channel response receiver (kept active in parallel)
    // =========================================================================
    task receive_r_responses();
        vif.master_cb.RREADY <= 1'b0;
        forever begin
            bit [AXI4_ID_WIDTH-1:0]   rid;
            bit [AXI4_DATA_WIDTH-1:0] rdata;
            axi4_resp_e               rresp;
            bit                       rlast;
            axi4_transaction          tr;
            int unsigned              beat_idx;

            wait_r_handshake(rid, rdata, rresp, rlast);

            //Hoang Ho: RID-based beat dispatcher with legal interleaving
            if (pending_r_tr.exists(rid) && pending_r_tr[rid].size() > 0) begin
                // Same-ID transactions remain ordered because only the front
                // transaction for this RID can consume beats. Different RIDs can
                // alternate freely from one handshake to the next.
                tr = pending_r_tr[rid][0];
                if (!pending_r_beat.exists(tr))
                    pending_r_beat[tr] = 0;
                beat_idx = pending_r_beat[tr];

                if (beat_idx > tr.len) begin
                    `uvm_error(get_type_name(),
                               $sformatf("Extra R beat for ID=0x%0h after expected LEN=%0d", rid, tr.len))
                end else begin
                    tr.data[beat_idx]  = rdata;
                    tr.rresp[beat_idx] = rresp;

                    if ((beat_idx == tr.len) && !rlast)
                        `uvm_error(get_type_name(),
                                   $sformatf("RLAST missing on final beat %0d for RID=0x%0h", beat_idx, rid))
                    if ((beat_idx != tr.len) && rlast)
                        `uvm_error(get_type_name(),
                                   $sformatf("RLAST asserted early on beat %0d of %0d for RID=0x%0h", beat_idx, tr.len, rid))

                    if (rlast || (beat_idx == tr.len)) begin
                        void'(pending_r_tr[rid].pop_front());
                        if (pending_r_tr[rid].size() == 0)
                            pending_r_tr.delete(rid);
                        pending_r_beat.delete(tr);
                        drop_driver_objection("Read completed");
                        //Hoang Ho: persistent completion state for read burst.
                        tr.completed       = 1'b1;
                        tr.completion_time = $time;
                        ->tr.done_event.ev;
                        `uvm_info(get_type_name(),
                                  $sformatf("Master driver completed R burst: ID=0x%0h beats=%0d",
                                            tr.id, tr.len + 1), UVM_HIGH)
                    end else begin
                        pending_r_beat[tr] = beat_idx + 1;
                    end
                end
            end else begin
                `uvm_error(get_type_name(),
                           $sformatf("Master driver received unexpected R response RID=0x%0h", rid))
            end
        end
    endtask : receive_r_responses


endclass : axi4_master_driver
