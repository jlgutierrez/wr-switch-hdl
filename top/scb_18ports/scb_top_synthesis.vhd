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

    -- 250/10 MHz aux clock for Swcore/rephasing AD9516 in master mode
    -- (from the AD9516 PLL output QDRII_200CLK)
    fpga_clk_aux_p_i : in std_logic;
    fpga_clk_aux_n_i : in std_logic;

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


    -- DMTD clock divider selection (0 = 125 MHz, 1 = 62.5 MHz)
    clk_dmtd_divsel_o : out std_logic;

    -- UART source selection (FPGA/DBGU)
    -- uart_sel_o : out std_logic;

    ---------------------------------------------------------------------------
    -- GTX ports
    ---------------------------------------------------------------------------

    gtx0_3_clk_n_i : in std_logic;
    gtx0_3_clk_p_i : in std_logic;

    gtx4_7_clk_n_i : in std_logic;
    gtx4_7_clk_p_i : in std_logic;

    gtx8_11_clk_n_i : in std_logic;
    gtx8_11_clk_p_i : in std_logic;

    gtx12_15_clk_n_i : in std_logic;
    gtx12_15_clk_p_i : in std_logic;

    gtx16_19_clk_n_i : in std_logic;
    gtx16_19_clk_p_i : in std_logic;

    gtx_rxp_i : in std_logic_vector(17 downto 0);
    gtx_rxn_i : in std_logic_vector(17 downto 0);

    gtx_txp_o : out std_logic_vector(17 downto 0);
    gtx_txn_o : out std_logic_vector(17 downto 0);

    ---------------------------------------------------------------------------
    -- Mini-Backplane signals
    ---------------------------------------------------------------------------

    led_act_o : out std_logic_vector(17 downto 0);

    mbl_scl_b : inout std_logic_vector(1 downto 0);
    mbl_sda_b : inout std_logic_vector(1 downto 0);

    sensors_scl_b: inout std_logic;
    sensors_sda_b: inout std_logic;

    mb_fan1_pwm_o : out std_logic;
    mb_fan2_pwm_o : out std_logic
  );

end scb_top_synthesis;

architecture Behavioral of scb_top_synthesis is

  constant c_NUM_PHYS  : integer := 18;
  constant c_NUM_PORTS : integer := 18;

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



  signal clk_sys_startup                        : std_logic;
  signal clk_sys, clk_ref, clk_25mhz , clk_dmtd : std_logic;
  signal pllout_clk_fb                          : std_logic;

  attribute maxskew: string;
  attribute maxskew of clk_dmtd : signal is "0.5ns";

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


  signal to_phys   : t_phyif_output_array(c_NUM_PHYS-1 downto 0);
  signal from_phys : t_phyif_input_array(c_NUM_PHYS-1 downto 0);

  signal clk_aux      : std_logic;
  signal clk_gtx0_3   : std_logic;
  signal clk_gtx4_7   : std_logic;
  signal clk_gtx8_11  : std_logic;
  signal clk_gtx12_15 : std_logic;
  signal clk_gtx16_19 : std_logic;

  signal clk_gtx : std_logic_vector(c_NUM_PHYS-1 downto 0);

  signal cpu_nwait_int : std_logic;

  signal top_master_in, bridge_master_in   : t_wishbone_master_in;
  signal top_master_out, bridge_master_out : t_wishbone_master_out;

  signal i2c_scl_oen : std_logic_vector(2 downto 0);
  signal i2c_scl_out : std_logic_vector(2 downto 0);
  signal i2c_sda_oen : std_logic_vector(2 downto 0);
  signal i2c_sda_out : std_logic_vector(2 downto 0);
  signal i2c_sda_in : std_logic_vector(2 downto 0);
  signal i2c_scl_in : std_logic_vector(2 downto 0);
  component scb_top_bare
    generic (
      g_num_ports       : integer;
      g_simulation      : boolean;
      g_without_network : boolean;
      g_with_TRU        : boolean;
      g_with_TATSU      : boolean;
      g_with_HWDU       : boolean);
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
--    uart_sel_o          : out std_logic;
      clk_dmtd_divsel_o   : out std_logic;
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
      i2c_sda_i       : in  std_logic_vector(2 downto 0) := "111";
      mb_fan1_pwm_o   : out std_logic;
      mb_fan2_pwm_o   : out std_logic
      );
  end component;

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

  signal CONTROL : std_logic_vector(35 downto 0);
  signal TRIG0   : std_logic_vector(31 downto 0);
  signal TRIG1   : std_logic_vector(31 downto 0);
  signal TRIG2   : std_logic_vector(31 downto 0);
  signal TRIG3   : std_logic_vector(31 downto 0);
