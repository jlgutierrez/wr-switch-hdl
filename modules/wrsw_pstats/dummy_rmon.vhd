library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dummy_rmon is
  generic(
    g_nports  : integer := 1;
    g_cnt_pp  : integer := 16);
  port(
    rst_n_i : in std_logic;
    clk_i   : in std_logic;
    events_i  : in std_logic_vector(g_nports*g_cnt_pp-1 downto 0));
end dummy_rmon;

architecture behav of dummy_rmon is

  type t_rmon_reg is array(natural range <>) of std_logic_vector(7 downto 0);
  signal regs : t_rmon_reg(g_nports*g_cnt_pp-1 downto 0);

begin
  GEN_REGS: for i in 0 to g_nports*g_cnt_pp-1 generate
    process(clk_i)
    begin
      if rising_edge(clk_i) then
        if(rst_n_i='0') then
          regs(i) <= (others=>'0');
        elsif(events_i(i) = '1') then
          regs(i) <= std_logic_vector(unsigned(regs(i)) + 1);
        end if;
      end if;
    end process;
  end generate;
end behav;
