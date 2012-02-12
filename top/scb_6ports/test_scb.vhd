library ieee;
use ieee.STD_LOGIC_1164.all;
use ieee.numeric_std.all;

use work.wishbone_pkg.all;
use work.gencores_pkg.all;
use work.wr_fabric_pkg.all;
use work.endpoint_pkg.all;
use work.wrsw_txtsu_pkg.all;
use work.wrsw_components_pkg.all;


library UNISIM;
use UNISIM.vcomponents.all;


entity test_scb is
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
end test_scb;

architecture Behavioral of test_scb is

  constant c_NUM_WB_SLAVES : integer := 6;
  constant c_NUM_PORTS     : integer := g_num_ports;
  constant c_MAX_PORTS     : integer := 18;


  type t_phy_interface is record
    rst          : std_logic;
    loopen       : std_logic;
    enable       : std_logic;
    syncen       : std_logic;
    ref_clk      : std_logic;
    tx_data      : std_logic_vector(15 downto 0);
    tx_k         : std_logic_vector(1 downto 0);
    tx_disparity : std_logic;
    tx_enc_err   : std_logic;
    rx_data      : std_logic_vector(15 downto 0);
    rx_clk       : std_logic;
    rx_k         : std_logic_vector(1 downto 0);
    rx_enc_err   : std_logic;
    rx_bitslide  : std_logic_vector(4 downto 0);
  end record;

  type t_phy_interface_array is array(integer range <>) of t_phy_interface;

-------------------------------------------------------------------------------
-- Interconnect & memory layout
-------------------------------------------------------------------------------  

  constant c_cnx_base_addr : t_wishbone_address_array(c_NUM_WB_SLAVES-1 downto 0) :=
    (x"00052000",                       -- PPSgen
     x"00051000",                       -- TXTsu
     x"00050000",                       -- VIC
     x"00030000",                       -- Endpoint 0 (following endpoints will
                                        -- be at 0x30000 + N * 0x400)
     x"00020000",                       -- NIC
     x"00000000");                      -- RT Subsys 

  constant c_cnx_base_mask : t_wishbone_address_array(c_NUM_WB_SLAVES-1 downto 0) :=
    (x"000ff000",
     x"000ff000",
     x"000ff000",
     x"000f0000",
     x"000f0000",
     x"000e0000");

  function f_gen_endpoint_addresses return t_wishbone_address_array is
    variable tmp : t_wishbone_address_array(c_MAX_PORTS-1 downto 0);
  begin
    for i in 0 to c_MAX_PORTS-1 loop
      tmp(i) := std_logic_vector(to_unsigned(i * 1024, c_wishbone_address_width));
    end loop;  -- i
    return tmp;
  end f_gen_endpoint_addresses;

  function f_bool2int(x : boolean) return integer is
  begin
    if(x) then
      return 1;
    else
      return 0;
    end if;
  end f_bool2int;

  constant c_cnx_endpoint_addr : t_wishbone_address_array(c_MAX_PORTS-1 downto 0) :=
    f_gen_endpoint_addresses;
  constant c_cnx_endpoint_mask : t_wishbone_address_array(c_MAX_PORTS-1 downto 0) :=
    (others => x"0000FC00");

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

  signal clk_sys_startup, clk_sys_pll           : std_logic;
  signal clk_sys, clk_ref, clk_25mhz , clk_dmtd : std_logic;
  signal pllout_clk_fb                          : std_logic;
  signal clk_rx_vec                             : std_logic_vector(c_NUM_PORTS-1 downto 0);


-------------------------------------------------------------------------------
-- Fabric/Endpoint interconnect
-------------------------------------------------------------------------------

  signal endpoint_src_out : t_wrf_source_out_array(c_NUM_PORTS-1 downto 0);
  signal endpoint_src_in  : t_wrf_source_in_array(c_NUM_PORTS-1 downto 0);
  signal endpoint_snk_out : t_wrf_sink_out_array(c_NUM_PORTS-1 downto 0);
  signal endpoint_snk_in  : t_wrf_sink_in_array(c_NUM_PORTS-1 downto 0);



  signal nic_src_out : t_wrf_source_out;
  signal nic_src_in  : t_wrf_source_in;
  signal nic_snk_out : t_wrf_sink_out;
  signal nic_snk_in  : t_wrf_sink_in;

