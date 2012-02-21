library ieee;
use ieee.STD_LOGIC_1164.all;
use ieee.numeric_std.all;

use work.wishbone_pkg.all;
use work.gencores_pkg.all;
use work.wr_fabric_pkg.all;
use work.endpoint_pkg.all;
use work.wrsw_txtsu_pkg.all;
use work.wrsw_top_pkg.all;


library UNISIM;
use UNISIM.vcomponents.all;


entity scb_top_synthesis is
  generic(
    g_cpu_addr_width : integer := 19;
    g_num_ports      : integer := 6;
    g_simulation     : boolean := false
    );
  port (
    sys_rst_n_i : in std_logic;         -- global reset

    -- Startup 25 MHz clock (from onboard 25 MHz oscillator)
    fpga_clk_25mhz_p_i : in std_logic;
    fpga_clk_25mhz_n_i : in std_logic;

    -- 125 MHz timing reference (from the AD9516 PLL output QDRII_CLK)
    fpga_clk_ref_p_i : in std_logic;
    fpga_clk_ref_n_i : in std_logic;

    -- 125+ MHz DMTD offset clock (from the CDCM62001 PLL output DMTDCLK_MAIN)
    fpga_clk_dmtd_p_i : in std_logic;
    fpga_clk_dmtd_n_i : in std_logic;

    -- 62.5 MHz system clock (from the AD9516 PLL output QDRII_200CLK)
    fpga_clk_sys_p_i : in std_logic;
    fpga_clk_sys_n_i : in std_logic;

    -------------------------------------------------------------------------------
    -- Atmel EBI bus
    -------------------------------------------------------------------------------
    cpu_clk_i   : in    std_logic;      -- clock (not used now)
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

    gtx0_3_clk_n_i : in std_logic;
    gtx0_3_clk_p_i : in std_logic;

    gtx4_7_clk_n_i : in std_logic;
    gtx4_7_clk_p_i : in std_logic;

    gtx_rxp_i : in std_logic_vector(g_num_ports-1 downto 0);
    gtx_rxn_i : in std_logic_vector(g_num_ports-1 downto 0);

    gtx_txp_o        : out std_logic_vector(g_num_ports-1 downto 0);
    gtx_txn_o        : out std_logic_vector(g_num_ports-1 downto 0);
    gtx_sfp_tx_dis_o : out std_logic_vector(g_num_ports-1 downto 0);

    led_link_o : out std_logic_vector(g_num_ports-1 downto 0);
    led_act_o  : out std_logic_vector(g_num_ports-1 downto 0)
    );
end scb_top_synthesis;

architecture Behavioral of scb_top_synthesis is

  constant c_MAX_PORTS : integer := 18;


  function f_bool2int(x : boolean) return integer is
  begin
    if(x) then
      return 1;
    else
      return 0;
    end if;
  end f_bool2int;


  -------------------------------------------------------------------------------
  -- Clocks
  -------------------------------------------------------------------------------

  signal clk_sys_startup, clk_sys_pll           : std_logic;
  signal clk_sys, clk_ref, clk_25mhz , clk_dmtd : std_logic;
  signal pllout_clk_fb                          : std_logic;


  -----------------------------------------------------------------------------
  -- Component declarations
  -----------------------------------------------------------------------------

  component IBUFGDS
    generic (
      DIFF_TERM  : boolean := true;
      IOSTANDARD : string  := "DEFAULT")  ;
    port (
      O  : out std_ulogic;
      I  : in  std_ulogic;
      IB : in  std_ulogic);
  end component;

  component BUFGMUX
    generic (
      CLK_SEL_TYPE : string := "SYNC");
    port (
      O  : out std_ulogic := '0';
      I0 : in  std_ulogic := '0';
      I1 : in  std_ulogic := '0';
      S  : in  std_ulogic := '0');
  end component;

  component scb_top_bare
    generic (
      g_num_ports  : integer;
      g_simulation : boolean);
    port (
      sys_rst_n_i         : in  std_logic;
      clk_startup_i       : in  std_logic;
      clk_ref_i           : in  std_logic;
      clk_dmtd_i          : in  std_logic;
      clk_sys_i           : in  std_logic;
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
      led_act_o           : out std_logic_vector(g_num_ports-1 downto 0));
  end component;

  signal to_phys   : t_phyif_output_array(g_num_ports-1 downto 0);
  signal from_phys : t_phyif_input_array(g_num_ports-1 downto 0);

  signal clk_gtx0_3 : std_logic;
  signal clk_gtx4_7 : std_logic;
  signal clk_gtx    : std_logic_vector(c_MAX_PORTS-1 downto 0);

  signal cpu_nwait_int : std_logic;

  signal top_master_in, bridge_master_in   : t_wishbone_master_in;
  signal top_master_out, bridge_master_out : t_wishbone_master_out;
  
