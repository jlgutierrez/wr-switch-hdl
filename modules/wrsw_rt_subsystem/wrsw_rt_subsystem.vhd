-------------------------------------------------------------------------------
-- Title      : WR Switch Real-Time Subsystem module
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_rt_subsystem.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-01-10
-- Last update: 2014-02-06
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description:
-- LM32 + SoftPLL + some memory + debug UART
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

use work.gencores_pkg.all;
use work.wishbone_pkg.all;


entity wrsw_rt_subsystem is
  
  generic (
    g_num_rx_clocks : integer;
    g_simulation    : boolean);

  port(
    clk_ref_i  : in std_logic;
    clk_sys_i  : in std_logic;
    clk_dmtd_i : in std_logic;
    clk_rx_i   : in std_logic_vector(g_num_rx_clocks-1 downto 0);
    clk_ext_i  : in std_logic;
		clk_ext_mul_i	:	in std_logic;

    rst_n_i : in  std_logic;
    rst_n_o : out std_logic;

    wb_i : in  t_wishbone_slave_in;
    wb_o : out t_wishbone_slave_out;

    ---------------------------------------------------------------------------
    -- PLL DAC Drive
    ---------------------------------------------------------------------------

    dac_helper_sync_n_o : out std_logic;
    dac_helper_sclk_o   : out std_logic;
    dac_helper_data_o   : out std_logic;

    dac_main_sync_n_o : out std_logic;
    dac_main_sclk_o   : out std_logic;
    dac_main_data_o   : out std_logic;

    -- Debug UART
    uart_txd_o : out std_logic;
    uart_rxd_i : in  std_logic;

    -------------------------------------------------------------------------------
    -- Time base signals
    -------------------------------------------------------------------------------    

    -- cleaned-up, retimed PPS for use in the rest of the switch
    pps_csync_o : out std_logic;

    -- PPS valid flag - when 1, pps_csync_o has produced at least two correctly
    -- aligned PPS resync pulses (so we can be sure that endpoint's individual
    -- TSCs are in sync with the master time counter and the timestamps are correct).
    pps_valid_o : out std_logic;

    pps_ext_i : in  std_logic;  -- external PPS input (from the front panel)
    pps_ext_o : out std_logic;  -- external PPS output (to the front panel)

    sel_clk_sys_o : out std_logic;      -- system clock selection: 0 = startup
                                        -- clock, 1 = PLL clock

    -- WR timebase
    tm_utc_o        : out std_logic_vector(39 downto 0);
    tm_cycles_o     : out std_logic_vector(27 downto 0);
    tm_time_valid_o : out std_logic;

    -- AD9516 signals
    pll_status_i  : in  std_logic;
    pll_mosi_o    : out std_logic;
    pll_miso_i    : in  std_logic;
    pll_sck_o     : out std_logic;
    pll_cs_n_o    : out std_logic;
    pll_sync_n_o  : out std_logic;
    pll_reset_n_o : out std_logic;

    -- Debug
    spll_dbg_o  : out std_logic_vector(5 downto 0)
    );
end wrsw_rt_subsystem;

