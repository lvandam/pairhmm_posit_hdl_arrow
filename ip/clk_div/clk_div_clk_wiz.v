
// file: clk_div.v
// 
// (c) Copyright 2008 - 2013 Xilinx, Inc. All rights reserved.
// 
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.
// 
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) Xilinx shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or Xilinx had been advised of the
// possibility of the same.
// 
// CRITICAL APPLICATIONS
// Xilinx products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of Xilinx products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
// 
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
// 
//----------------------------------------------------------------------------
// User entered comments
//----------------------------------------------------------------------------
// None
//
//----------------------------------------------------------------------------
//  Output     Output      Phase    Duty Cycle   Pk-to-Pk     Phase
//   Clock     Freq (MHz)  (degrees)    (%)     Jitter (ps)  Error (ps)
//----------------------------------------------------------------------------
// clk_out1___125.000______0.000______50.0______102.531_____85.928
//
//----------------------------------------------------------------------------
// Input Clock   Freq (MHz)    Input Jitter (UI)
//----------------------------------------------------------------------------
// __primary_____________250____________0.010

`timescale 1ps/1ps

module clk_div_clk_wiz 

 (// Clock in ports
  // Clock out ports
  output        clk_out1,
  input         clk_in1
 );
  // Input buffering
  //------------------------------------
wire clk_in1_clk_div;
wire clk_in2_clk_div;
  IBUF clkin1_ibuf
   (.O (clk_in1_clk_div),
    .I (clk_in1));




  // Clocking PRIMITIVE
  //------------------------------------

  // Instantiation of the MMCM PRIMITIVE
  //    * Unused inputs are tied off
  //    * Unused outputs are labeled unused

  wire        clk_out1_clk_div;
  wire        clk_out2_clk_div;
  wire        clk_out3_clk_div;
  wire        clk_out4_clk_div;
  wire        clk_out5_clk_div;
  wire        clk_out6_clk_div;
  wire        clk_out7_clk_div;

  wire [15:0] do_unused;
  wire        drdy_unused;
  wire        psdone_unused;
  wire        locked_int;
  wire        clkfbout_clk_div;
  wire        clkfboutb_unused;
    wire clkout0b_unused;
   wire clkout1_unused;
   wire clkout1b_unused;
   wire clkout2_unused;
   wire clkout2b_unused;
   wire clkout3_unused;
   wire clkout3b_unused;
   wire clkout4_unused;
  wire        clkout5_unused;
  wire        clkout6_unused;
  wire        clkfbstopped_unused;
  wire        clkinstopped_unused;

 

// Auto Instantiation//


BUFGCE_DIV #(
      .BUFGCE_DIVIDE(2.0),      // 1-8
      // Programmable Inversion Attributes: Specifies built-in programmable inversion on specific pins
      .IS_CE_INVERTED(1'b0),  // Optional inversion for CE
      .IS_CLR_INVERTED(1'b0), // Optional inversion for CLR
      .IS_I_INVERTED(1'b0)    // Optional inversion for I
   )
   BUFGCE_DIV_CLK1_inst (
      .O(clk_out1_clk_div),     // 1-bit output: Buffer
      .CE(1'b1),   // 1-bit input: Buffer enable
      .CLR(1'b0), // 1-bit input: Asynchronous clear
      .I(clk_in1_clk_div)      // 1-bit input: Buffer
   );
   
   



// Clock Monitor clock assigning
//--------------------------------------
 // Output buffering
  //-----------------------------------






  assign clk_out1 = clk_out1_clk_div;




endmodule
