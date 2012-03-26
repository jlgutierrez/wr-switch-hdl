-- LM32 + SoftPLL + some memory + debug UART


library ieee;
use ieee.std_logic_1164.all;

use work.gencores_pkg.all;
use work.wishbone_pkg.all;


entity wrsw_rt_subsystem is
  
  generic (
    g_num_rx_clocks : integer);

  port(
    clk_ref_i  : in std_logic;
    clk_sys_i  : in std_logic;
    clk_dmtd_i : in std_logic;
    clk_rx_i   : in std_logic_vector(g_num_rx_clocks-1 downto 0);
    clk_aux_i  : in std_logic;

    rst_n_i : in  std_logic;
    rst_n_o : out std_logic;

    wb_i : in  t_wishbone_slave_in;
    wb_o : out t_wishbone_slave_out;

    -- DAC Drive
    dac_helper_sync_n_o : out std_logic;
    dac_helper_sclk_o   : out std_logic;
    dac_helper_data_o   : out std_logic;

    dac_main_sync_n_o : out std_logic;
    dac_main_sclk_o   : out std_logic;
    dac_main_data_o   : out std_logic;

    -- Debug UART
    uart_txd_o : out std_logic;
    uart_rxd_i : in  std_logic;

    pps_p_o : out std_logic;            -- cleaned-up, retimed PPS for use in
                                        -- the rest of the switch

    pps_raw_i : in std_logic;           -- raw PPS input (from the front panel)

    sel_clk_sys_o : out std_logic;      -- system clock selection: 0 = startup
                                        -- clock, 1 = PLL clock

    -- AD9516 signals
    pll_status_i  : in  std_logic;
    pll_mosi_o    : out std_logic;
    pll_miso_i    : in  std_logic;
    pll_sck_o     : out std_logic;
    pll_cs_n_o    : out std_logic;
    pll_sync_n_o  : out std_logic;
    pll_reset_n_o : out std_logic
    );
end wrsw_rt_subsystem;

architecture rtl of wrsw_rt_subsystem is

  component xwr_softpll_ng
    generic (
      g_tag_bits                 : integer;
      g_interface_mode           : t_wishbone_interface_mode;
      g_address_granularity      : t_wishbone_address_granularity;
      g_num_ref_inputs           : integer;
      g_num_outputs              : integer;
     	g_with_debug_fifo: boolean := true

      );
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
      slave_i         : in  t_wishbone_slave_in;
      slave_o         : out t_wishbone_slave_out;
      debug_o         : out std_logic_vector(3 downto 0));
  end component;

  constant c_NUM_GPIO_PINS : integer := 32;

  signal cnx_slave_in   : t_wishbone_slave_in_array(1 downto 0);
  signal cnx_slave_out  : t_wishbone_slave_out_array(1 downto 0);
  signal cnx_master_in  : t_wishbone_master_in_array(5 downto 0);
  signal cnx_master_out : t_wishbone_master_out_array(5 downto 0);

  signal cpu_iwb_out : t_wishbone_master_out;
  signal cpu_iwb_in  : t_wishbone_master_in;

  signal cpu_irq_vec : std_logic_vector(31 downto 0);
  signal cpu_reset_n : std_logic;

  signal dummy             : std_logic_vector(63 downto 0);
  signal gpio_out, gpio_in : std_logic_vector(c_NUM_GPIO_PINS-1 downto 0);

  signal dac_out_data, dac_dmtd_data : std_logic_vector(15 downto 0);
  signal dac_out_load, dac_dmtd_load : std_logic;


  constant c_cnx_base_addr : t_wishbone_address_array(5 downto 0) :=
    (x"00010400", x"00010300", x"00010200", x"00010100", x"00010000", x"00000000");

  constant c_cnx_base_mask : t_wishbone_address_array(5 downto 0) :=
    (x"000fff00", x"000fff00", x"000fff00", x"000fff00", x"000fff00", x"000f0000");

  alias clk_ref_10m is pll_status_i;
  signal clk_rx_vec : std_logic_vector(g_num_rx_clocks+1 downto 0);

  function f_mask_single_bit(index : integer; size : integer) return std_logic_vector is
    variable tmp : std_logic_vector(size-1 downto 0);
  begin
    tmp        := (others => '1');
    tmp(index) := '0';
    return tmp;
  end f_mask_single_bit;

