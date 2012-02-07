library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.genram_pkg.all;                -- for f_log2_size

entity mpm_async_shrink_fifo is
  
  generic (
    g_width          : integer;         -- narrow port width
    g_ratio          : integer;
    g_size           : integer;
    g_sideband_width : integer);

  port (
    rst_n_a_i : in std_logic;
    clk_wr_i  : in std_logic;
    clk_rd_i  : in std_logic;

    we_i : in std_logic;
    d_i  : in std_logic_vector(g_width*g_ratio-1 downto 0);

    rd_i : in  std_logic;
    q_o  : out std_logic_vector(g_width-1 downto 0);

    side_i : in  std_logic_vector(g_sideband_width-1 downto 0);
    side_o : out std_logic_vector(g_sideband_width-1 downto 0);

    flush_i : in  std_logic := '0';
    full_o  : out std_logic;
    empty_o : out std_logic);

end mpm_async_shrink_fifo;

architecture rtl of mpm_async_shrink_fifo is

  component mpm_fifo_mem_cell
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

  component mpm_async_fifo_ctrl
    generic (
      g_size : integer);
    port (
      rst_n_a_i : in  std_logic;
      clk_wr_i  : in  std_logic;
      clk_rd_i  : in  std_logic;
      rd_i      : in  std_logic;
      wr_i      : in  std_logic;
      wr_addr_o : out std_logic_vector(f_log2_size(g_size)-1 downto 0);
      rd_addr_o : out std_logic_vector(f_log2_size(g_size)-1 downto 0);
      full_o    : out std_logic;
      empty_o   : out std_logic);
  end component;

  signal rd_count                 : unsigned(3 downto 0);
  signal real_rd                  : std_logic;
  signal q_muxed                  : std_logic_vector(g_width-1 downto 0);
  signal q_comb, q_reg            : std_logic_vector(g_width*g_ratio-1 downto 0);
  signal wr_addr, rd_addr         : std_logic_vector(f_log2_size(g_size)-1 downto 0);
  signal empty_wide, empty_narrow : std_logic;
  signal line_flushed             : std_logic;
  
begin  -- rtl


  gen_sb_mem : if(g_sideband_width > 0) generate
    U_Sideband_Mem : mpm_fifo_mem_cell
      generic map (
        g_width => g_sideband_width,
        g_size  => g_size)
      port map (
        clk_i => clk_wr_i,
        wa_i  => wr_addr,
        wd_i  => side_i,
        we_i  => we_i,
        ra_i  => rd_addr,
        rd_o  => side_o);
  end generate gen_sb_mem;

  gen_mem_cells : for i in 0 to g_ratio-1 generate

    U_Mem : mpm_fifo_mem_cell
      generic map (
        g_width => g_width,
        g_size  => g_size)
      port map (
        clk_i => clk_wr_i,
        wa_i  => wr_addr,
        wd_i  => d_i(g_width*(i+1) -1 downto g_width*i),
        we_i  => we_i,
        ra_i  => rd_addr,
        rd_o  => q_comb(g_width*(i+1) -1 downto g_width*i));
  end generate gen_mem_cells;

  U_CTRL : mpm_async_fifo_ctrl
    generic map (
      g_size => g_size)
    port map (
      rst_n_a_i => rst_n_a_i,
      clk_wr_i  => clk_wr_i,
      clk_rd_i  => clk_rd_i,
      rd_i      => real_rd,
      wr_i      => we_i,
      wr_addr_o => wr_addr,
      rd_addr_o => rd_addr,
      full_o    => full_o,
      empty_o   => empty_wide);

  p_read_mux : process(clk_rd_i, rst_n_a_i)
  begin
    if rst_n_a_i = '0' then
      rd_count     <= (others => '0');
      q_reg        <= (others => '0');
      line_flushed <= real_rd;
      empty_narrow <= '1';
    elsif rising_edge(clk_rd_i) then

      if(empty_wide = '0') then
        empty_narrow <= '0';
      elsif(((rd_count = g_ratio-1 and rd_i = '1') or flush_i = '1') and empty_wide = '1') then
        empty_narrow <= '1';
      end if;

      line_flushed <= real_rd;

      if(real_rd = '1')then
        q_reg <= q_comb;
      end if;

      if(rd_i = '1' or flush_i = '1') then
        if(rd_count = g_ratio-1 or flush_i = '1') then
          rd_count <= (others => '0');
        else
          rd_count <= rd_count + 1;
        end if;

        q_muxed <= q_reg(((to_integer(rd_count)+1)*g_width)-1 downto to_integer(rd_count)*g_width);
      end if;
      
    end if;
  end process;


  real_rd <= '1'                       when (rd_count = 0) and rd_i = '1' else '0';
  q_o     <= q_reg(g_width-1 downto 0) when line_flushed = '1'            else q_muxed;
  empty_o <= empty_narrow;
  
end rtl;
