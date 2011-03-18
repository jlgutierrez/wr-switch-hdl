library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library lpm;
use lpm.all;

-------------------------------------------------------------------------------

package platform_specific is

  component alt_clock_divider
    port (
      inclk0 : in  std_logic := '0';
      c0     : out std_logic;
      c1     : out std_logic;
      locked : out std_logic);

    
  end component;

  component generic_pipelined_multiplier
    generic (
      g_width_a   : natural;
      g_width_b   : natural;
      g_width_out : natural;
      g_sign_mode : string);
    port (
      clk_i : in  std_logic;
      a_i   : in  std_logic_vector(g_width_a -1 downto 0);
      b_i   : in  std_logic_vector(g_width_b -1 downto 0);
      q_o   : out std_logic_vector(g_width_out-1 downto 0));
  end component;

end platform_specific;

-------------------------------------------------------------------------------