-- System clock selection: 0 = startup clock, 1 = PLL clock
  signal sel_clk_sys, sel_clk_sys_int : std_logic;
  signal switchover_cnt               : unsigned(4 downto 0);

  signal rst_n_sys  : std_logic;
  signal pps_p_main : std_logic;

  signal txtsu_timestamps_ack : std_logic_vector(c_NUM_PORTS-1 downto 0);
  signal txtsu_timestamps     : t_txtsu_timestamp_array(c_NUM_PORTS-1 downto 0);


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

  signal phys : t_phy_interface_array(c_NUM_PORTS-1 downto 0);

  signal clk_gtx0_3 : std_logic;
  signal clk_gtx4_7 : std_logic;
  signal clk_gtx    : std_logic_vector(c_MAX_PORTS-1 downto 0);

  signal vic_irqs : std_logic_vector(31 downto 0);

  signal trig0, trig1, trig2, trig3 : std_logic_vector(31 downto 0);
  signal cpu_nwait_int              : std_logic;
  signal rst_n_periph               : std_logic;

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
  
  
begin

  --CS_ICON : chipscope_icon
  --  port map (
  --    CONTROL0 => CONTROL0);

  --CS_ILA : chipscope_ila
  --  port map (
  --    CONTROL => CONTROL0,
  --    CLK     => phys(0).ref_clk,
  --    TRIG0   => TRIG0,
  --    TRIG1   => TRIG1,
  --    TRIG2   => TRIG2,
  --    TRIG3   => TRIG3);


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

