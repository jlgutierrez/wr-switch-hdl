library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.mpm_private_pkg.all;

use work.gencores_pkg.all;              -- for f_rr_arbitrate
use work.genram_pkg.all;                -- for f_log2_size

entity mpm_read_path is
  
  generic (
    g_data_width           : integer;
    g_ratio                : integer;
    g_page_size            : integer;
    g_num_pages            : integer;
    g_num_ports            : integer;
    g_fifo_size            : integer;
    g_page_addr_width      : integer;
    g_partial_select_width : integer;
    g_max_packet_size      : integer
    );

  port(
    -- I/O ports clock (slow)
    clk_io_i     : in std_logic;
    -- Memory/Core clock (fast)
    clk_core_i   : in std_logic;
    rst_n_io_i   : in std_logic;
    rst_n_core_i : in std_logic;

-- read-write ports I/F (streaming)
    rport_d_o        : out std_logic_vector (g_num_ports * g_data_width -1 downto 0);
    rport_dvalid_o   : out std_logic_vector (g_num_ports-1 downto 0);
    rport_dlast_o    : out std_logic_vector (g_num_ports-1 downto 0);
    rport_dsel_o     : out std_logic_vector(g_partial_select_width -1 downto 0);
    rport_dreq_i     : in  std_logic_vector (g_num_ports-1 downto 0);
    rport_abort_i    : in  std_logic_vector (g_num_ports-1 downto 0);
    rport_pg_addr_i  : in  std_logic_vector (g_num_ports * g_page_addr_width -1 downto 0);
    rport_pg_req_o   : out std_logic_vector(g_num_ports-1 downto 0);
    rport_pg_valid_i : in  std_logic_vector (g_num_ports-1 downto 0);

    -- Linked List I/F (I/O clock domain)
    ll_addr_o : out std_logic_vector(g_page_addr_width-1 downto 0);
    ll_data_i : in  std_logic_vector(g_page_addr_width+1 downto 0);

    -- F. B. Memory I/F
    fbm_addr_o : out std_logic_vector(f_log2_size(g_num_pages * g_page_size / g_ratio)-1 downto 0);
    fbm_data_i : in  std_logic_vector(g_ratio * g_data_width -1 downto 0)
    );

end mpm_read_path;

architecture rtl of mpm_read_path is

  component mpm_rpath_io_block
    generic (
      g_data_width           : integer;
      g_page_addr_width      : integer;
      g_page_size            : integer;
      g_partial_select_width : integer;
      g_ratio                : integer;
      g_max_packet_size      : integer);
    port (
      clk_io_i         : in  std_logic;
      rst_n_io_i       : in  std_logic;
      rport_d_o        : out std_logic_vector(g_page_addr_width-1 downto 0);
      rport_dvalid_o   : out std_logic;
      rport_dlast_o    : out std_logic;
      rport_dsel_o     : out std_logic_vector(g_partial_select_width-1 downto 0);
      rport_dreq_i     : in  std_logic;
      rport_abort_i    : in  std_logic;
      rport_pg_req_o   : out std_logic;
      rport_pg_valid_i : in  std_logic;
      rport_pg_addr_i  : in  std_logic_vector(g_page_addr_width-1 downto 0);
      ll_req_o         : out std_logic;
      ll_grant_i       : in  std_logic;
      ll_addr_o        : out std_logic_vector(g_page_addr_width-1 downto 0);
      ll_data_i        : in  std_logic_vector(g_page_addr_width + 1 downto 0);
      pf_full_i        : in  std_logic;
      pf_we_o          : out std_logic;
      pf_pg_addr_o     : out std_logic_vector(g_page_addr_width-1 downto 0);
      pf_pg_lines_o    : out std_logic_vector(f_log2_size(g_page_size / g_ratio)-1 downto 0);
      df_empty_i       : in  std_logic;
      df_flush_o       : out std_logic;
      df_rd_o          : out std_logic;
      df_d_i           : in  std_logic_vector(g_data_width-1 downto 0));
  end component;


  constant c_page_count_width    : integer := f_log2_size(g_max_packet_size / g_page_size + 1);
  constant c_line_size_width     : integer := f_log2_size(g_page_size / g_ratio);
  constant c_fbm_data_width      : integer := g_ratio * g_data_width;
  constant c_fbm_entries         : integer := g_num_pages * g_page_size / g_ratio;
  constant c_fbm_addr_width      : integer := f_log2_size(c_fbm_entries);
  constant c_fifo_sideband_width : integer := c_fbm_addr_width;

  type t_mpm_read_port is record
    d        : std_logic_vector(g_data_width-1 downto 0);
    d_valid  : std_logic;
    d_last   : std_logic;
    d_sel    : std_logic_vector(g_partial_select_width-1 downto 0);
    d_req    : std_logic;
    pg_addr  : std_logic_vector(g_page_addr_width-1 downto 0);
    pg_valid : std_logic;
    pg_req   : std_logic;
    abort    : std_logic;

  end record;

  type t_mpm_read_port_array is array (integer range <>) of t_mpm_read_port;

  type t_rport_io_state is record
    -- Data FIFO output port
    df_rd    : std_logic;
    df_empty : std_logic;
    df_flush : std_logic;
    df_q     : std_logic_vector(c_fbm_data_width -1 downto 0);

    -- Page FIFO input port
    pf_full     : std_logic;
    pf_we       : std_logic;
    pf_pg_addr  : std_logic_vector(g_page_addr_width-1 downto 0);
    pf_pg_lines : std_logic_vector(c_line_size_width-1 downto 0);
    pf_d        : std_logic_vector(c_line_size_width + g_page_addr_width -1 downto 0);

    -- Linked list address & arbitration
    ll_req     : std_logic;
    ll_grant_d : std_logic_vector(2 downto 0);
    ll_addr    : std_logic_vector(g_page_addr_width-1 downto 0);
  end record;

  -- clk_core_i domain state
  type t_rport_core_state is record
    df_full : std_logic;
    df_we   : std_logic;


    
    pf_q         : std_logic_vector(g_page_addr_width + c_line_size_width-1 downto 0);
    pf_rd        : std_logic;
    pf_empty     : std_logic;
    pg_remaining : std_logic_vector(c_line_size_width - 1 downto 0);
    fbm_addr     : std_logic_vector(c_fbm_addr_width - 1 downto 0);
    mem_req      : std_logic;
    mem_grant_d  : std_logic_vector(3 downto 0);
  end record;

