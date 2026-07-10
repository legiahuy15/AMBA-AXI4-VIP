# ============================================================================
# wave.do - AXI4 waveform setup for QuestaSim GUI
#   Custom radices show the enum names declared in src/cfg/axi4_types.sv on the
#   plain interface vectors: burst type, response, size, and lock.
#
#   Colors:
#     - AXI signals use Questa's DEFAULT wave color (green traces, RED for
#       unknown/X regions before reset) - no -color overrides, otherwise the
#       X region loses its red highlight.
#     - User-defined radix values carry their own -color (green) so those rows
#       match the other signals instead of the white/gray default.
#     - clk / rst_n stay yellow.
# ============================================================================

radix define axi4_burst {
    2'b00 "FIXED" -color #00ff00,
    2'b01 "INCR"  -color #00ff00,
    2'b10 "WRAP"  -color #00ff00,
    -default hex
}

radix define axi4_resp {
    2'b00 "OKAY"   -color #00ff00,
    2'b01 "EXOKAY" -color #00ff00,
    2'b10 "SLVERR" -color #00ff00,
    2'b11 "DECERR" -color #00ff00,
    -default hex
}

radix define axi4_size {
    3'b000 "1B"   -color #00ff00,
    3'b001 "2B"   -color #00ff00,
    3'b010 "4B"   -color #00ff00,
    3'b011 "8B"   -color #00ff00,
    3'b100 "16B"  -color #00ff00,
    3'b101 "32B"  -color #00ff00,
    3'b110 "64B"  -color #00ff00,
    3'b111 "128B" -color #00ff00,
    -default hex
}

radix define axi4_lock {
    1'b0 "NORMAL"    -color #00ff00,
    1'b1 "EXCLUSIVE" -color #00ff00,
    -default hex
}

add wave -divider {System}
add wave -color Yellow sim:/tb_top/intf/clk
add wave -color Yellow sim:/tb_top/intf/rst_n

add wave -divider {AW Channel}
add wave -hex sim:/tb_top/intf/AWID
add wave -hex sim:/tb_top/intf/AWADDR
add wave -hex sim:/tb_top/intf/AWLEN
add wave -radix axi4_size  sim:/tb_top/intf/AWSIZE
add wave -radix axi4_burst sim:/tb_top/intf/AWBURST
add wave -radix axi4_lock  sim:/tb_top/intf/AWLOCK
add wave sim:/tb_top/intf/AWVALID
add wave sim:/tb_top/intf/AWREADY

add wave -divider {W Channel}
add wave -hex sim:/tb_top/intf/WDATA
add wave -hex sim:/tb_top/intf/WSTRB
add wave sim:/tb_top/intf/WLAST
add wave sim:/tb_top/intf/WVALID
add wave sim:/tb_top/intf/WREADY

add wave -divider {B Channel}
add wave -hex sim:/tb_top/intf/BID
add wave -radix axi4_resp sim:/tb_top/intf/BRESP
add wave sim:/tb_top/intf/BVALID
add wave sim:/tb_top/intf/BREADY

add wave -divider {AR Channel}
add wave -hex sim:/tb_top/intf/ARID
add wave -hex sim:/tb_top/intf/ARADDR
add wave -hex sim:/tb_top/intf/ARLEN
add wave -radix axi4_size  sim:/tb_top/intf/ARSIZE
add wave -radix axi4_burst sim:/tb_top/intf/ARBURST
add wave -radix axi4_lock  sim:/tb_top/intf/ARLOCK
add wave sim:/tb_top/intf/ARVALID
add wave sim:/tb_top/intf/ARREADY

add wave -divider {R Channel}
add wave -hex sim:/tb_top/intf/RID
add wave -hex sim:/tb_top/intf/RDATA
add wave -radix axi4_resp sim:/tb_top/intf/RRESP
add wave sim:/tb_top/intf/RLAST
add wave sim:/tb_top/intf/RVALID
add wave sim:/tb_top/intf/RREADY
