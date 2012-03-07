-------------------------------------------------------------------------------
-- Title      : Routing Table Unit's CRC package (crc_pkg)
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_rtu_crc_pkg.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-05-12
-- Last update: 2010-05-12
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Here we just do a translation from input of
--       mac and fid
-- to input of
--       two times 16 bits
--
-- maybe later I will do one parametrized function to calculate CRC, at the 
-- moment the various functions are calculated using 
--
--                 http://www.easics.com/webtools/crctool  
--
--
-------------------------------------------------------------------------------
--
-- Copyright (c) 2010 Maciej Lipinski / CERN
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
-- Date        Version  Author          Description
-- 2010-05-12  1.0      lipinskimm	    Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.PCK_CRC16_D16.all;


package wrsw_rtu_crc_pkg is

  function crc16_ccitt
    (mac_addr_i: std_logic_vector(47 downto 0);
     fid_i:  std_logic_vector(7 downto 0))
    return std_logic_vector;
    
  function crc16_ibm
    (mac_addr_i: std_logic_vector(47 downto 0);
     fid_i:  std_logic_vector(7 downto 0))
    return std_logic_vector;  
    
  function crc16_dect
    (mac_addr_i: std_logic_vector(47 downto 0);
     fid_i:  std_logic_vector(7 downto 0))
    return std_logic_vector;
    
        
end wrsw_rtu_crc_pkg;


package body wrsw_rtu_crc_pkg is

  function crc16_ccitt
    (mac_addr_i: std_logic_vector(47 downto 0);
     fid_i:  std_logic_vector(7 downto 0))
    return std_logic_vector is

    variable v_d_0   :      std_logic_vector(15 downto 0);
    variable v_d_1   :      std_logic_vector(15 downto 0);
    variable v_d_2   :      std_logic_vector(15 downto 0);
    variable v_d_3   :      std_logic_vector(15 downto 0);
    variable v_reg_0 :      std_logic_vector(15 downto 0);
    variable v_reg_1 :      std_logic_vector(15 downto 0);
    variable v_reg_2 :      std_logic_vector(15 downto 0);
    variable v_hash_o:      std_logic_vector(15 downto 0);

  begin
    v_d_0 := x"00" & fid_i; --??
    v_d_1 := mac_addr_i(47 downto 32);
    v_d_2 := mac_addr_i(31 downto 16);
    v_d_3 := mac_addr_i(15 downto 0);


--    v_d_1 := mac_addr_i(15 downto 0);
--    v_d_2 := mac_addr_i(31 downto 16);
--    v_d_3 := mac_addr_i(47 downto 32);
    
    v_reg_0  := nextCRC16_CCITT(x"FFFF", v_d_0);
    v_reg_1  := nextCRC16_CCITT(v_reg_0, v_d_1);
    v_reg_2  := nextCRC16_CCITT(v_reg_1, v_d_2);
	  v_hash_o := nextCRC16_CCITT(v_reg_2, v_d_3);

    return v_hash_o;
  end crc16_ccitt;


  function crc16_ibm
    (mac_addr_i: std_logic_vector(47 downto 0);
     fid_i:  std_logic_vector(7 downto 0))
    return std_logic_vector is

    variable v_d_0   :      std_logic_vector(15 downto 0);
    variable v_d_1   :      std_logic_vector(15 downto 0);
    variable v_d_2   :      std_logic_vector(15 downto 0);
    variable v_d_3   :      std_logic_vector(15 downto 0);
    variable v_reg_0 :      std_logic_vector(15 downto 0);
    variable v_reg_1 :      std_logic_vector(15 downto 0);
    variable v_reg_2 :      std_logic_vector(15 downto 0);
    variable v_hash_o:      std_logic_vector(15 downto 0);

  begin
    v_d_0 := x"00" & fid_i; --??

    v_d_1 := mac_addr_i(47 downto 32);
    v_d_2 := mac_addr_i(31 downto 16);
    v_d_3 := mac_addr_i(15 downto 0);
    
--    v_d_1 := mac_addr_i(15 downto 0);
--    v_d_2 := mac_addr_i(31 downto 16);
--    v_d_3 := mac_addr_i(47 downto 32);
    
    v_reg_0  := nextCRC16_IBM(x"FFFF", v_d_0);
    v_reg_1  := nextCRC16_IBM(v_reg_0, v_d_1);
    v_reg_2  := nextCRC16_IBM(v_reg_1, v_d_2);
	  v_hash_o := nextCRC16_IBM(v_reg_2, v_d_3);

    return v_hash_o;
  end crc16_ibm;


  function crc16_dect
    (mac_addr_i: std_logic_vector(47 downto 0);
     fid_i:  std_logic_vector(7 downto 0))
    return std_logic_vector is

    variable v_d_0   :      std_logic_vector(15 downto 0);
    variable v_d_1   :      std_logic_vector(15 downto 0);
    variable v_d_2   :      std_logic_vector(15 downto 0);
    variable v_d_3   :      std_logic_vector(15 downto 0);
    variable v_reg_0 :      std_logic_vector(15 downto 0);
    variable v_reg_1 :      std_logic_vector(15 downto 0);
    variable v_reg_2 :      std_logic_vector(15 downto 0);
    variable v_hash_o:      std_logic_vector(15 downto 0);

  begin
    v_d_0 := x"00" & fid_i; --??

    v_d_1 := mac_addr_i(47 downto 32);
    v_d_2 := mac_addr_i(31 downto 16);
    v_d_3 := mac_addr_i(15 downto 0);

--    v_d_1 := mac_addr_i(15 downto 0);
--    v_d_2 := mac_addr_i(31 downto 16);
--    v_d_3 := mac_addr_i(47 downto 32);
    
    v_reg_0  := nextCRC16_DECT(x"FFFF", v_d_0);
    v_reg_1  := nextCRC16_DECT(v_reg_0, v_d_1);
    v_reg_2  := nextCRC16_DECT(v_reg_1, v_d_2);
	  v_hash_o := nextCRC16_DECT(v_reg_2, v_d_3);

    return v_hash_o;
  end crc16_dect;

end wrsw_rtu_crc_pkg;