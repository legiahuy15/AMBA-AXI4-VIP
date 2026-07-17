//==============================================================================
// File        : tb_top.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Top-level testbench module for AXI4 VIP.
//               Generates clock and reset, instantiates the interface,
//               propagates the virtual interface to UVM config_db,
//               and starts the UVM phase execution via run_test().
//==============================================================================

`timescale 1ns/1ps

//Huy Le: original architecture and baseline implementation.
module tb_top;

    // =========================================================================
    // Imports & Macros
    // =========================================================================
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Import VIP and Test packages
    import axi4_pkg::*;
    import axi4_test_pkg::*;

    // =========================================================================
    // Parameters (Match standard values used across agents & tests)
    // =========================================================================
    //Hoang Ho: these values are compiled consistently across the whole VIP.
    localparam int ADDR_WIDTH = AXI4_ADDR_WIDTH;
    localparam int DATA_WIDTH = AXI4_DATA_WIDTH;
    localparam int ID_WIDTH   = AXI4_ID_WIDTH;


    //Hoang Ho: fail early when an unsupported external configuration is used.
    initial begin
        if (!axi4_supported_data_width())
            $fatal(1, "Unsupported AXI4 DATA_WIDTH=%0d. Supported external profiles: 32/64/128/256/512/1024.", DATA_WIDTH);
        if ((DATA_WIDTH % 8) != 0 || ((DATA_WIDTH & (DATA_WIDTH-1)) != 0))
            $fatal(1, "DATA_WIDTH must be a power-of-two number of bits and divisible by 8.");
        if (ADDR_WIDTH < 12)
            $fatal(1, "ADDR_WIDTH must be at least 12 for AXI4 4KB-boundary checking.");
        if (ID_WIDTH < 1)
            $fatal(1, "ID_WIDTH must be at least 1.");
        $display("[AXI4-CONFIG] ADDR=%0d DATA=%0d ID=%0d STRB=%0d MAX_SIZE=%0d",
                 ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, AXI4_STRB_WIDTH, AXI4_MAX_SIZE);
    end

    // =========================================================================
    // Clock and Reset Generation
    // =========================================================================
    bit clk;
    bit rst_n;

    // 100 MHz Clock (10ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Reset assertion (Active low, held for 10 clock cycles)
    initial begin
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        `uvm_info("TOP_TB", "Reset de-asserted", UVM_MEDIUM)
    end

    // =========================================================================
    // Mid-simulation reset support
    //   A test can request an EXTRA reset pulse (to verify reset-recovery of the
    //   drivers and monitors) by triggering the global UVM event
    //   "axi4_reset_req". rst_n is driven low for a few cycles, then released.
    //   This is independent of the power-on reset above.
    // =========================================================================
    initial begin
        automatic uvm_event reset_ev = uvm_event_pool::get_global("axi4_reset_req");
        forever begin
            reset_ev.wait_trigger();
            `uvm_info("TB_TOP", "Mid-sim reset requested - asserting rst_n", UVM_LOW)
            rst_n = 1'b0;
            repeat (8) @(posedge clk);
            rst_n = 1'b1;
            `uvm_info("TB_TOP", "Mid-sim reset pulse complete - rst_n deasserted", UVM_LOW)
        end
    end

    // =========================================================================
    // Interface Instance
    // =========================================================================
    axi4_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) intf (
        .clk(clk),
        .rst_n(rst_n)
    );

    // =========================================================================
    // SVA - AXI4 protocol assertion checker
    //   Direct instantiation (Old versions of QuestaSim does not support bind-to-interface).
    //   All signals are connected via the interface instance `intf`.
    // =========================================================================
    axi4_sva #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_axi4_sva (
        .clk      (clk),
        .rst_n    (rst_n),
        // AW Channel
        .AWID     (intf.AWID),
        .AWADDR   (intf.AWADDR),
        .AWLEN    (intf.AWLEN),
        .AWSIZE   (intf.AWSIZE),
        .AWBURST  (intf.AWBURST),
        .AWLOCK   (intf.AWLOCK),
        .AWCACHE  (intf.AWCACHE),
        .AWPROT   (intf.AWPROT),
        .AWQOS    (intf.AWQOS),
        .AWREGION (intf.AWREGION),
        .AWVALID  (intf.AWVALID),
        .AWREADY  (intf.AWREADY),
        // W Channel
        .WDATA    (intf.WDATA),
        .WSTRB    (intf.WSTRB),
        .WLAST    (intf.WLAST),
        .WVALID   (intf.WVALID),
        .WREADY   (intf.WREADY),
        // B Channel
        .BID      (intf.BID),
        .BRESP    (intf.BRESP),
        .BVALID   (intf.BVALID),
        .BREADY   (intf.BREADY),
        // AR Channel
        .ARID     (intf.ARID),
        .ARADDR   (intf.ARADDR),
        .ARLEN    (intf.ARLEN),
        .ARSIZE   (intf.ARSIZE),
        .ARBURST  (intf.ARBURST),
        .ARLOCK   (intf.ARLOCK),
        .ARCACHE  (intf.ARCACHE),
        .ARPROT   (intf.ARPROT),
        .ARQOS    (intf.ARQOS),
        .ARREGION (intf.ARREGION),
        .ARVALID  (intf.ARVALID),
        .ARREADY  (intf.ARREADY),
        // R Channel
        .RID      (intf.RID),
        .RDATA    (intf.RDATA),
        .RRESP    (intf.RRESP),
        .RLAST    (intf.RLAST),
        .RVALID   (intf.RVALID),
        .RREADY   (intf.RREADY)
    );

    // =========================================================================
    // UVM Setup & Execution
    // =========================================================================
    initial begin
        uvm_config_db#(virtual axi4_if)::set(null, "*", "vif", intf);

        `uvm_info("TB_TOP", "Virtual interface set in config_db", UVM_LOW)

        // Kick off UVM phases. The active test is specified via +UVM_TESTNAME plusarg.
        run_test();
    end

    // =========================================================================
    // Simulation Control & Waveform Dumping
    // =========================================================================
    initial begin
        string vcd_file;

        // Huy Le: +DUMP_VCD enables waveform dumping for learning/debug.
        // Hoang Ho: +VCD_FILE=<path> gives every run a unique waveform name,
        // so selected-width runs do not overwrite another test waveform.
        if ($test$plusargs("DUMP_VCD")) begin
            if (!$value$plusargs("VCD_FILE=%s", vcd_file))
                vcd_file = "axi4_vip.vcd";
            $dumpfile(vcd_file);
            $dumpvars(0, tb_top);
            `uvm_info("TB_TOP",
                      $sformatf("Waveform VCD dumping enabled (%s)", vcd_file),
                      UVM_LOW)
        end
    end

    // =========================================================================
    // Safety simulation watchdog
    //   Prevents a regression from hanging forever if a test deadlocks (e.g. a
    //   lost handshake or a dropped response). Fires a UVM_FATAL, which prints
    //   the report summary and ends the run cleanly - so the regression harness
    //   detects the failure via its UVM_FATAL grep.
    //   The timeout (in ns) is overridable from the command line:
    //       make run PLUSARGS=+TIMEOUT_NS=2000000
    //   With the 1ns timescale, the default 10_000_000 ns = 10 ms of sim time.
    // =========================================================================
    initial begin
        automatic longint unsigned timeout_ns = 10_000_000;  // 10 ms default backup
        void'($value$plusargs("TIMEOUT_NS=%d", timeout_ns));
        #(timeout_ns);
        `uvm_fatal("TB_TOP",
                   $sformatf("Simulation safety timeout reached (%0d ns)! Possible hang detected.",
                             timeout_ns))
    end

endmodule : tb_top
