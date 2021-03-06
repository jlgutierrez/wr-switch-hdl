-------------------------------------------------------------------------------
-- Title      : WR Switch bare top level
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : scb_top_bare.vhd
-- Author     : Tomasz Wlostowski, Maciej Lipinski, Grzegorz Daniluk
-- Company    : CERN BE-CO-HT
-- Created    : 2012-02-21
-- Last update: 2014-03-17
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description:
-- Bare switch top module, without GTX transceivers and CPU bridge.
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
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use work.wishbone_pkg.all;
use work.gencores_pkg.all;
use work.wr_fabric_pkg.all;
use work.endpoint_pkg.all;
use work.wrsw_txtsu_pkg.all;
use work.hwinfo_pkg.all;
use work.wrsw_top_pkg.all;
use work.wrsw_shared_types_pkg.all;
use work.wrsw_tru_pkg.all;
use work.wrsw_tatsu_pkg.all;
use work.wrs_sdb_pkg.all;

library UNISIM;
use UNISIM.vcomponents.all;

entity scb_top_bare is
  generic(
    g_num_ports       : integer := 6;
    g_simulation      : boolean := false;
    g_without_network : boolean := false;
    g_with_TRU        : boolean := false;
    g_with_TATSU      : boolean := false;
    g_with_HWIU       : boolean := false;
    g_with_PSTATS     : boolean := true;
    g_with_muxed_CS   : boolean := false;
    g_with_watchdog   : boolean := false;
    g_inj_per_EP      : std_logic_vector(17 downto 0) := (others=>'0')
    );
  port (
    sys_rst_n_i : in std_logic;         -- global reset

    -- Startup 25 MHz clock (from onboard 25 MHz oscillator)
    clk_startup_i : in std_logic;

    -- 62.5 MHz timing reference (from the AD9516 PLL output QDRII_CLK)
    clk_ref_i : in std_logic;

    -- 62.5+ MHz DMTD offset clock (from the CDCM62001 PLL output DMTDCLK_MAIN)
    clk_dmtd_i : in std_logic;

    -- Programmable aux clock (from the AD9516 PLL output QDRII_200CLK). Used
    -- for re-phasing the 10 MHz input as well as clocking the 
    clk_aux_i : in std_logic;

		clk_ext_mul_i	:	in std_logic;
		clk_ext_mul_locked_i	:	in std_logic;

    clk_aux_p_o  : out std_logic; -- going to CLK2 SMC on the front pannel, by
    clk_aux_n_o  : out std_logic; -- default it's 10MHz, but is configurable

    clk_500_o    :  out std_logic;

    -- Muxed system clock
    clk_sys_o : out std_logic;

    -------------------------------------------------------------------------------
    -- Master wishbone bus (from the CPU bridge)
    -------------------------------------------------------------------------------
    cpu_wb_i    : in  t_wishbone_slave_in;
    cpu_wb_o    : out t_wishbone_slave_out;
    cpu_irq_n_o : out std_logic;

    -------------------------------------------------------------------------------
    -- Timing I/O
    -------------------------------------------------------------------------------    

    pps_i : in  std_logic;
    pps_o : out std_logic;

    -- DAC Drive
    dac_helper_sync_n_o : out std_logic;
    dac_helper_sclk_o   : out std_logic;
    dac_helper_data_o   : out std_logic;

    dac_main_sync_n_o : out std_logic;

    dac_main_sclk_o : out std_logic;
    dac_main_data_o : out std_logic;

    -------------------------------------------------------------------------------
    -- AD9516 PLL Control signals
    -------------------------------------------------------------------------------    

    pll_status_i  : in  std_logic;
    pll_mosi_o    : out std_logic;
    pll_miso_i    : in  std_logic;
    pll_sck_o     : out std_logic;
    pll_cs_n_o    : out std_logic;
    pll_sync_n_o  : out std_logic;
    pll_reset_n_o : out std_logic;

    uart_txd_o : out std_logic;
    uart_rxd_i : in  std_logic;

    -------------------------------------------------------------------------------
    -- Misc pins
    -------------------------------------------------------------------------------

    -- GTX clock fanout enable
    clk_en_o : out std_logic;

    -- GTX clock fanout source select
    clk_sel_o : out std_logic;

    -- DMTD clock divider selection (0 = 125 MHz, 1 = 62.5 MHz)
    clk_dmtd_divsel_o : out std_logic;

    -- UART source selection (FPGA/DBGU)
    uart_sel_o : out std_logic;

    ---------------------------------------------------------------------------
    -- GTX ports
    ---------------------------------------------------------------------------

    phys_o : out t_phyif_output_array(g_num_ports-1 downto 0);
    phys_i : in  t_phyif_input_array(g_num_ports-1 downto 0);

    led_link_o : out std_logic_vector(g_num_ports-1 downto 0);
    led_act_o  : out std_logic_vector(g_num_ports-1 downto 0);

    gpio_o : out std_logic_vector(31 downto 0);
    gpio_i : in  std_logic_vector(31 downto 0);

    ---------------------------------------------------------------------------
    -- I2C I/Os
    -- mapping: 0/1 -> MiniBackplane busses 0/1
    --          2   -> Onboard temp sensors
    ---------------------------------------------------------------------------

    i2c_scl_oen_o : out std_logic_vector(2 downto 0);
    i2c_scl_o     : out std_logic_vector(2 downto 0);
    i2c_scl_i     : in  std_logic_vector(2 downto 0) := "111";
    i2c_sda_oen_o : out std_logic_vector(2 downto 0);
    i2c_sda_o     : out std_logic_vector(2 downto 0);
    i2c_sda_i     : in  std_logic_vector(2 downto 0) := "111";

    ---------------------------------------------------------------------------
    -- Mini-backplane PWM fans
    ---------------------------------------------------------------------------

    mb_fan1_pwm_o : out std_logic;
    mb_fan2_pwm_o : out std_logic;

    spll_dbg_o  : out std_logic_vector(5 downto 0)
    );
end scb_top_bare;

