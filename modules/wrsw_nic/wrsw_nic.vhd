-------------------------------------------------------------------------------
-- Title      : Network Interface Controller
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_nic.vhd
-- Author     : Tomasz Wlostowski, Grzegorz Daniluk
-- Company    : CERN BE-CO-HT
-- Created    : 2012-01-19
-- Last update: 2014-02-14
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description:
-- std-logic-based wrapper for xwrsw_nic module
--
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 - 2014 CERN / BE-CO-HT
--
-- This source file is free software; you can redistribute it
-- and/or modify it under the terms of the GNU Lesser General
-- Public License as published by the Free Software Foundation;
-- either version 2.1 of the License, or (at your option) any
-- later version.
--
-- This source is distributed in the hope that it will be
-- useful, but WITHOUT ANY WARRANTY; without even the implied
-- warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
-- PURPOSE.  See the GNU Lesser General Public License for more
-- details.
--
-- You should have received a copy of the GNU Lesser General
-- Public License along with this source; if not, download it
-- from http://www.gnu.org/licenses/lgpl-2.1.html
--
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;

use work.wishbone_pkg.all;
use work.wr_fabric_pkg.all;

entity wrsw_nic is
  generic
    (
      g_interface_mode      : t_wishbone_interface_mode      := CLASSIC;
      g_address_granularity : t_wishbone_address_granularity := WORD;
      g_src_cyc_on_stall    : boolean := false;
      g_port_mask_bits      : integer := 32); --should be num_ports+1
  port (
    clk_sys_i : in std_logic;
    rst_n_i   : in std_logic;

-------------------------------------------------------------------------------
-- Pipelined Wishbone interface
-------------------------------------------------------------------------------

    -- WBP Master (TX)
    src_dat_o   : out std_logic_vector(15 downto 0);
    src_adr_o   : out std_logic_vector(1 downto 0);
    src_sel_o   : out std_logic_vector(1 downto 0);
    src_cyc_o   : out std_logic;
    src_stb_o   : out std_logic;
    src_we_o    : out std_logic;
    src_stall_i : in  std_logic;
    src_err_i   : in  std_logic;
    src_ack_i   : in  std_logic;

    -- WBP Slave (RX)
    snk_dat_i   : in  std_logic_vector(15 downto 0);
    snk_adr_i   : in  std_logic_vector(1 downto 0);
    snk_sel_i   : in  std_logic_vector(1 downto 0);
    snk_cyc_i   : in  std_logic;
    snk_stb_i   : in  std_logic;
    snk_we_i    : in  std_logic;
    snk_stall_o : out std_logic;
    snk_err_o   : out std_logic;
    snk_ack_o   : out std_logic;

-------------------------------------------------------------------------------
-- "Fake" RTU interface
-------------------------------------------------------------------------------

    rtu_dst_port_mask_o : out std_logic_vector(g_port_mask_bits-1 downto 0);
    rtu_prio_o          : out std_logic_vector(2 downto 0);
    rtu_drop_o          : out std_logic;
    rtu_rsp_valid_o     : out std_logic;
    rtu_rsp_ack_i       : in  std_logic;

-------------------------------------------------------------------------------
-- Wishbone bus
-------------------------------------------------------------------------------

    wb_cyc_i   : in  std_logic;
    wb_stb_i   : in  std_logic;
    wb_we_i    : in  std_logic;
    wb_sel_i   : in  std_logic_vector(c_wishbone_data_width/8-1 downto 0);
    wb_adr_i   : in  std_logic_vector(c_wishbone_address_width-1 downto 0);
    wb_dat_i   : in  std_logic_vector(c_wishbone_data_width-1 downto 0);
    wb_dat_o   : out std_logic_vector(c_wishbone_data_width-1 downto 0);
    wb_ack_o   : out std_logic;
    wb_stall_o : out std_logic;
    wb_int_o   : out std_logic

    );

end wrsw_nic;

architecture rtl of wrsw_nic is

  component xwrsw_nic
    generic (
      g_interface_mode      : t_wishbone_interface_mode;
      g_address_granularity : t_wishbone_address_granularity;
      g_src_cyc_on_stall    : boolean := false;
      g_port_mask_bits      : integer := 32);
    port (
      clk_sys_i           : in  std_logic;
      rst_n_i             : in  std_logic;
      snk_i               : in  t_wrf_sink_in;
      snk_o               : out t_wrf_sink_out;
      src_i               : in  t_wrf_source_in;
      src_o               : out t_wrf_source_out;
      rtu_dst_port_mask_o : out std_logic_vector(g_port_mask_bits-1 downto 0);
      rtu_prio_o          : out std_logic_vector(2 downto 0);
      rtu_drop_o          : out std_logic;
      rtu_rsp_valid_o     : out std_logic;
      rtu_rsp_ack_i       : in  std_logic;
      wb_i                : in  t_wishbone_slave_in;
      wb_o                : out t_wishbone_slave_out);
  end component;

  signal snk_out : t_wrf_sink_out;
  signal snk_in  : t_wrf_sink_in;

  signal src_out : t_wrf_source_out;
  signal src_in  : t_wrf_source_in;

  signal wb_out : t_wishbone_slave_out;
  signal wb_in  : t_wishbone_slave_in;
  

begin

  U_Wrapped_NIC : xwrsw_nic
    generic map (
      g_interface_mode      => g_interface_mode,
      g_address_granularity => g_address_granularity,
      g_src_cyc_on_stall    => g_src_cyc_on_stall,
      g_port_mask_bits      => g_port_mask_bits)
    port map (
      clk_sys_i           => clk_sys_i,
      rst_n_i             => rst_n_i,
      snk_i               => snk_in,
      snk_o               => snk_out,
      src_i               => src_in,
      src_o               => src_out,
      rtu_dst_port_mask_o => rtu_dst_port_mask_o,
      rtu_prio_o          => rtu_prio_o,
      rtu_drop_o          => rtu_drop_o,
      rtu_rsp_valid_o     => rtu_rsp_valid_o,
      rtu_rsp_ack_i       => rtu_rsp_ack_i,
      wb_i                => wb_in,
      wb_o                => wb_out);

  -- WBP Master (TX)
  src_dat_o    <= src_out.dat;
  src_adr_o    <= src_out.adr;
  src_sel_o    <= src_out.sel;
  src_cyc_o    <= src_out.cyc;
  src_stb_o    <= src_out.stb;
  src_we_o     <= src_out.we;
  src_in.stall <= src_stall_i;
  src_in.err   <= src_err_i;
  src_in.ack   <= src_ack_i;

  -- WBP Slave (RX)
  snk_in.dat  <= snk_dat_i;
  snk_in.adr  <= snk_adr_i;
  snk_in.sel  <= snk_sel_i;
  snk_in.cyc  <= snk_cyc_i;
  snk_in.stb  <= snk_stb_i;
  snk_in.we   <= snk_we_i;
  snk_stall_o <= snk_out.stall;
  snk_err_o   <= snk_out.err;
  snk_ack_o   <= snk_out.ack;

  wb_in.cyc  <= wb_cyc_i;
  wb_in.stb  <= wb_stb_i;
  wb_in.we   <= wb_we_i;
  wb_in.sel  <= wb_sel_i;
  wb_in.adr  <= wb_adr_i;
  wb_in.dat  <= wb_dat_i;
  wb_dat_o   <= wb_out.dat;
  wb_ack_o   <= wb_out.ack;
  wb_stall_o <= wb_out.stall;
  wb_int_o   <= wb_out.int;
  
end rtl;
