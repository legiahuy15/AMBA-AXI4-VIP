//=============================================================================
// OWNERSHIP NOTE
//   Original unmarked code in this file : Huy Le / original AXI4-VIP repo
//   Blocks marked //Hoang Ho            : Hoang Ho functional/spec fixes
//=============================================================================
//==============================================================================
// File        : axi4_agent_config.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Configuration object for AXI4 agents.
//               Controls active/passive mode, coverage enable, and slave
//               driver timing delays. Shared by both master and slave agents.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

class axi4_agent_config extends uvm_object;

    `uvm_object_utils(axi4_agent_config)

    // =========================================================================
    // Agent mode
    // =========================================================================
    //   UVM_ACTIVE  - agent has driver + sequencer + monitor (drives traffic)
    //   UVM_PASSIVE - agent has monitor only (passive observation)
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    // =========================================================================
    // Feature enables
    // =========================================================================
    bit has_coverage = 1;       // Enable functional coverage collection

    // =========================================================================
    // Slave driver timing - back-pressure and response delays
    //   Only used by slave agent. Ignored by master agent.
    //   When max = 0, no delay is inserted (fastest response).
    // =========================================================================
    int unsigned ready_delay_min = 0;   // Slave: min cycles before xREADY
    int unsigned ready_delay_max = 0;   // Slave: max cycles before xREADY
    int unsigned resp_delay_min  = 0;   // Slave: min cycles before B/R response
    int unsigned resp_delay_max  = 0;   // Slave: max cycles before B/R response


    //Hoang Ho - BEGIN: learning-profile subordinate behavior knobs
    // Defaults preserve Huy Le's original behavior. Directed tests can enable
    // continuously asserted WREADY and different-ID read response reordering.
    bit          wready_always_high = 0; // Slave keeps WREADY HIGH across a burst
    bit          r_reorder_enable   = 0; // OOO completion is allowed across IDs
    int unsigned r_outstanding_max  = 4; // Concurrent read response preparations
    //Hoang Ho - END: learning-profile subordinate behavior knobs

    //Hoang Ho - BEGIN: Master-side response backpressure configuration
    // =========================================================================
    // Master response back-pressure
    //   Only used by master agent. Controls random delay before asserting
    //   BREADY/RREADY. When max = 0, the master keeps the response channel
    //   ready as early as possible.
    // =========================================================================
    int unsigned bready_delay_min = 0;  // Master: min cycles before BREADY
    int unsigned bready_delay_max = 0;  // Master: max cycles before BREADY
    int unsigned rready_delay_min = 0;  // Master: min cycles before RREADY
    int unsigned rready_delay_max = 0;  // Master: max cycles before RREADY
    //Hoang Ho - END: Master-side response backpressure configuration

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_agent_config");
        super.new(name);
    endfunction : new

endclass : axi4_agent_config