begin


  --chipscope_icon_1 : chipscope_icon
  --  port map (
  --    CONTROL0 => CONTROL);

  --chipscope_ila_1 : chipscope_ila
  --  port map (
  --    CONTROL => CONTROL,
  --    CLK     => clk_25mhz,
  --    TRIG0   => TRIG0,
  --    TRIG1   => TRIG1,
  --    TRIG2   => TRIG2,
  --    TRIG3   => TRIG3);

  --TRIG0(0) <= mbl_scl_b(0);
  --TRIG0(1) <= mbl_sda_b(0);
  --TRIG0(2) <= mbl_scl_b(1);
  --TRIG0(3) <= mbl_sda_b(1);
  --TRIG1                              <= cpu_data_b;
  --TRIG2(0)                           <= cpu_cs_n_i;
  --TRIG2(1)                           <= cpu_rd_n_i;
  --TRIG2(2)                           <= cpu_wr_n_i;
  --TRIG2(3) <= sys_rst_n_i;


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

  U_Clk_Buf_GTX8_11 : IBUFDS_GTXE1
    port map
    (
      O     => clk_gtx8_11,
      ODIV2 => open,
      CEB   => '0',
      I     => gtx8_11_clk_p_i,
      IB    => gtx8_11_clk_n_i
      );

  U_Clk_Buf_GTX12_15 : IBUFDS_GTXE1
    port map
    (
      O     => clk_gtx12_15,
      ODIV2 => open,
      CEB   => '0',
      I     => gtx12_15_clk_p_i,
      IB    => gtx12_15_clk_n_i
      );

  U_Clk_Buf_GTX16_19 : IBUFDS_GTXE1
    port map
    (
      O     => clk_gtx16_19,
      ODIV2 => open,
      CEB   => '0',
      I     => gtx16_19_clk_p_i,
      IB    => gtx16_19_clk_n_i
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
      O  => clk_aux,
      I  => fpga_clk_aux_p_i,
      IB => fpga_clk_aux_n_i);


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
      clk_sys_i => clk_sys,
      rst_n_i   => sys_rst_n_i,
      slave_i   => bridge_master_out,
      slave_o   => bridge_master_in,
      master_i  => top_master_in,
      master_o  => top_master_out);

  cpu_nwait_o <= cpu_nwait_int;


-------------------------------------------------------------------------------
-- GTX PHYs
-------------------------------------------------------------------------------  

  clk_gtx(1 downto 0) <= (others => clk_gtx16_19);
  clk_gtx(5 downto 2) <= (others => clk_gtx12_15);
  clk_gtx(9 downto 6)   <= (others => clk_gtx8_11);
  clk_gtx(13 downto 10)  <= (others => clk_gtx4_7);
  clk_gtx(17 downto 14) <= (others => clk_gtx0_3);

  gen_phys : for i in 0 to c_NUM_PHYS-1 generate

    U_PHY : wr_gtx_phy_virtex6
      generic map (
        g_simulation         => f_bool2int(g_simulation),
        g_use_slave_tx_clock => f_bool2int(i /= (i/4)*4))
      port map (
        clk_gtx_i => clk_gtx(i),
        clk_ref_i => clk_ref,

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

    from_phys(i).ref_clk <= clk_ref;
  end generate gen_phys;

  gen_terminate_unused_phys : for i in c_NUM_PORTS to c_NUM_PHYS-1 generate
    to_phys(i).tx_data <= (others => '0');
    to_phys(i).tx_k    <= (others => '0');
    to_phys(i).rst     <= '1';
    to_phys(i).loopen  <= '0';
    led_act_o(i)       <= '0';
  end generate gen_terminate_unused_phys;



  -----------------------------------------------------------------------------
  -- "Bare" top module instantiation
  -----------------------------------------------------------------------------

  U_Real_Top : scb_top_bare
    generic map (
      g_num_ports       => c_NUM_PORTS,
      g_simulation      => g_simulation,
      g_without_network => false,
      g_with_TRU        => true,
      g_with_TATSU      => true,
      g_with_HWDU       => true)
    port map (
      sys_rst_n_i         => sys_rst_n_i,
      clk_startup_i       => clk_sys_startup,
      clk_ref_i           => clk_ref,
      clk_dmtd_i          => clk_dmtd,
      clk_sys_o           => clk_sys,
      clk_aux_i           => clk_aux,
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
--    uart_sel_o          => uart_sel_o,
      clk_dmtd_divsel_o   => clk_dmtd_divsel_o,
      gpio_i              => x"00000000",
      phys_o              => to_phys(c_NUM_PORTS-1 downto 0),
      phys_i              => from_phys(c_NUM_PORTS-1 downto 0),
--      led_link_o          => led_link_o,
      led_act_o           => led_act_o(c_NUM_PORTS-1 downto 0),
      i2c_scl_oen_o   => i2c_scl_oen,
      i2c_scl_o       => i2c_scl_out,
      i2c_scl_i       => i2c_scl_in,
      i2c_sda_oen_o   => i2c_sda_oen,
      i2c_sda_o       => i2c_sda_out,
      i2c_sda_i       => i2c_sda_in,
      mb_fan1_pwm_o   => mb_fan1_pwm_o,
      mb_fan2_pwm_o   => mb_fan2_pwm_o);

  i2c_scl_in(1 downto 0) <= mbl_scl_b(1 downto 0);
  i2c_sda_in(1 downto 0) <= mbl_sda_b(1 downto 0);

  i2c_scl_in(2) <= sensors_scl_b;
  i2c_sda_in(2) <= sensors_sda_b;
  
  gen_i2c_tribufs : for i in 0 to 1 generate
    mbl_scl_b(i) <= i2c_scl_out(i) when i2c_scl_oen(i) = '0' else 'Z';
    mbl_sda_b(i) <= i2c_sda_out(i) when i2c_sda_oen(i) = '0' else 'Z';
  end generate gen_i2c_tribufs;

  sensors_scl_b <= i2c_scl_out(2) when i2c_scl_oen(2) = '0' else 'Z';
  sensors_sda_b <= i2c_sda_out(2) when i2c_sda_oen(2) = '0' else 'Z';


end Behavioral;


