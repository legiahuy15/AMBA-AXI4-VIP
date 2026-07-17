//Hoang Ho: one compile-time configuration shared by interface, package, SVA and tb_top.
// Override from the Makefile, for example: make run DATA_WIDTH=512.
`ifndef AXI4_COMPILE_CFG_SVH
`define AXI4_COMPILE_CFG_SVH

`ifndef AXI4_ADDR_WIDTH_CFG
  `define AXI4_ADDR_WIDTH_CFG 32
`endif

`ifndef AXI4_DATA_WIDTH_CFG
  `define AXI4_DATA_WIDTH_CFG 32
`endif

`ifndef AXI4_ID_WIDTH_CFG
  `define AXI4_ID_WIDTH_CFG 4
`endif

`endif
