library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity swc_prio_encoder is
  
  generic (
    g_num_inputs  : integer range 2 to 64 := 32;
    g_output_bits : integer range 1 to 6  := 5);
  port (
    in_i  : in  std_logic_vector(g_num_inputs-1 downto 0);
    out_o : out std_logic_vector(g_output_bits-1 downto 0);
    mask_o : out std_logic_vector(g_num_inputs-1 downto 0);
    zero_o: out std_logic
    );


end swc_prio_encoder;

architecture syn of swc_prio_encoder is

  signal w : std_logic_vector(63 downto 0);
  signal q : std_logic_vector(5 downto 0);

begin  -- syn


  w(63 downto g_num_inputs) <= (others => '0');
  w(g_num_inputs-1 downto 0) <= in_i;

  
  
  q <= "000000" when w(0) = '1' else
       "000001" when w(1) = '1' else
       "000010" when w(2) = '1' else
       "000011" when w(3) = '1' else
       "000100" when w(4) = '1' else
       "000101" when w(5) = '1' else
       "000110" when w(6) = '1' else
       "000111" when w(7) = '1' else
       "001000" when w(8+0) = '1' else
       "001001" when w(8+1) = '1' else
       "001010" when w(8+2) = '1' else
       "001011" when w(8+3) = '1' else
       "001100" when w(8+4) = '1' else
       "001101" when w(8+5) = '1' else
       "001110" when w(8+6) = '1' else
       "001111" when w(8+7) = '1' else
       "010000" when w(16+0) = '1' else
       "010001" when w(16+1) = '1' else
       "010010" when w(16+2) = '1' else
       "010011" when w(16+3) = '1' else
       "010100" when w(16+4) = '1' else
       "010101" when w(16+5) = '1' else
       "010110" when w(16+6) = '1' else
       "010111" when w(16+7) = '1' else
       "011000" when w(24+0) = '1' else
       "011001" when w(24+1) = '1' else
       "011010" when w(24+2) = '1' else
       "011011" when w(24+3) = '1' else
       "011100" when w(24+4) = '1' else
       "011101" when w(24+5) = '1' else
       "011110" when w(24+6) = '1' else
       "011111" when w(24+7) = '1' else
       "100000" when w(32+0) = '1' else
       "100001" when w(32+1) = '1' else
       "100010" when w(32+2) = '1' else
       "100011" when w(32+3) = '1' else
       "100100" when w(32+4) = '1' else
       "100101" when w(32+5) = '1' else
       "100110" when w(32+6) = '1' else
       "100111" when w(32+7) = '1' else
       "101000" when w(32+8+0) = '1' else
       "101001" when w(32+8+1) = '1' else
       "101010" when w(32+8+2) = '1' else
       "101011" when w(32+8+3) = '1' else
       "101100" when w(32+8+4) = '1' else
       "101101" when w(32+8+5) = '1' else
       "101110" when w(32+8+6) = '1' else
       "101111" when w(32+8+7) = '1' else
       "110000" when w(32+16+0) = '1' else
       "110001" when w(32+16+1) = '1' else
       "110010" when w(32+16+2) = '1' else
       "110011" when w(32+16+3) = '1' else
       "110100" when w(32+16+4) = '1' else
       "110101" when w(32+16+5) = '1' else
       "110110" when w(32+16+6) = '1' else
       "110111" when w(32+16+7) = '1' else
       "111000" when w(32+24+0) = '1' else
       "111001" when w(32+24+1) = '1' else
       "111010" when w(32+24+2) = '1' else
       "111011" when w(32+24+3) = '1' else
       "111100" when w(32+24+4) = '1' else
       "111101" when w(32+24+5) = '1' else
       "111110" when w(32+24+6) = '1' else
       "111111" when w(32+24+7) = '1' else
       "XXXXXX";

  out_o <= q(g_output_bits-1 downto 0);
  zero_o <= '1' when (in_i = std_logic_vector(to_unsigned(0, g_num_inputs))) else '0';

  mask_o(0) <= w(0);
  
  genmask: for i in 1 to g_num_inputs-1 generate
    mask_o(i) <= '1' when (w(i) = '1' and w(i-1 downto 0) = std_logic_vector(to_unsigned(0, i))) else '0';
  end generate genmask;
     
    
    
  
  

end syn;
