library ieee;
use ieee.std_logic_1164.all;

use work.wishbone_pkg.all;
use work.wrsw_shared_types_pkg.all;
use work.wrsw_rtu_private_pkg.all;

entity xwrsw_rtu is
  
  generic (
    g_interface_mode      : t_wishbone_interface_mode      := PIPELINED;
    g_address_granularity : t_wishbone_address_granularity := BYTE;
    g_num_ports           : integer;
    g_port_mask_bits      : integer);

  port (
    clk_sys_i : in std_logic;
    rst_n_i   : in std_logic;

    req_i      : in  t_rtu_request_array(g_num_ports-1 downto 0);
    req_full_o : out std_logic_vector(g_num_ports-1 downto 0);

    rsp_o     : out t_rtu_response_array(g_num_ports-1 downto 0);
    rsp_ack_i : in  std_logic_vector(g_num_ports-1 downto 0);

    wb_i : in  t_wishbone_slave_in;
    wb_o : out t_wishbone_slave_out
    );

end xwrsw_rtu;
architecture wrapper of xwrsw_rtu is


  component wrsw_rtu
    port (
      clk_sys_i           : in  std_logic;
      clk_match_i         : in  std_logic;
      rst_n_i             : in  std_logic;
      rtu_idle_o          : out std_logic_vector(c_rtu_num_ports-1 downto 0);
      rq_strobe_p_i       : in  std_logic_vector(c_rtu_num_ports-1 downto 0);
      rq_smac_i           : in  std_logic_vector(c_wrsw_mac_addr_width * c_rtu_num_ports - 1 downto 0);
      rq_dmac_i           : in  std_logic_vector(c_wrsw_mac_addr_width * c_rtu_num_ports -1 downto 0);
      rq_vid_i            : in  std_logic_vector(c_wrsw_vid_width * c_rtu_num_ports - 1 downto 0);
      rq_has_vid_i        : in  std_logic_vector(c_rtu_num_ports -1 downto 0);
      rq_prio_i           : in  std_logic_vector(c_wrsw_prio_width * c_rtu_num_ports -1 downto 0);
      rq_has_prio_i       : in  std_logic_vector(c_rtu_num_ports -1 downto 0);
      rsp_valid_o         : out std_logic_vector (c_rtu_num_ports-1 downto 0);
      rsp_dst_port_mask_o : out std_logic_vector(c_wrsw_num_ports * c_rtu_num_ports - 1 downto 0);
      rsp_drop_o          : out std_logic_vector(c_rtu_num_ports -1 downto 0);
      rsp_prio_o          : out std_logic_vector (c_rtu_num_ports * c_wrsw_prio_width-1 downto 0);
      rsp_ack_i           : in  std_logic_vector(c_rtu_num_ports -1 downto 0);
      port_almost_full_o  : out std_logic_vector(c_rtu_num_ports -1 downto 0);
      port_full_o         : out std_logic_vector(c_rtu_num_ports -1 downto 0);
      wb_addr_i           : in  std_logic_vector(13 downto 0);
      wb_data_i           : in  std_logic_vector(31 downto 0);
      wb_data_o           : out std_logic_vector(31 downto 0);
      wb_sel_i            : in  std_logic_vector(3 downto 0);
      wb_cyc_i            : in  std_logic;
      wb_stb_i            : in  std_logic;
      wb_ack_o            :     out std_logic;
      wb_irq_o            : out std_logic;
      wb_we_i             : in  std_logic);
  end component;

  signal wb_in  : t_wishbone_slave_in;
  signal wb_out : t_wishbone_slave_out;


  signal rq_strobe_p       : std_logic_vector(c_rtu_num_ports-1 downto 0);
  signal rq_smac           : std_logic_vector(c_wrsw_mac_addr_width * c_rtu_num_ports - 1 downto 0);
  signal rq_dmac           : std_logic_vector(c_wrsw_mac_addr_width * c_rtu_num_ports -1 downto 0);
  signal rq_vid            : std_logic_vector(c_wrsw_vid_width * c_rtu_num_ports - 1 downto 0);
  signal rq_has_vid        : std_logic_vector(c_rtu_num_ports -1 downto 0);
  signal rq_prio           : std_logic_vector(c_wrsw_prio_width * c_rtu_num_ports -1 downto 0);
  signal rq_has_prio       : std_logic_vector(c_rtu_num_ports -1 downto 0);
  signal rsp_valid         : std_logic_vector (c_rtu_num_ports-1 downto 0);
  signal rsp_dst_port_mask : std_logic_vector(c_wrsw_num_ports * c_rtu_num_ports - 1 downto 0);
  signal rsp_drop          : std_logic_vector(c_rtu_num_ports -1 downto 0);
  signal rsp_prio          : std_logic_vector (c_rtu_num_ports * c_wrsw_prio_width-1 downto 0);
  signal rsp_ack           : std_logic_vector(c_rtu_num_ports -1 downto 0);
  signal port_full         : std_logic_vector(c_rtu_num_ports -1 downto 0);
  
