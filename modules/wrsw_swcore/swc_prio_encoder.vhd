-------------------------------------------------------------------------------
-- Title      : Priority encoder
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_prio_encoder.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-08
-- Last update: 2012-06-25
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2010 Tomasz Wlostowski, Maciej Lipinski / CERN
--
-- This source file is free software; you can redistribute it   
-- and/or modify it under the terms of the GNU Lesser General   
-- Public License as published by the Free Software Foundation; 
-- either version 2.1 of the License, or (at your option) any   
-- later version.                                               
--
-- This source is distributed in the hope that it will be       
-- useful, but WITHOUT ANY WARRANTY; without even the implied   
-- warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      
-- PURPOSE.  See the GNU Lesser General Public License for more 
-- details.                                                     
--
-- You should have received a copy of the GNU Lesser General    
-- Public License along with this source; if not, download it   
-- from http://www.gnu.org/licenses/lgpl-2.1.html
--
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2010-04-08  1.0      twlostow Created
-- 2010-10-11  1.1      mlipinsk comments added !!!!!
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity swc_prio_encoder is
  
  generic (
    g_num_inputs  : integer range 2 to 80 := 32;
    g_output_bits : integer range 1 to 7  := 5);
  port (
    
    
    -- input vector having some sequence of '1s' and '0s'
    -- the encoder detects the first least significant
    -- '1' (the most to the right)
    in_i  : in  std_logic_vector(g_num_inputs-1 downto 0);
    
    
    -- a number representing the position of bit on which
    -- a '1' is set (the least significant)
    -- e.g.: for 
    --       in_i  = 1110101011000 
    --       out_o = 3
    out_o : out std_logic_vector(g_output_bits-1 downto 0);
    
    -- one hot representation of out_o number
    -- e.g.: for 
    --       in_i     = 1110101011000 
    --       out_o    = 3
    --       onehot_o = 0000000001000
    onehot_o : out std_logic_vector(g_num_inputs-1 downto 0);

    -- bit mask : '1s' from LSB to the position of first '1' 
    -- detected, excluding; '0s' from the first '1' detected 
    -- (inclusive) to the MSB
    -- e.g.: for 
    --       in_i     = 1110101011000 
    --       out_o    = 3
    --       mask_o   = 0000000000111 
    mask_o: out std_logic_vector(g_num_inputs-1 downto 0);
    
    --  indicates that the input vector has no '1s'
    zero_o: out std_logic
    );


end swc_prio_encoder;

architecture syn of swc_prio_encoder is

  signal w : std_logic_vector(79 downto 0);
  signal q : std_logic_vector(6 downto 0);
  signal zero : std_logic;

begin  -- syn


  w(79 downto g_num_inputs) <= (others => '0');
  w(g_num_inputs-1 downto 0) <= in_i;

  
  
  q <= "0000000" when w(0) = '1' else
       "0000001" when w(1) = '1' else
       "0000010" when w(2) = '1' else
       "0000011" when w(3) = '1' else
       "0000100" when w(4) = '1' else
       "0000101" when w(5) = '1' else
       "0000110" when w(6) = '1' else
       "0000111" when w(7) = '1' else
       "0001000" when w(8+0) = '1' else
       "0001001" when w(8+1) = '1' else
       "0001010" when w(8+2) = '1' else
       "0001011" when w(8+3) = '1' else
       "0001100" when w(8+4) = '1' else
       "0001101" when w(8+5) = '1' else
       "0001110" when w(8+6) = '1' else
       "0001111" when w(8+7) = '1' else
       "0010000" when w(16+0) = '1' else
       "0010001" when w(16+1) = '1' else
       "0010010" when w(16+2) = '1' else
       "0010011" when w(16+3) = '1' else
       "0010100" when w(16+4) = '1' else
       "0010101" when w(16+5) = '1' else
       "0010110" when w(16+6) = '1' else
       "0010111" when w(16+7) = '1' else
       "0011000" when w(24+0) = '1' else
       "0011001" when w(24+1) = '1' else
       "0011010" when w(24+2) = '1' else
       "0011011" when w(24+3) = '1' else
       "0011100" when w(24+4) = '1' else
       "0011101" when w(24+5) = '1' else
       "0011110" when w(24+6) = '1' else
       "0011111" when w(24+7) = '1' else
       "0100000" when w(32+0) = '1' else
       "0100001" when w(32+1) = '1' else
       "0100010" when w(32+2) = '1' else
       "0100011" when w(32+3) = '1' else
       "0100100" when w(32+4) = '1' else
       "0100101" when w(32+5) = '1' else
       "0100110" when w(32+6) = '1' else
       "0100111" when w(32+7) = '1' else
       "0101000" when w(32+8+0) = '1' else
       "0101001" when w(32+8+1) = '1' else
       "0101010" when w(32+8+2) = '1' else
       "0101011" when w(32+8+3) = '1' else
       "0101100" when w(32+8+4) = '1' else
       "0101101" when w(32+8+5) = '1' else
       "0101110" when w(32+8+6) = '1' else
       "0101111" when w(32+8+7) = '1' else
       "0110000" when w(32+16+0) = '1' else
       "0110001" when w(32+16+1) = '1' else
       "0110010" when w(32+16+2) = '1' else
       "0110011" when w(32+16+3) = '1' else
       "0110100" when w(32+16+4) = '1' else
       "0110101" when w(32+16+5) = '1' else
       "0110110" when w(32+16+6) = '1' else
       "0110111" when w(32+16+7) = '1' else
       "0111000" when w(32+24+0) = '1' else
       "0111001" when w(32+24+1) = '1' else
       "0111010" when w(32+24+2) = '1' else
       "0111011" when w(32+24+3) = '1' else
       "0111100" when w(32+24+4) = '1' else
       "0111101" when w(32+24+5) = '1' else
       "0111110" when w(32+24+6) = '1' else
       "0111111" when w(32+24+7) = '1' else
       "1000000" when w(64+0) = '1' else
       "1000001" when w(64+1) = '1' else
       "1000010" when w(64+2) = '1' else
       "1000011" when w(64+3) = '1' else
       "1000100" when w(64+4) = '1' else
       "1000101" when w(64+5) = '1' else
       "1000110" when w(64+6) = '1' else
       "1000111" when w(64+7) = '1' else
       "1001000" when w(64+8) = '1' else
       "1001001" when w(64+9) = '1' else
       "1001010" when w(64+10) = '1' else
       "1001011" when w(64+11) = '1' else
       "1001100" when w(64+12) = '1' else
       "1001101" when w(64+13) = '1' else
       "1001110" when w(64+14) = '1' else
       "1001111" when w(64+15) = '1' else
       "0000000";

  out_o <= q(g_output_bits-1 downto 0);
  zero <= '1' when (in_i = std_logic_vector(to_unsigned(0, g_num_inputs))) else '0';

  zero_o <= zero;
  
  onehot_o(0) <= w(0);
  
  gen_onehot: for i in 1 to g_num_inputs-1 generate
    onehot_o(i) <= '1' when (w(i) = '1' and w(i-1 downto 0) = std_logic_vector(to_unsigned(0, i))) else '0';
  end generate gen_onehot;

  gen_mask: for i in 0 to g_num_inputs-1 generate
      mask_o(i) <= '1' when (to_integer(unsigned(q)) < i) else '0';
   
  end generate gen_mask;
    
    
  
  

end syn;
