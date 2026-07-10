# ============================================================================
# wave.do - AXI4 waveform setup for QuestaSim GUI
#   Custom radices show the enum names declared in src/cfg/axi4_types.sv on the
#   plain interface vectors: burst type, response, size, and lock.
# ============================================================================

radix define axi4_burst {2'b00 "FIXED", 2'b01 "INCR", 2'b10 "WRAP", -default hex}
radix define axi4_resp  {2'b00 "OKAY", 2'b01 "EXOKAY", 2'b10 "SLVERR", 2'b11 "DECERR", -default hex}
radix define axi4_size  {3'b000 "1B", 3'b001 "2B", 3'b010 "4B", 3'b011 "8B", 3'b100 "16B", 3'b101 "32B", 3'b110 "64B", 3'b111 "128B", -default hex}
radix define axi4_lock  {1'b0 "NORMAL", 1'b1 "EXCLUSIVE", -default hex}

add wave -divider {System}
add wave -color Yellow sim:/tb_top/intf/clk
add wave -color Yellow sim:/tb_top/intf/rst_n

add wave -divider {AW Channel}
add wave -hex sim:/tb_top/intf/AWID sim:/tb_top/intf/AWADDR sim:/tb_top/intf/AWLEN
add wave -radix axi4_size  sim:/tb_top/intf/AWSIZE
add wave -radix axi4_burst sim:/tb_top/intf/AWBURST
add wave -radix axi4_lock  sim:/tb_top/intf/AWLOCK
add wave sim:/tb_top/intf/AWVALID sim:/tb_top/intf/AWREADY

add wave -divider {W Channel}
add wave -hex sim:/tb_top/intf/WDATA sim:/tb_top/intf/WSTRB
add wave sim:/tb_top/intf/WLAST sim:/tb_top/intf/WVALID sim:/tb_top/intf/WREADY

add wave -divider {B Channel}
add wave -hex sim:/tb_top/intf/BID
add wave -radix axi4_resp sim:/tb_top/intf/BRESP
add wave sim:/tb_top/intf/BVALID sim:/tb_top/intf/BREADY

add wave -divider {AR Channel}
add wave -hex sim:/tb_top/intf/ARID sim:/tb_top/intf/ARADDR sim:/tb_top/intf/ARLEN
add wave -radix axi4_size  sim:/tb_top/intf/ARSIZE
add wave -radix axi4_burst sim:/tb_top/intf/ARBURST
add wave -radix axi4_lock  sim:/tb_top/intf/ARLOCK
add wave sim:/tb_top/intf/ARVALID sim:/tb_top/intf/ARREADY

add wave -divider {R Channel}
add wave -hex sim:/tb_top/intf/RID sim:/tb_top/intf/RDATA
add wave -radix axi4_resp sim:/tb_top/intf/RRESP
add wave sim:/tb_top/intf/RLAST sim:/tb_top/intf/RVALID sim:/tb_top/intf/RREADY
