library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.swc_private_pkg.all;
use work.genram_pkg.all;

entity swc_async_multiport_mem is
  
  generic (
    g_ratio     : integer;
    g_page_size : integer;
    g_num_pages : integer;
    g_num_ports : integer
    );

  port(
    -- I/O ports clock (slow)
    clk_io_i   : in std_logic;
    -- Memory/Core clock (fast)
    clk_core_i : in std_logic;
    rst_n_i    : in std_logic;

-- read-write ports I/F (streaming)
    wport_i : in  t_mpm_write_in_array(0 to g_num_ports-1);
    wport_o : out t_mpm_write_out_array(0 to g_num_ports-1);

    rport_i : in  t_mpm_read_in_array(0 to g_num_ports-1);
    rport_o : out t_mpm_read_out_array(0 to g_num_ports-1);

-- linked list I/F

    ll_addr_o : out std_logic_vector(f_log2_size(g_num_pages)-1 downto 0);
    ll_data_o : out std_logic_vector(f_log2_size(g_num_pages)-1 downto 0);
    ll_data_i : in  std_logic_vector(f_log2_size(g_num_pages)-1 downto 0);
    ll_we_o   : out std_logic
    );

end swc_async_multiport_mem;

architecture rtl of swc_async_multiport_mem is

  
  component swc_async_grow_fifo
    generic (
      g_width : integer;
      g_ratio : integer;
      g_size  : integer);
    port (
      rst_n_i  : in  std_logic;
      clk_wr_i : in  std_logic;
      clk_rd_i : in  std_logic;
      align_i  : in  std_logic;
      we_i     : in  std_logic;
      d_i      : in  std_logic_vector(g_width-1 downto 0);
      rd_i     : in  std_logic;
      q_o      : out std_logic_vector(g_width * g_ratio-1 downto 0);
      full_o   : out std_logic;
      empty_o  : out std_logic);
  end component;

  type t_fifo_slv_array is array(0 to g_num_ports-1) of std_logic_vector(c_data_path_width downto 0);

  type t_wport_state is record
    cur_page    : unsigned(c_page_addr_width-1 downto 0);
    cur_offset  : unsigned(f_log2_size(g_page_size)-1 downto 0);
    cur_valid   : std_logic;
    next_page   : unsigned(c_page_addr_width-1 downto 0);
    next_offset : unsigned(f_log2_size(g_page_size)-1 downto 0);
    next_valid  : std_logic;

    fifo_empty  : std_logic;
    fifo_full   : std_logic;
    fifo_nempty : std_logic;
    fifo_rd     : std_logic;
    fifo_q      : std_logic_vector((c_data_path_width+1) * g_ratio - 1 downto 0);
  end record;

  type t_wport_state_array is array(0 to g_num_ports-1) of t_wport_state;

  signal w_req, w_sel, w_mask : std_logic_vector(f_log2_size(g_num_ports)-1 downto 0);
  signal wstate               : t_wport_state_array;

  procedure f_rr_arbitrate (
    signal req       : in  std_logic_vector;
    signal pre_grant : in  std_logic_vector;
    signal grant     : out std_logic_vector)is

    variable reqs  : std_logic_vector(g_width - 1 downto 0);
    variable gnts  : std_logic_vector(g_width - 1 downto 0);
    variable gnt   : std_logic_vector(g_width - 1 downto 0);
    variable gntM  : std_logic_vector(g_width - 1 downto 0);
    variable zeros : std_logic_vector(g_width - 1 downto 0);
    
  begin
    zeros := (others => '0');

    -- bit twiddling magic :
    s_gnt  := req and std_logic_vector(unsigned(not req) + 1);
    s_reqs := req and not (std_logic_vector(unsigned(pre_grant) - 1) or pre_grant);
    s_gnts := reqs and std_logic_vector(unsigned(not reqs)+1);
    s_gntM := gnt when reqs = zeros else gnts;

    if((req and pre_grant) = s_zeros) then
      grant       <= gntM;
      s_pre_grant <= gntM;  -- remember current grant vector, for the next operation
    end if;
    
  end f_rr_arbitrate;
  
  
begin  -- rtl

  gen_input_fifos : for i in 0 to g_num_ports-1 generate

    U_Input_FIFOx : swc_async_grow_fifo
      generic map (
        g_width => c_data_path_width + 1,
        g_ratio => g_ratio,
        g_size  => c_mpm_async_fifo_depth)
      port map (
        rst_n_i                           => rst_n_i,
        clk_wr_i                          => clk_io_i,
        clk_rd_i                          => clk_core_i,
        we_i                              => wport_i(i).d_valid,
        d_i(c_data_path_width-2 downto 0) => wport_i(i).d,
        d_i(c_data_path_width-1)          => wport_i(i).d_eof,
        align_i                           => wport_i(i).d_eof,

        rd_i    => wstate(i).fifo_rd,
        q_o     => wstate(i).fifo_q,
        full_o  => wstate(i).fifo_full,
        empty_o => wstate(i).fifo_empty);
  end generate gen_input_fifos;



  
end rtl;
