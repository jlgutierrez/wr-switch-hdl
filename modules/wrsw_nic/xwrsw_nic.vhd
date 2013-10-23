library ieee;
use ieee.std_logic_1164.all;

library work;

use work.nic_constants_pkg.all;
use work.nic_descriptors_pkg.all;

use work.wishbone_pkg.all;
use work.wr_fabric_pkg.all;

use work.nic_wbgen2_pkg.all;


entity xwrsw_nic is
  generic
    (
      g_interface_mode      : t_wishbone_interface_mode      := CLASSIC;
      g_address_granularity : t_wishbone_address_granularity := WORD;
      g_port_mask_bits      : integer := 32); --should be num_ports+1
  port (
    clk_sys_i : in std_logic;
    rst_n_i   : in std_logic;

-------------------------------------------------------------------------------
-- WRF sink
-------------------------------------------------------------------------------

    snk_i : in  t_wrf_sink_in;
    snk_o : out t_wrf_sink_out;

    src_i : in  t_wrf_source_in;
    src_o : out t_wrf_source_out;

-------------------------------------------------------------------------------
-- "Fake" RTU interface
-------------------------------------------------------------------------------

    rtu_dst_port_mask_o : out std_logic_vector(g_port_mask_bits-1 downto 0);
    rtu_prio_o          : out std_logic_vector(2 downto 0);
    rtu_drop_o          : out std_logic;
    rtu_rsp_valid_o     : out std_logic;
    rtu_rsp_ack_i       : in  std_logic;

-------------------------------------------------------------------------------
-- Wishbone bus
-------------------------------------------------------------------------------

    wb_i : in  t_wishbone_slave_in;
    wb_o : out t_wishbone_slave_out
    );

end xwrsw_nic;

