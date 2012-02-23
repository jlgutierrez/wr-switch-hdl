-------------------------------------------------------------------------------
-- Copyright (C) 2009 OutputLogic.com
-- This source file may be used and distributed without restriction
-- provided that this copyright statement is not removed from the file
-- and that any derivative work contains the original copyright notice
-- and the associated disclaimer.
-- 
-- THIS SOURCE FILE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS
-- OR IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
-- WARRANTIES OF MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
-------------------------------------------------------------------------------
-- CRC module for data(15:0)
--   lfsr(15:0)=1+x^5+x^12+x^16;
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- SOME EXPLANATION REGARDING VHDL vs C  CRC IMPLEMENTATION BY ML
-------------------------------------------------------------------------------
-- C code to produce exactly the same CRC 
-- it uses naive method, it's not optimal at all
-- but it's good enough to chech whether VHDL works OK
-- It was made (by maciej.lipinski@cern.ch) modifying source from here:
-- http://www.netrino.com/Embedded-Systems/How-To/CRC-Calculation-C-Code
-- the website provides explanation of CRC
-- 
-- To get the POLY below (0x88108), here is the trick:
--
-- 1) we are using the following ply equation: 1+x^5+x^12+x^16;
-- 2) it translates to binary: (1) 0001 0000 0010 0001 = 0x1021 
--                              |                        |
--                              |   this is default      |   this you can find in 
--                              |-> it's the 16th bit    |-> the wiki as description
--                                                           of the polly equation
-- 
-- 3) we include the "default" bit into the polly and add zeroes at the end
--    creating 20 bit polly, like this
--     (1) 0001 0000 0010 0001 => 1000 1000 0001 0000 1000 = 0x88108 
--
--------------------------------------------------------------------------------
--|        name   |      polly equation     | polly (hex) | our polly | tested |
--------------------------------------------------------------------------------
--|  CRC-16-CCITT | 1+x^5+x^12+x^16         |    0x1021   |  0x88108  |  yes   |
--|  CRC-16-IBM   | 1+x^2+x^15+x^16         |    0x8005   |  0xC0028  |  yes   |
--|  CRC-16-DECT  | 1+x^3+x^7+x^8+x^10+x^16 |    0x0589   |  0x82C48  |  yes   |  
--------------------------------------------------------------------------------
--
--
--
-- #define POLYNOMIAL_DECT   0x82C48 
-- #define POLYNOMIAL_CCITT  0x88108 
-- #define POLYNOMIAL_IBM    0xC0028 

--
--uint16_t 
--crcNaive16_2(uint16_t const message, uint16_t const init_crc)
--{
--    uint32_t  remainder;	
--    int bit;
--
--    /*
--     * Initially, the dividend is the remainder.
--     */
--    
--    remainder = message^init_crc;
--
--    /*
--     * For each bit position in the message....
--     */
--    for (bit = 20; bit > 0; --bit)
--    {
--        /*
--         * If the uppermost bit is a 1...
--         */
--        if (remainder & 0x80000)
--        {
--            /*
--             * XOR the previous remainder with the divisor.
--             */
--            remainder ^= POLYNOMIAL_CCITT;
--        }
--
--        /*
--         * Shift the next bit of the message into the remainder.
--         */
--        remainder = (remainder << 1);
--    }
--
--    /*
--     * Return only the relevant bits of the remainder as CRC.
--     */
--    return (remainder >> 4);
--
--    return remainder;
--}   /* crcNaive() */


library ieee;
use ieee.std_logic_1164.all;

package PCK_CRC16_D16 is


    
  -- polynomial: (0 5 12 16)
  -- data width: 16
  -- convention: the first serial bit is D[15]
  function nextCRC16_CCITT
    (crc: std_logic_vector(15 downto 0);
     Data:  std_logic_vector(15 downto 0))
    return std_logic_vector;

 -- polynomial: (0 2 15 16)
  -- data width: 16
  -- convention: the first serial bit is D[15]
  function nextCRC16_IBM
    (crc: std_logic_vector(15 downto 0);
     Data:  std_logic_vector(15 downto 0))
    return std_logic_vector;
    
    
  -- polynomial: (0 3 7 8 10 16)
  -- data width: 16
  -- convention: the first serial bit is D[15]
  function nextCRC16_DECT
    (crc: std_logic_vector(15 downto 0);
     Data:  std_logic_vector(15 downto 0))
    return std_logic_vector;
        