begin

  U_Clk_Buf_GTX0_3 : IBUFDS_GTXE1
    port map
    (
      O     => clk_gtx0_3,
      ODIV2 => open,
      CEB   => '0',
      I     => gtx0_3_clk_p_i,
      IB    => gtx0_3_clk_n_i
      );

  U_Clk_Buf_GTX4_7 : IBUFDS_GTXE1
    port map
    (
      O     => clk_gtx4_7,
      ODIV2 => open,
      CEB   => '0',
      I     => gtx4_7_clk_p_i,
      IB    => gtx4_7_clk_n_i
      );

  U_Buf_CLK_Startup : IBUFGDS
    generic map (
      DIFF_TERM  => true,
      IOSTANDARD => "LVDS_25")
    port map (
      O  => clk_25mhz,
      I  => fpga_clk_25mhz_p_i,
      IB => fpga_clk_25mhz_n_i);

  U_Buf_CLK_Ref : IBUFGDS
    generic map (
      DIFF_TERM  => true,
      IOSTANDARD => "LVDS_25")
    port map (
      O  => clk_ref,
      I  => fpga_clk_ref_p_i,
      IB => fpga_clk_ref_n_i);

  U_Buf_CLK_Sys : IBUFGDS
    generic map (
      DIFF_TERM  => true,
      IOSTANDARD => "LVDS_25")
    port map (
      O  => clk_sys_pll,
      I  => fpga_clk_sys_p_i,
      IB => fpga_clk_sys_n_i);


  U_Buf_CLK_DMTD : IBUFGDS
    generic map (
      DIFF_TERM  => true,
      IOSTANDARD => "LVDS_25")
    port map (
      O  => clk_dmtd,
      I  => fpga_clk_dmtd_p_i,
      IB => fpga_clk_dmtd_n_i);

  
  U_SYS_PLL : PLL_BASE
    generic map (
      BANDWIDTH          => "OPTIMIZED",
      CLK_FEEDBACK       => "CLKFBOUT",
      COMPENSATION       => "INTERNAL",
      DIVCLK_DIVIDE      => 1,
      CLKFBOUT_MULT      => 40,
      CLKFBOUT_PHASE     => 0.000,
      CLKOUT0_DIVIDE     => 16,         -- 62.5 MHz
      CLKOUT0_PHASE      => 0.000,
      CLKOUT0_DUTY_CYCLE => 0.500,
      CLKOUT1_DIVIDE     => 16,         -- 62.5 MHz
      CLKOUT1_PHASE      => 0.000,
      CLKOUT1_DUTY_CYCLE => 0.500,
      CLKOUT2_DIVIDE     => 8,
      CLKOUT2_PHASE      => 0.000,
      CLKOUT2_DUTY_CYCLE => 0.500,
      CLKIN_PERIOD       => 40.0,
      REF_JITTER         => 0.016)
    port map (
      CLKFBOUT => pllout_clk_fb,
      CLKOUT0  => clk_sys_startup,
      CLKOUT1  => open,
      CLKOUT2  => open,
      CLKOUT3  => open,
      CLKOUT4  => open,
      CLKOUT5  => open,
      LOCKED   => open,
      RST      => '0',
      CLKFBIN  => pllout_clk_fb,
      CLKIN    => clk_25mhz);


  ------------------------------------------------    
  cmp_wb_cpu_bridge : wb_cpu_bridge
    --generic map(
    --)
    port map(
      sys_rst_n_i => sys_rst_n_i,

      -- Atmel EBI bus
      cpu_clk_i   => cpu_clk_i,
      cpu_cs_n_i  => cpu_cs_n_i,
      cpu_wr_n_i  => cpu_wr_n_i,
      cpu_rd_n_i  => cpu_rd_n_i,
      cpu_bs_n_i  => "1111",
      cpu_addr_i  => cpu_addr_i,
      cpu_data_b  => cpu_data_b,
      cpu_nwait_o => cpu_nwait_int,

      wb_clk_i  => clk_sys,
      wb_addr_o => bridge_master_out.adr(18 downto 0),
      wb_data_o => bridge_master_out.dat,
      wb_stb_o  => bridge_master_out.stb,
      wb_we_o   => bridge_master_out.we,
      wb_sel_o  => bridge_master_out.sel,
      wb_cyc_o  => bridge_master_out.cyc,
      wb_data_i => bridge_master_in.dat,
      wb_ack_i  => bridge_master_in.ack
      );

  bridge_master_out.adr(31 downto 19) <= (others => '0');

  U_Bridge_to_pipelined : wb_slave_adapter
    generic map (
      g_master_use_struct  => true,
      g_master_mode        => PIPELINED,
      g_master_granularity => BYTE,
      g_slave_use_struct   => true,
      g_slave_mode         => CLASSIC,
      g_slave_granularity  => WORD)
    port map (
      clk_sys_i => clk_sys_pll,
      rst_n_i   => sys_rst_n_i,
      slave_i   => bridge_master_out,
      slave_o   => bridge_master_in,
      master_i  => top_master_in,
      master_o  => top_master_out);

  cpu_nwait_o <= cpu_nwait_int;


