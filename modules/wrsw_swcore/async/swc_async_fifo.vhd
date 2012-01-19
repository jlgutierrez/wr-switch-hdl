library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.genram_pkg.all;                -- for f_log2_size

entity swc_async_grow_fifo is
  
  generic (
    g_width : integer;
    g_ratio : integer;
    g_size  : integer);

  port (
    rst_n_i  : in std_logic;
    clk_wr_i : in std_logic;
    clk_rd_i : in std_logic;

    we_i : in std_logic;
    d_i  : in std_logic_vector(g_width-1 downto 0);

    rd_i : in  std_logic;
    q_o  : out std_logic_vector(g_width * g_ratio-1 downto 0);

    wr_full_o  : out std_logic;
    rd_empty_o : out std_logic);

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
  
  signal wr_sreg        : std_logic_vector(g_ratio-1 downto 0);
  signal wr_cell        : std_logic_vector(g_ratio-1 downto 0);
  signal real_we             : std_logic;
  signal q_int               : std_logic_vector(g_width*g_ratio-1 downto 0);
  signal wr_addr, rd_addr : std_logic_vector(f_log2_size(g_size)-1 downto 0);
  
begin  -- rtl

  gen_mem_cells : for i in 0 to g_ratio-1 generate

    wr_cell(i) <= we_i and wr_sreg(i);
    U_Mem : swc_fifo_mem_cell
      generic map (
        g_width => g_width * g_ratio,
        g_size  => g_size)
      port map (
        clk_i => clk_wr_i,
        wa_i  => wr_addr,
        wd_i  => d_i,
        we_i  => rd_addr,
        ra_i  => std_logic_vector(rd_ptr),
        rd_o  => q_int(g_width*(i+1) -1 downto g_width*i));
  end generate gen_mem_cells;

  p_write_grow_sreg : process(clk_wr_i, rst_n_i)
  begin
    if rst_n_i = '0' then
      wr_sreg(0)                     <= '1';
      wr_sreg(wr_sreg'left downto 1) <= (others => '0');
      real_we                        <= '0';
    elsif rising_edge(clk_wr_i) then
      if(we_i = '1') then
        wr_sreg <= wr_sreg(wr_sreg'left-1 downto 0) & wr_sreg(wr_sreg'left);

        if(wr_sreg(wr_sreg'left) = '1' and full_int = '0') then
          real_we <= '1';
        else
          real_we <= '0';
        end if;
      else
        real_we <= '0';
      end if;
    end if;
  end process;

  
end rtl;
