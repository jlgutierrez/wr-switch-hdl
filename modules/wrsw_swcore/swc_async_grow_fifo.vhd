library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.genram_pkg.all;                -- for f_log2_size

entity swc_async_grow_fifo is
  
  generic (
    g_width : integer := 16;
    g_ratio : integer := 6;
    g_size  : integer := 8);

  port (
    rst_n_i  : in std_logic;
    clk_wr_i : in std_logic;
    clk_rd_i : in std_logic;

    we_i    : in std_logic;
    align_i : in std_logic;             -- 1: aligned write
    d_i     : in std_logic_vector(g_width-1 downto 0);

    rd_i : in  std_logic;
    q_o  : out std_logic_vector(g_width * g_ratio-1 downto 0);

    full_o  : out std_logic;
    empty_o : out std_logic);

end swc_async_grow_fifo;

architecture rtl of swc_async_grow_fifo is

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

  signal wr_sreg          : std_logic_vector(g_ratio-1 downto 0);
  signal wr_cell          : std_logic_vector(g_ratio-1 downto 0);
  signal real_we          : std_logic;
  signal q_int            : std_logic_vector(g_width*g_ratio-1 downto 0);
  signal wr_addr, rd_addr : std_logic_vector(f_log2_size(g_size)-1 downto 0);
  signal full_int         : std_logic;
  
begin  -- rtl

  gen_mem_cells : for i in 0 to g_ratio-1 generate

    wr_cell(i) <= wr_sreg(i) and we_i;

    U_Mem : swc_fifo_mem_cell
      generic map (
        g_width => g_width,
        g_size  => g_size)
      port map (
        clk_i => clk_wr_i,
        wa_i  => wr_addr,
        wd_i  => d_i,
        we_i  => wr_cell(i),
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
      rd_i      => rd_i,
      wr_i      => real_we,
      wr_addr_o => wr_addr,
      rd_addr_o => rd_addr,
      full_o    => full_int,
      empty_o   => empty_o);

  p_write_grow_sreg : process(clk_wr_i, rst_n_i)
  begin
    if rst_n_i = '0' then
      wr_sreg(0)                     <= '1';
      wr_sreg(wr_sreg'left downto 1) <= (others => '0');
    elsif rising_edge(clk_wr_i) then
      if(we_i = '1') then
        if(align_i = '1') then
          wr_sreg(0)                     <= '1';
          wr_sreg(wr_sreg'left downto 1) <= (others => '0');
        else
          wr_sreg <= wr_sreg(wr_sreg'left-1 downto 0) & wr_sreg(wr_sreg'left);
        end if;
      end if;
    end if;
  end process;

  real_we <= wr_cell(wr_cell'left);

  p_output_reg : process(clk_rd_i, rst_n_i)
  begin
    if (rst_n_i = '0') then
      q_o <= (others => '0');
    elsif rising_edge(clk_rd_i) then
      if(rd_i = '1') then
        q_o <= q_int;
      end if;
    end if;
  end process;

  full_o <= full_int and wr_sreg(wr_sreg'left);
  
end rtl;