-------------------------------------------------------------------------------
-- GTX PHYs
-------------------------------------------------------------------------------  

  clk_gtx(3 downto 0) <= (others => clk_gtx0_3);
  clk_gtx(7 downto 4) <= (others => clk_gtx4_7);

  gen_phys : for i in 0 to g_num_ports-1 generate

    U_PHY : wr_gtx_phy_virtex6
      generic map (
        g_simulation         => f_bool2int(g_simulation),
        g_use_slave_tx_clock => f_bool2int(i /= (i/4)*4))
      port map (
        clk_ref_i => clk_gtx(i),

        tx_clk_i       => from_phys((i / 4) * 4).ref_clk,
        tx_clk_o       => from_phys(i).ref_clk,
        tx_data_i      => to_phys(i).tx_data,
        tx_k_i         => to_phys(i).tx_k,
        tx_disparity_o => from_phys(i).tx_disparity,
        tx_enc_err_o   => from_phys(i).tx_enc_err,
        rx_rbclk_o     => from_phys(i).rx_clk,
        rx_data_o      => from_phys(i).rx_data,
        rx_k_o         => from_phys(i).rx_k,
        rx_enc_err_o   => from_phys(i).rx_enc_err,
        rx_bitslide_o  => from_phys(i).rx_bitslide,
        rst_i          => to_phys(i).rst,
        loopen_i       => to_phys(i).loopen,
        pad_txn_o      => gtx_txn_o(i),
        pad_txp_o      => gtx_txp_o(i),
        pad_rxn_i      => gtx_rxn_i(i),
        pad_rxp_i      => gtx_rxp_i(i));

  end generate gen_phys;


  -----------------------------------------------------------------------------
  -- "Bare" top module instantiation
  -----------------------------------------------------------------------------

  U_Real_Top : scb_top_bare
    generic map (
      g_num_ports  => g_num_ports,
      g_simulation => g_simulation)
    port map (
      sys_rst_n_i         => sys_rst_n_i,
      clk_startup_i       => clk_sys_startup,
      clk_ref_i           => clk_ref,
      clk_dmtd_i          => clk_dmtd,
      clk_sys_i           => clk_sys_pll,
      clk_sys_o           => clk_sys,
      cpu_wb_i            => top_master_out,
      cpu_wb_o            => top_master_in,
      cpu_irq_n_o         => cpu_irq_n_o,
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
      phys_o              => to_phys,
      phys_i              => from_phys,
      led_link_o          => led_link_o,
      led_act_o           => led_act_o);

  gtx_sfp_tx_dis_o <= (others => '1');


end Behavioral;


