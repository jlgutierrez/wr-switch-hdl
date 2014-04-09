-------------------------------------------------------------------------------
-- Title      : Hardware Info Unit
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_hwiu.vhd
-- Author     : Grzegorz Daniluk
-- Company    : CERN BE-CO-HT
-- Created    : 2013-03-26
-- Last update: 2014-02-05
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description:
-- std-logic-based wrapper for xwrsw_hwiu module.
-------------------------------------------------------------------------------
--
-- Copyright (c) 2013 - 2014 CERN / BE-CO-HT
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
-- Revisions  :
-- Date        Version  Author          Description
-- 2013-03-26  0.1      greg.d          Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use work.wishbone_pkg.all;
use work.hwinfo_pkg.all;

entity wrsw_hwiu is
  generic (
    g_ndbg_regs : integer := 1;
    g_ver_major : integer;
    g_ver_minor : integer;
    g_build     : integer := 0);
  port(
    rst_n_i : in std_logic;
    clk_i   : in std_logic;

    dbg_regs_i    : in std_logic_vector(g_ndbg_regs*32-1 downto 0) := (others => '0');
    dbg_chps_id_o : out std_logic_vector(7 downto 0);

    wb_adr_i   : in  std_logic_vector(1 downto 0);
    wb_dat_i   : in  std_logic_vector(31 downto 0);
    wb_dat_o   : out std_logic_vector(31 downto 0);
    wb_cyc_i   : in  std_logic;
    wb_sel_i   : in  std_logic_vector(3 downto 0);
    wb_stb_i   : in  std_logic;
    wb_we_i    : in  std_logic;
    wb_ack_o   : out std_logic;
    wb_stall_o : out std_logic;
    wb_int_o   : out std_logic);
end wrsw_hwiu;

architecture behav of wrsw_hwiu is

  component xwrsw_hwiu
    generic (
      g_interface_mode      : t_wishbone_interface_mode;
      g_address_granularity : t_wishbone_address_granularity;
      g_ndbg_regs           : integer;
      g_ver_major           : integer;
      g_ver_minor           : integer;
      g_build               : integer);
    port(
      rst_n_i : in std_logic;
      clk_i   : in std_logic;

      dbg_regs_i    : in std_logic_vector(g_ndbg_regs*32-1 downto 0);
      dbg_chps_id_o : out std_logic_vector(7 downto 0);

      wb_i : in  t_wishbone_slave_in;
      wb_o : out t_wishbone_slave_out);
  end component;

  signal wb_in  : t_wishbone_slave_in;
  signal wb_out : t_wishbone_slave_out;

begin

  U_XHWIU : xwrsw_hwiu
    generic map (
      g_interface_mode      => PIPELINED,
      g_address_granularity => WORD,
      g_ndbg_regs           => g_ndbg_regs,
      g_ver_major           => g_ver_major,
      g_ver_minor           => g_ver_minor,
      g_build               => g_build)
    port map(
      rst_n_i => rst_n_i,
      clk_i   => clk_i,

      dbg_regs_i    => dbg_regs_i,
      dbg_chps_id_o => dbg_chps_id_o,

      wb_i => wb_in,
      wb_o => wb_out
    );

  wb_in.adr(1 downto 0)           <= wb_adr_i;
  wb_in.adr(31 downto 2) <= (others => '0');
  wb_in.dat              <= wb_dat_i;
  wb_in.cyc              <= wb_cyc_i;
  wb_in.stb              <= wb_stb_i;
  wb_in.sel              <= wb_sel_i;
  wb_in.we               <= wb_we_i;
  wb_dat_o               <= wb_out.dat;
  wb_ack_o               <= wb_out.ack;
  wb_stall_o             <= wb_out.stall;
  wb_int_o               <= wb_out.int;

end behav;
