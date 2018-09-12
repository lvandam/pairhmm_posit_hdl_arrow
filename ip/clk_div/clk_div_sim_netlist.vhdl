-- Copyright 1986-2017 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2017.4 (lin64) Build 2086221 Fri Dec 15 20:54:30 MST 2017
-- Date        : Mon Sep 10 21:31:00 2018
-- Host        : laurens-ubuntu running 64-bit Ubuntu 16.04.5 LTS
-- Command     : write_vhdl -force -mode funcsim
--               /home/laurens/Desktop/project_snap/project_snap.srcs/sources_1/ip/clk_div/clk_div_sim_netlist.vhdl
-- Design      : clk_div
-- Purpose     : This VHDL netlist is a functional simulation representation of the design and should not be modified or
--               synthesized. This netlist cannot be used for SDF annotated simulation.
-- Device      : xcku060-ffva1156-2-e
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity clk_div_clk_div_clk_wiz is
  port (
    clk_out1 : out STD_LOGIC;
    clk_in1 : in STD_LOGIC
  );
  attribute ORIG_REF_NAME : string;
  attribute ORIG_REF_NAME of clk_div_clk_div_clk_wiz : entity is "clk_div_clk_wiz";
end clk_div_clk_div_clk_wiz;

architecture STRUCTURE of clk_div_clk_div_clk_wiz is
  signal clk_in1_clk_div : STD_LOGIC;
  attribute BOX_TYPE : string;
  attribute BOX_TYPE of BUFGCE_DIV_CLK1_inst : label is "PRIMITIVE";
  attribute BOX_TYPE of clkin1_ibuf : label is "PRIMITIVE";
  attribute CAPACITANCE : string;
  attribute CAPACITANCE of clkin1_ibuf : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE : string;
  attribute IBUF_DELAY_VALUE of clkin1_ibuf : label is "0";
  attribute IFD_DELAY_VALUE : string;
  attribute IFD_DELAY_VALUE of clkin1_ibuf : label is "AUTO";
begin
BUFGCE_DIV_CLK1_inst: unisim.vcomponents.BUFGCE_DIV
    generic map(
      BUFGCE_DIVIDE => 2,
      IS_CE_INVERTED => '0',
      IS_CLR_INVERTED => '0',
      IS_I_INVERTED => '0'
    )
        port map (
      CE => '1',
      CLR => '0',
      I => clk_in1_clk_div,
      O => clk_out1
    );
clkin1_ibuf: unisim.vcomponents.IBUF
    generic map(
      IOSTANDARD => "DEFAULT"
    )
        port map (
      I => clk_in1,
      O => clk_in1_clk_div
    );
end STRUCTURE;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity clk_div is
  port (
    clk_out1 : out STD_LOGIC;
    clk_in1 : in STD_LOGIC
  );
  attribute NotValidForBitStream : boolean;
  attribute NotValidForBitStream of clk_div : entity is true;
end clk_div;

architecture STRUCTURE of clk_div is
begin
inst: entity work.clk_div_clk_div_clk_wiz
     port map (
      clk_in1 => clk_in1,
      clk_out1 => clk_out1
    );
end STRUCTURE;