-------------------------------------------------------------------------------
-- System clock mux: starts up using 25 MHz oscillator, then switches to network-synchronous
-- PLL clock
-------------------------------------------------------------------------------


  U_Sys_Clock_Mux : BUFGMUX
    generic map (
      CLK_SEL_TYPE => "SYNC")
    port map (
      O  => clk_sys,
      I0 => clk_sys_startup,
      I1 => clk_sys_pll,
      S  => sel_clk_sys_int);

  ------------------------------------------------    
  cmp_wb_cpu_bridge : wb_cpu_bridge
    --generic map(
    --)
    port map(
      sys_rst_n_i => rst_n_sys,

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
      rst_n_i   => rst_n_sys,
      slave_i   => bridge_master_out,
      slave_o   => bridge_master_in,
      master_i  => cnx_slave_out(0),
      master_o  => cnx_slave_in(0));


  --TRIG0             <= cnx_slave_in(0).adr;
  --trig1             <= cnx_slave_in(0).dat;
  --trig2(0)          <= cnx_slave_in(0).cyc;
  --trig2(1)          <= cnx_slave_in(0).stb;
  --trig2(2)          <= cnx_slave_in(0).we;
  --trig2(6 downto 3) <= cnx_slave_in(0).sel;
  --trig2(7)          <= cnx_slave_out(0).ack;
  --trig2(8)          <= cnx_slave_out(0).err;
  --trig2(9)          <= cnx_slave_out(0).rty;
  --trig2(10)         <= cnx_slave_out(0).stall;
  --trig2(11)         <= cpu_cs_n_i;
  --trig2(12)         <= cpu_rd_n_i;
  --trig2(13)         <= cpu_wr_n_i;
  --trig2(14)         <= cpu_nwait_int;

  cpu_nwait_o <= cpu_nwait_int;

  U_Intercon : xwb_crossbar
    generic map (
      g_num_masters => 1,
      g_num_slaves  => c_NUM_WB_SLAVES,
      g_registered  => true)
    port map (
      clk_sys_i     => clk_sys,
      rst_n_i       => rst_n_sys,
      slave_i       => cnx_slave_in,
      slave_o       => cnx_slave_out,
      master_i      => cnx_master_in,
      master_o      => cnx_master_out,
      cfg_address_i => c_cnx_base_addr,
      cfg_mask_i    => c_cnx_base_mask);


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
      g_num_rx_clocks => c_NUM_PORTS)
    port map (
      clk_ref_i           => clk_ref,
      clk_sys_i           => clk_sys,
      clk_dmtd_i          => clk_dmtd,
      clk_rx_i            => clk_rx_vec,
      rst_n_i             => rst_n_sys,
      rst_n_o             => rst_n_periph,
      wb_i                => cnx_master_out(0),
      wb_o                => cnx_master_in(0),
      dac_helper_sync_n_o => dac_helper_sync_n_o,
      dac_helper_sclk_o   => dac_helper_sclk_o,
      dac_helper_data_o   => dac_helper_data_o,
      dac_main_sync_n_o   => dac_main_sync_n_o,
      dac_main_sclk_o     => dac_main_sclk_o,
      dac_main_data_o     => dac_main_data_o,
      uart_txd_o          => uart_txd_o,
      uart_rxd_i          => uart_rxd_i,
      pps_p_o             => pps_p_main,
      pps_raw_i           => pps_i,
      sel_clk_sys_o       => sel_clk_sys,
      pll_status_i        => pll_status_i,
      pll_mosi_o          => pll_mosi_o,
      pll_miso_i          => pll_miso_i,
      pll_sck_o           => pll_sck_o,
      pll_cs_n_o          => pll_cs_n_o,
      pll_sync_n_o        => pll_sync_n_o,
      pll_reset_n_o       => pll_reset_n_o);

  U_IRQ_Controller : xwb_vic
    generic map (
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE,
      g_num_interrupts      => 32)
    port map (
      clk_sys_i    => clk_sys,
      rst_n_i      => rst_n_sys,
      slave_i      => cnx_master_out(3),
      slave_o      => cnx_master_in(3),
      irqs_i       => vic_irqs,
      irq_master_o => cpu_irq_n_o);

  U_Nic : xwrsw_nic
    generic map (
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE)
    port map (
      clk_sys_i           => clk_sys,
      rst_n_i             => rst_n_sys,
      snk_i               => nic_snk_in,
      snk_o               => nic_snk_out,
      src_i               => nic_src_in,
      src_o               => nic_src_out,
      rtu_dst_port_mask_o => open,
      rtu_prio_o          => open,
      rtu_drop_o          => open,
      rtu_rsp_valid_o     => open,
      rtu_rsp_ack_i       => '1',
      wb_i                => cnx_master_out(1),
      wb_o                => cnx_master_in(1));

  U_Endpoint_Fanout : xwb_crossbar
    generic map (
      g_num_masters => 1,
      g_num_slaves  => c_MAX_PORTS,
      g_registered  => true)
    port map (
      clk_sys_i     => clk_sys,
      rst_n_i       => rst_n_sys,
      slave_i(0)    => cnx_master_out(2),
      slave_o(0)    => cnx_master_in(2),
      master_i      => cnx_endpoint_in,
      master_o      => cnx_endpoint_out,
      cfg_address_i => c_cnx_endpoint_addr,
      cfg_mask_i    => c_cnx_endpoint_mask);

  clk_gtx(3 downto 0) <= (others => clk_gtx0_3);
  clk_gtx(7 downto 4) <= (others => clk_gtx4_7);

  gen_endpoints_and_phys : for i in 0 to c_NUM_PORTS-1 generate
    U_Endpoint_X : xwr_endpoint
      generic map (
        g_interface_mode      => PIPELINED,
        g_address_granularity => BYTE,
        g_simulation          => g_simulation,
        g_pcs_16bit           => true,
        g_rx_buffer_size      => 1024,
        g_with_rx_buffer      => true,
        g_with_flow_control   => false,
        g_with_timestamper    => true,
        g_with_dpi_classifier => false,
        g_with_vlans          => false,
        g_with_rtu            => false,
        g_with_leds           => true)
      port map (
        clk_ref_i          => clk_ref,
        clk_sys_i          => clk_sys,
        clk_dmtd_i         => clk_dmtd,
        rst_n_i            => rst_n_periph,
        pps_csync_p1_i     => '0',
        phy_rst_o          => phys(i).rst,
        phy_loopen_o       => phys(i).loopen,
        phy_enable_o       => phys(i).enable,
        phy_ref_clk_i      => phys(i).ref_clk,
        phy_tx_data_o      => phys(i).tx_data,
        phy_tx_k_o         => phys(i).tx_k,
        phy_tx_disparity_i => phys(i).tx_disparity,
        phy_tx_enc_err_i   => phys(i).tx_enc_err,
        phy_rx_data_i      => phys(i).rx_data,
        phy_rx_clk_i       => phys(i).rx_clk,
        phy_rx_k_i         => phys(i).rx_k,
        phy_rx_enc_err_i   => phys(i).rx_enc_err,
        phy_rx_bitslide_i  => phys(i).rx_bitslide,

        txtsu_port_id_o  => txtsu_timestamps(i).port_id(4 downto 0),
        txtsu_frame_id_o => txtsu_timestamps(i).frame_id,
        txtsu_tsval_o    => txtsu_timestamps(i).tsval,
        txtsu_valid_o    => txtsu_timestamps(i).valid,
        txtsu_ack_i      => txtsu_timestamps_ack(i),


        src_o      => endpoint_src_out(i),
        src_i      => endpoint_src_in(i),
        snk_o      => endpoint_snk_out(i),
        snk_i      => endpoint_snk_in(i),
        wb_i       => cnx_endpoint_out(i),
        wb_o       => cnx_endpoint_in(i),
        led_link_o => led_link_o(i),
        led_act_o  => led_act_o(i));

    txtsu_timestamps(i).port_id(5) <= '0';

    U_PHY_X : wr_gtx_phy_virtex6
      generic map (
        g_simulation => f_bool2int(g_simulation),
        g_use_slave_tx_clock => f_bool2int(i /= (i/4)*4))
      port map (
        clk_ref_i      => clk_gtx(i),
        tx_clk_i       => phys((i / 4) * 4).ref_clk,
        tx_clk_o       => phys(i).ref_clk,
        tx_data_i      => phys(i).tx_data,
        tx_k_i         => phys(i).tx_k,
        tx_disparity_o => phys(i).tx_disparity,
        tx_enc_err_o   => phys(i).tx_enc_err,
        rx_rbclk_o     => phys(i).rx_clk,
        rx_data_o      => phys(i).rx_data,
        rx_k_o         => phys(i).rx_k,
        rx_enc_err_o   => phys(i).rx_enc_err,
        rx_bitslide_o  => phys(i).rx_bitslide,
        rst_i          => phys(i).rst,
        loopen_i       => phys(i).loopen,
        pad_txn_o      => gtx_txn_o(i),
        pad_txp_o      => gtx_txp_o(i),
        pad_rxn_i      => gtx_rxn_i(i),
        pad_rxp_i      => gtx_rxp_i(i));

  end generate gen_endpoints_and_phys;


  gen_terminate_unused_eps : for i in c_NUM_PORTS to c_MAX_PORTS-1 generate
    cnx_endpoint_in(i).ack   <= '1';
    cnx_endpoint_in(i).stall <= '0';
    cnx_endpoint_in(i).dat   <= x"deadbeef";
    cnx_endpoint_in(i).err   <= '0';
    cnx_endpoint_in(i).rty   <= '0';
  end generate gen_terminate_unused_eps;

  gen_fabric_term : for i in 1 to c_NUM_PORTS-1 generate
    endpoint_src_in(i).ack   <= '1';
    endpoint_src_in(i).err   <= '0';
    endpoint_src_in(i).rty   <= '0';
    endpoint_src_in(i).stall <= '0';
    endpoint_snk_in(i).cyc   <= '0';
  end generate gen_fabric_term;

  nic_snk_in         <= endpoint_src_out(0);
  nic_src_in         <= endpoint_snk_out(0);
  endpoint_src_in(0) <= nic_snk_out;
  endpoint_snk_in(0) <= nic_src_out;

  --trig0 <= f_fabric_2_slv(nic_src_out, nic_src_in);
  --trig1 <= f_fabric_2_slv(nic_snk_in, nic_snk_out);

  trig0(15 downto 0)  <= phys(0).tx_data;
  trig0(17 downto 16) <= phys(0).tx_k;
  trig0(18)           <= phys(0).tx_disparity;
  trig0(19)           <= phys(0).tx_enc_err;
  trig0(20)           <= phys(0).rst;
  trig0(21)           <= phys(0).loopen;

  trig1(15 downto 0)  <= phys(0).rx_data;
  trig1(17 downto 16) <= phys(0).rx_k;
  trig1(18)           <= phys(0).rx_enc_err;

  U_PPS_Gen : xwr_pps_gen
    generic map (
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE)
    port map (
      clk_ref_i       => clk_ref,
      clk_sys_i       => clk_sys,
      rst_n_i         => rst_n_periph,
      slave_i         => cnx_master_out(4),
      slave_o         => cnx_master_in(4),
      pps_in_i        => '0',
      pps_csync_o     => open,
      pps_out_o       => open,
      tm_utc_o        => open,
      tm_cycles_o     => open,
      tm_time_valid_o => open);

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
      wb_i             => cnx_master_out(5),
      wb_o             => cnx_master_in(5));


  vic_irqs(0)           <= cnx_master_in(1).int;
  vic_irqs(1)           <= cnx_master_in(5).int;
  vic_irqs(31 downto 2) <= (others => '0');

  gtx_sfp_tx_dis_o <= (others => '1');

  clk_en_o  <= '1';
  clk_sel_o <= '0';

end Behavioral;


