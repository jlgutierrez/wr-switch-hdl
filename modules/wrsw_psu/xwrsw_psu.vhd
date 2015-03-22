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

use work.wr_fabric_pkg.all;
use work.genram_pkg.all;
use work.wishbone_pkg.all;
use work.psu_wbgen2_pkg.all;
use work.psu_pkg.all;

entity xwrsw_psu is
  generic(
    g_port_number   : integer := 18;
    g_port_mask_bits: integer := 32;
    g_interface_mode     : t_wishbone_interface_mode      := PIPELINED;
    g_address_granularity: t_wishbone_address_granularity := BYTE);
  port (
    clk_sys_i : in std_logic;
    rst_n_i   : in std_logic;

    -- interface with NIC: tx path
    tx_snk_i : in  t_wrf_sink_in;
    tx_snk_o : out t_wrf_sink_out;
    tx_rtu_dst_port_mask_i :  in std_logic_vector(g_port_mask_bits-1 downto 0);
    tx_rtu_prio_i          :  in std_logic_vector(2 downto 0);
    tx_rtu_drop_i          :  in std_logic;
    tx_rtu_rsp_valid_i     :  in std_logic;
    tx_rtu_rsp_ack_o       : out std_logic;

    -- interface with NIC: rx path
    rx_src_i : in  t_wrf_source_in;
    rx_src_o : out t_wrf_source_out;

    -- interface with RTU/SWcore: tx path
    tx_src_i : in  t_wrf_source_in;
    tx_src_o : out t_wrf_source_out;
    tx_rtu_dst_port_mask_o : out std_logic_vector(g_port_mask_bits-1 downto 0);
    tx_rtu_prio_o          : out std_logic_vector(2 downto 0);
    tx_rtu_drop_o          : out std_logic;
    tx_rtu_rsp_valid_o     : out std_logic;
    tx_rtu_rsp_ack_i       : in  std_logic;

    -- interface with SWcore: rx path
    rx_snk_i : in  t_wrf_sink_in;
    rx_snk_o : out t_wrf_sink_out;

    -- communciation with rt_subsystem
    selected_ref_clk_i  : in  std_logic_vector(g_port_number-1 downto 0); 
    holdover_on_i       : in  std_logic;
    rx_holdover_msg_o   : out  std_logic;
    -- config via WB
    wb_i                : in  t_wishbone_slave_in;
    wb_o                : out t_wishbone_slave_out

    );

end xwrsw_psu;

architecture behavioral of xwrsw_psu is

    signal wb_in                  : t_wishbone_slave_in;
    signal wb_out                 : t_wishbone_slave_out;
    signal s_regs_towb            : t_psu_in_registers;
    signal s_regs_fromwb          : t_psu_out_registers;

    signal tx_detected_mask       : std_logic_vector(g_port_number-1 downto 0);
    signal rx_detected_mask       : std_logic_vector(g_port_number-1 downto 0);

    signal tx_snoop_ports_mask       : std_logic_vector(g_port_number-1 downto 0);
    signal rx_snoop_ports_mask       : std_logic_vector(g_port_number-1 downto 0);

    signal tx_wr_ram_addr         : std_logic_vector( 9 downto 0);
    signal tx_wr_ram_data         : std_logic_vector(17 downto 0);
    signal tx_wr_ram_ena          : std_logic;
    signal tx_rd_ram_addr         : std_logic_vector( 9 downto 0);
    signal tx_rd_ram_data         : std_logic_vector(17 downto 0);
    signal tx_snoop_ram_addr      : std_logic_vector( 9 downto 0);
    signal tx_snoop_ram_data      : std_logic_vector(17 downto 0);
    signal tx_snp_ram_data        : std_logic_vector(17 downto 0);
    signal tx_rd_ram_sel          : std_logic;

    signal rx_wr_ram_addr         : std_logic_vector( 9 downto 0);
    signal rx_wr_ram_data         : std_logic_vector(17 downto 0);
    signal rx_wr_ram_ena          : std_logic;
    signal rx_rd_ram_addr         : std_logic_vector( 9 downto 0);
    signal rx_rd_ram_data         : std_logic_vector(17 downto 0);

    signal tx_inj_ram_addr        : std_logic_vector(9 downto 0);
    signal tx_inj_ram_read        : std_logic;

    signal tx_src_in              : t_wrf_source_in;
    signal tx_src_out             : t_wrf_source_out;
    
    signal inject_req             : std_logic;
    signal inject_ready           : std_logic;
    signal inject_port_mask       : std_logic_vector(g_port_number-1 downto 0);

    signal holdover_on            : std_logic;
    signal tx_rtu_dst_port_mask   : std_logic_vector(g_port_number-1 downto 0);