architecture rtl of scb_top_bare is

  constant c_GW_VERSION    : std_logic_vector(31 downto 0) := x"20_02_14_00"; --DD_MM_YY_VV
  constant c_NUM_WB_SLAVES : integer := 14;
  constant c_NUM_PORTS     : integer := g_num_ports;
  constant c_MAX_PORTS     : integer := 18;
  constant c_NUM_GL_PAUSE  : integer := 2; -- number of output global PAUSE sources for SWcore
  constant c_RTU_EVENTS    : integer := 9; -- number of RMON events per port
  constant c_DBG_V_SWCORE  : integer := (3*10) + 2;         -- 3 resources, each has with of CNT of 10 bits +2 to make it 32
  constant c_DBG_N_REGS    : integer := 1 + integer(ceil(real(c_DBG_V_SWCORE)/real(32))); -- 32-bits debug registers which go to HWIU
  constant c_TRU_EVENTS    : integer := 1;
  constant c_ALL_EVENTS    : integer := c_TRU_EVENTS + c_RTU_EVENTS + c_epevents_sz;
  constant c_DUMMY_RMON    : boolean := false; -- define TRUE to enable dummy_rmon module for debugging PSTAT
  constant c_NUM_GPIO_PINS : integer := 1;
  constant c_NUM_IRQS      : integer := 4;
--   constant c_epevents_sz   : integer := 15;
-------------------------------------------------------------------------------
-- Interconnect & memory layout
-------------------------------------------------------------------------------  

  constant c_SLAVE_RT_SUBSYSTEM : integer := 0;
  constant c_SLAVE_NIC          : integer := 1;
  constant c_SLAVE_ENDPOINTS    : integer := 2;
  constant c_SLAVE_VIC          : integer := 3;
  constant c_SLAVE_TXTSU        : integer := 4;
  constant c_SLAVE_RTU          : integer := 5;
  constant c_SLAVE_GPIO         : integer := 6;
  constant c_SLAVE_I2C          : integer := 7;
  constant c_SLAVE_PWM          : integer := 8;
  constant c_SLAVE_TRU          : integer := 9;
  constant c_SLAVE_TATSU        : integer := 10;
  constant c_SLAVE_PSTATS       : integer := 11;
  constant c_SLAVE_HWIU         : integer := 12;
  constant c_SLAVE_WDOG         : integer := 13;
  --constant c_SLAVE_DUMMY        : integer := 13;


  function f_bool2int(x : boolean) return integer is
  begin
    if(x) then
      return 1;
    else
      return 0;
    end if;
  end f_bool2int;

  function f_logic2bool(x : std_logic) return boolean is
  begin
    if(x = '1') then
      return true;
    else
      return false;
    end if;
  end f_logic2bool;


  signal cnx_slave_in  : t_wishbone_slave_in_array(0 downto 0);
  signal cnx_slave_out : t_wishbone_slave_out_array(0 downto 0);

  signal bridge_master_in  : t_wishbone_master_in;
  signal bridge_master_out : t_wishbone_master_out;

  signal cnx_master_in  : t_wishbone_master_in_array(c_NUM_WB_SLAVES-1 downto 0);
  signal cnx_master_out : t_wishbone_master_out_array(c_NUM_WB_SLAVES-1 downto 0);

  signal cnx_endpoint_in  : t_wishbone_master_in_array(c_MAX_PORTS-1 downto 0);
  signal cnx_endpoint_out : t_wishbone_master_out_array(c_MAX_PORTS-1 downto 0);

  -------------------------------------------------------------------------------
  -- Clocks
  -------------------------------------------------------------------------------

  signal clk_sys    : std_logic;
  signal clk_rx_vec : std_logic_vector(c_NUM_PORTS-1 downto 0);


-------------------------------------------------------------------------------
-- Fabric/Endpoint interconnect
-------------------------------------------------------------------------------

  signal endpoint_src_out : t_wrf_source_out_array(c_NUM_PORTS downto 0);
  signal endpoint_src_in  : t_wrf_source_in_array(c_NUM_PORTS downto 0);
  signal endpoint_snk_out : t_wrf_sink_out_array(c_NUM_PORTS downto 0);
  signal endpoint_snk_in  : t_wrf_sink_in_array(c_NUM_PORTS downto 0);

  signal wrfreg_src_out : t_wrf_source_out_array(c_NUM_PORTS downto 0);
  signal wrfreg_src_in  : t_wrf_source_in_array(c_NUM_PORTS downto 0);

  signal swc_src_out : t_wrf_source_out_array(c_NUM_PORTS downto 0);
  signal swc_src_in  : t_wrf_source_in_array(c_NUM_PORTS downto 0);
  signal swc_snk_out : t_wrf_sink_out_array(c_NUM_PORTS downto 0);
  signal swc_snk_in  : t_wrf_sink_in_array(c_NUM_PORTS downto 0);

  signal dummy_snk_in  : t_wrf_sink_in_array(c_NUM_PORTS downto 0);
  signal dummy_src_in  : t_wrf_source_in_array(c_NUM_PORTS downto 0);
  signal dummy_src_out : t_wrf_source_out_array(c_NUM_PORTS downto 0);


  signal rtu_req                            : t_rtu_request_array(c_NUM_PORTS downto 0);
  signal rtu_rsp                            : t_rtu_response_array(c_NUM_PORTS downto 0);
  signal rtu_req_ack, rtu_full, rtu_rsp_ack, rtu_rq_abort, rtu_rsp_abort: std_logic_vector(c_NUM_PORTS downto 0);
  signal swc_rtu_ack  : std_logic_vector(c_NUM_PORTS downto 0);