-------------------------------------------------------------------------------
-- Functions
-------------------------------------------------------------------------------

  type t_rport_core_state_array is array(integer range <>) of t_rport_core_state;
  type t_rport_io_state_array is array(integer range <>) of t_rport_io_state;

  signal mem_req, mem_grant : std_logic_vector(g_num_ports-1 downto 0);
  signal ll_req, ll_grant   : std_logic_vector(g_num_ports-1 downto 0);

  signal io   : t_rport_io_state_array(g_num_ports-1 downto 0);
  signal core : t_rport_core_state_array(g_num_ports-1 downto 0);

  signal rport : t_mpm_read_port_array(g_num_ports-1 downto 0);

  signal rd_mux_a_in : std_logic_vector(g_num_ports * c_fbm_data_width -1 downto 0);
  signal rd_mux_sel  : std_logic_vector(g_num_ports-1 downto 0);

  signal fbm_data_reg : std_logic_vector(c_fbm_data_width-1 downto 0);

begin  -- rtl

-- I/O structure serialization/deserialization
  gen_serialize_ios : for i in 0 to g_num_ports-1 generate

    rport_d_o (g_data_width * (i+1) - 1 downto g_data_width * i) <=
      rport(i).d;
    rport_dvalid_o(i) <=
      rport(i).d_valid;
    rport_dlast_o(i) <=
      rport(i).d_last;
    rport_dsel_o(g_partial_select_width * (i+1) - 1 downto g_partial_select_width * i) <=
      rport(i).d_sel;

    rport(i).d_req    <= rport_dreq_i(i);
    rport(i).abort    <= rport_abort_i(i);
    rport(i).pg_addr  <= f_slice(rport_pg_addr_i, i, g_page_addr_width);
    rport(i).pg_valid <= rport_pg_valid_i(i);
    rport_pg_req_o(i) <= rport(i).pg_req;

  end generate gen_serialize_ios;



  -- The actual round-robin arbiter for muxing memory accesses.
  p_mem_arbiter : process(clk_core_i)
  begin
    if rising_edge(clk_core_i) then
      if rst_n_core_i = '0' then
        mem_grant <= (others => '0');
      else
        f_rr_arbitrate(mem_req, mem_grant, mem_grant);
      end if;
    end if;
  end process;

  gen_mem_access_arbiter : for i in 0 to g_num_ports-1 generate

    mem_req(i)             <= core(i).mem_req and not core(i).mem_grant_d(0);
    core(i).mem_grant_d(0) <= mem_grant(i);

    -- Delay the grant signal to generate enables for each pipeline stage
    process(clk_core_i)
    begin
      if rising_edge(clk_core_i) then
        if rst_n_core_i = '0' then
          core(i).mem_grant_d(3 downto 1) <= (others => '0');
        else
          core(i).mem_grant_d(3) <= core(i).mem_grant_d(2);
          core(i).mem_grant_d(2) <= core(i).mem_grant_d(1);
          core(i).mem_grant_d(1) <= core(i).mem_grant_d(0);
        end if;
      end if;
    end process;
  end generate gen_mem_access_arbiter;

  gen_mux_inputs : for i in 0 to g_num_ports-1 generate
    rd_mux_a_in(c_fbm_addr_width * (i + 1) - 1 downto c_fbm_addr_width * i) <= core(i).fbm_addr;
    rd_mux_sel(i)                                                           <= core(i).mem_grant_d(0);
  end generate gen_mux_inputs;

  U_Rd_Address_Mux : mpm_pipelined_mux
    generic map (
      g_width  => c_fbm_addr_width,
      g_inputs => g_num_ports)
    port map (
      clk_i   => clk_core_i,
      rst_n_i => rst_n_core_i,
      d_i     => rd_mux_a_in,
      q_o     => fbm_addr_o,
      sel_i   => rd_mux_sel);

  p_fbm_data_reg : process(clk_core_i)
  begin
    if rising_edge(clk_core_i) then
      fbm_data_reg <= fbm_data_i;
    end if;
  end process;


  gen_fifos : for i in 0 to g_num_ports-1 generate
    U_Page_Fifo : mpm_async_fifo
      generic map (
        g_width => g_page_addr_width + 1,
        g_size  => 8)
      port map (
        rst_n_a_i => rst_n_core_i,
        clk_wr_i  => clk_io_i,
        clk_rd_i  => clk_core_i,
        we_i      => io(i).pf_we,
        d_i       => io(i).pf_d,
        rd_i      => core(i).pf_rd,
        q_o       => core(i).pf_q,
        full_o    => io(i).pf_full,
        empty_o   => core(i).pf_empty);

    U_Output_Fifo : mpm_async_shrink_fifo
      generic map (
        g_width          => g_data_width,
        g_ratio          => g_ratio,
        g_size           => g_fifo_size,
        g_sideband_width => 0)
      port map (
        rst_n_a_i => rst_n_core_i,
        clk_wr_i  => clk_core_i,
        clk_rd_i  => clk_io_i,
        we_i      => core(i).df_we,
        d_i       => fbm_data_reg,
        rd_i      => io(i).df_rd,
        q_o       => io(i).df_q,
        side_i => "",
        flush_i   => io(i).df_flush,
        full_o    => core(i).df_full,
        empty_o   => io(i).df_empty);

  end generate gen_fifos;