architecture rtl of xwrsw_nic is

  component nic_descriptor_manager
    generic (
      g_desc_mode            : string;
      g_num_descriptors      : integer;
      g_num_descriptors_log2 : integer;
      g_port_mask_bits       : integer := 32);
    port (
      clk_sys_i             : in  std_logic;
      rst_n_i               : in  std_logic;
      enable_i              : in  std_logic;
      bna_o                 : out std_logic;
      bna_clear_i           : in  std_logic;
      cur_desc_idx_o        : out std_logic_vector(g_num_descriptors_log2-1 downto 0);
      dtbl_addr_o           : out std_logic_vector(g_num_descriptors_log2+1 downto 0);
      dtbl_data_i           : in  std_logic_vector(31 downto 0);
      dtbl_rd_o             : out std_logic;
      dtbl_data_o           : out std_logic_vector(31 downto 0);
      dtbl_wr_o             : out std_logic;
      desc_reload_current_i : in  std_logic;
      desc_request_next_i   : in  std_logic;
      desc_grant_o          : out std_logic;
      rxdesc_current_o      : out t_rx_descriptor;
      rxdesc_new_i          : in  t_rx_descriptor;
      txdesc_current_o      : out t_tx_descriptor;
      txdesc_new_i          : in  t_tx_descriptor;
      desc_write_i          : in  std_logic;
      desc_write_done_o     : out std_logic);
  end component;

  component nic_rx_fsm
    port (
      clk_sys_i             : in  std_logic;
      rst_n_i               : in  std_logic;
      snk_i                 : in  t_wrf_sink_in;
      snk_o                 : out t_wrf_sink_out;
      regs_i                : in  t_nic_out_registers;
      regs_o                : out t_nic_in_registers;
      bna_i                 : in  std_logic;
      irq_rcomp_o           : out std_logic;
      irq_rcomp_ack_i       : in  std_logic;
      rxdesc_request_next_o : out std_logic;
      rxdesc_grant_i        : in  std_logic;
      rxdesc_current_i      : in  t_rx_descriptor;
      rxdesc_new_o          : out t_rx_descriptor;
      rxdesc_write_o        : out std_logic;
      rxdesc_write_done_i   : in  std_logic;
      buf_grant_i           : in  std_logic;
      buf_addr_o            : out std_logic_vector(c_nic_buf_size_log2-3 downto 0);
      buf_wr_o              : out std_logic;
      buf_data_o            : out std_logic_vector(31 downto 0));
  end component;

  component nic_buffer
    generic (
      g_memsize_log2 : integer);
    port (
      clk_sys_i : in  std_logic;
      rst_n_i   : in  std_logic;
      addr_i    : in  std_logic_vector(g_memsize_log2-1 downto 0);
      data_i    : in  std_logic_vector(31 downto 0);
      wr_i      : in  std_logic;
      data_o    : out std_logic_vector(31 downto 0);
      wb_data_i : in  std_logic_vector(31 downto 0);
      wb_data_o : out std_logic_vector(31 downto 0);
      wb_addr_i : in  std_logic_vector(g_memsize_log2-1 downto 0);
      wb_cyc_i  : in  std_logic;
      wb_stb_i  : in  std_logic;
      wb_we_i   : in  std_logic;
      wb_ack_o  : out std_logic);
  end component;

  component nic_wishbone_slave
    port (
      rst_n_i          : in  std_logic;
      clk_sys_i        : in  std_logic;
      wb_adr_i         : in  std_logic_vector(6 downto 0);
      wb_dat_i         : in  std_logic_vector(31 downto 0);
      wb_dat_o         : out std_logic_vector(31 downto 0);
      wb_cyc_i         : in  std_logic;
      wb_sel_i         : in  std_logic_vector(3 downto 0);
      wb_stb_i         : in  std_logic;
      wb_we_i          : in  std_logic;
      wb_ack_o         : out std_logic;
      wb_stall_o       : out std_logic;
      wb_int_o         : out std_logic;
      irq_rcomp_i      : in  std_logic;
      irq_rcomp_ack_o  : out std_logic;
      irq_tcomp_i      : in  std_logic;
      irq_tcomp_ack_o  : out std_logic;
      irq_tcomp_mask_o : out std_logic;
      irq_txerr_i      : in  std_logic;
      irq_txerr_ack_o  : out std_logic;
      irq_txerr_mask_o : out std_logic;
      nic_dtx_addr_i   : in  std_logic_vector(4 downto 0);
      nic_dtx_data_o   : out std_logic_vector(31 downto 0);
      nic_dtx_rd_i     : in  std_logic;
      nic_dtx_data_i   : in  std_logic_vector(31 downto 0);
      nic_dtx_wr_i     : in  std_logic;
      nic_drx_addr_i   : in  std_logic_vector(4 downto 0);
      nic_drx_data_o   : out std_logic_vector(31 downto 0);
      nic_drx_rd_i     : in  std_logic;
      nic_drx_data_i   : in  std_logic_vector(31 downto 0);
      nic_drx_wr_i     : in  std_logic;
      regs_i           : in  t_nic_in_registers;
      regs_o           : out t_nic_out_registers);
  end component;

  component nic_tx_fsm
    generic(
      g_port_mask_bits  : integer := 32);
    port (
      clk_sys_i               : in  std_logic;
      rst_n_i                 : in  std_logic;
      src_o                   : out t_wrf_source_out;
      src_i                   : in  t_wrf_source_in;
      rtu_dst_port_mask_o     : out std_logic_vector(g_port_mask_bits-1 downto 0);
      rtu_prio_o              : out std_logic_vector(2 downto 0);
      rtu_drop_o              : out std_logic;
      rtu_rsp_valid_o         : out std_logic;
      rtu_rsp_ack_i           : in  std_logic;
      regs_i                  : in  t_nic_out_registers;
      regs_o                  : out t_nic_in_registers;
      irq_tcomp_o             : out std_logic;
      irq_tcomp_ack_i         : in  std_logic;
      irq_tcomp_mask_i        : in  std_logic;
      irq_txerr_o             : out std_logic;
      irq_txerr_ack_i         : in  std_logic;
      irq_txerr_mask_i        : in  std_logic;
      txdesc_reload_current_o : out std_logic;
      txdesc_request_next_o   : out std_logic;
      txdesc_grant_i          : in  std_logic;
      txdesc_current_i        : in  t_tx_descriptor;
      txdesc_new_o            : out t_tx_descriptor;
      txdesc_write_o          : out std_logic;
      txdesc_write_done_i     : in  std_logic;
      bna_i                   : in  std_logic;
      buf_grant_i             : in  std_logic;
      buf_addr_o              : out std_logic_vector(c_nic_buf_size_log2-3 downto 0);
      buf_data_i              : in  std_logic_vector(31 downto 0));
  end component;

  signal rxdesc_request_next : std_logic;
  signal rxdesc_grant        : std_logic;
  signal rxdesc_current      : t_rx_descriptor;
  signal rxdesc_new          : t_rx_descriptor;
  signal rxdesc_write        : std_logic;
  signal rxdesc_write_done   : std_logic;

  signal txdesc_reload_current : std_logic;
  signal txdesc_request_next   : std_logic;
  signal txdesc_grant          : std_logic;
  signal txdesc_current        : t_tx_descriptor;
  signal txdesc_new            : t_tx_descriptor;
  signal txdesc_write          : std_logic;
  signal txdesc_write_done     : std_logic;

  signal regs_fromwb                                           : t_nic_out_registers;
  signal regs_towb_main, regs_towb_rx, regs_towb_tx, regs_towb : t_nic_in_registers;

  signal irq_rcomp      : std_logic;
  signal irq_rcomp_ack  : std_logic;
  signal irq_tcomp      : std_logic;
  signal irq_tcomp_ack  : std_logic;
  signal irq_tcomp_mask : std_logic;
  signal irq_txerr      : std_logic;
  signal irq_txerr_ack  : std_logic;
  signal irq_txerr_mask : std_logic;

  signal nic_dtx_addr    : std_logic_vector(4 downto 0);
  signal nic_dtx_wr_data : std_logic_vector(31 downto 0);
  signal nic_dtx_rd      : std_logic;
  signal nic_dtx_rd_data : std_logic_vector(31 downto 0);
  signal nic_dtx_wr      : std_logic;

  signal nic_drx_addr    : std_logic_vector(4 downto 0);
  signal nic_drx_wr_data : std_logic_vector(31 downto 0);
  signal nic_drx_rd      : std_logic;
  signal nic_drx_rd_data : std_logic_vector(31 downto 0);
  signal nic_drx_wr      : std_logic;

  signal nic_mem_addr    : std_logic_vector(12 downto 0);
  signal nic_mem_wr_data : std_logic_vector(31 downto 0);
  signal nic_mem_rd      : std_logic;
  signal nic_mem_rd_data : std_logic_vector(31 downto 0);
  signal nic_mem_wr      : std_logic;

  signal mem_grant_rx   : std_logic;
  signal mem_grant_tx   : std_logic;
  signal mem_addr_tx    : std_logic_vector(c_nic_buf_size_log2-3 downto 0);
  signal mem_addr_rx    : std_logic_vector(c_nic_buf_size_log2-3 downto 0);
  signal mem_wr_rx      : std_logic;
  signal mem_wr_data_rx : std_logic_vector(31 downto 0);


  signal tx_bna : std_logic;

  signal nic_reset_n : std_logic;

  signal dummy_rx_desc : t_rx_descriptor;  -- stupid VHDL
  signal dummy_tx_desc : t_tx_descriptor;

  signal wb_cyc_slave : std_logic;
  signal wb_cyc_buf   : std_logic;
  signal wb_ack_slave : std_logic;
  signal wb_ack_buf   : std_logic;

  signal wb_rdata_slave : std_logic_vector(31 downto 0);
  signal wb_rdata_buf   : std_logic_vector(31 downto 0);

  signal wb_in  : t_wishbone_master_out;
  signal wb_out : t_wishbone_master_in;
  