-- System clock selection: 0 = startup clock, 1 = PLL clock
  signal sel_clk_sys, sel_clk_sys_int : std_logic;
  signal switchover_cnt               : unsigned(4 downto 0);

  signal rst_n_sys  : std_logic;
  signal pps_p_main : std_logic;

  signal txtsu_timestamps_ack : std_logic_vector(c_NUM_PORTS-1 downto 0);
  signal txtsu_timestamps     : t_txtsu_timestamp_array(c_NUM_PORTS-1 downto 0);
  signal tru_enabled          : std_logic;

  -- PSTAT: RMON counters
  signal rtu_events  : std_logic_vector(c_NUM_PORTS*c_RTU_EVENTS  -1 downto 0);  --
  signal ep_events   : std_logic_vector(c_NUM_PORTS*c_epevents_sz -1 downto 0);  --
  signal rmon_events : std_logic_vector(c_NUM_PORTS*c_ALL_EVENTS  -1 downto 0);  --

  --TEMP
  signal dummy_events : std_logic_vector(c_NUM_PORTS*2-1 downto 0);

  -----------------------------------------------------------------------------
  -- Component declarations
  -----------------------------------------------------------------------------

  signal vic_irqs : std_logic_vector(c_NUM_IRQS-1 downto 0);
  type t_trig is array(integer range <>) of std_logic_vector(31 downto 0);

  signal control0                   : std_logic_vector(35 downto 0);
  signal trig0, trig1, trig2, trig3 : t_trig(7 downto 0);--std_logic_vector(31 downto 0);
  signal t0, t1, t2, t3             : std_logic_vector(31 downto 0);
  signal rst_n_periph               : std_logic;
  signal link_kill                  : std_logic_vector(c_NUM_PORTS-1 downto 0);
  signal rst_n_swc  : std_logic;
  signal swc_nomem  : std_logic;
  signal swc_wdog_out : t_swc_fsms_array(c_NUM_PORTS downto 0);
  signal ep_stop_traffic : std_logic;

 



  function f_fabric_2_slv (
    in_i : t_wrf_sink_in;
    in_o : t_wrf_sink_out) return std_logic_vector is
    variable tmp : std_logic_vector(31 downto 0);
  begin
    tmp(15 downto 0)  := in_i.dat;
    tmp(17 downto 16) := in_i.adr;
    tmp(19 downto 18) := in_i.sel;
    tmp(20)           := in_i.cyc;
    tmp(21)           := in_i.stb;
    tmp(22)           := in_i.we;
    tmp(23)           := in_o.ack;
    tmp(24)           := in_o.stall;
    tmp(25)           := in_o.err;
    tmp(26)           := in_o.rty;
    return tmp;
  end f_fabric_2_slv;

  function f_swc_ratio return integer is
  begin
    if(g_num_ports < 12) then
      return 4;
    else
      return 6;
    end if;
  end f_swc_ratio;


  signal cpu_irq_n            : std_logic;
  signal pps_csync, pps_valid : std_logic;



  component chipscope_icon
    port (
      CONTROL0 : inout std_logic_vector(35 downto 0));
  end component;

  component chipscope_ila
    port (
      CONTROL : inout std_logic_vector(35 downto 0);
      CLK     : in    std_logic;
      TRIG0   : in    std_logic_vector(31 downto 0);
      TRIG1   : in    std_logic_vector(31 downto 0);
      TRIG2   : in    std_logic_vector(31 downto 0);
      TRIG3   : in    std_logic_vector(31 downto 0));
  end component;

  signal gpio_out : std_logic_vector(c_NUM_GPIO_PINS-1 downto 0);
  signal gpio_in  : std_logic_vector(c_NUM_GPIO_PINS-1 downto 0);
  signal dummy    : std_logic_vector(c_NUM_GPIO_PINS-1 downto 0);

  -----------------------------------------------------------------------------
  -- TRU stuff
  -----------------------------------------------------------------------------
  signal tru_req    : t_tru_request;
  signal tru_resp   : t_tru_response;    
  signal rtu2tru    : t_rtu2tru;
  signal ep2tru     : t_ep2tru_array(g_num_ports-1 downto 0);
  signal tru2ep     : t_tru2ep_array(g_num_ports-1 downto 0);
  signal swc2tru_req: t_global_pause_request; -- for pause
  -----------------------------------------------------------------------------
  -- Time-Aware Traffic Shaper
  -----------------------------------------------------------------------------

  signal tm_utc              : std_logic_vector(39 downto 0);
  signal tm_cycles           : std_logic_vector(27 downto 0);
  signal tm_time_valid       : std_logic;
  signal pps_o_predelay      : std_logic;
  signal ppsdel_tap_out      : std_logic_vector(4 downto 0);
  signal ppsdel_tap_in       : std_logic_vector(4 downto 0);
  signal ppsdel_tap_wr_in    : std_logic;
  signal shaper_request      : t_global_pause_request;
  signal shaper_drop_at_hp_ena : std_logic;
  signal   fc_rx_pause       : t_pause_request_array(g_num_ports+1-1 downto 0);
  constant c_zero_pause      : t_pause_request        :=('0',x"0000", x"00");
  constant c_zero_gl_pause   : t_global_pause_request :=('0',x"0000", x"00",(others=>'0'));
  signal global_pause        : t_global_pause_request_array(c_NUM_GL_PAUSE-1 downto 0);

  signal dbg_n_regs          : std_logic_vector(c_DBG_N_REGS*32 -1 downto 0);
  
  type t_ep_dbg_data_array   is array(integer range <>) of std_logic_vector(15 downto 0);
  type t_ep_dbg_k_array      is array(integer range <>) of std_logic_vector(1 downto 0);
  type t_ep_dbg_rx_buf_array is array(integer range <>) of std_logic_vector(7 downto 0);
  type t_ep_dbg_fab_pipes_array is array(integer range <>) of std_logic_vector(63 downto 0);
  type t_ep_dbg_tx_pcs_array is array(integer range <>) of std_logic_vector(5+4 downto 0);

  signal ep_dbg_data_array   : t_ep_dbg_data_array(g_num_ports-1 downto 0);
  signal ep_dbg_k_array      : t_ep_dbg_k_array(g_num_ports-1 downto 0);
  signal ep_dbg_rx_buf_array : t_ep_dbg_rx_buf_array(g_num_ports-1 downto 0);
  signal ep_dbg_fab_pipes_array : t_ep_dbg_fab_pipes_array(g_num_ports-1 downto 0);
  signal ep_dbg_tx_pcs_wr_array : t_ep_dbg_tx_pcs_array(g_num_ports-1 downto 0);
  signal ep_dbg_tx_pcs_rd_array : t_ep_dbg_tx_pcs_array(g_num_ports-1 downto 0);
  signal dbg_chps_id          : std_logic_vector(7 downto 0);
  
