-- Bare switch top module, without GTX transceivers and CPU bridge. Used as a
-- simulation top module.

library ieee;
use ieee.STD_LOGIC_1164.all;
use ieee.numeric_std.all;

use work.wishbone_pkg.all;
use work.gencores_pkg.all;
use work.wr_fabric_pkg.all;
use work.endpoint_pkg.all;
use work.wrsw_txtsu_pkg.all;
use work.wrsw_top_pkg.all;
use work.wrsw_shared_types_pkg.all;
use work.wrsw_tru_pkg.all;

library UNISIM;
use UNISIM.vcomponents.all;

entity scb_top_bare is
  generic(
    g_num_ports       : integer := 6;
    g_simulation      : boolean := false;
    g_without_network : boolean := false;
    g_with_TRU        : boolean := false
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
    clk_en_o  : out std_logic;

    -- GTX clock fanout source select
    clk_sel_o : out std_logic;

    -- DMTD clock divider selection (0 = 125 MHz, 1 = 62.5 MHz)
    clk_dmtd_divsel_o: out std_logic;

    -- UART source selection (FPGA/DBGU)
    uart_sel_o: out std_logic;

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
    i2c_sda_i     : in  std_logic_vector(2 downto 0) := "111"
    );
end scb_top_bare;

architecture rtl of scb_top_bare is

  constant c_NUM_WB_SLAVES : integer := 11;
  constant c_NUM_PORTS     : integer := g_num_ports;
  constant c_MAX_PORTS     : integer := 18;


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
  constant c_SLAVE_MBL_I2C0     : integer := 7;
  constant c_SLAVE_MBL_I2C1     : integer := 8;
  constant c_SLAVE_SENSOR_I2C   : integer := 9;
  constant c_SLAVE_TRU          : integer := 10;

  constant c_cnx_base_addr : t_wishbone_address_array(c_NUM_WB_SLAVES-1 downto 0) :=
    (
      x"00057000",                      -- TRU
      x"00056000",                      -- Sensors-I2C
      x"00055000",                      -- MBL-I2C1
      x"00054000",                      -- MBL-I2C0
      x"00053000",                      -- GPIO
      x"00060000",                      -- RTU
      x"00051000",                      -- TXTsu
      x"00050000",                      -- VIC
      x"00030000",                      -- Endpoint 0 (following endpoints will
                                        -- be at 0x30000 + N * 0x400)
      x"00020000",                      -- NIC
      x"00000000");                     -- RT Subsys 

  constant c_cnx_base_mask : t_wishbone_address_array(c_NUM_WB_SLAVES-1 downto 0) :=
    (x"000ff000",
     x"000ff000",
     x"000ff000",
     x"000ff000",
     x"000ff000",
     x"000f0000",
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

  signal clk_sys    : std_logic;
  signal clk_rx_vec : std_logic_vector(c_NUM_PORTS-1 downto 0);


-------------------------------------------------------------------------------
-- Fabric/Endpoint interconnect
-------------------------------------------------------------------------------

  signal endpoint_src_out : t_wrf_source_out_array(c_NUM_PORTS downto 0);
  signal endpoint_src_in  : t_wrf_source_in_array(c_NUM_PORTS downto 0);
  signal endpoint_snk_out : t_wrf_sink_out_array(c_NUM_PORTS downto 0);
  signal endpoint_snk_in  : t_wrf_sink_in_array(c_NUM_PORTS downto 0);

  signal dummy_snk_in  : t_wrf_sink_in_array(c_NUM_PORTS downto 0);
  signal dummy_src_in  : t_wrf_source_in_array(c_NUM_PORTS downto 0);
  signal dummy_src_out : t_wrf_source_out_array(c_NUM_PORTS downto 0);


  signal rtu_req                            : t_rtu_request_array(c_NUM_PORTS downto 0);
  signal rtu_rsp                            : t_rtu_response_array(c_NUM_PORTS downto 0);
  signal rtu_req_ack, rtu_full, rtu_rsp_ack : std_logic_vector(c_NUM_PORTS downto 0);

-- System clock selection: 0 = startup clock, 1 = PLL clock
  signal sel_clk_sys, sel_clk_sys_int : std_logic;
  signal switchover_cnt               : unsigned(4 downto 0);

  signal rst_n_sys  : std_logic;
  signal pps_p_main : std_logic;

  signal txtsu_timestamps_ack : std_logic_vector(c_NUM_PORTS-1 downto 0);
  signal txtsu_timestamps     : t_txtsu_timestamp_array(c_NUM_PORTS-1 downto 0);
  signal dummy                : std_logic_vector(31 downto 0);
  signal tru_enabled          : std_logic;
  -----------------------------------------------------------------------------
  -- Component declarations
  -----------------------------------------------------------------------------

  signal vic_irqs : std_logic_vector(31 downto 0);

  signal control0                   : std_logic_vector(35 downto 0);
  signal trig0, trig1, trig2, trig3 : std_logic_vector(31 downto 0);
  signal rst_n_periph               : std_logic;
  signal link_kill                  : std_logic_vector(c_NUM_PORTS-1 downto 0);

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

  signal gpio_out : std_logic_vector(31 downto 0);

  -----------------------------------------------------------------------------
  -- TRU stuff
  -----------------------------------------------------------------------------
  signal tru_req    : t_tru_request;
  signal tru_resp   : t_tru_response;    
  signal rtu2tru    : t_rtu2tru;
  signal ep2tru     : t_ep2tru_array(g_num_ports-1 downto 0);
  signal tru2ep     : t_tru2ep_array(g_num_ports-1 downto 0);
  signal swc2tru    : std_logic_vector(g_num_ports-1 downto 0); -- for pausing

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



  U_Intercon : xwb_crossbar
    generic map (
      g_num_masters => 1,
      g_num_slaves  => c_NUM_WB_SLAVES,
      g_registered  => true,
      g_address     => c_cnx_base_addr,
      g_mask        => c_cnx_base_mask)
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
      pps_ext_o   => pps_o,

      sel_clk_sys_o => sel_clk_sys,
      pll_status_i  => '0',
      pll_mosi_o    => pll_mosi_o,
      pll_miso_i    => pll_miso_i,
      pll_sck_o     => pll_sck_o,
      pll_cs_n_o    => pll_cs_n_o,
      pll_sync_n_o  => pll_sync_n_o,
      pll_reset_n_o => pll_reset_n_o);

  U_IRQ_Controller : xwb_vic
    generic map (
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE,
      g_num_interrupts      => 32)
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
        g_address_granularity => BYTE)
      port map (
        clk_sys_i           => clk_sys,
        rst_n_i             => rst_n_sys,
        snk_i               => endpoint_snk_in(c_NUM_PORTS),
        snk_o               => endpoint_snk_out(c_NUM_PORTS),
        src_i               => endpoint_src_in(c_NUM_PORTS),
        src_o               => endpoint_src_out(c_NUM_PORTS),
        rtu_dst_port_mask_o => rtu_rsp(c_NUM_PORTS).port_mask(31 downto 0),
        rtu_prio_o          => rtu_rsp(c_NUM_PORTS).prio,
        rtu_drop_o          => rtu_rsp(c_NUM_PORTS).drop,
        rtu_rsp_valid_o     => rtu_rsp(c_NUM_PORTS).valid,
        rtu_rsp_ack_i       => rtu_rsp_ack(c_NUM_PORTS),
        wb_i                => cnx_master_out(c_SLAVE_NIC),
        wb_o                => cnx_master_in(c_SLAVE_NIC));

    
    U_Endpoint_Fanout : xwb_crossbar
      generic map (
        g_num_masters => 1,
        g_num_slaves  => c_MAX_PORTS,
        g_registered  => true,
        g_address     => c_cnx_endpoint_addr,
        g_mask        => c_cnx_endpoint_mask)
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
          g_pcs_16bit           => true,
          g_rx_buffer_size      => 1024,
          g_with_rx_buffer      => true,
          g_with_flow_control   => false,
          g_with_timestamper    => true,
          g_with_dpi_classifier => false,
          g_with_vlans          => false,
          g_with_rtu            => true,
          g_with_leds           => true,
          g_with_dmtd           => false)
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
          phy_ref_clk_i      => phys_i(i).ref_clk,
          phy_tx_data_o      => phys_o(i).tx_data,
          phy_tx_k_o         => phys_o(i).tx_k,
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
          pfilter_pclass_o     => ep2tru(i).pfilter_pclass_o,
          pfilter_drop_o       => ep2tru(i).pfilter_drop_o,
          pfilter_done_o       => ep2tru(i).pfilter_done_o,
          fc_pause_req_i       => tru2ep(i).fc_pause_req,
          fc_pause_delay_i     => tru2ep(i).fc_pause_delay,
          fc_pause_ready_o     => ep2tru(i).fc_pause_ready,
          inject_req_i         => tru2ep(i).inject_req,
          inject_ready_o       => ep2tru(i).inject_ready,
          inject_packet_sel_i  => tru2ep(i).inject_packet_sel,
          inject_user_value_i  => tru2ep(i).inject_user_value,
          link_kill_i          => tru2ep(i).link_kill, --'0' , --link_kill(i), -- to change
          link_up_o            => ep2tru(i).status,
          ----------------------------
          led_link_o => led_link_o(i),
          led_act_o  => led_act_o(i));

      txtsu_timestamps(i).port_id(5) <= '0';
      
      ------- TEMP ---------
