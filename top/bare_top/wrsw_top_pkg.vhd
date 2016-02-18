-------------------------------------------------------------------------------
-- Title      : WR Switch top level package
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_top_pkg.vhd
-- Author     : Tomasz Wlostowski, Maciej Lipinski, Grzegorz Daniluk
-- Company    : CERN BE-CO-HT
-- Created    : 2012-02-21
-- Last update: 2014-02-14
-- Platform   : FPGA-generic
-- Standard   : VHDL
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
use ieee.STD_LOGIC_1164.all;

use work.wr_fabric_pkg.all;
use work.wishbone_pkg.all;
use work.wrsw_txtsu_pkg.all;
use work.wrsw_shared_types_pkg.all;
use work.endpoint_pkg.all;

package wrsw_top_pkg is

  -- Output from SCB core to PHY
  type t_phyif_output is record
    rst     : std_logic;
    loopen  : std_logic;
    enable  : std_logic;
    syncen  : std_logic;
    tx_data : std_logic_vector(15 downto 0);
    tx_k    : std_logic_vector(1 downto 0);
  end record;

  type t_phyif_input is record
    ref_clk      : std_logic;
    tx_disparity : std_logic;
    tx_enc_err   : std_logic;
    rx_data      : std_logic_vector(15 downto 0);
    rx_clk       : std_logic;
    rx_k         : std_logic_vector(1 downto 0);
    rx_enc_err   : std_logic;
    rx_bitslide  : std_logic_vector(4 downto 0);
  end record;

  type t_phyif_output_array is array(integer range <>) of t_phyif_output;
  type t_phyif_input_array is array(integer range <>) of t_phyif_input;

  component wb_cpu_bridge
    generic (
      g_simulation          : integer := 0;
      g_cpu_addr_width      : integer := 19;
      g_wishbone_addr_width : integer := 19);

    port(
      sys_rst_n_i : in std_logic;       -- global reset

      -- Atmel EBI bus
      cpu_clk_i   : in    std_logic;    -- clock (not used now)
      -- async chip select, active LOW
      cpu_cs_n_i  : in    std_logic;
      -- async write, active LOW
      cpu_wr_n_i  : in    std_logic;
      -- async read, active LOW
      cpu_rd_n_i  : in    std_logic;
      -- byte select, active  LOW (not used due to weird CPU pin layout - NBS2 line is
      -- shared with 100 Mbps Ethernet PHY)
      cpu_bs_n_i  : in    std_logic_vector(3 downto 0);
      -- address input
      cpu_addr_i  : in    std_logic_vector(g_cpu_addr_width-1 downto 0);
      -- data bus (bidirectional)
      cpu_data_b  : inout std_logic_vector(31 downto 0);
      -- async wait, active LOW
      cpu_nwait_o : out   std_logic;

      -- Wishbone master I/F 
      -- wishbone clock input (refclk/2)
      wb_clk_i  : in  std_logic;
      -- wishbone master address output (m->s, common for all slaves)
      wb_addr_o : out std_logic_vector(g_wishbone_addr_width - 1 downto 0);
      -- wishbone master data output (m->s, common for all slaves)
      wb_data_o : out std_logic_vector(31 downto 0);
      -- wishbone cycle strobe (m->s, common for all slaves)
      wb_stb_o  : out std_logic;
      -- wishbone write enable (m->s, common for all slaves)
      wb_we_o   : out std_logic;
      -- wishbone byte select output (m->s, common for all slaves)
      wb_sel_o  : out std_logic_vector(3 downto 0);
      -- wishbone cycle select (m->s, individual)
      wb_cyc_o  : out std_logic;
      wb_data_i : in  std_logic_vector(31 downto 0);
      wb_ack_i  : in  std_logic
      );
  end component;

  component wr_gtx_phy_virtex6
    generic (
      g_simulation         : integer;
      g_use_slave_tx_clock : integer;
      g_use_bufr           : boolean := false);
    port (
      clk_ref_i      : in  std_logic;
      clk_gtx_i      : in  std_logic;
      tx_data_i      : in  std_logic_vector(15 downto 0);
      tx_k_i         : in  std_logic_vector(1 downto 0);
      tx_disparity_o : out std_logic;
      tx_enc_err_o   : out std_logic;
      rx_rbclk_o     : out std_logic;
      rx_data_o      : out std_logic_vector(15 downto 0);
      rx_k_o         : out std_logic_vector(1 downto 0);
      rx_enc_err_o   : out std_logic;
      rx_bitslide_o  : out std_logic_vector(4 downto 0);
      rst_i          : in  std_logic;
      loopen_i       : in  std_logic;
      pad_txn_o      : out std_logic;
      pad_txp_o      : out std_logic;
      pad_rxn_i      : in  std_logic := '0';
      pad_rxp_i      : in  std_logic := '0');
  end component;

  component xwr_pps_gen
    generic (
      g_interface_mode      : t_wishbone_interface_mode;
      g_address_granularity : t_wishbone_address_granularity;
      g_ref_clock_rate      : integer);
    port (
      clk_ref_i       : in  std_logic;
      clk_sys_i       : in  std_logic;
      rst_n_i         : in  std_logic;
      slave_i         : in  t_wishbone_slave_in;
      slave_o         : out t_wishbone_slave_out;
      pps_in_i        : in  std_logic;
      pps_csync_o     : out std_logic;
      pps_out_o       : out std_logic;
      tm_utc_o        : out std_logic_vector(39 downto 0);
      tm_cycles_o     : out std_logic_vector(27 downto 0);
      tm_time_valid_o : out std_logic);
  end component;

  component xwrsw_tx_tsu
    generic (
      g_num_ports           : integer;
      g_interface_mode      : t_wishbone_interface_mode;
      g_address_granularity : t_wishbone_address_granularity);
    port (
      clk_sys_i        : in  std_logic;
      rst_n_i          : in  std_logic;
      timestamps_i     : in  t_txtsu_timestamp_array(g_num_ports-1 downto 0);
      timestamps_ack_o : out std_logic_vector(g_num_ports -1 downto 0);
      wb_i             : in  t_wishbone_slave_in;
      wb_o             : out t_wishbone_slave_out);
  end component;

  component xwrsw_nic
    generic (
      g_interface_mode      : t_wishbone_interface_mode;
      g_address_granularity : t_wishbone_address_granularity;
      g_src_cyc_on_stall    : boolean := false;
      g_port_mask_bits      : integer := 32; --should be num_ports+1
      g_rx_untagging        : boolean := false);
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


  component wrsw_rt_subsystem
    generic (
      g_num_rx_clocks : integer;
      g_simulation : boolean);
    port (
      clk_ref_i           : in  std_logic;
      clk_sys_i           : in  std_logic;
      clk_dmtd_i          : in  std_logic;
      clk_rx_i            : in  std_logic_vector(g_num_rx_clocks-1 downto 0);
      clk_ext_i           : in  std_logic;
      clk_ext_mul_i       : in  std_logic;
      rst_n_i             : in  std_logic;
      rst_n_o             : out std_logic;
      wb_i                : in  t_wishbone_slave_in;
      wb_o                : out t_wishbone_slave_out;
      dac_helper_sync_n_o : out std_logic;
      dac_helper_sclk_o   : out std_logic;
      dac_helper_data_o   : out std_logic;
      dac_main_sync_n_o   : out std_logic;
      dac_main_sclk_o     : out std_logic;
      dac_main_data_o     : out std_logic;
      uart_txd_o          : out std_logic;
      uart_rxd_i          : in  std_logic;
      pps_csync_o         : out std_logic;
      pps_valid_o         : out std_logic;
      pps_ext_i           : in  std_logic;
      pps_ext_o           : out std_logic;
      sel_clk_sys_o       : out std_logic;
      tm_utc_o            : out std_logic_vector(39 downto 0);
      tm_cycles_o         : out std_logic_vector(27 downto 0);
      tm_time_valid_o     : out std_logic;
      pll_status_i        : in  std_logic;
      pll_mosi_o          : out std_logic;
      pll_miso_i          : in  std_logic;
      pll_sck_o           : out std_logic;
      pll_cs_n_o          : out std_logic;
      pll_sync_n_o        : out std_logic;
      pll_reset_n_o       : out std_logic;
      clk_rx_status_i     : in  std_logic_vector(g_num_rx_clocks-1 downto 0) :=(others=>'0'); 
      selected_ref_clk_o  : out  std_logic_vector(g_num_rx_clocks-1 downto 0);
      holdover_on_o       : out  std_logic;
      rx_holdover_msg_i   : in std_logic;
      rx_holdover_clr_o   : out std_logic;
      spll_dbg_o          : out std_logic_vector(5 downto 0));
  end component;
  
  component chipscope_icon
    port (
      CONTROL0 : inout std_logic_vector(35 downto 0));
  end component;

  signal Control0 : std_logic_vector(35 downto 0);

  component chipscope_ila
    port (
      CONTROL : inout std_logic_vector(35 downto 0);
      CLK     : in    std_logic;
      TRIG0   : in    std_logic_vector(31 downto 0);
      TRIG1   : in    std_logic_vector(31 downto 0);
      TRIG2   : in    std_logic_vector(31 downto 0);
      TRIG3   : in    std_logic_vector(31 downto 0));
  end component;

  component scb_top_bare
    generic (
      g_num_ports       : integer;
      g_simulation      : boolean;
      g_without_network : boolean;
      g_with_TRU        : boolean  := false;
      g_with_TATSU      : boolean  := false;
      g_with_HWIU       : boolean  := false;
      g_with_PSTATS     : boolean := true;
      g_with_muxed_CS   : boolean := false;
      g_with_PSU        : boolean := false;
      g_inj_per_EP      : std_logic_vector(17 downto 0) := (others=>'0'));
    port (
      sys_rst_n_i         : in  std_logic;
      clk_startup_i       : in  std_logic;
      clk_ref_i           : in  std_logic;
      clk_dmtd_i          : in  std_logic;
      clk_aux_i           : in  std_logic;
      clk_sys_o           : out std_logic;
      cpu_wb_i            : in  t_wishbone_slave_in;
      cpu_wb_o            : out t_wishbone_slave_out;
      cpu_irq_n_o         : out std_logic;
      pps_i               : in  std_logic;
      pps_o               : out std_logic;
      dac_helper_sync_n_o : out std_logic;
      dac_helper_sclk_o   : out std_logic;
      dac_helper_data_o   : out std_logic;
      dac_main_sync_n_o   : out std_logic;
      dac_main_sclk_o     : out std_logic;
      dac_main_data_o     : out std_logic;
      pll_status_i        : in  std_logic;
      pll_mosi_o          : out std_logic;
      pll_miso_i          : in  std_logic;
      pll_sck_o           : out std_logic;
      pll_cs_n_o          : out std_logic;
      pll_sync_n_o        : out std_logic;
      pll_reset_n_o       : out std_logic;
      uart_txd_o          : out std_logic;
      uart_rxd_i          : in  std_logic;
      clk_en_o            : out std_logic;
      clk_sel_o           : out std_logic;
      phys_o              : out t_phyif_output_array(g_num_ports-1 downto 0);
      phys_i              : in  t_phyif_input_array(g_num_ports-1 downto 0);
      led_link_o          : out std_logic_vector(g_num_ports-1 downto 0);
      led_act_o           : out std_logic_vector(g_num_ports-1 downto 0);
      gpio_o              : out std_logic_vector(31 downto 0);
      gpio_i              : in  std_logic_vector(31 downto 0);
      i2c_scl_oen_o   : out std_logic_vector(2 downto 0);
      i2c_scl_o       : out std_logic_vector(2 downto 0);
      i2c_scl_i       : in  std_logic_vector(2 downto 0) := "111";
      i2c_sda_oen_o   : out std_logic_vector(2 downto 0);
      i2c_sda_o       : out std_logic_vector(2 downto 0);
      i2c_sda_i       : in  std_logic_vector(2 downto 0) := "111");
  end component;
  component xswc_core is
    generic( 
      g_prio_num                         : integer ;--:= c_swc_output_prio_num; [works only for value of 8, output_block-causes problem]
      g_output_queue_num                 : integer ;
      g_max_pck_size                     : integer ;-- in 16bits words --:= c_swc_max_pck_size
      g_max_oob_size                     : integer ;
      g_num_ports                        : integer ;--:= c_swc_num_ports
      g_pck_pg_free_fifo_size            : integer ; --:= c_swc_freeing_fifo_size (in pck_pg_free_module.vhd)
      g_input_block_cannot_accept_data   : string  ;--:= "drop_pck"; --"stall_o", "rty_o" -- (xswc_input_block) Don't CHANGE !
      g_output_block_per_queue_fifo_size  : integer ; --:= c_swc_output_fifo_size    (xswc_output_block)
      g_wb_data_width                    : integer ;
      g_wb_addr_width                    : integer ;
      g_wb_sel_width                     : integer ;
      g_wb_ob_ignore_ack                 : boolean := true ;
      g_mpm_mem_size                     : integer ; -- in 16bits words 
      g_mpm_page_size                    : integer ; -- in 16bits words 
      g_mpm_ratio                        : integer ;
      g_mpm_fifo_size                    : integer ;
      g_mpm_fetch_next_pg_in_advance     : boolean ;
      g_drop_outqueue_head_on_full       : boolean ;
      g_num_global_pause                 : integer ;
      g_num_dbg_vector_width             : integer := 8
    );
   port (
      clk_i          : in std_logic;
      clk_mpm_core_i : in std_logic;
      rst_n_i        : in std_logic;
  
      snk_i          : in  t_wrf_sink_in_array(g_num_ports-1 downto 0);
      snk_o          : out t_wrf_sink_out_array(g_num_ports-1 downto 0);
  
      src_i          : in  t_wrf_source_in_array(g_num_ports-1 downto 0);
      src_o          : out t_wrf_source_out_array(g_num_ports-1 downto 0);
      
      global_pause_i            : in  t_global_pause_request_array(g_num_global_pause-1 downto 0);
      perport_pause_i           : in  t_pause_request_array(g_num_ports-1 downto 0);      
      shaper_drop_at_hp_ena_i   : in  std_logic := '0';
      dbg_o                      : out std_logic_vector(g_num_dbg_vector_width - 1 downto 0);
      rtu_rsp_i      : in t_rtu_response_array(g_num_ports  - 1 downto 0);
      rtu_ack_o      : out std_logic_vector(g_num_ports  - 1 downto 0);
      rtu_abort_o    : out std_logic_vector(g_num_ports  - 1 downto 0)
      );
  end component;

  component xwrsw_rtu
    generic (
      g_interface_mode      : t_wishbone_interface_mode;
      g_address_granularity : t_wishbone_address_granularity;
      g_handle_only_single_req_per_port : boolean := FALSE;
      g_prio_num            : integer;
      g_num_ports           : integer;
      g_port_mask_bits      : integer);
    port (
      clk_sys_i  : in  std_logic;
      rst_n_i    : in  std_logic;
      req_i      : in  t_rtu_request_array(g_num_ports-1 downto 0);
      req_full_o : out std_logic_vector(g_num_ports-1 downto 0);
      rsp_o      : out t_rtu_response_array(g_num_ports-1 downto 0);
      rsp_ack_i  : in  std_logic_vector(g_num_ports-1 downto 0);
      tru_req_o  : out  t_tru_request;
      tru_resp_i : in   t_tru_response;      
      rtu2tru_o  : out  t_rtu2tru;
      tru_enabled_i: in std_logic;
      wb_i       : in  t_wishbone_slave_in;
      wb_o       : out t_wishbone_slave_out);
  end component;
  component xwrsw_rtu_new
    generic (
      g_interface_mode                  : t_wishbone_interface_mode      := PIPELINED;
      g_address_granularity             : t_wishbone_address_granularity := BYTE;
      g_handle_only_single_req_per_port : boolean                        := FALSE;
      g_prio_num                        : integer;
      g_num_ports                       : integer;
      g_cpu_port_num                    : integer := -1;
      g_match_req_fifo_size             : integer := 32;        
      g_port_mask_bits                  : integer;
      g_rmon_events_bits_pp             : integer := 8);
    port (
      clk_sys_i   : in std_logic;
      rst_n_i     : in std_logic;
      req_i       : in  t_rtu_request_array(g_num_ports-1 downto 0);
      req_full_o  : out std_logic_vector(g_num_ports-1 downto 0);
      rsp_o       : out t_rtu_response_array(g_num_ports-1 downto 0);
      rsp_ack_i   : in  std_logic_vector(g_num_ports-1 downto 0);
      rq_abort_i : in  std_logic_vector(g_num_ports-1 downto 0);
      rsp_abort_i  : in  std_logic_vector(g_num_ports-1 downto 0);
      tru_req_o   : out  t_tru_request;
      tru_resp_i  : in   t_tru_response;  
      rtu2tru_o   : out  t_rtu2tru;
      tru_enabled_i: in std_logic;
      rmon_events_o : out std_logic_vector(g_num_ports*g_rmon_events_bits_pp-1 downto 0);
      wb_i        : in  t_wishbone_slave_in;
      wb_o        : out t_wishbone_slave_out
      );
  end component; 
   
  component pll200MhZ is
    port
    (-- Clock in ports (62.5MhZ)
     CLK_IN1           : in     std_logic;
     -- Clock out ports (200MhZ)
     CLK_OUT1          : out    std_logic
    );
    end component;

  component xwrsw_pstats
    generic(
      g_interface_mode      : t_wishbone_interface_mode      := PIPELINED;
      g_address_granularity : t_wishbone_address_granularity := BYTE;
      g_nports : integer := 2;
      g_cnt_pp : integer := 16;
      g_cnt_pw : integer := 4);
    port(
      rst_n_i : in std_logic;
      clk_i   : in std_logic;
  
      events_i : in std_logic_vector(g_nports*g_cnt_pp-1 downto 0);
  
      wb_i : in  t_wishbone_slave_in;
      wb_o : out t_wishbone_slave_out );
  end component;

  component xwrsw_hwdu
    generic (
      g_interface_mode      : t_wishbone_interface_mode      := PIPELINED;
      g_address_granularity : t_wishbone_address_granularity := BYTE;
      g_nregs   : integer := 1;
      g_rwidth  : integer := 32);
    port(
      rst_n_i : in std_logic;
      clk_i   : in std_logic;
  
      dbg_regs_i  : in std_logic_vector(g_nregs*g_rwidth-1 downto 0);
      dbg_chps_id_o : out std_logic_vector(7 downto 0);

      wb_i : in  t_wishbone_slave_in;
      wb_o : out t_wishbone_slave_out);
  end component;

  --TEMP
  component dummy_rmon
    generic(
      g_interface_mode      : t_wishbone_interface_mode      := PIPELINED;
      g_address_granularity : t_wishbone_address_granularity := BYTE;
      g_nports  : integer := 8;
      g_cnt_pp  : integer := 2);
    port(
      rst_n_i : in std_logic;
      clk_i   : in std_logic;
      events_i  : in std_logic_vector(g_nports*g_cnt_pp-1 downto 0);
  
      wb_i : in  t_wishbone_slave_in;
      wb_o : out t_wishbone_slave_out);
  end component;

  component xwrsw_psu
    generic(
      g_port_number   : integer := 18;
      g_port_mask_bits: integer := 32);
    port (
      clk_sys_i : in std_logic;
      rst_n_i   : in std_logic;
      tx_snk_i : in  t_wrf_sink_in;
      tx_snk_o : out t_wrf_sink_out;
      tx_rtu_dst_port_mask_i :  in std_logic_vector(g_port_mask_bits-1 downto 0);
      tx_rtu_prio_i          :  in std_logic_vector(2 downto 0);
      tx_rtu_drop_i          :  in std_logic;
      tx_rtu_rsp_valid_i     :  in std_logic;
      tx_rtu_rsp_ack_o       : out std_logic;
      rx_src_i : in  t_wrf_source_in;
      rx_src_o : out t_wrf_source_out;
      tx_src_i : in  t_wrf_source_in;
      tx_src_o : out t_wrf_source_out;
      tx_rtu_dst_port_mask_o : out std_logic_vector(g_port_mask_bits-1 downto 0);
      tx_rtu_prio_o          : out std_logic_vector(2 downto 0);
      tx_rtu_drop_o          : out std_logic;
      tx_rtu_rsp_valid_o     : out std_logic;
      tx_rtu_rsp_ack_i       : in  std_logic;
      rx_snk_i : in  t_wrf_sink_in;
      rx_snk_o : out t_wrf_sink_out;
      selected_ref_clk_i  : in  std_logic_vector(g_port_number-1 downto 0); 
      holdover_on_i       : in  std_logic;
      rx_holdover_msg_o   : out  std_logic;
      rx_holdover_clr_i   : in std_logic;
      wb_i                : in  t_wishbone_slave_in;
      wb_o                : out t_wishbone_slave_out);
  end component;
  
  component xwrsw_hsr_lre
    generic(
		g_adr_width : integer := 2;
		g_dat_width : integer :=16;
		g_num_ports : integer);
    port (
		rst_n_i : in  std_logic;
		clk_i   : in  std_logic;

		ep_snk_i : in  t_wrf_sink_in_array(g_num_ports-1 downto 0);
		ep_snk_o : out t_wrf_sink_out_array(g_num_ports-1 downto 0);
		ep_src_i : in  t_wrf_source_in_array(g_num_ports-1 downto 0);
		ep_src_o : out t_wrf_source_out_array(g_num_ports-1 downto 0);
		swc_snk_i : in  t_wrf_sink_in_array(g_num_ports-1 downto 0);
		swc_snk_o : out t_wrf_sink_out_array(g_num_ports-1 downto 0);
		swc_src_i : in  t_wrf_source_in_array(g_num_ports-1 downto 0);
		swc_src_o : out t_wrf_source_out_array(g_num_ports-1 downto 0));
  end component;

end wrsw_top_pkg;