begin



  --CS_ICON : chipscope_icon
  --  port map (
  --   CONTROL0 => CONTROL0);
  --CS_ILA : chipscope_ila
  --  port map (
  --    CONTROL => CONTROL0,

  --    CLK     => clk_sys,
  --    TRIG0   => TRIG0,
  --    TRIG1   => TRIG1,
  --    TRIG2   => TRIG2,
  --    TRIG3   => TRIG3);


  cnx_slave_in(0) <= cpu_wb_i;
  cpu_wb_o        <= cnx_slave_out(0);

  --TRIG0 <= cpu_wb_i.adr;
  --TRIG1 <= cpu_wb_i.dat;
  --TRIG3 <= cnx_slave_out(0).dat;
  --TRIG2(0) <= cpu_wb_i.cyc;
  --TRIG2(1) <= cpu_wb_i.stb;
  --TRIG2(2) <= cpu_wb_i.we;
  --TRIG2(3) <= cnx_slave_out(0).stall;
  --TRIG2(4) <= cnx_slave_out(0).ack;

  U_Sys_Clock_Mux : BUFGMUX
    generic map (
      CLK_SEL_TYPE => "SYNC")
    port map (
      O  => clk_sys,
      I0 => clk_startup_i,
      I1 => clk_ref_i,                  -- both are 62.5 MHz
      S  => sel_clk_sys_int);



  U_Intercon : xwb_sdb_crossbar
    generic map (
      g_num_masters => 1,
      g_num_slaves  => c_NUM_WB_SLAVES,
      g_registered  => true,
      g_wraparound  => true,
      g_layout      => c_layout,
      g_sdb_addr    => c_sdb_address)
    port map (
      clk_sys_i => clk_sys,
      rst_n_i   => rst_n_sys,
      slave_i   => cnx_slave_in,
      slave_o   => cnx_slave_out,
      master_i  => cnx_master_in,
      master_o  => cnx_master_out);


  U_sync_reset : gc_sync_ffs
    port map (
      clk_i    => clk_sys,
      rst_n_i  => '1',
      data_i   => sys_rst_n_i,
      synced_o => rst_n_sys);

  p_gen_sel_clk_sys : process(sys_rst_n_i, clk_sys)
  begin
    if sys_rst_n_i = '0' then
      sel_clk_sys_int <= '0';
      switchover_cnt  <= (others => '0');
    elsif rising_edge(clk_sys) then
      if(switchover_cnt = "11111") then
        sel_clk_sys_int <= sel_clk_sys;
      else
        switchover_cnt <= switchover_cnt + 1;
      end if;
    end if;
  end process;


  U_RT_Subsystem : wrsw_rt_subsystem
    generic map (
      g_num_rx_clocks => c_NUM_PORTS,
      g_simulation    => g_simulation)
    port map (
      clk_ref_i           => clk_ref_i,
      clk_sys_i           => clk_sys,
      clk_dmtd_i          => clk_dmtd_i,
      clk_rx_i            => clk_rx_vec,
      clk_ext_i           => pll_status_i,  -- FIXME: UGLY HACK
			clk_ext_mul_i				=> clk_ext_mul_i,
      clk_ext_mul_locked_i  => clk_ext_mul_locked_i,
      clk_aux_p_o         => clk_aux_p_o,
      clk_aux_n_o         => clk_aux_n_o,
      clk_500_o           => clk_500_o,
      rst_n_i             => rst_n_sys,
      rst_n_o             => rst_n_periph,
      wb_i                => cnx_master_out(c_SLAVE_RT_SUBSYSTEM),
      wb_o                => cnx_master_in(c_SLAVE_RT_SUBSYSTEM),
      dac_helper_sync_n_o => dac_helper_sync_n_o,
      dac_helper_sclk_o   => dac_helper_sclk_o,
      dac_helper_data_o   => dac_helper_data_o,
      dac_main_sync_n_o   => dac_main_sync_n_o,
      dac_main_sclk_o     => dac_main_sclk_o,
      dac_main_data_o     => dac_main_data_o,
      uart_txd_o          => uart_txd_o,
      uart_rxd_i          => uart_rxd_i,

      pps_csync_o => pps_csync,
      pps_valid_o => pps_valid,
      pps_ext_i   => pps_i,
      pps_ext_o   => pps_o_predelay,

      sel_clk_sys_o => sel_clk_sys,

      ppsdel_tap_i    => ppsdel_tap_out,
      ppsdel_tap_o    => ppsdel_tap_in,
      ppsdel_tap_wr_o => ppsdel_tap_wr_in,

      tm_utc_o            => tm_utc, 
      tm_cycles_o         => tm_cycles, 
      tm_time_valid_o     => tm_time_valid, 

      pll_status_i  => '0',
      pll_mosi_o    => pll_mosi_o,
      pll_miso_i    => pll_miso_i,
      pll_sck_o     => pll_sck_o,
      pll_cs_n_o    => pll_cs_n_o,
      pll_sync_n_o  => pll_sync_n_o,
      pll_reset_n_o => pll_reset_n_o,
      spll_dbg_o    => spll_dbg_o);

  U_DELAY_PPS: IODELAYE1
    generic map (
      CINVCTRL_SEL           => FALSE,
      DELAY_SRC              => "O",
      HIGH_PERFORMANCE_MODE  => TRUE,
      IDELAY_TYPE            => "FIXED",
      IDELAY_VALUE           => 0,
      ODELAY_TYPE            => "VAR_LOADABLE",
      ODELAY_VALUE           => 0,
      REFCLK_FREQUENCY       => 200.0,
      SIGNAL_PATTERN         => "DATA")
    port map (
      DATAOUT                => pps_o,
      DATAIN                 => '0',
      C                      => clk_sys,
      CE                     => '0',
      INC                    => '0',
      IDATAIN                => '0',
      ODATAIN                => pps_o_predelay,
      RST                    => ppsdel_tap_wr_in,
      T                      => '0',
      CNTVALUEIN             => ppsdel_tap_in,
      CNTVALUEOUT            => ppsdel_tap_out,
      CLKIN                  => '0',
      CINVCTRL               => '0');

  U_IRQ_Controller : xwb_vic
    generic map (
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE,
      g_num_interrupts      => c_NUM_IRQS)
    port map (
      clk_sys_i    => clk_sys,
      rst_n_i      => rst_n_sys,
      slave_i      => cnx_master_out(c_SLAVE_VIC),
      slave_o      => cnx_master_in(c_SLAVE_VIC),
      irqs_i       => vic_irqs,
      irq_master_o => cpu_irq_n_o);

  gen_network_stuff : if(g_without_network = false) generate
    
    U_Nic : xwrsw_nic
      generic map (
        g_interface_mode      => PIPELINED,
        g_address_granularity => BYTE,
        g_port_mask_bits      => c_NUM_PORTS+1)
      port map (
        clk_sys_i           => clk_sys,
        rst_n_i             => rst_n_sys,
        snk_i               => endpoint_snk_in(c_NUM_PORTS),
        snk_o               => endpoint_snk_out(c_NUM_PORTS),
        src_i               => endpoint_src_in(c_NUM_PORTS),
        src_o               => endpoint_src_out(c_NUM_PORTS),
        rtu_dst_port_mask_o => rtu_rsp(c_NUM_PORTS).port_mask(c_NUM_PORTS downto 0),
        rtu_prio_o          => rtu_rsp(c_NUM_PORTS).prio,
        rtu_drop_o          => rtu_rsp(c_NUM_PORTS).drop,
        rtu_rsp_valid_o     => rtu_rsp(c_NUM_PORTS).valid,
        rtu_rsp_ack_i       => rtu_rsp_ack(c_NUM_PORTS),
        wb_i                => cnx_master_out(c_SLAVE_NIC),
        wb_o                => cnx_master_in(c_SLAVE_NIC));
  
    rtu_rsp(c_NUM_PORTS).hp <= '0';
    fc_rx_pause(c_NUM_PORTS)       <= c_zero_pause; -- no pause for NIC  
    
    U_Endpoint_Fanout : xwb_sdb_crossbar
      generic map (
        g_num_masters => 1,
        g_num_slaves  => c_MAX_PORTS,
        g_registered  => true,
        g_wraparound  => true,
        g_layout      => c_epbar_layout,
        g_sdb_addr    => c_epbar_sdb_address)
      port map (
        clk_sys_i  => clk_sys,
        rst_n_i    => rst_n_sys,
        slave_i(0) => cnx_master_out(c_SLAVE_ENDPOINTS),
        slave_o(0) => cnx_master_in(c_SLAVE_ENDPOINTS),
        master_i   => cnx_endpoint_in,
        master_o   => cnx_endpoint_out);


    gen_endpoints_and_phys : for i in 0 to c_NUM_PORTS-1 generate
      U_Endpoint_X : xwr_endpoint
        generic map (
          g_interface_mode      => PIPELINED,
          g_address_granularity => BYTE,
          g_simulation          => g_simulation,
          g_tx_force_gap_length => 0,
          g_tx_runt_padding     => false,
          g_pcs_16bit           => true,
          g_rx_buffer_size      => 1024,
          g_with_rx_buffer      => true,
          g_with_flow_control   => false,-- useless: flow control commented out 
          g_with_timestamper    => true,
          g_with_dpi_classifier => true,
          g_with_vlans          => true,
          g_with_rtu            => true,
          g_with_leds           => true,
          g_with_dmtd           => false,
          g_with_packet_injection => f_logic2bool(g_inj_per_EP(i)),
          g_use_new_rxcrc       => true,
          g_use_new_txcrc       => false,
          g_with_stop_traffic   => g_with_watchdog)
        port map (
          clk_ref_i  => clk_ref_i,
          clk_sys_i  => clk_sys,
          clk_dmtd_i => clk_dmtd_i,
          rst_n_i    => rst_n_periph,

          pps_csync_p1_i => pps_csync,
          pps_valid_i    => pps_valid,

          phy_rst_o          => phys_o(i).rst,
          phy_loopen_o       => phys_o(i).loopen,
          phy_enable_o       => phys_o(i).enable,
          phy_rdy_i          => phys_i(i).rdy,
          phy_ref_clk_i      => phys_i(i).ref_clk,
          phy_tx_data_o      => ep_dbg_data_array(i), -- phys_o(i).tx_data, --
          phy_tx_k_o         => ep_dbg_k_array(i),    -- phys_o(i).tx_k,    -- 
          phy_tx_disparity_i => phys_i(i).tx_disparity,
          phy_tx_enc_err_i   => phys_i(i).tx_enc_err,
          phy_rx_data_i      => phys_i(i).rx_data,
          phy_rx_clk_i       => phys_i(i).rx_clk,
          phy_rx_k_i         => phys_i(i).rx_k,
          phy_rx_enc_err_i   => phys_i(i).rx_enc_err,
          phy_rx_bitslide_i  => phys_i(i).rx_bitslide,

          txtsu_port_id_o      => txtsu_timestamps(i).port_id(4 downto 0),
          txtsu_frame_id_o     => txtsu_timestamps(i).frame_id,
          txtsu_ts_value_o     => txtsu_timestamps(i).tsval,
          txtsu_ts_incorrect_o => txtsu_timestamps(i).incorrect,
          txtsu_stb_o          => txtsu_timestamps(i).stb,
          txtsu_ack_i          => txtsu_timestamps_ack(i),

          rtu_full_i         => rtu_full(i),
          rtu_rq_strobe_p1_o => rtu_req(i).valid,
          rtu_rq_abort_o     => rtu_rq_abort(i),
          rtu_rq_smac_o      => rtu_req(i).smac,
          rtu_rq_dmac_o      => rtu_req(i).dmac,
          rtu_rq_prio_o      => rtu_req(i).prio,
          rtu_rq_vid_o       => rtu_req(i).vid,
          rtu_rq_has_vid_o   => rtu_req(i).has_vid,
          rtu_rq_has_prio_o  => rtu_req(i).has_prio,

          src_o      => endpoint_src_out(i),
          src_i      => endpoint_src_in(i),
          snk_o      => endpoint_snk_out(i),
          snk_i      => endpoint_snk_in(i),
          wb_i       => cnx_endpoint_out(i),
          wb_o       => cnx_endpoint_in(i),

          ----- TRU stuff ------------
          pfilter_pclass_o     => ep2tru(i).pfilter_pclass,
          pfilter_drop_o       => ep2tru(i).pfilter_drop,
          pfilter_done_o       => ep2tru(i).pfilter_done,
          fc_tx_pause_req_i    => tru2ep(i).fc_pause_req,   -- we don't use it, use inject instead
          fc_tx_pause_delay_i  => tru2ep(i).fc_pause_delay, -- we don't use it, use inject instead
          fc_tx_pause_ready_o  => ep2tru(i).fc_pause_ready, -- we don't use it, use inject instead
          inject_req_i         => tru2ep(i).inject_req,
          inject_ready_o       => ep2tru(i).inject_ready,
          inject_packet_sel_i  => tru2ep(i).inject_packet_sel,
          inject_user_value_i  => tru2ep(i).inject_user_value,
          link_kill_i          => tru2ep(i).link_kill, --'0' , --link_kill(i), -- to change
          link_up_o            => ep2tru(i).status,
          ------ PAUSE to SWcore  ------------
          fc_rx_pause_start_p_o   => fc_rx_pause(i).req,  
          fc_rx_pause_quanta_o    => fc_rx_pause(i).quanta,    
          fc_rx_pause_prio_mask_o => fc_rx_pause(i).classes, 
          ----------------------------

          rmon_events_o => ep_events((i+1)*c_epevents_sz-1 downto i*c_epevents_sz),

          led_link_o => led_link_o(i),
          led_act_o  => led_act_o(i),
          stop_traffic_i => ep_stop_traffic
          );

          phys_o(i).tx_data <= ep_dbg_data_array(i);
          phys_o(i).tx_k    <= ep_dbg_k_array(i);

      txtsu_timestamps(i).port_id(5) <= '0';
      
      ------- TEMP ---------
