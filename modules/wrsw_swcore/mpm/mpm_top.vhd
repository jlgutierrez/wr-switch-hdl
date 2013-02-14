library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.gencores_pkg.all;              -- for f_rr_arbitrate
use work.genram_pkg.all;                -- for f_log2_size

use work.mpm_private_pkg.all;

entity mpm_top is
  generic (
    g_data_width           : integer := 18;
    g_ratio                : integer := 2;
    g_page_size            : integer := 64;
    g_num_pages            : integer := 2048;
    g_num_ports            : integer := 8;
    g_fifo_size            : integer := 4;
    g_page_addr_width      : integer := 11;
    g_partial_select_width : integer := 1;
    g_max_oob_size         : integer := 3;
    g_max_packet_size      : integer := 10000;
    g_ll_data_width        : integer := 15
    );

  port(
    -- I/O ports clock (slow)
    clk_io_i   : in std_logic;
    -- Memory/Core clock (fast)
    clk_core_i : in std_logic;
    rst_n_i    : in std_logic;

-- read-write ports I/F (streaming)
    wport_d_i       : in  std_logic_vector (g_num_ports * g_data_width -1 downto 0);
    wport_dvalid_i  : in  std_logic_vector (g_num_ports-1 downto 0);
    wport_dlast_i   : in  std_logic_vector (g_num_ports-1 downto 0);
    wport_pg_addr_i : in  std_logic_vector (g_num_ports * g_page_addr_width -1 downto 0);
    wport_pg_req_o  : out std_logic_vector(g_num_ports -1 downto 0);
    wport_dreq_o    : out std_logic_vector (g_num_ports-1 downto 0);


    rport_d_o        : out std_logic_vector (g_num_ports * g_data_width -1 downto 0);
    rport_dvalid_o   : out std_logic_vector (g_num_ports-1 downto 0);
    rport_dlast_o    : out std_logic_vector (g_num_ports-1 downto 0);
    rport_dsel_o     : out std_logic_vector (g_num_ports * g_partial_select_width -1 downto 0);
    rport_dreq_i     : in  std_logic_vector (g_num_ports-1 downto 0);
    rport_abort_i    : in  std_logic_vector (g_num_ports-1 downto 0);
    rport_pg_addr_i  : in  std_logic_vector (g_num_ports * g_page_addr_width -1 downto 0);
    rport_pg_valid_i : in  std_logic_vector (g_num_ports-1 downto 0);
    rport_pg_req_o   : out std_logic_vector (g_num_ports-1 downto 0);

    ll_addr_o : out std_logic_vector(g_page_addr_width-1 downto 0);
    ll_data_i : in  std_logic_vector(g_ll_data_width  -1 downto 0)
    );

end mpm_top;

architecture rtl of mpm_top is

  signal rst_n_core : std_logic;
  signal rst_n_io   : std_logic;

  component mpm_write_path
    generic (
      g_data_width           : integer;
      g_ratio                : integer;
      g_page_size            : integer;
      g_num_pages            : integer;
      g_num_ports            : integer;
      g_fifo_size            : integer;
      g_page_addr_width      : integer;
      g_partial_select_width : integer);
    port (
      clk_io_i        : in  std_logic;
      clk_core_i      : in  std_logic;
      rst_n_io_i      : in  std_logic;
      rst_n_core_i    : in  std_logic;
      wport_d_i       : in  std_logic_vector (g_num_ports * g_data_width -1 downto 0);
      wport_dvalid_i  : in  std_logic_vector (g_num_ports-1 downto 0);
      wport_dlast_i   : in  std_logic_vector (g_num_ports-1 downto 0);
      wport_pg_addr_i : in  std_logic_vector (g_num_ports * g_page_addr_width -1 downto 0);
      wport_pg_req_o  : out std_logic_vector(g_num_ports -1 downto 0);
      wport_dreq_o    : out std_logic_vector (g_num_ports-1 downto 0);
      fbm_addr_o      : out std_logic_vector(f_log2_size(g_num_pages * g_page_size / g_ratio)-1 downto 0);
      fbm_data_o      : out std_logic_vector(g_ratio * g_data_width -1 downto 0);
      fbm_we_o        : out std_logic);
  end component;

  component mpm_read_path
    generic (
      g_data_width           : integer;
      g_ratio                : integer;
      g_page_size            : integer;
      g_num_pages            : integer;
      g_num_ports            : integer;
      g_fifo_size            : integer;
      g_page_addr_width      : integer;
      g_partial_select_width : integer;
      g_max_oob_size         : integer;
      g_max_packet_size      : integer;
      g_ll_data_width        : integer);
    port (
      clk_io_i         : in  std_logic;
      clk_core_i       : in  std_logic;
      rst_n_io_i       : in  std_logic;
      rst_n_core_i     : in  std_logic;
      rport_d_o        : out std_logic_vector (g_num_ports * g_data_width -1 downto 0);
      rport_dvalid_o   : out std_logic_vector (g_num_ports-1 downto 0);
      rport_dlast_o    : out std_logic_vector (g_num_ports-1 downto 0);
      rport_dsel_o     : out std_logic_vector(g_num_ports * g_partial_select_width -1 downto 0);
      rport_dreq_i     : in  std_logic_vector (g_num_ports-1 downto 0);
      rport_abort_i    : in  std_logic_vector (g_num_ports-1 downto 0);
      rport_pg_addr_i  : in  std_logic_vector (g_num_ports * g_page_addr_width -1 downto 0);
      rport_pg_req_o   : out std_logic_vector(g_num_ports-1 downto 0);
      rport_pg_valid_i : in  std_logic_vector (g_num_ports-1 downto 0);
      ll_addr_o        : out std_logic_vector(g_page_addr_width-1 downto 0);
      ll_data_i        : in  std_logic_vector(g_ll_data_width  -1 downto 0);
      fbm_addr_o       : out std_logic_vector(f_log2_size(g_num_pages * g_page_size / g_ratio)-1 downto 0);
      fbm_data_i       : in  std_logic_vector(g_ratio * g_data_width -1 downto 0));
  end component;

  signal fbm_wr_addr, fbm_rd_addr : std_logic_vector(f_log2_size(g_num_pages * g_page_size / g_ratio)-1 downto 0);
  signal fbm_wr_data, fbm_rd_data : std_logic_vector(g_ratio * g_data_width -1 downto 0);
  signal fbm_we                   : std_logic;
  
