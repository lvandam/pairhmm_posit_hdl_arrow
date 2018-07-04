// Copyright 1986-2017 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2017.4 (lin64) Build 2086221 Fri Dec 15 20:54:30 MST 2017
// Date        : Mon Jul  2 10:12:15 2018
// Host        : laurens-ubuntu running 64-bit Ubuntu 16.04.4 LTS
// Command     : write_verilog -force -mode synth_stub
//               /home/laurens/Desktop/project_snap/project_snap.srcs/sources_1/ip/baseram/baseram_stub.v
// Design      : baseram
// Purpose     : Stub declaration of top-level module interface
// Device      : xcku115-flva1517-2-e
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "blk_mem_gen_v8_4_1,Vivado 2017.4" *)
module baseram(clka, wea, addra, dina, clkb, addrb, doutb)
/* synthesis syn_black_box black_box_pad_pin="clka,wea[0:0],addra[8:0],dina[2:0],clkb,addrb[4:0],doutb[47:0]" */;
  input clka;
  input [0:0]wea;
  input [8:0]addra;
  input [2:0]dina;
  input clkb;
  input [4:0]addrb;
  output [47:0]doutb;
endmodule