--       link_kill(i)                <= not tru2ep(i).ctrlWr; 
--       tru2ep(i).fc_pause_req      <= '0';
--       tru2ep(i).fc_pause_delay    <= (others =>'0');
--       tru2ep(i).inject_req        <= '0';
--       tru2ep(i).inject_packet_sel <= (others => '0');
--       tru2ep(i).inject_user_value <= (others => '0');
--       ep2tru(i).rx_pck            <= '0';
--       ep2tru(i).rx_pck_class      <= (others => '0');
      ---------------------------

      clk_rx_vec(i) <= phys_i(i).rx_clk;

    end generate gen_endpoints_and_phys;

    GEN_TIMING: for I in 0 to c_NUM_PORTS generate
      -- improve timing
      U_WRF_RXREG_X: xwrf_reg
        port map (
          rst_n_i => rst_n_periph,
          clk_i   => clk_sys,
          snk_i   => endpoint_src_out(i),
          snk_o   => endpoint_src_in(i),
          src_o   => wrfreg_src_out(i),
          src_i   => wrfreg_src_in(i));

      U_WRF_TXREG_X: xwrf_reg
        port map(
          rst_n_i => rst_n_periph,
          clk_i   => clk_sys,
          snk_i   => swc_src_out(i),
          snk_o   => swc_src_in(i),
          src_o   => endpoint_snk_in(i),
          src_i   => endpoint_snk_out(i));
    end generate;

    gen_terminate_unused_eps : for i in c_NUM_PORTS to c_MAX_PORTS-1 generate
      cnx_endpoint_in(i).ack   <= '1';
      cnx_endpoint_in(i).stall <= '0';
      cnx_endpoint_in(i).dat   <= x"deadbeef";
      cnx_endpoint_in(i).err   <= '0';
      cnx_endpoint_in(i).rty   <= '0';
      --txtsu_timestamps(i).valid <= '0';
    end generate gen_terminate_unused_eps;