begin  -- rtl

  clk_rx_vec(g_num_rx_clocks-1 downto 0) <= clk_rx_i;
  clk_rx_vec(g_num_rx_clocks)   <= clk_ref_10m;
  clk_rx_vec(g_num_rx_clocks+1) <= clk_aux_i;

-- interconnect layout:
-- 0x00000 - 0x10000: RAM
-- 0x10000 - 0x10100: UART
-- 0x10100 - 0x10200: SoftPLL
-- 0x10200 - 0x10300: SPI master (to PLL)
-- 0x10300 - 0x10400: GPIO
-- 0x10400 - 0x10500: Timer

  cnx_slave_in(0) <= wb_i;
  wb_o            <= cnx_slave_out(0);

  U_Intercon : xwb_crossbar
    generic map (
      g_num_masters => 2,
      g_num_slaves  => 6,
      g_registered  => true)
    port map (
      clk_sys_i     => clk_sys_i,
      rst_n_i       => rst_n_i,
      slave_i       => cnx_slave_in,
      slave_o       => cnx_slave_out,
      master_i      => cnx_master_in,
      master_o      => cnx_master_out,
      cfg_address_i => c_cnx_base_addr,
      cfg_mask_i    => c_cnx_base_mask);

  U_CPU : xwb_lm32
    generic map (
      g_profile => "medium")
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
      slave1_i  => cnx_master_out(0),
      slave1_o  => cnx_master_in(0),
      slave2_i  => cpu_iwb_out,
      slave2_o  => cpu_iwb_in);

  U_UART : xwb_simple_uart
    generic map (
      g_with_virtual_uart   => false,
      g_with_physical_uart  => true,
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE)
    port map (
      clk_sys_i  => clk_sys_i,
      rst_n_i    => rst_n_i,
      slave_i    => cnx_master_out(1),
      slave_o    => cnx_master_in(1),
      desc_o     => open,
      uart_rxd_i => uart_rxd_i,
      uart_txd_o => uart_txd_o);


  U_SoftPLL : xwr_softpll_ng
    generic map (
      g_tag_bits                 => 22,
      g_interface_mode           => PIPELINED,
      g_address_granularity      => BYTE,
      g_num_ref_inputs           => g_num_rx_clocks + 2,
      g_num_outputs              => 1)
    port map (
      clk_sys_i       => clk_sys_i,
      rst_n_i         => rst_n_i,
      clk_ref_i       => clk_rx_vec,
      clk_fb_i(0)     => clk_ref_i,
      clk_dmtd_i      => clk_dmtd_i,
      dac_dmtd_data_o => dac_dmtd_data,
      dac_dmtd_load_o => dac_dmtd_load,
      dac_out_data_o  => dac_out_data,
      dac_out_sel_o   => open,
      dac_out_load_o  => dac_out_load,
      out_enable_i    => "0",
      out_locked_o    => open,
      slave_i         => cnx_master_out(2),
      slave_o         => cnx_master_in(2),
      debug_o         => open);

  cpu_irq_vec(0)           <= cnx_master_in(2).int;
  cpu_irq_vec(31 downto 1) <= (others => '0');

  U_SPI_Master : xwb_spi
    generic map (
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE)
    port map (
      clk_sys_i            => clk_sys_i,
      rst_n_i              => rst_n_i,
      slave_i              => cnx_master_out(3),
      slave_o              => cnx_master_in(3),
      desc_o               => open,
      pad_cs_o(0)          => pll_cs_n_o,
      pad_cs_o(7 downto 1) => dummy(7 downto 1),
      pad_sclk_o           => pll_sck_o,
      pad_mosi_o           => pll_mosi_o,
      pad_miso_i           => pll_miso_i);

  U_GPIO : xwb_gpio_port
    generic map (
      g_interface_mode         => PIPELINED,
      g_address_granularity    => BYTE,
      g_num_pins               => 32,
      g_with_builtin_tristates => false)
    port map (
      clk_sys_i  => clk_sys_i,
      rst_n_i    => rst_n_i,
      slave_i    => cnx_master_out(4),
      slave_o    => cnx_master_in(4),
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
      slave_i   => cnx_master_out(5),
      slave_o   => cnx_master_in(5),
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

