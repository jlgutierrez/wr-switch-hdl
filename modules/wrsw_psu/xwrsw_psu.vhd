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
use work.genram_pkg.all;
use work.wishbone_pkg.all;

entity xwrsw_psu is
  generic(
    g_port_number   : integer := 18;
    g_port_mask_bits: integer := 32;
    g_interface_mode     : t_wishbone_interface_mode      := PIPELINED;
    g_address_granularity: t_wishbone_address_granularity := BYTE);
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

    signal wb_in                  : t_wishbone_slave_in;
    signal wb_out                 : t_wishbone_slave_out;
    signal s_regs_towb            : t_psu_in_registers;
    signal s_regs_fromwb          : t_psu_out_registers;

    signal tx_detected_mask       : std_logic_vector(g_port_number-1 downto 0);
    signal rx_detected_mask       : std_logic_vector(g_port_number-1 downto 0);


    signal tx_wr_ram_addr         : std_logic_vector( 9 downto 0);
    signal tx_wr_ram_data         : std_logic_vector(17 downto 0);
    signal tx_wr_ram_ena          : std_logic;
    signal tx_rd_ram_addr         : std_logic_vector( 9 downto 0);
    signal tx_rd_ram_data         : std_logic_vector(17 downto 0);
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

begin



  tx_snooper: psu_announce_snooper
    generic map(
      g_port_number         => g_port_number,
      g_snoop_mode          => TX_SEQ_ID_MODE)
    port map(
      clk_sys_i             => clk_sys_i,
      rst_n_i               => rst_n_i,
      snk_i                 => tx_src_out,
      snk_o                 => tx_src_in,
      
      src_i                 => tx_src_i,
      src_o                 => src_o,
      
      rtu_dst_port_mask_i   => rtu_dst_port_mask_i(g_port_number-1 downto 0),
      
      snoop_ports_mask_i    => s_regs_fromwb.txpm_port_mask_o(g_port_number-1 downto 0),
      clock_class_i         => s_regs_fromwb.pcr_holdover_clk_class_o, 
      detected_announce_o   => tx_detected_mask,
      srcdst_port_mask_o    => ,
      sourcePortID_match_o  => ,
      clockClass_match_o    => ,
      announce_duplicate_o  => ,
      sequenceID_wrong_o    => ,
      wr_ram_ena_o          => tx_wr_ram_ena,
      wr_ram_data_o         => tx_wr_ram_data,
      wr_ram_addr_o         => tx_wr_ram_addr,
      wr_ram_sel_o          => open,
      rd_ram_data_i         => tx_snp_ram_data,
      rd_ram_addr_o         => tx_rd_ram_addr,
      rd_ram_sel_o          => tx_rd_ram_sel);

  tx_rd_ram_addr <= tx_inj_ram_addr when (tx_inj_ram_read = '1') else tx_snp_ram_addr;

  tx_pck_injector: psu_packet_injection
    port map(
      clk_sys_i             => clk_sys_i,
      rst_n_i               => rst_n_i,
      src_i                 => tx_src_in,
      src_o                 => tx_src_out,
      snk_i                 => tx_snk_i,
      snk_o                 => tx_snk_o,
      inject_req_i          => ,
      inject_ready_o        => ,
      inject_packet_sel_i   => tx_rd_ram_sel,
      inject_clockClass_i   => ,
      inject_port_index_i   => 
      mem_addr_o            => tx_inj_ram_addr,
      mem_data_i            => tx_rd_ram_addr,
      mem_read_o            => tx_inj_ram_read);

  TX_RAM : generic_dpram
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
      snoop_ports_mask_i    => s_regs_fromwb.rxpm_port_mask_o(g_port_number-1 downto 0),
      clock_class_i         => s_regs_fromwb.pcr_holdover_clk_class_o,
      detected_announce_o   => rx_detected_mask,
      srcdst_port_mask_o    => ,
      sourcePortID_match_o  => ,
      clockClass_match_o    => ,
      announce_duplicate_o  => ,
      sequenceID_wrong_o    => ,
      wr_ram_ena_o          => rx_wr_ram_ena,
      wr_ram_data_o         => rx_wr_ram_data,
      wr_ram_addr_o         => rx_wr_ram_addr,
      wr_ram_sel_o          => open,
      rd_ram_data_i         => (others =>'0'),
      rd_ram_addr_o         => rx_rd_ram_data,
      rd_ram_sel_o          => rx_rd_ram_addr);

  RX_RAM : generic_dpram
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

    tx_src_o            <= tx_snk_i;
    tx_snk_o            <= tx_src_i;
    
    rx_snk_o            <= rx_src_i;
    rx_src_o            <= rx_snk_i;

    rtu_dst_port_mask_o <= rtu_dst_port_mask_i;
    rtu_prio_o          <= rtu_prio_i;
    rtu_drop_o          <= rtu_drop_i;
    rtu_rsp_valid_o     <= rtu_rsp_valid_i;
    rtu_rsp_ack_o       <= rtu_rsp_ack_i;

  U_WB_ADAPTER : wb_slave_adapter
    generic map (
      g_master_use_struct  => true,
      g_master_mode        => CLASSIC,
      g_master_granularity => WORD,
      g_slave_use_struct   => true,
      g_slave_mode         => g_interface_mode,
      g_slave_granularity  => g_address_granularity)
    port map (
      clk_sys_i => clk_i,
      rst_n_i   => rst_n_i,
      slave_i   => wb_i,
      slave_o   => wb_o,
      master_i  => wb_out,
      master_o  => wb_in);

  WB_CTRL:  psu_wishbone_controller
    port map(
      rst_n_i          <= rst_n_i,
      clk_sys_i        <= clk_sys_i,
      wb_adr_i         <= wb_in.adr(3 downto 0),
      wb_dat_i         <= wb_in.dat,
      wb_dat_o         <=  wb_out.dat,
      wb_cyc_i         <= wb_in.cyc,
      wb_sel_i         <= wb_in.sel,
      wb_stb_i         <= wb_in.stb,
      wb_we_i          <= wb_in.we,
      wb_ack_o         <= wb_out.ack,
      wb_stall_o       <= wb_out.stall,
      regs_i           <= s_regs_towb,
      regs_o           <= s_regs_fromwb
  );


end behavioral;