end PCK_CRC16_D16;




package body PCK_CRC16_D16 is

  -- polynomial: (0 5 12 16) == 0x1021
  -- data width: 16
  -- generated with: http://outputlogic.com/
  function nextCRC16_CCITT
    (crc: std_logic_vector(15 downto 0);
     Data:  std_logic_vector(15 downto 0))
    return std_logic_vector is

    variable data_in:      std_logic_vector(15 downto 0);
    variable lfsr_q :      std_logic_vector(15 downto 0);
    variable newcrc :      std_logic_vector(15 downto 0);

  begin
    data_in := Data;
    lfsr_q  := crc;

  
    
    newcrc(0)  := lfsr_q(0) xor lfsr_q(4) xor lfsr_q(8) xor lfsr_q(11) xor lfsr_q(12) xor data_in(0) xor data_in(4) xor data_in(8) xor data_in(11) xor data_in(12);
    newcrc(1)  := lfsr_q(1) xor lfsr_q(5) xor lfsr_q(9) xor lfsr_q(12) xor lfsr_q(13) xor data_in(1) xor data_in(5) xor data_in(9) xor data_in(12) xor data_in(13);
    newcrc(2)  := lfsr_q(2) xor lfsr_q(6) xor lfsr_q(10) xor lfsr_q(13) xor lfsr_q(14) xor data_in(2) xor data_in(6) xor data_in(10) xor data_in(13) xor data_in(14);
    newcrc(3)  := lfsr_q(3) xor lfsr_q(7) xor lfsr_q(11) xor lfsr_q(14) xor lfsr_q(15) xor data_in(3) xor data_in(7) xor data_in(11) xor data_in(14) xor data_in(15);
    newcrc(4)  := lfsr_q(4) xor lfsr_q(8) xor lfsr_q(12) xor lfsr_q(15) xor data_in(4) xor data_in(8) xor data_in(12) xor data_in(15);
    newcrc(5)  := lfsr_q(0) xor lfsr_q(4) xor lfsr_q(5) xor lfsr_q(8) xor lfsr_q(9) xor lfsr_q(11) xor lfsr_q(12) xor lfsr_q(13) xor data_in(0) xor data_in(4) xor data_in(5) xor data_in(8) xor data_in(9) xor data_in(11) xor data_in(12) xor data_in(13);
    newcrc(6)  := lfsr_q(1) xor lfsr_q(5) xor lfsr_q(6) xor lfsr_q(9) xor lfsr_q(10) xor lfsr_q(12) xor lfsr_q(13) xor lfsr_q(14) xor data_in(1) xor data_in(5) xor data_in(6) xor data_in(9) xor data_in(10) xor data_in(12) xor data_in(13) xor data_in(14);
    newcrc(7)  := lfsr_q(2) xor lfsr_q(6) xor lfsr_q(7) xor lfsr_q(10) xor lfsr_q(11) xor lfsr_q(13) xor lfsr_q(14) xor lfsr_q(15) xor data_in(2) xor data_in(6) xor data_in(7) xor data_in(10) xor data_in(11) xor data_in(13) xor data_in(14) xor data_in(15);
    newcrc(8)  := lfsr_q(3) xor lfsr_q(7) xor lfsr_q(8) xor lfsr_q(11) xor lfsr_q(12) xor lfsr_q(14) xor lfsr_q(15) xor data_in(3) xor data_in(7) xor data_in(8) xor data_in(11) xor data_in(12) xor data_in(14) xor data_in(15);
    newcrc(9)  := lfsr_q(4) xor lfsr_q(8) xor lfsr_q(9) xor lfsr_q(12) xor lfsr_q(13) xor lfsr_q(15) xor data_in(4) xor data_in(8) xor data_in(9) xor data_in(12) xor data_in(13) xor data_in(15);
    newcrc(10) := lfsr_q(5) xor lfsr_q(9) xor lfsr_q(10) xor lfsr_q(13) xor lfsr_q(14) xor data_in(5) xor data_in(9) xor data_in(10) xor data_in(13) xor data_in(14);
    newcrc(11) := lfsr_q(6) xor lfsr_q(10) xor lfsr_q(11) xor lfsr_q(14) xor lfsr_q(15) xor data_in(6) xor data_in(10) xor data_in(11) xor data_in(14) xor data_in(15);
    newcrc(12) := lfsr_q(0) xor lfsr_q(4) xor lfsr_q(7) xor lfsr_q(8) xor lfsr_q(15) xor data_in(0) xor data_in(4) xor data_in(7) xor data_in(8) xor data_in(15);
    newcrc(13) := lfsr_q(1) xor lfsr_q(5) xor lfsr_q(8) xor lfsr_q(9) xor data_in(1) xor data_in(5) xor data_in(8) xor data_in(9);
    newcrc(14) := lfsr_q(2) xor lfsr_q(6) xor lfsr_q(9) xor lfsr_q(10) xor data_in(2) xor data_in(6) xor data_in(9) xor data_in(10);
    newcrc(15) := lfsr_q(3) xor lfsr_q(7) xor lfsr_q(10) xor lfsr_q(11) xor data_in(3) xor data_in(7) xor data_in(10) xor data_in(11);    
    
    
    return newcrc;
  end nextCRC16_CCITT;

 -- polynomial: (0 2 15 16)
 -- data width: 16
 -- generated with: http://outputlogic.com/
  function nextCRC16_IBM
    (crc: std_logic_vector(15 downto 0);
     Data:  std_logic_vector(15 downto 0))
    return std_logic_vector is

    variable data_in:      std_logic_vector(15 downto 0);
    variable lfsr_q :      std_logic_vector(15 downto 0);
    variable newcrc :      std_logic_vector(15 downto 0);

  begin
    data_in := Data;
    lfsr_q  := crc;
    
    newcrc(0) := lfsr_q(0) xor lfsr_q(1) xor lfsr_q(2) xor lfsr_q(3) xor lfsr_q(4) xor lfsr_q(5) xor lfsr_q(6) xor lfsr_q(7) xor lfsr_q(8) xor lfsr_q(9) xor lfsr_q(10) xor lfsr_q(11) xor lfsr_q(12) xor lfsr_q(13) xor lfsr_q(15) xor data_in(0) xor data_in(1) xor data_in(2) xor data_in(3) xor data_in(4) xor data_in(5) xor data_in(6) xor data_in(7) xor data_in(8) xor data_in(9) xor data_in(10) xor data_in(11) xor data_in(12) xor data_in(13) xor data_in(15);
    newcrc(1) := lfsr_q(1) xor lfsr_q(2) xor lfsr_q(3) xor lfsr_q(4) xor lfsr_q(5) xor lfsr_q(6) xor lfsr_q(7) xor lfsr_q(8) xor lfsr_q(9) xor lfsr_q(10) xor lfsr_q(11) xor lfsr_q(12) xor lfsr_q(13) xor lfsr_q(14) xor data_in(1) xor data_in(2) xor data_in(3) xor data_in(4) xor data_in(5) xor data_in(6) xor data_in(7) xor data_in(8) xor data_in(9) xor data_in(10) xor data_in(11) xor data_in(12) xor data_in(13) xor data_in(14);
    newcrc(2) := lfsr_q(0) xor lfsr_q(1) xor lfsr_q(14) xor data_in(0) xor data_in(1) xor data_in(14);
    newcrc(3) := lfsr_q(1) xor lfsr_q(2) xor lfsr_q(15) xor data_in(1) xor data_in(2) xor data_in(15);
    newcrc(4) := lfsr_q(2) xor lfsr_q(3) xor data_in(2) xor data_in(3);
    newcrc(5) := lfsr_q(3) xor lfsr_q(4) xor data_in(3) xor data_in(4);
    newcrc(6) := lfsr_q(4) xor lfsr_q(5) xor data_in(4) xor data_in(5);
    newcrc(7) := lfsr_q(5) xor lfsr_q(6) xor data_in(5) xor data_in(6);
    newcrc(8) := lfsr_q(6) xor lfsr_q(7) xor data_in(6) xor data_in(7);
    newcrc(9) := lfsr_q(7) xor lfsr_q(8) xor data_in(7) xor data_in(8);
    newcrc(10) := lfsr_q(8) xor lfsr_q(9) xor data_in(8) xor data_in(9);
    newcrc(11) := lfsr_q(9) xor lfsr_q(10) xor data_in(9) xor data_in(10);
    newcrc(12) := lfsr_q(10) xor lfsr_q(11) xor data_in(10) xor data_in(11);
    newcrc(13) := lfsr_q(11) xor lfsr_q(12) xor data_in(11) xor data_in(12);
    newcrc(14) := lfsr_q(12) xor lfsr_q(13) xor data_in(12) xor data_in(13);
    newcrc(15) := lfsr_q(0) xor lfsr_q(1) xor lfsr_q(2) xor lfsr_q(3) xor lfsr_q(4) xor lfsr_q(5) xor lfsr_q(6) xor lfsr_q(7) xor lfsr_q(8) xor lfsr_q(9) xor lfsr_q(10) xor lfsr_q(11) xor lfsr_q(12) xor lfsr_q(14) xor lfsr_q(15) xor data_in(0) xor data_in(1) xor data_in(2) xor data_in(3) xor data_in(4) xor data_in(5) xor data_in(6) xor data_in(7) xor data_in(8) xor data_in(9) xor data_in(10) xor data_in(11) xor data_in(12) xor data_in(14) xor data_in(15);


    return newcrc;
  end nextCRC16_IBM;

  -- polynomial: (0 3 7 8 10 16)
  -- data width: 16
  -- generated with: http://outputlogic.com/
  function nextCRC16_DECT
    (crc: std_logic_vector(15 downto 0);
     Data:  std_logic_vector(15 downto 0))
    return std_logic_vector is

    variable data_in:      std_logic_vector(15 downto 0);
    variable lfsr_q :      std_logic_vector(15 downto 0);
    variable newcrc :      std_logic_vector(15 downto 0);

  begin
  data_in := Data;
  lfsr_q  := crc;

    newcrc(0) := lfsr_q(0) xor lfsr_q(6) xor lfsr_q(8) xor lfsr_q(9) xor lfsr_q(12) xor lfsr_q(13) xor data_in(0) xor data_in(6) xor data_in(8) xor data_in(9) xor data_in(12) xor data_in(13);
    newcrc(1) := lfsr_q(1) xor lfsr_q(7) xor lfsr_q(9) xor lfsr_q(10) xor lfsr_q(13) xor lfsr_q(14) xor data_in(1) xor data_in(7) xor data_in(9) xor data_in(10) xor data_in(13) xor data_in(14);
    newcrc(2) := lfsr_q(2) xor lfsr_q(8) xor lfsr_q(10) xor lfsr_q(11) xor lfsr_q(14) xor lfsr_q(15) xor data_in(2) xor data_in(8) xor data_in(10) xor data_in(11) xor data_in(14) xor data_in(15);
    newcrc(3) := lfsr_q(0) xor lfsr_q(3) xor lfsr_q(6) xor lfsr_q(8) xor lfsr_q(11) xor lfsr_q(13) xor lfsr_q(15) xor data_in(0) xor data_in(3) xor data_in(6) xor data_in(8) xor data_in(11) xor data_in(13) xor data_in(15);
    newcrc(4) := lfsr_q(1) xor lfsr_q(4) xor lfsr_q(7) xor lfsr_q(9) xor lfsr_q(12) xor lfsr_q(14) xor data_in(1) xor data_in(4) xor data_in(7) xor data_in(9) xor data_in(12) xor data_in(14);
    newcrc(5) := lfsr_q(2) xor lfsr_q(5) xor lfsr_q(8) xor lfsr_q(10) xor lfsr_q(13) xor lfsr_q(15) xor data_in(2) xor data_in(5) xor data_in(8) xor data_in(10) xor data_in(13) xor data_in(15);
    newcrc(6) := lfsr_q(3) xor lfsr_q(6) xor lfsr_q(9) xor lfsr_q(11) xor lfsr_q(14) xor data_in(3) xor data_in(6) xor data_in(9) xor data_in(11) xor data_in(14);
    newcrc(7) := lfsr_q(0) xor lfsr_q(4) xor lfsr_q(6) xor lfsr_q(7) xor lfsr_q(8) xor lfsr_q(9) xor lfsr_q(10) xor lfsr_q(13) xor lfsr_q(15) xor data_in(0) xor data_in(4) xor data_in(6) xor data_in(7) xor data_in(8) xor data_in(9) xor data_in(10) xor data_in(13) xor data_in(15);
    newcrc(8) := lfsr_q(0) xor lfsr_q(1) xor lfsr_q(5) xor lfsr_q(6) xor lfsr_q(7) xor lfsr_q(10) xor lfsr_q(11) xor lfsr_q(12) xor lfsr_q(13) xor lfsr_q(14) xor data_in(0) xor data_in(1) xor data_in(5) xor data_in(6) xor data_in(7) xor data_in(10) xor data_in(11) xor data_in(12) xor data_in(13) xor data_in(14);
    newcrc(9) := lfsr_q(1) xor lfsr_q(2) xor lfsr_q(6) xor lfsr_q(7) xor lfsr_q(8) xor lfsr_q(11) xor lfsr_q(12) xor lfsr_q(13) xor lfsr_q(14) xor lfsr_q(15) xor data_in(1) xor data_in(2) xor data_in(6) xor data_in(7) xor data_in(8) xor data_in(11) xor data_in(12) xor data_in(13) xor data_in(14) xor data_in(15);
    newcrc(10) := lfsr_q(0) xor lfsr_q(2) xor lfsr_q(3) xor lfsr_q(6) xor lfsr_q(7) xor lfsr_q(14) xor lfsr_q(15) xor data_in(0) xor data_in(2) xor data_in(3) xor data_in(6) xor data_in(7) xor data_in(14) xor data_in(15);
    newcrc(11) := lfsr_q(1) xor lfsr_q(3) xor lfsr_q(4) xor lfsr_q(7) xor lfsr_q(8) xor lfsr_q(15) xor data_in(1) xor data_in(3) xor data_in(4) xor data_in(7) xor data_in(8) xor data_in(15);
    newcrc(12) := lfsr_q(2) xor lfsr_q(4) xor lfsr_q(5) xor lfsr_q(8) xor lfsr_q(9) xor data_in(2) xor data_in(4) xor data_in(5) xor data_in(8) xor data_in(9);
    newcrc(13) := lfsr_q(3) xor lfsr_q(5) xor lfsr_q(6) xor lfsr_q(9) xor lfsr_q(10) xor data_in(3) xor data_in(5) xor data_in(6) xor data_in(9) xor data_in(10);
    newcrc(14) := lfsr_q(4) xor lfsr_q(6) xor lfsr_q(7) xor lfsr_q(10) xor lfsr_q(11) xor data_in(4) xor data_in(6) xor data_in(7) xor data_in(10) xor data_in(11);
    newcrc(15) := lfsr_q(5) xor lfsr_q(7) xor lfsr_q(8) xor lfsr_q(11) xor lfsr_q(12) xor data_in(5) xor data_in(7) xor data_in(8) xor data_in(11) xor data_in(12);


    return newcrc;
  end nextCRC16_DECT;






end PCK_CRC16_D16;