--     gen_txtsu_debug : for i in 0 to c_NUM_PORTS-1 generate
--       TRIG0(i) <= txtsu_timestamps(i).stb;
--       trig1(i) <= txtsu_timestamps_ack(i);
--       trig2(0) <= vic_irqs(0);
--       trig2(1) <= vic_irqs(1);
--       trig2(2) <= vic_irqs(2);
--     end generate gen_txtsu_debug;

    U_Swcore : xswc_core
      generic map (
        g_prio_num                        => 8,
        g_output_queue_num                => 8,
        g_max_pck_size                    => 10 * 1024,
        g_max_oob_size                    => 3,
        g_num_ports                       => g_num_ports+1,
        g_pck_pg_free_fifo_size           => 512,
        g_input_block_cannot_accept_data  => "drop_pck",
        g_output_block_per_queue_fifo_size=> 64,
        g_wb_data_width                   => 16,
        g_wb_addr_width                   => 2,
        g_wb_sel_width                    => 2,
        g_wb_ob_ignore_ack                => false,
        g_mpm_mem_size                    => 65536, --test: 61440,--old: 65536,
        g_mpm_page_size                   => 64,    --test:    60,--old: 64,
        g_mpm_ratio                       => 8,     --test:    10,--old: 8,  --f_swc_ratio,  --2
        g_mpm_fifo_size                   => 8,
        g_mpm_fetch_next_pg_in_advance    => false,
        g_drop_outqueue_head_on_full      => true,
        g_num_global_pause                => c_NUM_GL_PAUSE,
        g_num_dbg_vector_width            => c_DBG_V_SWCORE)
      port map (
        clk_i          => clk_sys,
        clk_mpm_core_i => clk_aux_i,
        rst_n_i        => rst_n_swc,

        src_i => swc_src_in,
        src_o => swc_src_out,
        snk_i => swc_snk_in,
        snk_o => swc_snk_out,

        shaper_drop_at_hp_ena_i   => shaper_drop_at_hp_ena,
        
        -- pause stuff
        global_pause_i            => global_pause,
        perport_pause_i           => fc_rx_pause,

        dbg_o     => dbg_n_regs(32+c_DBG_V_SWCORE-1 downto 32), 
        
        rtu_rsp_i       => rtu_rsp,
        rtu_ack_o       => swc_rtu_ack,
        rtu_abort_o     =>rtu_rsp_abort,-- open --rtu_rsp_abort
        wdog_o    => swc_wdog_out
        );
     
    -- SWcore global pause nr=0 assigned to TRU
    global_pause(0)          <= swc2tru_req;

    -- SWcore global pause nr=1 assigned to TATSU
    global_pause(1)          <= shaper_request; 
    
    -- NIC sink
    --TRIG0 <= f_fabric_2_slv(endpoint_snk_in(1), endpoint_snk_out(1));
    ---- NIC source
    --TRIG1 <= f_fabric_2_slv(endpoint_src_out(1), endpoint_src_in(1));
    ---- NIC sink
    --TRIG2 <= f_fabric_2_slv(endpoint_snk_in(2), endpoint_snk_out(2));
    ---- NIC source
    --TRIG3 <= f_fabric_2_slv(endpoint_src_out(2), endpoint_src_in(2));
    --TRIG3(31) <= rst_n_periph;

    --TRIG2 <= rtu_rsp(c_NUM_PORTS).port_mask(31 downto 0);
    --TRIG3(0) <= rtu_rsp(c_NUM_PORTS).valid;
    --TRIG3(1) <= rtu_rsp_ack(c_NUM_PORTS);

   U_RTU : xwrsw_rtu_new