begin  -- rtl

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

  nic_reset_n <= rst_n_i and (not regs_fromwb.cr_sw_rst_o);

  regs_towb <= regs_towb_tx or regs_towb_rx or regs_towb_main;

  U_WB_SLAVE : nic_wishbone_slave
    port map (
      rst_n_i   => rst_n_i,
      clk_sys_i => clk_sys_i,
      wb_adr_i  => wb_in.adr(6 downto 0),
      wb_dat_i  => wb_in.dat,
      wb_dat_o  => wb_rdata_slave,
      wb_cyc_i  => wb_cyc_slave,
      wb_sel_i  => wb_in.sel,
      wb_stb_i  => wb_in.stb,
      wb_we_i   => wb_in.we,
      wb_ack_o  => wb_ack_slave,
      wb_stall_o=> wb_out.stall,
      wb_int_o  => wb_out.int,


      regs_o => regs_fromwb,
      regs_i => regs_towb,

      irq_rcomp_i     => irq_rcomp,
      irq_rcomp_ack_o => irq_rcomp_ack,

      irq_tcomp_i      => irq_tcomp,
      irq_tcomp_ack_o  => irq_tcomp_ack,
      irq_tcomp_mask_o => irq_tcomp_mask,

      irq_txerr_i      => irq_txerr,
      irq_txerr_ack_o  => irq_txerr_ack,
      irq_txerr_mask_o => irq_txerr_mask,

      nic_dtx_addr_i => nic_dtx_addr,
      nic_dtx_data_o => nic_dtx_rd_data,
      nic_dtx_rd_i   => nic_dtx_rd,
      nic_dtx_data_i => nic_dtx_wr_data,
      nic_dtx_wr_i   => nic_dtx_wr,
      nic_drx_addr_i => nic_drx_addr,
      nic_drx_data_o => nic_drx_rd_data,
      nic_drx_rd_i   => nic_drx_rd,
      nic_drx_data_i => nic_drx_wr_data,
      nic_drx_wr_i   => nic_drx_wr);


  U_BUFFER : nic_buffer
    generic map (
      g_memsize_log2 => c_nic_buf_size_log2 - 2)
    port map (
      clk_sys_i => clk_sys_i,
      rst_n_i   => nic_reset_n,
      addr_i    => nic_mem_addr,
      data_i    => nic_mem_wr_data,
      wr_i      => nic_mem_wr,
      data_o    => nic_mem_rd_data,
      wb_data_i => wb_in.dat,
      wb_data_o => wb_rdata_buf,
      wb_addr_i => wb_in.adr(c_nic_buf_size_log2 - 3 downto 0),
      wb_cyc_i  => wb_cyc_buf,
      wb_stb_i  => wb_in.stb,
      wb_we_i   => wb_in.we,
      wb_ack_o  => wb_ack_buf);

  wb_cyc_slave <= wb_in.cyc when wb_in.adr(13) = '0' else '0';
  wb_cyc_buf   <= wb_in.cyc when wb_in.adr(13) = '1' else '0';

  wb_out.ack <= wb_ack_buf or wb_ack_slave;

  wb_out.dat <= wb_rdata_slave when (wb_in.adr(13) = '0')
                else wb_rdata_buf;
  
  p_buffer_arb : process(clk_sys_i, nic_reset_n)
  begin
    if rising_edge(clk_sys_i) then
      if(nic_reset_n = '0') then
        mem_grant_rx <= '0';
      else
        mem_grant_rx <= not mem_grant_rx;  -- round-robin    
      end if;
    end if;
  end process;

  mem_grant_tx <= not mem_grant_rx;

  p_mux_buffer_addr : process(mem_grant_rx, mem_addr_tx, mem_addr_rx)
  begin
    if(mem_grant_rx = '0') then
      nic_mem_addr <= mem_addr_tx;
    else
      nic_mem_addr <= mem_addr_rx;
    end if;
  end process;


  nic_mem_wr_data <= mem_wr_data_rx;
  nic_mem_wr      <= mem_wr_rx when mem_grant_rx = '1' else '0';

