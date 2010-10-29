library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use std.textio.all;

use work.platform_specific.all;


entity generic_ssram_dp_rw_rw is
  generic(
    g_width     : integer;
    g_addr_bits : integer;
    g_size      : integer;
    g_init_file : string);
  port(
    clk_i   : in  std_logic;
    wr_en_a_i : in  std_logic;
    addr_a_i  : in  std_logic_vector(g_addr_bits-1 downto 0);
    data_a_i  : in  std_logic_vector(g_width-1 downto 0);
    q_a_o     : out std_logic_vector(g_width-1 downto 0);

    wr_en_b_i : in  std_logic;
    addr_b_i  : in  std_logic_vector(g_addr_bits-1 downto 0);
    data_b_i  : in  std_logic_vector(g_width-1 downto 0);
    q_b_o     : out std_logic_vector(g_width-1 downto 0));
end generic_ssram_dp_rw_rw;

architecture behavioral of generic_ssram_dp_rw_rw is
  type t_ram_array is array(2**g_addr_bits-1 downto 0) of std_logic_vector(g_width-1 downto 0);

  impure function f_load_from_file (file_name : in string) return t_ram_array is
    file rfile   : text is in file_name;
    variable l   : line;
    variable ram : t_ram_array;
    variable tmp : bit_vector(g_width-1 downto 0);
    variable i   : integer;
  begin

    if(file_name = "") then
      return ram;
    end if;

    i := 0;

    while (i<9999) loop

      if endfile(rfile) then 
        return ram;
      end if;
      
      readline (rfile, l);
      read (l, tmp);
      if(i<2**g_addr_bits) then
        ram(i) := to_stdLogicVector(tmp);
      end if;
      i      :=i+1;
    end loop;
    return ram;
  end function;

  shared variable ram_array : t_ram_array := f_load_from_file(g_init_file);
begin

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(wr_en_a_i = '1') then
        ram_array(conv_integer(addr_a_i)) := data_a_i;
      end if;
      q_a_o <= ram_array(conv_integer(addr_a_i));
    end if;
  end process;

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(wr_en_b_i = '1') then
        ram_array(conv_integer(addr_b_i)) := data_b_i;
      end if;
      q_b_o <= ram_array(conv_integer(addr_b_i));
    end if;
  end process;

end behavioral;