--       link_kill(i)                <= not tru2ep(i).ctrlWr; 
--       tru2ep(i).fc_pause_req      <= '0';
--       tru2ep(i).fc_pause_delay    <= (others =>'0');
      tru2ep(i).inject_req        <= '0';
      tru2ep(i).inject_packet_sel <= (others => '0');
      tru2ep(i).inject_user_value <= (others => '0');
      ep2tru(i).rx_pck            <= '0';
      ep2tru(i).rx_pck_class      <= (others => '0');
      ---------------------------

      clk_rx_vec(i) <= phys_i(i).rx_clk;
    end generate gen_endpoints_and_phys;

    gen_terminate_unused_eps : for i in c_NUM_PORTS to c_MAX_PORTS-1 generate
      cnx_endpoint_in(i).ack   <= '1';
      cnx_endpoint_in(i).stall <= '0';
      cnx_endpoint_in(i).dat   <= x"deadbeef";
      cnx_endpoint_in(i).err   <= '0';
      cnx_endpoint_in(i).rty   <= '0';
      --txtsu_timestamps(i).valid <= '0';
    end generate gen_terminate_unused_eps;


    gen_txtsu_debug: for i in 0 to c_NUM_PORTS-1 generate
      TRIG0(i) <= txtsu_timestamps(i).stb;
      trig1(i) <= txtsu_timestamps_ack(i);
      trig2(0) <= vic_irqs(0);
      trig2(1) <= vic_irqs(1);
      trig2(2) <= vic_irqs(2);
    end generate gen_txtsu_debug;

    U_Swcore : xswc_core
      generic map (
        g_prio_num                        => 8,
        g_max_pck_size                    => 10 * 1024,
        g_max_oob_size                    => 3,
        g_num_ports                       => g_num_ports+1,
        g_pck_pg_free_fifo_size           => 512,
        g_input_block_cannot_accept_data  => "drop_pck",
        g_output_block_per_prio_fifo_size => 64,
        g_wb_data_width                   => 16,
        g_wb_addr_width                   => 2,
        g_wb_sel_width                    => 2,
        g_wb_ob_ignore_ack                => false,
        g_mpm_mem_size                    => 67584,
        g_mpm_page_size                   => 66,
        g_mpm_ratio                       => 6, --f_swc_ratio,  --2
        g_mpm_fifo_size                   => 8,
        g_mpm_fetch_next_pg_in_advance    => false)
      port map (
        clk_i          => clk_sys,
        clk_mpm_core_i => clk_aux_i,
        rst_n_i        => rst_n_periph,

        src_i => endpoint_snk_out,
        src_o => endpoint_snk_in,
        snk_i => endpoint_src_out,
        snk_o => endpoint_src_in,

        rtu_rsp_i => rtu_rsp,
        rtu_ack_o => rtu_rsp_ack
        );

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
        g_port_mask_bits                  => g_num_ports+1,
        g_handle_only_single_req_per_port => true)
      port map (
        clk_sys_i  => clk_sys,
        rst_n_i    => rst_n_sys,--rst_n_periph,
        req_i      => rtu_req(g_num_ports-1 downto 0),
        req_full_o => rtu_full(g_num_ports-1 downto 0),
        rsp_o      => rtu_rsp(g_num_ports-1 downto 0),
        rsp_ack_i  => rtu_rsp_ack(g_num_ports-1 downto 0),
        ------ new TRU stuff ----------
        tru_req_o  => tru_req,
        tru_resp_i => tru_resp,
        rtu2tru_o  => rtu2tru,
        tru_enabled_i => tru_enabled,
        -------------------------------
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
          swc_o               => swc2tru,
          enabled_o           => tru_enabled,
          wb_i                => cnx_master_out(c_SLAVE_TRU),
          wb_o                => cnx_master_in(c_SLAVE_TRU));
    end generate gen_TRU;    

    gen_no_TRU : if(g_with_TRU = false) generate
      swc2tru                        <= (others =>'0');  
      tru_enabled                    <= '0';
      cnx_master_in(c_SLAVE_TRU).ack <= '1';
    end generate gen_no_TRU; 

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
      g_num_pins               => 32,
      g_with_builtin_tristates => false)
    port map (
      clk_sys_i  => clk_sys,
      rst_n_i    => rst_n_periph,
      slave_i    => cnx_master_out(c_SLAVE_GPIO),
      slave_o    => cnx_master_in(c_SLAVE_GPIO),
      gpio_b     => dummy,
      gpio_out_o => gpio_out,
      gpio_in_i  => gpio_i);

  uart_sel_o <= gpio_out(31);

  
  gpio_o <= gpio_out;

  U_MiniBackplane_I2C0 : xwb_i2c_master
    generic map (
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE)
    port map (
      clk_sys_i    => clk_sys,
      rst_n_i      => rst_n_periph,
      slave_i      => cnx_master_out(c_SLAVE_MBL_I2C0),
      slave_o      => cnx_master_in(c_SLAVE_MBL_I2C0),
      desc_o       => open,
      scl_pad_i    => i2c_scl_i(0),
      scl_pad_o    => i2c_scl_o(0),
      scl_padoen_o => i2c_scl_oen_o(0),
      sda_pad_i    => i2c_sda_i(0),
      sda_pad_o    => i2c_sda_o(0),
      sda_padoen_o => i2c_sda_oen_o(0));

  U_MiniBackplane_I2C1 : xwb_i2c_master
    generic map (
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE)
    port map (
      clk_sys_i    => clk_sys,
      rst_n_i      => rst_n_periph,
      slave_i      => cnx_master_out(c_SLAVE_MBL_I2C1),
      slave_o      => cnx_master_in(c_SLAVE_MBL_I2C1),
      desc_o       => open,
      scl_pad_i    => i2c_scl_i(1),
      scl_pad_o    => i2c_scl_o(1),
      scl_padoen_o => i2c_scl_oen_o(1),
      sda_pad_i    => i2c_sda_i(1),
      sda_pad_o    => i2c_sda_o(1),
      sda_padoen_o => i2c_sda_oen_o(1));

  U_Sensors_I2C : xwb_i2c_master
    generic map (
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE)
    port map (
      clk_sys_i    => clk_sys,
      rst_n_i      => rst_n_periph,
      slave_i      => cnx_master_out(c_SLAVE_SENSOR_I2C),
      slave_o      => cnx_master_in(c_SLAVE_SENSOR_I2C),
      desc_o       => open,
      scl_pad_i    => i2c_scl_i(2),
      scl_pad_o    => i2c_scl_o(2),
      scl_padoen_o => i2c_scl_oen_o(2),
      sda_pad_i    => i2c_sda_i(2),
      sda_pad_o    => i2c_sda_o(2),
      sda_padoen_o => i2c_sda_oen_o(2));

  -----------------------------------------------------------------------------
  -- Interrupt assignment
  -----------------------------------------------------------------------------
  
  vic_irqs(0)           <= cnx_master_in(c_SLAVE_NIC).int;
  vic_irqs(1)           <= cnx_master_in(c_SLAVE_TXTSU).int;
  vic_irqs(2)           <= cnx_master_in(c_SLAVE_RTU).int;
  vic_irqs(31 downto 3) <= (others => '0');

-------------------------------------------------------------------------------
-- Various constant-driven I/Os
-------------------------------------------------------------------------------

  clk_en_o  <= '0';
  clk_sel_o <= '0';
  clk_dmtd_divsel_o <= '1';             -- choose 62.5 MHz DDMTD clock
  clk_sys_o <= clk_sys;
  
end rtl;