--mem_addr_tx <= (others => '0');
  nic_mem_rd <= '1';

--  bna_clear_rx <= nic_sr_bna_out and nic_sr_bna_load;


-------------------------------------------------------------------------------
-- RX Path
-------------------------------------------------------------------------------  

  U_RX_DESC_MANAGER : nic_descriptor_manager
    generic map (
      g_desc_mode            => "rx",
      g_num_descriptors      => c_nic_num_rx_descriptors,
      g_num_descriptors_log2 => c_nic_num_rx_descriptors_log2,
      g_port_mask_bits       => g_port_mask_bits)
    port map (
      clk_sys_i => clk_sys_i,
      rst_n_i   => nic_reset_n,

      enable_i       => regs_fromwb.cr_rx_en_o,
      bna_o          => regs_towb_main.sr_bna_i,
      bna_clear_i    => '1',
      cur_desc_idx_o => regs_towb_main.sr_cur_rx_desc_i,

      dtbl_addr_o => nic_drx_addr,
      dtbl_data_i => nic_drx_rd_data,
      dtbl_rd_o   => nic_drx_rd,
      dtbl_data_o => nic_drx_wr_data,
      dtbl_wr_o   => nic_drx_wr,

      desc_reload_current_i => '0',
      desc_request_next_i   => rxdesc_request_next,
      desc_grant_o          => rxdesc_grant,
      desc_write_i          => rxdesc_write,
      desc_write_done_o     => rxdesc_write_done,

      rxdesc_current_o => rxdesc_current,
      rxdesc_new_i     => rxdesc_new,
      txdesc_current_o => open,
      txdesc_new_i     => dummy_tx_desc
      );


  U_RX_FSM : nic_rx_fsm
    port map (
      clk_sys_i => clk_sys_i,
      rst_n_i   => nic_reset_n,

      snk_i => snk_i,
      snk_o => snk_o,

      bna_i => regs_towb_main.sr_bna_i,

      regs_i => regs_fromwb,
      regs_o => regs_towb_rx,

      irq_rcomp_o     => irq_rcomp,
      irq_rcomp_ack_i => irq_rcomp_ack,

      rxdesc_request_next_o => rxdesc_request_next,
      rxdesc_grant_i        => rxdesc_grant,
      rxdesc_current_i      => rxdesc_current,
      rxdesc_new_o          => rxdesc_new,
      rxdesc_write_o        => rxdesc_write,
      rxdesc_write_done_i   => rxdesc_write_done,

      buf_grant_i => mem_grant_rx,
      buf_addr_o  => mem_addr_rx,
      buf_wr_o    => mem_wr_rx,
      buf_data_o  => mem_wr_data_rx);