--   U_RTU : xwrsw_rtu
      generic map (
        g_prio_num                        => 8,
        g_interface_mode                  => PIPELINED,
        g_address_granularity             => BYTE,
        g_num_ports                       => g_num_ports,
        g_cpu_port_num                    => g_num_ports, -- g_num_ports-nt port is connected to CPU
        g_port_mask_bits                  => g_num_ports+1,
        g_handle_only_single_req_per_port => true,
        g_rmon_events_bits_pp             => c_RTU_EVENTS)
      port map (
        clk_sys_i  => clk_sys,
        rst_n_i    => rst_n_sys,--rst_n_periph,
        req_i      => rtu_req(g_num_ports-1 downto 0),
        req_full_o => rtu_full(g_num_ports-1 downto 0),
        rsp_o      => rtu_rsp(g_num_ports-1 downto 0),
        rsp_ack_i  => rtu_rsp_ack(g_num_ports-1 downto 0),
        rsp_abort_i=> rtu_rsp_abort(g_num_ports-1 downto 0), -- this is request from response receiving node
        rq_abort_i => rtu_rq_abort(g_num_ports-1 downto 0), -- this is request from requesting module
        ------ new TRU stuff ----------
        tru_req_o  => tru_req,
        tru_resp_i => tru_resp,
        rtu2tru_o  => rtu2tru,
        tru_enabled_i => tru_enabled,
        -------------------------------
        rmon_events_o => rtu_events,
        wb_i       => cnx_master_out(c_SLAVE_RTU),
        wb_o       => cnx_master_in(c_SLAVE_RTU));

    gen_TRU : if(g_with_TRU = true) generate
      U_TRU: xwrsw_tru
        generic map(     
          g_num_ports           => g_num_ports,
          g_tru_subentry_num    => 8,
          g_patternID_width     => 4,
          g_pattern_width       => g_num_ports,
          g_stableUP_treshold   => 100,
          g_pclass_number       => 8,
          g_mt_trans_max_fr_cnt => 1000,
          g_prio_width          => 3,
          g_pattern_mode_width  => 4,
          g_tru_entry_num       => 256,
          g_interface_mode      => PIPELINED,
          g_address_granularity => BYTE 
         )
        port map(
          clk_i               => clk_sys,
          rst_n_i             => rst_n_periph,
          req_i               => tru_req,
          resp_o              => tru_resp,
          rtu_i               => rtu2tru, 
          ep_i                => ep2tru,
          ep_o                => tru2ep,
          swc_block_oq_req_o  => swc2tru_req,
          enabled_o           => tru_enabled,
          wb_i                => cnx_master_out(c_SLAVE_TRU),
          wb_o                => cnx_master_in(c_SLAVE_TRU));

    end generate gen_TRU;    

    gen_no_TRU : if(g_with_TRU = false) generate
      swc2tru_req                    <= c_zero_gl_pause;
      tru2ep                         <= (others => c_tru2ep_zero);
      tru_resp                       <= c_tru_response_zero;
      tru_enabled                    <= '0';
      cnx_master_in(c_SLAVE_TRU).ack <= '1';
    end generate gen_no_TRU; 

    gen_TATSU: if(g_with_TATSU = true) generate
      U_TATSU:  xwrsw_tatsu
        generic map(     
          g_num_ports             => g_num_ports,
          g_simulation            => g_simulation,
          g_interface_mode        => PIPELINED,
          g_address_granularity   => BYTE
          )
        port map(
          clk_sys_i               => clk_sys,
          clk_ref_i               => clk_ref_i,
          rst_n_i                 => rst_n_sys,

          shaper_request_o        => shaper_request,
          shaper_drop_at_hp_ena_o => shaper_drop_at_hp_ena,
          tm_utc_i                => tm_utc,
          tm_cycles_i             => tm_cycles,
          tm_time_valid_i         => tm_time_valid,
          wb_i                    => cnx_master_out(c_SLAVE_TATSU),
          wb_o                    => cnx_master_in(c_SLAVE_TATSU)
        );

    end generate gen_TATSU;
    
    gen_no_TATSU: if(g_with_TATSU = false) generate
      shaper_request                            <= c_zero_gl_pause;
      shaper_drop_at_hp_ena                     <= '0';
      cnx_master_in(c_SLAVE_TATSU).ack          <= '1';
    end generate gen_no_TATSU;

  end generate gen_network_stuff;

  gen_no_network_stuff : if(g_without_network = true) generate
    gen_dummy_resets : for i in 0 to g_num_ports-1 generate
      phys_o(i).rst    <= not rst_n_periph;
      phys_o(i).loopen <= '0';
    end generate gen_dummy_resets;
  end generate gen_no_network_stuff;

  U_Tx_TSU : xwrsw_tx_tsu
    generic map (
      g_num_ports           => c_NUM_PORTS,
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE)
    port map (
      clk_sys_i        => clk_sys,
      rst_n_i          => rst_n_periph,
      timestamps_i     => txtsu_timestamps,
      timestamps_ack_o => txtsu_timestamps_ack,
      wb_i             => cnx_master_out(c_SLAVE_TXTSU),
      wb_o             => cnx_master_in(c_SLAVE_TXTSU));


  --TRIG2(15 downto 0) <= txtsu_timestamps(0).frame_id;
  --TRIG2(21 downto 16) <= txtsu_timestamps(0).port_id;
  --TRIG2(22) <= txtsu_timestamps(0).valid;
  
  U_GPIO : xwb_gpio_port
    generic map (
      g_interface_mode         => PIPELINED,
      g_address_granularity    => BYTE,
      g_num_pins               => c_NUM_GPIO_PINS,
      g_with_builtin_tristates => false)
    port map (
      clk_sys_i  => clk_sys,
      rst_n_i    => rst_n_periph,
      slave_i    => cnx_master_out(c_SLAVE_GPIO),
      slave_o    => cnx_master_in(c_SLAVE_GPIO),
      gpio_b     => dummy,
      gpio_out_o => gpio_out,
      gpio_in_i  => gpio_in);

  uart_sel_o <= gpio_out(0);


  gpio_o(0) <= gpio_out(0);
  gpio_in(0) <= gpio_i(0);

  U_MiniBackplane_I2C : xwb_i2c_master
    generic map (
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE,
      g_num_interfaces      => 3)
    port map (
      clk_sys_i    => clk_sys,
      rst_n_i      => rst_n_periph,
      slave_i      => cnx_master_out(c_SLAVE_I2C),
      slave_o      => cnx_master_in(c_SLAVE_I2C),
      desc_o       => open,
      scl_pad_i    => i2c_scl_i,
      scl_pad_o    => i2c_scl_o,
      scl_padoen_o => i2c_scl_oen_o,
      sda_pad_i    => i2c_sda_i,
      sda_pad_o    => i2c_sda_o,
      sda_padoen_o => i2c_sda_oen_o);

  --=====================================--
  --               PSTATS                --
  --=====================================--
  gen_PSTATS: if(g_with_PSTATS = true) generate
    U_PSTATS : xwrsw_pstats
      generic map(
        g_interface_mode      => PIPELINED,
        g_address_granularity => BYTE,
        g_nports => c_NUM_PORTS,
        g_cnt_pp => c_ALL_EVENTS,
        g_cnt_pw => 4)
      port map(
        rst_n_i => rst_n_periph,
        clk_i   => clk_sys,
  
        events_i => rmon_events,
  
        wb_i  => cnx_master_out(c_SLAVE_PSTATS),
        wb_o  => cnx_master_in(c_SLAVE_PSTATS));
 
  end generate;

  gen_no_PSTATS: if(g_with_PSTATS = false) generate
    cnx_master_in(c_SLAVE_PSTATS).ack <= '1';
    cnx_master_in(c_SLAVE_PSTATS).int <= '0';
  end generate;

  gen_events_assemble : for i in 0 to c_NUM_PORTS-1 generate
    rmon_events((i+1)*c_ALL_EVENTS-1 downto i*c_ALL_EVENTS) <= 
                std_logic(tru_resp.respMask(i) and tru_resp.valid)     &
                rtu_events((i+1)*c_RTU_EVENTS-1 downto i*c_RTU_EVENTS) &
                ep_events ((i+1)*c_epevents_sz-1 downto i*c_epevents_sz);
  end generate gen_events_assemble;

  --============================================================--
  -- Hardware Info Unit providing firmware version for software --
  --============================================================--

  gen_HWIU: if(g_with_HWIU = true) generate
    U_HWIU: xwrsw_hwiu
      generic map(
        g_interface_mode => PIPELINED,
        g_address_granularity => BYTE,
        g_ndbg_regs => c_DBG_N_REGS,
        g_ver_major => 4,
        g_ver_minor => 2,
        g_build     => 1)
      port map(
        rst_n_i       => rst_n_periph,
        clk_i         => clk_sys,
        dbg_regs_i    => dbg_n_regs,
        dbg_chps_id_o => dbg_chps_id,
        wb_i          => cnx_master_out(c_SLAVE_HWIU),
        wb_o          => cnx_master_in(c_SLAVE_HWIU));
  end generate;

  gen_no_HWIU: if(g_with_HWIU = false) generate
    cnx_master_in(c_SLAVE_HWIU).ack   <= '1';
    cnx_master_in(c_SLAVE_HWIU).dat   <= c_GW_VERSION;
    cnx_master_in(c_SLAVE_HWIU).err   <= '0';
    cnx_master_in(c_SLAVE_HWIU).stall <= '0';
    cnx_master_in(c_SLAVE_HWIU).rty   <= '0';
    dbg_chps_id                       <= (others =>'0');
  end generate;

  -----------------------------------------------------------------------------
  -- PWM Controlle for mini-backplane fan drive
  -----------------------------------------------------------------------------
  
  U_PWM_Controller : xwb_simple_pwm
    generic map (
      g_num_channels        => 2,
      g_regs_size           => 8,
      g_default_period      => 255,
      g_default_presc       => 30,
      g_default_val         => 255,
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE)
    port map (
      clk_sys_i => clk_sys,
      rst_n_i   => rst_n_periph,
      slave_i   => cnx_master_out(c_SLAVE_PWM),
      slave_o   => cnx_master_in(c_SLAVE_PWM),
      pwm_o(0)  => mb_fan1_pwm_o,
      pwm_o(1)  => mb_fan2_pwm_o);

  -----------------------------------------------------------------------------
  -- Interrupt assignment
  -----------------------------------------------------------------------------
  
  vic_irqs(0)           <= cnx_master_in(c_SLAVE_NIC).int;
  vic_irqs(1)           <= cnx_master_in(c_SLAVE_TXTSU).int;
  vic_irqs(2)           <= cnx_master_in(c_SLAVE_RTU).int;
  vic_irqs(3)           <= cnx_master_in(c_SLAVE_PSTATS).int;

