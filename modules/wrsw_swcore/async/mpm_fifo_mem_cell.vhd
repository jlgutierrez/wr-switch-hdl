library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.genram_pkg.all;

entity mpm_fifo_mem_cell is
  
  generic (
    g_width : integer;
    g_size  : integer);

  port (
    clk_i : in std_logic;
    wa_i  : in std_logic_vector(f_log2_size(g_size)-1 downto 0);
    wd_i  : in std_logic_vector(g_width-1 downto 0);
    we_i  : in std_logic;

    ra_i : in  std_logic_vector(f_log2_size(g_size)-1 downto 0);
    rd_o : out std_logic_vector(g_width-1 downto 0));

end mpm_fifo_mem_cell;

architecture rtl of mpm_fifo_mem_cell is
  type t_mem_array is array(0 to g_size-1) of std_logic_vector(g_width-1 downto 0);

  signal mem : t_mem_array;
begin  -- rtl

  rd_o <= mem(to_integer(unsigned(ra_i)));
  p_write : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(we_i = '1') then
        mem(to_integer(unsigned(wa_i))) <= wd_i;
      end if;
    end if;
  end process;
end rtl;
