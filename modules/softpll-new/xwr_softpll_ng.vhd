-------------------------------------------------------------------------------
-- Title      : White Rabbit Softcore PLL (new generation) - SoftPLL-ng
-- Project    : White Rabbit
-------------------------------------------------------------------------------
-- File       : xwr_softpll_ng.vhd
-- Author     : Tomasz Włostowski
-- Company    : CERN BE-CO-HT
-- Created    : 2011-01-29
-- Last update: 2012-03-26
-- Platform   : FPGA-generic
-- Standard   : VHDL'93
-------------------------------------------------------------------------------
-- Description: 
--
-- Struct'ized version of wr_softpll_ng.
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 CERN
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
use ieee.numeric_std.all;

use work.wishbone_pkg.all;

entity xwr_softpll_ng is
  generic(
-- Number of bits in phase tags produced by DDMTDs.
-- Must be large enough to cover at least a hundred of DDMTD periods to ensure
-- correct operation of the SoftPLL software servo algorithm - that
-- means, for a typical DMTD frequency offset N=16384, there number of tag bits
-- should be log2(N) + 7 == 21. Note: the value must match the TAG_BITS constant
-- in spll_defs.h file!
    g_tag_bits : integer;

-- These two are obvious:
    g_num_ref_inputs : integer := 1;
    g_num_outputs    : integer := 1;

-- When true, an additional period detector is provided, measuring the
-- frequency offset between the DDMTD clock and a chosen reference input clock.
-- The feature is not required by the current version of the SoftPLL servo
-- algorithm, but is kept for testing/debugging purposes.
    g_with_period_detector : boolean := false;

-- When true, an additional FIFO is instantiated, providing a realtime record
-- of user-selectable SoftPLL parameters (e.g. tag values, phase error, DAC drive).
-- These values can be read by "spll_dbg_proxy" daemon for further analysis.
    g_with_debug_fifo : boolean := false;

    g_interface_mode      : t_wishbone_interface_mode      := PIPELINED;
    g_address_granularity : t_wishbone_address_granularity := BYTE
    );

  port(
    clk_sys_i : in std_logic;
    rst_n_i   : in std_logic;


-- Reference inputs (i.e. the RX clocks recovered by the PHYs)
    clk_ref_i  : in std_logic_vector(g_num_ref_inputs-1 downto 0);
-- Feedback clocks (i.e. the outputs of the main or aux oscillator)
    clk_fb_i   : in std_logic_vector(g_num_outputs-1 downto 0);
-- DMTD Offset clock
    clk_dmtd_i : in std_logic;

-- DMTD oscillator drive
    dac_dmtd_data_o : out std_logic_vector(15 downto 0);
    dac_dmtd_load_o : out std_logic;

-- Output channel DAC value
    dac_out_data_o : out std_logic_vector(15 downto 0);
-- Output channel select (0 = channel 0, etc. )
    dac_out_sel_o  : out std_logic_vector(3 downto 0);
    dac_out_load_o : out std_logic;

    out_enable_i : in  std_logic_vector(g_num_outputs-1 downto 0);
    out_locked_o : out std_logic_vector(g_num_outputs-1 downto 0);

    slave_i : in  t_wishbone_slave_in;
    slave_o : out t_wishbone_slave_out;

    debug_o        : out std_logic_vector(3 downto 0);
    dbg_fifo_irq_o : out std_logic
    );

end xwr_softpll_ng;

architecture wrapper of xwr_softpll_ng is

  component wr_softpll_ng
    generic (
      g_tag_bits             : integer;
      g_num_ref_inputs       : integer;
      g_num_outputs          : integer;
      g_with_period_detector : boolean;
      g_with_debug_fifo      : boolean;
      g_interface_mode       : t_wishbone_interface_mode;
      g_address_granularity  : t_wishbone_address_granularity);
    port (
      clk_sys_i       : in  std_logic;
      rst_n_i         : in  std_logic;
      clk_ref_i       : in  std_logic_vector(g_num_ref_inputs-1 downto 0);
      clk_fb_i        : in  std_logic_vector(g_num_outputs-1 downto 0);
      clk_dmtd_i      : in  std_logic;
      dac_dmtd_data_o : out std_logic_vector(15 downto 0);
      dac_dmtd_load_o : out std_logic;
      dac_out_data_o  : out std_logic_vector(15 downto 0);
      dac_out_sel_o   : out std_logic_vector(3 downto 0);
      dac_out_load_o  : out std_logic;
      out_enable_i    : in  std_logic_vector(g_num_outputs-1 downto 0);
      out_locked_o    : out std_logic_vector(g_num_outputs-1 downto 0);
      wb_adr_i        : in  std_logic_vector(6 downto 0);
      wb_dat_i        : in  std_logic_vector(31 downto 0);
      wb_dat_o        : out std_logic_vector(31 downto 0);
      wb_cyc_i        : in  std_logic;
      wb_sel_i        : in  std_logic_vector(3 downto 0);
      wb_stb_i        : in  std_logic;
      wb_we_i         : in  std_logic;
      wb_ack_o        : out std_logic;
      wb_stall_o      : out std_logic;
      wb_irq_o        : out std_logic;
      debug_o         : out std_logic_vector(3 downto 0);
      dbg_fifo_irq_o  : out std_logic);
  end component;
  
begin  -- behavioral

  U_Wrapped_Softpll : wr_softpll_ng
    generic map (
      g_tag_bits             => g_tag_bits,
      g_interface_mode       => g_interface_mode,
      g_address_granularity  => g_address_granularity,
      g_num_ref_inputs       => g_num_ref_inputs,
      g_num_outputs          => g_num_outputs,
      g_with_debug_fifo      => g_with_debug_fifo,
      g_with_period_detector => g_with_period_detector)
    port map (
      clk_sys_i       => clk_sys_i,
      rst_n_i         => rst_n_i,
      clk_ref_i       => clk_ref_i,
      clk_fb_i        => clk_fb_i,
      clk_dmtd_i      => clk_dmtd_i,
      dac_dmtd_data_o => dac_dmtd_data_o,
      dac_dmtd_load_o => dac_dmtd_load_o,
      dac_out_data_o  => dac_out_data_o,
      dac_out_sel_o   => dac_out_sel_o,
      dac_out_load_o  => dac_out_load_o,
      out_enable_i    => out_enable_i,
      out_locked_o    => out_locked_o,
      wb_adr_i        => slave_i.adr(6 downto 0),
      wb_dat_i        => slave_i.dat,
      wb_dat_o        => slave_o.dat,
      wb_cyc_i        => slave_i.cyc,
      wb_sel_i        => slave_i.sel,
      wb_stb_i        => slave_i.stb,
      wb_we_i         => slave_i.we,
      wb_ack_o        => slave_o.ack,
      wb_stall_o      => slave_o.stall,
      wb_irq_o        => slave_o.int,
      debug_o         => debug_o,
      dbg_fifo_irq_o  => dbg_fifo_irq_o);

end wrapper;