-------------------------------------------------------------------------------
-- Various constant-driven I/Os
-------------------------------------------------------------------------------

  clk_en_o          <= '0';
  clk_sel_o         <= '0';
  clk_dmtd_divsel_o <= '1';             -- choose 62.5 MHz DDMTD clock
  clk_sys_o         <= clk_sys;

-------------------------------------------------------------------------------
-- Reset of the SW-Core in case something goes horribly wrong
-------------------------------------------------------------------------------
  GEN_SWC_RST: if(g_with_watchdog) generate
    WDOG: xwrsw_watchdog
      generic map(
        g_num_ports => g_num_ports+1)
      port map(
        rst_n_i => rst_n_periph,
        clk_i   => clk_sys,
        swc_nomem_i => swc_nomem,
        swc_fsms_i  => swc_wdog_out,

        swcrst_n_o  => rst_n_swc,
        epstop_o   => ep_stop_traffic,

        rtu_ack_i  => swc_rtu_ack,
        rtu_ack_o  => rtu_rsp_ack,

        snk_i => wrfreg_src_out,
        snk_o => wrfreg_src_in,
        src_o => swc_snk_in,
        src_i => swc_snk_out,
        wb_i  => cnx_master_out(c_SLAVE_WDOG),
        wb_o  => cnx_master_in(c_SLAVE_WDOG));
  end generate;

  GEN_NO_SWC_RST: if(not g_with_watchdog) generate
    ep_stop_traffic <= '0';
    rst_n_swc     <= rst_n_periph;
    rtu_rsp_ack   <= swc_rtu_ack;
    wrfreg_src_in <= swc_snk_out;
    swc_snk_in    <= wrfreg_src_out;
  end generate;

  gen_muxed_CS: if g_with_muxed_CS = true generate
    CS_ICON : chipscope_icon
     port map (
      CONTROL0 => CONTROL0);
    CS_ILA : chipscope_ila
     port map (
       CONTROL => CONTROL0,
       CLK     => clk_sys, --phys_i(0).rx_clk,
       TRIG0   => T0,
       TRIG1   => T1,
       TRIG2   => T2,
       TRIG3   => T3);
  
       T0   <= TRIG0(to_integer(unsigned(dbg_chps_id)));
       T1   <= TRIG1(to_integer(unsigned(dbg_chps_id)));
       T2   <= TRIG2(to_integer(unsigned(dbg_chps_id)));
       T3   <= TRIG3(to_integer(unsigned(dbg_chps_id)));
  end generate;
  
end rtl;
