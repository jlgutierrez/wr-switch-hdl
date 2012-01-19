library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.genram_pkg.all;                -- for f_log2_size

entity swc_async_shrink_fifo is
  
  generic (
    g_width : integer;                  -- narrow port width
    g_ratio : integer;
    g_size  : integer);

  port (
    rst_n_i  : in std_logic;
    clk_wr_i : in std_logic;
    clk_rd_i : in std_logic;

    we_i : in std_logic;
    d_i  : in std_logic_vector(g_width*g_ratio-1 downto 0);

    rd_i : in  std_logic;
    q_o  : out std_logic_vector(g_width-1 downto 0);

    full_o  : out std_logic;
    empty_o : out std_logic);

end swc_async_shrink_fifo;

architecture rtl of swc_async_shrink_fifo is

  component swc_fifo_mem_cell
    generic (
      g_width : integer;
      g_size  : integer);
    port (
      clk_i : in  std_logic;
      wa_i  : in  std_logic_vector(f_log2_size(g_size)-1 downto 0);
      wd_i  : in  std_logic_vector(g_width-1 downto 0);
      we_i  : in  std_logic;
      ra_i  : in  std_logic_vector(f_log2_size(g_size)-1 downto 0);
      rd_o  : out std_logic_vector(g_width-1 downto 0));
  end component;

  component swc_async_fifo_ctrl
    generic (
      g_size : integer);
    port (
      rst_n_i   : in  std_logic;
      clk_wr_i  : in  std_logic;
      clk_rd_i  : in  std_logic;
      rd_i      : in  std_logic;
      wr_i      : in  std_logic;
      wr_addr_o : out std_logic_vector(f_log2_size(g_size)-1 downto 0);
      rd_addr_o : out std_logic_vector(f_log2_size(g_size)-1 downto 0);
      full_o    : out std_logic;
      empty_o   : out std_logic);
  end component;

  signal rd_count         : unsigned(3 downto 0);
  signal real_rd          : std_logic;
  signal q_int            : std_logic_vector(g_width*g_ratio-1 downto 0);
  signal wr_addr, rd_addr : std_logic_vector(f_log2_size(g_size)-1 downto 0);
  signal empty_int        : std_logic;
  signal line_flushed     : std_logic;
begin  -- rtl

  gen_mem_cells : for i in 0 to g_ratio-1 generate

    U_Mem : swc_fifo_mem_cell
      generic map (
        g_width => g_width,
        g_size  => g_size)
      port map (
        clk_i => clk_wr_i,
        wa_i  => wr_addr,
        wd_i  => d_i(g_width*(i+1) -1 downto g_width*i),
        we_i  => we_i,
        ra_i  => rd_addr,
        rd_o  => q_int(g_width*(i+1) -1 downto g_width*i));
  end generate gen_mem_cells;

  U_CTRL : swc_async_fifo_ctrl
    generic map (
      g_size => g_size)
    port map (
      rst_n_i   => rst_n_i,
      clk_wr_i  => clk_wr_i,
      clk_rd_i  => clk_rd_i,
      rd_i      => real_rd,
      wr_i      => we_i,
      wr_addr_o => wr_addr,
      rd_addr_o => rd_addr,
      full_o    => full_o,
      empty_o   => empty_int);

  p_read_mux : process(clk_rd_i, rst_n_i)
  begin
    if rst_n_i = '0' then
      rd_count <= (others => '0');
      q_o      <= (others => '0');
    elsif rising_edge(clk_rd_i) then
      if(rd_i = '1' and empty_int = '0') then
        if(rd_count = g_ratio-1) then
          rd_count <= (others => '0');
        else
          rd_count <= rd_count + 1;
        end if;

        q_o <= q_int(((to_integer(rd_count)+1)*g_width)-1 downto to_integer(rd_count)*g_width);
      end if;
      
    end if;
  end process;


  line_flushed <= '1' when (rd_count = g_ratio-1) else '0';
  real_rd      <= line_flushed and rd_i;

  empty_o <= empty_int and line_flushed;
  
end rtl;
