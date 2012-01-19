library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.genram_pkg.all;

entity swc_async_fifo_ctrl is
  
  generic (
    g_size : integer);

  port(
    rst_n_i  : in std_logic;
    clk_wr_i : in std_logic;
    clk_rd_i : in std_logic;

    rd_i : in std_logic;
    wr_i : in std_logic;

    wr_addr_o : out std_logic_vector(f_log2_size(g_size)-1 downto 0);
    rd_addr_o : out std_logic_vector(f_log2_size(g_size)-1 downto 0);

    full_o  : out std_logic;
    empty_o : out std_logic);
  
end swc_async_fifo_ctrl;

architecture rtl of swc_async_fifo_ctrl is

  function f_gray_inc(x : unsigned) return unsigned is
    variable bin, tmp : unsigned(x'left downto 0);
  begin
  -- gray to binary
    for i in 0 to x'left loop
      bin(i) := '0';
      for j in i to x'left loop
        bin(i) := bin(i) xor x(j);
      end loop;  -- j 
    end loop;  -- i
    -- increase
    tmp := bin + 1;
    -- binary to gray
    return tmp(tmp'left) & (tmp(tmp'left-1 downto 0) xor tmp(tmp'left downto 1));
  end f_gray_inc;

  signal wr_ptr, rd_ptr : unsigned(f_log2_size(g_size) -1 downto 0);
  signal full_int, empty_int : std_logic;
  signal same_addr           : std_logic;
  signal rst_stat, set_stat  : std_logic;
  signal set_full, set_empty : std_logic;
  signal stat                : std_logic;
begin  -- rtl

  p_write_ptr : process(clk_wr_i, rst_n_i)
  begin
    if rst_n_i = '0' then
      wr_ptr <= (others => '0');
    elsif rising_edge(clk_wr_i) then
      if(wr_i = '1' and full_int = '0') then
        wr_ptr <= f_gray_inc(wr_ptr);
      end if;
    end if;
  end process;


  p_read_ptr : process(clk_rd_i, rst_n_i)
  begin
    if rst_n_i = '0' then
      rd_ptr <= (others => '0');
    elsif rising_edge(clk_rd_i) then
      if(rd_i = '1' and empty_int = '0') then
        rd_ptr <= f_gray_inc(rd_ptr);
      end if;
    end if;
  end process;

  p_quardant_status : process(rd_ptr, wr_ptr)
  begin
    set_stat <= (wr_ptr(wr_ptr'left-1) xnor rd_ptr(rd_ptr'left))
                and (wr_ptr(wr_ptr'left) xor rd_ptr(rd_ptr'left-1));
    rst_stat <= (wr_ptr(wr_ptr'left-1) xor rd_ptr(rd_ptr'left))
                and (wr_ptr(wr_ptr'left) xnor rd_ptr(rd_ptr'left-1));
  end process;

  process(set_stat, rst_stat, rst_n_i)
  begin
    if(rst_stat = '1' or rst_n_i = '0') then
      stat <= '0';
    elsif(set_stat = '1') then
      stat <= '1';
    end if;
  end process;

  set_full  <= '1' when (stat = '1' and wr_ptr = rd_ptr) else '0';
  set_empty <= '1' when (stat = '0' and wr_ptr = rd_ptr) else '0';

  p_full_flag : process(clk_wr_i, set_full)
  begin
    if(set_full = '1') then
      full_int <= '1';
    elsif rising_edge(clk_wr_i) then
      full_int <= set_full;
    end if;
  end process;

  p_empty_flag : process(clk_rd_i, set_empty)
  begin
    if(set_empty = '1') then
      empty_int <= '1';
    elsif rising_edge(clk_rd_i) then
      empty_int <= set_empty;
    end if;
  end process;

  full_o  <= full_int;
  empty_o <= empty_int;

  wr_addr_o <= std_logic_vector(wr_ptr);
  rd_addr_o <= std_logic_vector(rd_ptr);
end rtl;
