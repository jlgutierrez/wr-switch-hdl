library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.genram_pkg.all;                -- for f_log2_size

entity mpm_async_fifo is
  
  generic (
    g_width : integer := 11 + 1;
    g_size  : integer := 8);

  port (
    rst_n_a_i : in std_logic;
    clk_wr_i  : in std_logic;
    clk_rd_i  : in std_logic;

    we_i : in std_logic;
    d_i  : in std_logic_vector(g_width-1 downto 0);

    rd_i : in  std_logic;
    q_o  : out std_logic_vector(g_width-1 downto 0);

    full_o  : out std_logic;
    empty_o : out std_logic);

end mpm_async_fifo;

architecture rtl of mpm_async_fifo is

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

  signal q_comb           : std_logic_vector(g_width-1 downto 0);
  signal wr_addr, rd_addr : std_logic_vector(f_log2_size(g_size)-1 downto 0);
  
begin  -- rtl


  U_Mem_Mem : mpm_fifo_mem_cell
    generic map (
      g_width => g_width,
      g_size  => g_size)
    port map (
      clk_i => clk_wr_i,
      wa_i  => wr_addr,
      wd_i  => d_i,
      we_i  => we_i,
      ra_i  => rd_addr,
      rd_o  => q_comb);


  U_CTRL : mpm_async_fifo_ctrl
    generic map (
      g_size => g_size)
    port map (
      rst_n_a_i => rst_n_a_i,
      clk_wr_i  => clk_wr_i,
      clk_rd_i  => clk_rd_i,
      rd_i      => rd_i,
      wr_i      => we_i,
      wr_addr_o => wr_addr,
      rd_addr_o => rd_addr,
      full_o    => full_o,
      empty_o   => empty_o);

  p_output_reg : process(clk_rd_i)
  begin
    if rising_edge(clk_rd_i) then
      q_o <= q_comb;
    end if;
  end process;
  
end rtl;