begin  -- wrapper

  gen_merge_signals : for i in 0 to g_num_ports-1 generate
    rq_strobe_p(i)                                                              <= req_i(i).valid;
    rq_smac(c_wrsw_mac_addr_width * (i+1) - 1 downto c_wrsw_mac_addr_width * i) <= req_i(i).smac;
    rq_dmac(c_wrsw_mac_addr_width * (i+1) - 1 downto c_wrsw_mac_addr_width * i) <= req_i(i).dmac;
    rq_vid(c_wrsw_vid_width * (i+1) - 1 downto c_wrsw_vid_width * i)            <= req_i(i).vid;
    rq_prio(c_wrsw_prio_width * (i+1) - 1 downto c_wrsw_prio_width * i)         <= req_i(i).prio;
    rq_has_prio(i)                                                              <= req_i(i).has_prio;
    rq_has_vid(i)                                                               <= req_i(i).has_vid;

    rsp_o(i).valid                                  <= rsp_valid(i);
    rsp_o(i).port_mask(g_port_mask_bits-1 downto 0) <= rsp_dst_port_mask(c_wrsw_num_ports * i + g_port_mask_bits -1 downto c_wrsw_num_ports * i);
    rsp_o(i).drop                                   <= rsp_drop(i);
    rsp_ack(i)                                      <= rsp_ack_i(i);
    rsp_o(i).prio<=(others => '0');
    req_full_o(i)                                   <= port_full(i);
  end generate gen_merge_signals;


  gen_term_unused : for i in g_num_ports to c_rtu_num_ports-1 generate
    rq_strobe_p(i) <= '0';
    rsp_ack(i)   <= '1';
  end generate gen_term_unused;

  U_Adapter : wb_slave_adapter
    generic map (
      g_master_use_struct  => true,
      g_master_mode        => CLASSIC,
      g_master_granularity => WORD,
      g_slave_use_struct   => true,
      g_slave_mode         => g_interface_mode,
      g_slave_granularity  => g_address_granularity)
    port map (
      clk_sys_i => clk_sys_i,
      rst_n_i   => rst_n_i,
      slave_i   => wb_i,
      slave_o   => wb_o,
      master_i  => wb_out,
      master_o  => wb_in);

  wb_out.err <= '0';
  wb_out.rty <= '0';


  U_Wrapped_RTU : wrsw_rtu
    port map (
      clk_sys_i           => clk_sys_i,
      clk_match_i         => clk_sys_i,
      rst_n_i             => rst_n_i,
      rtu_idle_o          => open,
      rq_strobe_p_i       => rq_strobe_p,
      rq_smac_i           => rq_smac,
      rq_dmac_i           => rq_dmac,
      rq_vid_i            => rq_vid,
      rq_has_vid_i        => rq_has_vid,
      rq_prio_i           => rq_prio,
      rq_has_prio_i       => rq_has_prio,
      rsp_valid_o         => rsp_valid,
      rsp_dst_port_mask_o => rsp_dst_port_mask,
      rsp_drop_o          => rsp_drop,
      rsp_prio_o          => rsp_prio,
      rsp_ack_i           => rsp_ack,
      port_full_o         => port_full,
      wb_addr_i           => wb_in.adr(13 downto 0),
      wb_data_i           => wb_in.dat,
      wb_data_o           => wb_out.dat,
      wb_sel_i            => wb_in.sel,
      wb_cyc_i            => wb_in.cyc,
      wb_stb_i            => wb_in.stb,
      wb_ack_o            => wb_out.ack,
      wb_irq_o            => wb_out.int,
      wb_we_i             => wb_in.we);

end wrapper;