architecture rtl of wrsw_rt_subsystem is

  component xwr_softpll_ng
    generic (
      g_tag_bits             : integer;
      g_num_ref_inputs       : integer;
      g_num_outputs          : integer;
      g_with_debug_fifo      : boolean;
      g_with_ext_clock_input : boolean;
      g_divide_input_by_2 	 : boolean;
      g_reverse_dmtds        : boolean;
    	g_ref_clock_rate			 : integer;
    	g_ext_clock_rate			 : integer;
      g_interface_mode       : t_wishbone_interface_mode;
      g_address_granularity  : t_wishbone_address_granularity);
    port (
      clk_sys_i       : in  std_logic;
      rst_n_i         : in  std_logic;
      clk_ref_i       : in  std_logic_vector(g_num_ref_inputs-1 downto 0);
      clk_fb_i        : in  std_logic_vector(g_num_outputs-1 downto 0);
      clk_dmtd_i      : in  std_logic;
      clk_ext_i       : in  std_logic;
    	clk_ext_mul_i		: in std_logic;
    	pps_csync_p1_i	: in std_logic;
    	pps_ext_a_i			: in std_logic;
      dac_dmtd_data_o : out std_logic_vector(15 downto 0);
      dac_dmtd_load_o : out std_logic;
      dac_out_data_o  : out std_logic_vector(15 downto 0);
      dac_out_sel_o   : out std_logic_vector(3 downto 0);
      dac_out_load_o  : out std_logic;
      out_enable_i    : in  std_logic_vector(g_num_outputs-1 downto 0);
      out_locked_o    : out std_logic_vector(g_num_outputs-1 downto 0);
    	out_status_o		: out std_logic_vector(4*g_num_outputs-1 downto 0);
      slave_i         : in  t_wishbone_slave_in;
      slave_o         : out t_wishbone_slave_out;
      debug_o         : out std_logic_vector(5 downto 0);
      dbg_fifo_irq_o  : out std_logic);
  end component;

  component xwr_pps_gen
    generic (
      g_interface_mode       : t_wishbone_interface_mode;
      g_address_granularity  : t_wishbone_address_granularity;
      g_ref_clock_rate       : integer;
      g_ext_clock_rate       : integer;
      g_with_ext_clock_input : boolean);
    port (
      clk_ref_i       : in  std_logic;
      clk_sys_i       : in  std_logic;
      clk_ext_i       : in  std_logic;
      rst_n_i         : in  std_logic;
      slave_i         : in  t_wishbone_slave_in;
      slave_o         : out t_wishbone_slave_out;
      pps_in_i        : in  std_logic;
      pps_csync_o     : out std_logic;
      pps_out_o       : out std_logic;
      pps_valid_o     : out std_logic;
      tm_utc_o        : out std_logic_vector(39 downto 0);
      tm_cycles_o     : out std_logic_vector(27 downto 0);
      tm_time_valid_o : out std_logic);
  end component;



-- interconnect layout:
-- 0x00000 - 0x10000: RAM
-- 0x10000 - 0x10100: UART
-- 0x10100 - 0x10200: SoftPLL
-- 0x10200 - 0x10300: SPI master (to PLL)
-- 0x10300 - 0x10400: GPIO
-- 0x10400 - 0x10500: Timer

  constant c_NUM_GPIO_PINS : integer := 4;
  constant c_NUM_WB_SLAVES : integer := 7;

  constant c_SLAVE_DPRAM   : integer := 0;
  constant c_SLAVE_UART    : integer := 1;
  constant c_SLAVE_SOFTPLL : integer := 2;
  constant c_SLAVE_SPI     : integer := 3;
  constant c_SLAVE_GPIO    : integer := 4;
  constant c_SLAVE_TIMER   : integer := 5;
  constant c_SLAVE_PPSGEN  : integer := 6;

  constant c_cnx_base_addr : t_wishbone_address_array(c_NUM_WB_SLAVES-1 downto 0) :=
    (x"00010500",
     x"00010400",
     x"00010300",
     x"00010200",
     x"00010100",
     x"00010000",
     x"00000000");

  constant c_cnx_base_mask : t_wishbone_address_array(c_NUM_WB_SLAVES-1 downto 0) :=
    (x"000fff00",
     x"000fff00",
     x"000fff00",
     x"000fff00",
     x"000fff00",
     x"000fff00",
     x"000f0000");


  signal cnx_slave_in   : t_wishbone_slave_in_array(1 downto 0);
  signal cnx_slave_out  : t_wishbone_slave_out_array(1 downto 0);
  signal cnx_master_in  : t_wishbone_master_in_array(c_NUM_WB_SLAVES-1 downto 0);
  signal cnx_master_out : t_wishbone_master_out_array(c_NUM_WB_SLAVES-1 downto 0);

  signal cpu_iwb_out : t_wishbone_master_out;
  signal cpu_iwb_in  : t_wishbone_master_in;

  signal cpu_irq_vec : std_logic_vector(31 downto 0);
  signal cpu_reset_n : std_logic;

  signal dummy             : std_logic_vector(63 downto 0);
  signal gpio_out, gpio_in : std_logic_vector(c_NUM_GPIO_PINS-1 downto 0);

  signal dac_out_data, dac_dmtd_data : std_logic_vector(15 downto 0);
  signal dac_out_load, dac_dmtd_load : std_logic;

  signal clk_rx_vec : std_logic_vector(g_num_rx_clocks-1 downto 0);
	signal pps_csync	:	std_logic;

  function f_pick (
    cond     : boolean;
    if_true  : integer;
    if_false : integer
    ) return integer is
  begin
    if(cond) then
      return if_true;
    else
      return if_false;
    end if;
  end f_pick;