begin

  U_TX_CTRL: psu_tx_ctrl
    generic map(
      g_port_number         => g_port_number)
    port map(
      clk_sys_i             => clk_sys_i,
      rst_n_i               => rst_n_i,
      inject_req_o          => inject_req,
      inject_ready_i        => inject_ready,
      inject_port_mask_o    => inject_port_mask,
      tx_port_mask_i        => tx_snoop_ports_mask,
      tx_ann_detect_mask_i  => tx_detected_mask,
      holdover_on_i         => holdover_on
    );

  holdover_on <= '1' when( s_regs_fromwb.ptd_dbg_holdover_on_o = '1' or holdover_on_i ='1') else 
                 '0' ;
  -- disable when dumping RAM
  tx_snoop_ports_mask <=   (others => '0') when (s_regs_fromwb.ptd_tx_ram_rd_ena_o= '1') else
                           s_regs_fromwb.txpm_port_mask_o(g_port_number-1 downto 0);

  U_TX_SNOOPER: psu_announce_snooper
    generic map(
      g_port_number         => g_port_number,
      g_snoop_mode          => TX_SEQ_ID_MODE)
    port map(
      clk_sys_i             => clk_sys_i,
      rst_n_i               => rst_n_i,
      snk_i                 => tx_src_out,
      snk_o                 => tx_src_in,

      src_i                 => tx_src_i,
      src_o                 => tx_src_o,

      rtu_dst_port_mask_i   => tx_rtu_dst_port_mask,
      snoop_ports_mask_i    => tx_snoop_ports_mask,
      holdover_on_i         => holdover_on, -- todo : need internal signal
      holdover_clk_class_i  => s_regs_fromwb.pcr_holdover_clk_class_o, 

      detected_announce_o   => open,
      srcdst_port_mask_o    => tx_detected_mask,
      sourcePortID_match_o  => open,
      clockClass_match_o    => open,
      announce_duplicate_o  => open,
      sequenceID_wrong_o    => open,
      wr_ram_ena_o          => tx_wr_ram_ena,
      wr_ram_data_o         => tx_wr_ram_data,
      wr_ram_addr_o         => tx_wr_ram_addr,
      wr_ram_sel_o          => open,
      rd_ram_data_i         => tx_snoop_ram_data,
      rd_ram_addr_o         => tx_snoop_ram_addr,
      rd_ram_sel_o          => open);

  U_TX_INJECTOR: psu_packet_injection
    generic map (
      g_port_number        => g_port_number
    )
    port map(
      clk_sys_i             => clk_sys_i,
      rst_n_i               => rst_n_i,
      src_i                 => tx_src_in,
      src_o                 => tx_src_out,
      snk_i                 => tx_snk_i,
      snk_o                 => tx_snk_o,

      rtu_dst_port_mask_o   => tx_rtu_dst_port_mask,
      rtu_prio_o            => tx_rtu_prio_o,
      rtu_drop_o            => tx_rtu_drop_o,
      rtu_rsp_valid_o       => tx_rtu_rsp_valid_o,
      rtu_rsp_ack_i         => tx_rtu_rsp_ack_i,

      rtu_dst_port_mask_i   => tx_rtu_dst_port_mask_i(g_port_number-1 downto 0),
      rtu_prio_i            => tx_rtu_prio_i,
      rtu_drop_i            => tx_rtu_drop_i,
      rtu_rsp_valid_i       => tx_rtu_rsp_valid_i,
      rtu_rsp_ack_o         => tx_rtu_rsp_ack_o,

      inject_req_i          => inject_req,
      inject_ready_o        => inject_ready,
      inject_clockClass_i   => s_regs_fromwb.pcr_holdover_clk_class_o,
      inject_port_mask_i    => inject_port_mask,
      inject_pck_prio_i     => s_regs_fromwb.pcr_inj_prio_o,

      rd_ram_data_i         => tx_rd_ram_data);

      tx_rtu_dst_port_mask_o(g_port_number-1 downto 0)                <= tx_rtu_dst_port_mask;
      
      tx_rtu_dst_port_mask_o(g_port_mask_bits-1 downto g_port_number) <= 
      tx_rtu_dst_port_mask_i(g_port_mask_bits-1 downto g_port_number);

  U_TX_RAM : generic_dpram
    generic map (
      g_data_width          => 18,
      g_size                => 1024,
      g_dual_clock          => false)
    port map (
      rst_n_i               => rst_n_i,
      clka_i                => clk_sys_i,
      clkb_i                => '0',
      wea_i                 => '0',
      aa_i                  => tx_rd_ram_addr,
      qa_o                  => tx_rd_ram_data,
      web_i                 => tx_wr_ram_ena,
      ab_i                  => tx_wr_ram_addr,
      db_i                  => tx_wr_ram_data);

  tx_rd_ram_addr                  <= s_regs_fromwb.ptd_tx_ram_rd_adr_o when(s_regs_fromwb.ptd_tx_ram_rd_ena_o='1') else tx_snoop_ram_addr;
  tx_snoop_ram_data               <= tx_rd_ram_data;
  s_regs_towb.ptd_tx_ram_rd_dat_i <= tx_rd_ram_data;

  rx_snoop_ports_mask  <= s_regs_fromwb.rxpm_port_mask_o(g_port_number-1 downto 0); -- and selected_ref_clk_i;

  U_RX_SNOOPER: psu_announce_snooper
    generic map(
      g_port_number         => g_port_number,
      g_snoop_mode          => RX_CLOCK_CLASS_MODE)
    port map(
      clk_sys_i             => clk_sys_i,
      rst_n_i               => rst_n_i,

      snk_i                 => rx_snk_i,
      snk_o                 => rx_snk_o,

      src_i                 => rx_src_i,
      src_o                 => rx_src_o,

      rtu_dst_port_mask_i   => (others => '0'),
      snoop_ports_mask_i    => rx_snoop_ports_mask,
      holdover_on_i         => holdover_on, -- TODO
      holdover_clk_class_i  => s_regs_fromwb.pcr_holdover_clk_class_o,
      detected_announce_o   => open,
      srcdst_port_mask_o    => open,
      sourcePortID_match_o  => open,
      clockClass_match_o    => open,
      announce_duplicate_o  => open,
      sequenceID_wrong_o    => open,
      wr_ram_ena_o          => rx_wr_ram_ena,
      wr_ram_data_o         => rx_wr_ram_data,
      wr_ram_addr_o         => rx_wr_ram_addr,
      wr_ram_sel_o          => open,
      rd_ram_data_i         => (others =>'0'),
      rd_ram_addr_o         => open,
      rd_ram_sel_o          => open);

  U_RX_RAM : generic_dpram
    generic map (
      g_data_width          => 18,
      g_size                => 1024,
      g_dual_clock          => false)
    port map (
      rst_n_i               => rst_n_i,
      clka_i                => clk_sys_i,
      clkb_i                => '0',
      wea_i                 => '0',
      aa_i                  => rx_rd_ram_addr,
      qa_o                  => rx_rd_ram_data,
      web_i                 => rx_wr_ram_ena,
      ab_i                  => rx_wr_ram_addr,
      db_i                  => rx_wr_ram_data);

  U_WB_ADAPTER : wb_slave_adapter
    generic map (
      g_master_use_struct  => true,
      g_master_mode        => CLASSIC,
      g_master_granularity => WORD,
      g_slave_use_struct   => true,
      g_slave_mode         => g_interface_mode,
      g_slave_granularity  => g_address_granularity)
    port map (
      clk_sys_i => clk_sys_i,
      rst_n_i   => rst_n_i,
      slave_i   => wb_i,
      slave_o   => wb_o,
      master_i  => wb_out,
      master_o  => wb_in);

  U_WB_CTRL:  psu_wishbone_controller
    port map(
      rst_n_i          => rst_n_i,
      clk_sys_i        => clk_sys_i,
      wb_adr_i         => wb_in.adr(1 downto 0),
      wb_dat_i         => wb_in.dat,
      wb_dat_o         => wb_out.dat,
      wb_cyc_i         => wb_in.cyc,
      wb_sel_i         => wb_in.sel,
      wb_stb_i         => wb_in.stb,
      wb_we_i          => wb_in.we,
      wb_ack_o         => wb_out.ack,
      wb_stall_o       => wb_out.stall,
      regs_i           => s_regs_towb,
      regs_o           => s_regs_fromwb
  );


end behavioral;

