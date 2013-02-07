-------------------------------------------------------------------------------
-- Title      : Routing Table Unit's CRC (RTU_CRC)
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_rtu_crc.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-05-12
-- Last update: 2012-06-22
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- I calls function to calculate CRC16, depending in the crc_poly_i input, 
-- different CRC16 functions are used 
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
use work.rtu_crc_pkg.all;
use work.rtu_private_pkg.all;




entity rtu_crc is
    port (
        mac_addr_i        : in  std_logic_vector(c_wrsw_mac_addr_width - 1 downto 0);
        fid_i             : in  std_logic_vector(c_wrsw_fid_width      - 1 downto 0);
        crc_poly_i        : in  std_logic_vector(c_wrsw_crc_width      - 1 downto 0);
        hash_o            : out std_logic_vector(c_wrsw_hash_width     - 1 downto 0)        
    );
end entity;

architecture behavior of rtu_crc is
    signal s_crc16        : std_logic_vector(15 downto 0);
    signal s_fid          : std_logic_vector(15 downto 0);
begin


    with crc_poly_i select
	     s_crc16  <= crc16_ccitt(mac_addr_i,fid_i) when x"8408" | x"1021" | x"8810" ,
	                 crc16_ibm(mac_addr_i,fid_i)   when x"8005" | x"A001" | x"C002",
	                 crc16_dect(mac_addr_i,fid_i)  when x"0589" | x"91A0" | x"82C4",
	                 crc16_ccitt(mac_addr_i,fid_i) when others;
	
	hash_o  <= s_crc16(c_wrsw_hash_width - 1 downto 0);


end architecture;