begin  -- rtl



  -- Reset synchronizer for the core clock domain
  U_Sync_Reset_Coreclk : gc_sync_ffs
    port map (
      clk_i    => clk_core_i,
      rst_n_i  => '1',
      data_i   => rst_n_i,
      synced_o => rst_n_core);

  rst_n_io <= rst_n_i;

  U_Write_Path : mpm_write_path
    generic map (
      g_data_width           => g_data_width,
      g_ratio                => g_ratio,
      g_page_size            => g_page_size,
      g_num_pages            => g_num_pages,
      g_num_ports            => g_num_ports,
      g_fifo_size            => g_fifo_size,
      g_page_addr_width      => g_page_addr_width,
      g_partial_select_width => g_partial_select_width)
    port map (
      clk_io_i        => clk_io_i,
      clk_core_i      => clk_core_i,
      rst_n_io_i      => rst_n_io,
      rst_n_core_i    => rst_n_core,
      wport_d_i       => wport_d_i,
      wport_dvalid_i  => wport_dvalid_i,
      wport_dlast_i   => wport_dlast_i,
      wport_pg_addr_i => wport_pg_addr_i,
      wport_pg_req_o  => wport_pg_req_o,
      wport_dreq_o    => wport_dreq_o,
      fbm_addr_o      => fbm_wr_addr,
      fbm_data_o      => fbm_wr_data,
      fbm_we_o        => fbm_we);

  U_Read_Path : mpm_read_path
    generic map (
      g_data_width           => g_data_width,
      g_ratio                => g_ratio,
      g_page_size            => g_page_size,
      g_num_pages            => g_num_pages,
      g_num_ports            => g_num_ports,
      g_fifo_size            => g_fifo_size,
      g_page_addr_width      => g_page_addr_width,
      g_partial_select_width => g_partial_select_width,
      g_max_oob_size         => g_max_oob_size,
      g_max_packet_size      => g_max_packet_size,
      g_ll_data_width        => g_ll_data_width)
    port map (
      clk_io_i         => clk_io_i,
      clk_core_i       => clk_core_i,
      rst_n_core_i          => rst_n_core,
      rst_n_io_i => rst_n_io,
      rport_d_o        => rport_d_o,
      rport_dvalid_o   => rport_dvalid_o,
      rport_dlast_o    => rport_dlast_o,
      rport_dsel_o     => rport_dsel_o,
      rport_dreq_i     => rport_dreq_i,
      rport_abort_i    => rport_abort_i,
      rport_pg_addr_i  => rport_pg_addr_i,
      rport_pg_req_o   => rport_pg_req_o,
      rport_pg_valid_i => rport_pg_valid_i,
      ll_addr_o        => ll_addr_o,
      ll_data_i        => ll_data_i,
      fbm_addr_o       => fbm_rd_addr,
      fbm_data_i       => fbm_rd_data);


  -- The Frame Buffer Memory (F.B.M.), Formerly known as F.... Big Memory
  U_F_B_Memory : generic_dpram
    generic map (
      g_data_width => g_data_width * g_ratio,
      g_size       => g_num_pages * (g_page_size / g_ratio),
      g_dual_clock => false)
    port map (
      rst_n_i => rst_n_core,
      clka_i  => clk_core_i,
      wea_i   => fbm_we,
      aa_i    => fbm_wr_addr,
      da_i    => fbm_wr_data,
      clkb_i => '0',
      web_i   => '0',
      ab_i    => fbm_rd_addr,
      qb_o    => fbm_rd_data);

end rtl;
