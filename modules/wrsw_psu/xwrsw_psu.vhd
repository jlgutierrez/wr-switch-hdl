-------------------------------------------------------------------------------
-- Title      : PTP Support Unit
-- Project    : White Rabbit
-------------------------------------------------------------------------------
-- File       : xwrsw_psu.vhd
-- Author     : Maciej Lip0inski
-- Company    : CERN BE-CO-HT
-- Created    : 2015-03-17
-- Last update: 2015-03-17
-- Platform   : FPGA-generic
-- Standard   : VHDL'93
-------------------------------------------------------------------------------
-- Description: This unit supports ultra-fast tx and rx of Announce messages
-- with informatin about holdover
-------------------------------------------------------------------------------

-- Copyright (c) 2015 CERN / BE-CO-HT
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
-- FIXME:
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2015-03-17  1.0      mlipinsk	    Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.psu_pkg.all;
use work.wr_fabric_pkg.all;
use work.wishbone_pkg.all;

entity xwrsw_psu is
  generic(
    g_port_number   : integer := 18;
    g_port_mask_bits: integer := 32);
  port (
    clk_sys_i : in std_logic;
    rst_n_i   : in std_logic;

    -- interface with NIC
    tx_snk_i : in  t_wrf_sink_in;
    tx_snk_o : out t_wrf_sink_out;
    
    rx_src_i : in  t_wrf_source_in;
    rx_src_o : out t_wrf_source_out;

    rtu_dst_port_mask_i :  in std_logic_vector(g_port_mask_bits-1 downto 0);
    rtu_prio_i          :  in std_logic_vector(2 downto 0);
    rtu_drop_i          :  in std_logic;
    rtu_rsp_valid_i     :  in std_logic;
    rtu_rsp_ack_o       : out std_logic;

    -- interface with SWcore/RTU
    tx_src_i : in  t_wrf_source_in;
    tx_src_o : out t_wrf_source_out;

    rx_snk_i : in  t_wrf_sink_in;
    rx_snk_o : out t_wrf_sink_out;
    
    rtu_dst_port_mask_o : out std_logic_vector(g_port_mask_bits-1 downto 0);
    rtu_prio_o          : out std_logic_vector(2 downto 0);
    rtu_drop_o          : out std_logic;
    rtu_rsp_valid_o     : out std_logic;
    rtu_rsp_ack_i       : in  std_logic;

    -- communciation with rt_subsystem
    rx_announce_o       : out std_logic_vector(g_port_number-1 downto 0); 
    tx_announce_i       : in  std_logic;

    -- communication with SW (PPSi/wrsw_hal)
    wb_i                : in  t_wishbone_slave_in;
    wb_o                : out t_wishbone_slave_out

    );

end xwrsw_psu;

architecture behavioral of xwrsw_psu is

    signal tx_detected_mask       : std_logic_vector(g_port_number-1 downto 0);
    signal rx_detected_mask       : std_logic_vector(g_port_number-1 downto 0);
    signal tx_seq_id              : std_logic_vector(15 downto 0);
    signal tx_seq_id_valid        : std_logic;
    signal rx_clock_class         : std_logic_vector(15 downto 0);
    signal rx_clock_class_valid   : std_logic;
    signal rx_ram_addr            : std_logic_vector( 7 downto 0);
    signal tx_ram_addr            : std_logic_vector( 7 downto 0);
    signal rx_ram_data            : std_logic_vector(15 downto 0);
    signal tx_ram_data            : std_logic_vector(15 downto 0);
    
    signal mem_addr               : std_logic_vector(9 downto 0);
    signal mem_data               : std_logic_vector(17 downto 0)
begin

  tx_snooper: psu_announce_snooper
    generic map(
      g_port_number         => g_port_number,
      g_snoop_mode          => TX_SEQ_ID_MODE)
    port map(
      clk_sys_i             => clk_sys_i,
      rst_n_i               => rst_n_i,
      snk_i                 => tx_snk_i,
      src_i                 => tx_src_i,
      rtu_dst_port_mask_i   => rtu_dst_port_mask_i(g_port_number-1 downto 0),
      ptp_source_id_addr_o  => open,
      ptp_source_id_data_i  => (others => '0'),
      rxtx_detected_mask_o  => tx_detected_mask,
      seq_id_o              => tx_seq_id,
      seq_id_valid_o        => tx_seq_id_valid,
      clock_class_o         => open,
      clock_class_valid_o   => open,
      ignore_rx_port_id_i   => '1');

  rx_snooper: psu_announce_snooper
    generic map(
      g_port_number         => g_port_number,
      g_snoop_mode          => RX_CLOCK_CLASS_MODE)
    port map(
      clk_sys_i             => clk_sys_i,
      rst_n_i               => rst_n_i,
      snk_i                 => rx_snk_i,
      src_i                 => rx_src_i,
      rtu_dst_port_mask_i   => (others => '0'),
      ptp_source_id_addr_o  => rx_ram_addr,
      ptp_source_id_data_i  => rx_ram_data,
      rxtx_detected_mask_o  => rx_detected_mask,
      seq_id_o              => open,
      seq_id_valid_o        => open,
      clock_class_o         => rx_clock_class,
      clock_class_valid_o   => rx_clock_class_valid,
      ignore_rx_port_id_i   => '1');


  tx_pck_injector: psu_packet_injection
    port map(
      clk_sys_i             => clk_sys_i,
      rst_n_i               => rst_n_i,
      src_i                 => tx_src_i,
      src_o                 => tx_src_o,
      snk_i                 => tx_snk_i,
      snk_o                 => tx_snk_o,
      inject_req_i          => ,
      inject_ready_o        => ,
      inject_packet_sel_i   => ,
      inject_user_value_i   => ,
      inject_mode_i         => ,
      mem_addr_o            => mem_addr,
      mem_data_i            => mem_data);

  RXTX_RAM : generic_dpram
    generic map (
      g_data_width          => 18,
      g_size                => 512,
      g_dual_clock          => false)
    port map (
      rst_n_i               => rst_n_i,
      clka_i                => clk_sys_i,
      clkb_i                => '0',
      wea_i                 => '0',
      aa_i                  => mem_addr,
      qa_o                  => mem_data,
      web_i                 => ,
      ab_i                  => ,
      db_i                  => );


    tx_src_o            <= tx_snk_i;
    tx_snk_o            <= tx_src_i;
    
    rx_snk_o            <= rx_src_i;
    rx_src_o            <= rx_snk_i;

    rtu_dst_port_mask_o <= rtu_dst_port_mask_i;
    rtu_prio_o          <= rtu_prio_i;
    rtu_drop_o          <= rtu_drop_i;
    rtu_rsp_valid_o     <= rtu_rsp_valid_i;
    rtu_rsp_ack_o       <= rtu_rsp_ack_i;

end behavioral;