-------------------------------------------------------------------------------
-- TX Path
-------------------------------------------------------------------------------  

  U_TX_DESC_MANAGER : nic_descriptor_manager
    generic map (
      g_desc_mode            => "tx",
      g_num_descriptors      => c_nic_num_tx_descriptors,
      g_num_descriptors_log2 => c_nic_num_tx_descriptors_log2,
      g_port_mask_bits       => g_port_mask_bits)
    port map (
      clk_sys_i      => clk_sys_i,
      rst_n_i        => nic_reset_n,
      enable_i       => regs_fromwb.cr_tx_en_o,
      bna_o          => tx_bna,
      bna_clear_i    => '0',
      cur_desc_idx_o => regs_towb_main.sr_cur_tx_desc_i,
      dtbl_addr_o    => nic_dtx_addr,
      dtbl_data_i    => nic_dtx_rd_data,
      dtbl_rd_o      => nic_dtx_rd,
      dtbl_data_o    => nic_dtx_wr_data,
      dtbl_wr_o      => nic_dtx_wr,

      desc_reload_current_i => txdesc_reload_current,
      desc_request_next_i   => txdesc_request_next,
      desc_grant_o          => txdesc_grant,

      rxdesc_current_o => open,
      rxdesc_new_i     => dummy_rx_desc,
      txdesc_current_o => txdesc_current,
      txdesc_new_i     => txdesc_new,

      desc_write_i      => txdesc_write,
      desc_write_done_o => txdesc_write_done);


  U_TX_FSM : nic_tx_fsm
    generic map(
      g_port_mask_bits  => g_port_mask_bits)
    port map (
      clk_sys_i => clk_sys_i,
      rst_n_i   => nic_reset_n,

      src_o => src_o,
      src_i => src_i,

      rtu_dst_port_mask_o => rtu_dst_port_mask_o,
      rtu_prio_o          => rtu_prio_o,
      rtu_drop_o          => rtu_drop_o,
      rtu_rsp_valid_o     => rtu_rsp_valid_o,
      rtu_rsp_ack_i       => rtu_rsp_ack_i,

      regs_i => regs_fromwb,
      regs_o => regs_towb_tx,


      irq_tcomp_o             => irq_tcomp,
      irq_tcomp_ack_i         => irq_tcomp_ack,
      irq_tcomp_mask_i        => irq_tcomp_mask,
      irq_txerr_o             => irq_txerr,
      irq_txerr_ack_i         => irq_txerr_ack,
      irq_txerr_mask_i        => irq_txerr_mask,
      txdesc_reload_current_o => txdesc_reload_current,
      txdesc_request_next_o   => txdesc_request_next,
      txdesc_grant_i          => txdesc_grant,
      txdesc_current_i        => txdesc_current,
      txdesc_new_o            => txdesc_new,
      txdesc_write_o          => txdesc_write,
      txdesc_write_done_i     => txdesc_write_done,
      bna_i                   => tx_bna,
      buf_grant_i             => mem_grant_tx,
      buf_addr_o              => mem_addr_tx,
      buf_data_i              => nic_mem_rd_data);


end rtl;