-- The arbiter for accessing the linked list
  p_ll_arbiter : process(clk_io_i)
  begin
    if rising_edge(clk_io_i) then
      if rst_n_io_i = '0' then
        ll_grant <= (others => '0');
      else
        f_rr_arbitrate(ll_req, ll_grant, ll_grant);
      end if;
    end if;
  end process;

  gen_ll_access_arbiter : for i in 0 to g_num_ports-1 generate
    ll_req(i)           <= io(i).ll_req and not io(i).ll_grant_d(0);
    io(i).ll_grant_d(0) <= ll_grant(i);
  end generate gen_ll_access_arbiter;

  p_ll_mux_addr : process(clk_io_i)
    variable muxed : std_logic_vector(g_page_addr_width-1 downto 0);
  begin
    if rising_edge(clk_io_i) then
      if rst_n_io_i = '0' then
        ll_addr_o <= (others => '0');
      else
        for i in 0 to g_num_ports-1 loop
          if(io(i).ll_grant_d(0) = '1') then
            muxed := io(i).ll_addr;
          end if;
        end loop;  -- i
        ll_addr_o <= muxed;
      end if;
    end if;
  end process;


  gen_output_controllers : for i in 0 to g_num_ports-1 generate
    U_Output_Ctrl : mpm_rpath_io_block
      generic map (
        g_data_width           => g_data_width,
        g_page_addr_width      => g_page_addr_width,
        g_page_size            => g_page_size,
        g_partial_select_width => g_partial_select_width,
        g_ratio                => g_ratio,
        g_max_packet_size      => g_max_packet_size)
      port map (
        clk_io_i         => clk_io_i,
        rst_n_io_i       => rst_n_io_i,
        rport_d_o        => rport(i).d,
        rport_dvalid_o   => rport(i).d_valid,
        rport_dlast_o    => rport(i).d_last,
        rport_dsel_o     => rport(i).d_sel,
        rport_dreq_i     => rport(i).d_req,
        rport_abort_i    => rport(i).abort,
        rport_pg_req_o   => rport(i).pg_req,
        rport_pg_valid_i => rport(i).pg_valid,
        rport_pg_addr_i  => rport(i).pg_addr,
        ll_req_o         => io(i).ll_req,
        ll_grant_i       => io(i).ll_grant_d(2),
        ll_addr_o        => io(i).ll_addr,
        ll_data_i        => ll_data_i,
        pf_full_i        => io(i).pf_full,
        pf_we_o          => io(i).pf_we,
        pf_pg_addr_o     => io(i).pf_pg_addr,
        pf_pg_lines_o    => io(i).pf_pg_lines,
        df_empty_i       => io(i).df_empty,
        df_flush_o       => io(i).df_flush,
        df_rd_o          => io(i).df_rd,
        df_d_i           => io(i).df_q);

    io(i).pf_d <= io(i).pf_pg_lines & io(i).pf_pg_addr;
  end generate gen_output_controllers;
  

end rtl;
