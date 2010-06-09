

library ieee;
use ieee.std_logic_1164.all;

library lpm;
use lpm.all;


library work;
use work.platform_specific.all;

entity generic_pipelined_multiplier is
  generic(
    g_width_a   : natural;
    g_width_b   : natural;
    g_width_out : natural;
    g_sign_mode : string := "signed"
    );
  port (
    clk_i : in  std_logic;
    a_i   : in  std_logic_vector(g_width_a -1 downto 0);
    b_i   : in  std_logic_vector(g_width_b -1 downto 0);
    q_o   : out std_logic_vector(g_width_out-1 downto 0)
    );

end generic_pipelined_multiplier;


architecture SYN of generic_pipelined_multiplier is

  signal sub_wire0 : std_logic_vector (g_width_out-1 downto 0);


  component lpm_mult
    generic (
      lpm_hint           : string;
      lpm_pipeline       : natural;
      lpm_representation : string;
      lpm_type           : string;
      lpm_widtha         : natural;
      lpm_widthb         : natural;
      lpm_widthp         : natural
      );
    port (
      dataa  : in  std_logic_vector (g_width_a-1 downto 0);
      datab  : in  std_logic_vector (g_width_b-1 downto 0);
      clock  : in  std_logic;
      result : out std_logic_vector (g_width_out-1 downto 0)
      );
  end component;

begin
  q_o <= sub_wire0(g_width_out-1 downto 0);

  lpm_mult_component : lpm_mult
    generic map (
      lpm_hint           => "DEDICATED_MULTIPLIER_CIRCUITRY=YES,MAXIMIZE_SPEED=9",
      lpm_pipeline       => 2,
      lpm_representation => "SIGNED",
      lpm_type           => "LPM_MULT",
      lpm_widtha         => g_width_a,
      lpm_widthb         => g_width_b,
      lpm_widthp         => g_width_out
      )
    port map (
      dataa  => a_i,
      datab  => b_i,
      clock  => clk_i,
      result => sub_wire0
      );



end SYN;