begin  -- rtl

  clk_rx_vec(g_num_rx_clocks-1 downto 0) <= clk_rx_i;

  cnx_slave_in(0) <= wb_i;
  wb_o            <= cnx_slave_out(0);

  U_Intercon : xwb_crossbar
    generic map (
      g_num_masters => 2,
      g_num_slaves  => c_NUM_WB_SLAVES,
      g_registered  => true,
      g_address     => c_cnx_base_addr,
      g_mask        => c_cnx_base_mask)
    port map (
      clk_sys_i => clk_sys_i,
      rst_n_i   => rst_n_i,
      slave_i   => cnx_slave_in,
      slave_o   => cnx_slave_out,
      master_i  => cnx_master_in,
      master_o  => cnx_master_out);

  U_CPU : xwb_lm32
    generic map (
      g_profile => "medium_icache_debug")
    port map (
      clk_sys_i => clk_sys_i,
      rst_n_i   => cpu_reset_n,
      irq_i     => cpu_irq_vec,
      dwb_o     => cnx_slave_in(1),
      dwb_i     => cnx_slave_out(1),
      iwb_o     => cpu_iwb_out,
      iwb_i     => cpu_iwb_in);

  U_DPRAM : xwb_dpram
    generic map (
      g_size                  => 16384,
      g_init_file             => "",
      g_slave1_interface_mode => PIPELINED,
      g_slave2_interface_mode => PIPELINED,
      g_slave1_granularity    => BYTE,
      g_slave2_granularity    => BYTE)
    port map (
      clk_sys_i => clk_sys_i,
      rst_n_i   => rst_n_i,
      slave1_i  => cnx_master_out(c_SLAVE_DPRAM),
      slave1_o  => cnx_master_in(c_SLAVE_DPRAM),
      slave2_i  => cpu_iwb_out,
      slave2_o  => cpu_iwb_in);

  U_UART : xwb_simple_uart
    generic map (
      g_with_virtual_uart   => true,
      g_with_physical_uart  => true,
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE)
    port map (
      clk_sys_i  => clk_sys_i,
      rst_n_i    => rst_n_i,
      slave_i    => cnx_master_out(c_SLAVE_UART),
      slave_o    => cnx_master_in(c_SLAVE_UART),
      desc_o     => open,
      uart_rxd_i => uart_rxd_i,
      uart_txd_o => uart_txd_o);


  U_SoftPLL : xwr_softpll_ng
    generic map (
      g_tag_bits             => 22,
      g_interface_mode       => PIPELINED,
      g_address_granularity  => BYTE,
      g_num_ref_inputs       => g_num_rx_clocks,
      g_num_outputs          => 1,
      g_reverse_dmtds        => true,
      g_with_ext_clock_input => true,
      g_divide_input_by_2    => false,
      g_with_debug_fifo      => true,
			g_ref_clock_rate			 => 62500000,
			g_ext_clock_rate			 => 10000000)
    port map (
      clk_sys_i       => clk_sys_i,
      rst_n_i         => rst_n_i,
      clk_ref_i       => clk_rx_vec,
      clk_fb_i(0)     => clk_ref_i,
      clk_dmtd_i      => clk_dmtd_i,
      clk_ext_i       => clk_ext_i,
			clk_ext_mul_i		=> clk_ext_mul_i,
			pps_csync_p1_i	=> pps_csync,
      pps_ext_a_i     => pps_ext_i,
      dac_dmtd_data_o => dac_dmtd_data,
      dac_dmtd_load_o => dac_dmtd_load,
      dac_out_data_o  => dac_out_data,
      dac_out_sel_o   => open,
      dac_out_load_o  => dac_out_load,
      out_enable_i    => "0",
      out_locked_o    => open,
      slave_i         => cnx_master_out(c_SLAVE_SOFTPLL),
      slave_o         => cnx_master_in(c_SLAVE_SOFTPLL),
      debug_o         => spll_dbg_o);
  
  U_PPS_Gen : xwr_pps_gen
    generic map (
      g_interface_mode       => PIPELINED,
      g_address_granularity  => BYTE,
      g_ref_clock_rate       => f_pick(g_simulation, 10000, 62500000),
      g_ext_clock_rate       => f_pick(g_simulation, 1600, 10000000),
      g_with_ext_clock_input => true)
    port map (
      clk_ref_i       => clk_ref_i,
      clk_sys_i       => clk_sys_i,
      clk_ext_i       => clk_ext_i,
      rst_n_i         => gpio_out(3),
      slave_i         => cnx_master_out(c_SLAVE_PPSGEN),
      slave_o         => cnx_master_in(c_SLAVE_PPSGEN),
      pps_in_i        => pps_ext_i,
      pps_csync_o     => pps_csync,
      pps_out_o       => pps_ext_o,
      pps_valid_o     => pps_valid_o,
      tm_utc_o        => tm_utc_o,
      tm_cycles_o     => tm_cycles_o,
      tm_time_valid_o => tm_time_valid_o);

	pps_csync_o	<= pps_csync;

  cpu_irq_vec(0)           <= cnx_master_in(2).int;
  cpu_irq_vec(31 downto 1) <= (others => '0');

  U_SPI_Master : xwb_spi
    generic map (
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE,
      g_divider_len         => 8,
      g_max_char_len        => 24,
      g_num_slaves          => 1)
    port map (
      clk_sys_i            => clk_sys_i,
      rst_n_i              => rst_n_i,
      slave_i              => cnx_master_out(c_SLAVE_SPI),
      slave_o              => cnx_master_in(c_SLAVE_SPI),
      desc_o               => open,
      pad_cs_o(0)          => pll_cs_n_o,
      pad_sclk_o           => pll_sck_o,
      pad_mosi_o           => pll_mosi_o,
      pad_miso_i           => pll_miso_i);

  U_GPIO : xwb_gpio_port
    generic map (
      g_interface_mode         => PIPELINED,
      g_address_granularity    => BYTE,
      g_num_pins               => c_NUM_GPIO_PINS,
      g_with_builtin_tristates => false)
    port map (
      clk_sys_i  => clk_sys_i,
      rst_n_i    => rst_n_i,
      slave_i    => cnx_master_out(c_SLAVE_GPIO),
      slave_o    => cnx_master_in(c_SLAVE_GPIO),
      desc_o     => open,
      gpio_b     => open,
      gpio_out_o => gpio_out,
      gpio_in_i  => gpio_in,
      gpio_oen_o => open);



  U_Timer : xwb_tics
    generic map (
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE,
      g_period              => 625)     -- 10us tick period
    port map (
      clk_sys_i => clk_sys_i,
      rst_n_i   => rst_n_i,
      slave_i   => cnx_master_out(c_SLAVE_TIMER),
      slave_o   => cnx_master_in(c_SLAVE_TIMER),
      desc_o    => open);

  sel_clk_sys_o <= gpio_out(0);
  pll_reset_n_o <= gpio_out(1);
  cpu_reset_n   <= not gpio_out(2) and rst_n_i;
  rst_n_o       <= gpio_out(3);

  U_Main_DAC : gc_serial_dac
    generic map (
      g_num_data_bits  => 16,
      g_num_extra_bits => 8,
      g_num_cs_select  => 1,
      g_sclk_polarity  => 0)
    port map (
      clk_i         => clk_sys_i,
      rst_n_i       => rst_n_i,
      value_i       => dac_out_data,
      cs_sel_i      => "1",
      load_i        => dac_out_load,
      sclk_divsel_i => "010",
      dac_cs_n_o(0) => dac_main_sync_n_o,
      dac_sclk_o    => dac_main_sclk_o,
      dac_sdata_o   => dac_main_data_o);

  U_DMTD_DAC : gc_serial_dac
    generic map (
      g_num_data_bits  => 16,
      g_num_extra_bits => 8,
      g_num_cs_select  => 1,
      g_sclk_polarity  => 0)
    port map (
      clk_i         => clk_sys_i,
      rst_n_i       => rst_n_i,
      value_i       => dac_dmtd_data,
      cs_sel_i      => "1",
      load_i        => dac_dmtd_load,
      sclk_divsel_i => "010",
      dac_cs_n_o(0) => dac_helper_sync_n_o,
      dac_sclk_o    => dac_helper_sclk_o,
      dac_sdata_o   => dac_helper_data_o);

end rtl;

