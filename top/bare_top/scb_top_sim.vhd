library ieee;
use ieee.STD_LOGIC_1164.all;

use work.wishbone_pkg.all;
use work.wrsw_top_pkg.all;
use work.disparity_gen_pkg.all;

entity scb_top_sim is
  generic(
    g_num_ports : integer := 6
    );
  port (

    sys_rst_n_i : in std_logic;         -- global reset

    -- Startup 25 MHz clock (from onboard 25 MHz oscillator)
    clk_startup_i : in std_logic;

    -- 125 MHz timing reference (from the AD9516 PLL output QDRII_CLK)
    clk_ref_i : in std_logic;

    -- 125+ MHz DMTD offset clock (from the CDCM62001 PLL output DMTDCLK_MAIN)
    clk_dmtd_i : in std_logic;

    -- 62.5 MHz system clock (from the AD9516 PLL output QDRII_200CLK)
    clk_sys_i : in std_logic;

    -- 200MHz clock to run the core of Multiport Memory in SWcore
    clk_swc_mpm_core_i : in std_logic;
    -------------------------------------------------------------------------------
    -- Master wishbone bus (from the CPU bridge)
    -------------------------------------------------------------------------------

    wb_adr_i   : in  std_logic_vector(c_wishbone_address_width-1 downto 0);
    wb_dat_i   : in  std_logic_vector(31 downto 0);
    wb_dat_o   : out std_logic_vector(31 downto 0);
    wb_cyc_i   : in  std_logic;
    wb_sel_i   : in  std_logic_vector(3 downto 0);
    wb_stb_i   : in  std_logic;
    wb_we_i    : in  std_logic;
    wb_ack_o   : out std_logic;
    wb_stall_o : out std_logic;
    wb_irq_o   : out std_logic;

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
    dac_main_sclk_o   : out std_logic;
    dac_main_data_o   : out std_logic;

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
    -- Clock fanout control
    -------------------------------------------------------------------------------
    clk_en_o  : out std_logic;
    clk_sel_o : out std_logic;

    ---------------------------------------------------------------------------
    -- GTX ports
    ---------------------------------------------------------------------------

    td_o    : out std_logic_vector(18 * g_num_ports-1 downto 0);
    rd_i    : in  std_logic_vector(18 * g_num_ports-1 downto 0);
    rbclk_i : in  std_logic_vector(g_num_ports-1 downto 0);


    led_link_o : out std_logic_vector(g_num_ports-1 downto 0);
    led_act_o  : out std_logic_vector(g_num_ports-1 downto 0)
    );

end scb_top_sim;

architecture rtl of scb_top_sim is

  type t_8b10b_disparity_array is array (integer range <>) of t_8b10b_disparity;
  
  signal cur_disp : t_8b10b_disparity_array(g_num_ports-1 downto 0);
  signal cpu_wb_in : t_wishbone_slave_in;
  signal cpu_wb_out  : t_wishbone_slave_out;
  signal phys_out   : t_phyif_output_array(g_num_ports-1 downto 0);
  signal phys_in    : t_phyif_input_array(g_num_ports-1 downto 0);
  signal cpu_irq_n : std_logic;
begin  -- rtl

  cpu_wb_in.adr <= wb_adr_i;
  cpu_wb_in.dat <= wb_dat_i;
  cpu_wb_in.cyc <= wb_cyc_i;
  cpu_wb_in.sel <= wb_sel_i;
  cpu_wb_in.we  <= wb_we_i;
  cpu_wb_in.stb <= wb_stb_i;
  wb_ack_o      <= cpu_wb_out.ack;
  wb_stall_o    <= cpu_wb_out.stall;
  wb_irq_o      <= not cpu_irq_n;
  wb_dat_o <= cpu_wb_out.dat;

  U_Wrapped_SCBCore : scb_top_bare
    generic map (
      g_num_ports  => g_num_ports,
      g_simulation => true)
    port map (
      sys_rst_n_i         => sys_rst_n_i,
      clk_startup_i       => clk_startup_i,
      clk_ref_i           => clk_ref_i,
      clk_dmtd_i          => clk_dmtd_i,
      clk_sys_i           => clk_sys_i,
      clk_swc_mpm_core_i  => clk_swc_mpm_core_i,
      cpu_wb_i            => cpu_wb_in,
      cpu_wb_o            => cpu_wb_out,
      cpu_irq_n_o         => cpu_irq_n,
      pps_i               => pps_i,
      pps_o               => pps_o,
      dac_helper_sync_n_o => dac_helper_sync_n_o,
      dac_helper_sclk_o   => dac_helper_sclk_o,
      dac_helper_data_o   => dac_helper_data_o,
      dac_main_sync_n_o   => dac_main_sync_n_o,
      dac_main_sclk_o     => dac_main_sclk_o,
      dac_main_data_o     => dac_main_data_o,
      pll_status_i        => pll_status_i,
      pll_mosi_o          => pll_mosi_o,
      pll_miso_i          => pll_miso_i,
      pll_sck_o           => pll_sck_o,
      pll_cs_n_o          => pll_cs_n_o,
      pll_sync_n_o        => pll_sync_n_o,
      pll_reset_n_o       => pll_reset_n_o,
      uart_txd_o          => uart_txd_o,
      uart_rxd_i          => uart_rxd_i,
      clk_en_o            => clk_en_o,
      clk_sel_o           => clk_sel_o,
      phys_o              => phys_out,
      phys_i              => phys_in,
      led_link_o          => led_link_o,
      led_act_o           => led_act_o,
      gpio_o              => open,
      gpio_i              => (others => '0')
      );

  gen_phys : for i in 0 to g_num_ports-1 generate
    td_o(18 * i + 15 downto 18 * i)      <= phys_out(i).tx_data;
    td_o(18 * i + 17 downto 18 * i + 16) <= phys_out(i).tx_k;

    phys_in(i).ref_clk    <= clk_ref_i;
    phys_in(i).rx_data    <= rd_i(18 * i + 15 downto 18 * i);
    phys_in(i).rx_k       <= rd_i(18 * i + 17 downto 18 * i + 16);
    phys_in(i).rx_clk     <= rbclk_i(i);
    phys_in(i).tx_enc_err <= '0';
    phys_in(i).rx_enc_err <= '0';


    p_gen_tx_disparity : process(clk_ref_i)
    begin
      if rising_edge(clk_ref_i) then
        if phys_out(i).rst = '1' then
          cur_disp(i) <= RD_MINUS;
        else
          cur_disp(i) <= f_next_8b10b_disparity16(cur_disp(i), phys_out(i).tx_k, phys_out(i).tx_data);
        end if;
      end if;
    end process;

    phys_in(i).tx_disparity <= to_std_logic(cur_disp(i));
    

  end generate gen_phys;
  
end rtl;

