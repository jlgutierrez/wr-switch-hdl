-------------------------------------------------------------------------------
-- Title      : Topology Resolution Unit: sub VLAN pattern 
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : tru_sub_vlan_pattern.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-08-28
-- Last update: 2013-03-14
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: A wrapper for different implementations of pattern generation.
-- Here, based on configuration, proper pattern generator is chosen. 
--
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- Pattern is used to decide which information from TRU Table is used to 
-- make the forwarding decision (combination of more info can be used)
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 - 2013 CERN / BE-CO-HT
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
-- 2012-08-28  1.0      mlipinsk Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

library work;
use work.wrsw_shared_types_pkg.all; -- need this for:
                                    -- * t_rtu_request

use work.rtu_private_pkg.all;       -- we need it for RTU's datatypes (records):
                                    -- * t_rtu_vlan_tab_entry

use work.gencores_pkg.all;          -- for f_rr_arbitrate
use work.wrsw_tru_pkg.all;

entity tru_sub_vlan_pattern is
  generic(     
     g_num_ports        : integer;
     g_patternID_width  : integer;
     g_pattern_width    : integer
     
    );
  port (
    clk_i              : in std_logic;
    rst_n_i            : in std_logic;
 
    portID_i           : in std_logic_vector(integer(CEIL(LOG2(real(g_num_ports + 1))))-1 downto 0);
    patternID_i        : in std_logic_vector(g_patternID_width-1 downto 0);
    ------------------------------- I/F with RTU ----------------------------------
    tru_req_i          : in  t_tru_request;
    
    ------------------------------- I/F with tru_endpoint ----------------------------------
    endpoints_i        : in  t_tru_endpoints;
    
    -------------------------------global config/variable ----------------------------------
    config_i           : in  t_tru_config;
    
    -- thee required response
    pattern_o          : out std_logic_vector(g_pattern_width-1 downto 0)
    
    );
end tru_sub_vlan_pattern;

architecture rtl of tru_sub_vlan_pattern is

-- type t_pattern is std_logic_vector(patternID_i'lengt-1 downto 0);

constant c_p_default     : std_logic_vector(g_patternID_width-1 downto 0) :=x"0"; -- default
constant c_p_port_down   : std_logic_vector(g_patternID_width-1 downto 0) :=x"1"; -- port down 
constant c_p_quick_fwd   : std_logic_vector(g_patternID_width-1 downto 0) :=x"2"; -- quick forward received frames 
constant c_p_quick_blk   : std_logic_vector(g_patternID_width-1 downto 0) :=x"3"; -- quick block received frames 
constant c_p_aggr_gr_id  : std_logic_vector(g_patternID_width-1 downto 0) :=x"4"; -- aggregation group id
constant c_p_rx_port     : std_logic_vector(g_patternID_width-1 downto 0) :=x"5"; -- received port 


signal rxFrameNumber : integer range 0 to endpoints_i.rxFrameMaskReg'length-1;
signal rxPort        : integer range 0 to g_num_ports;

begin --rtl
    
    -----------------------------------------------------------------------------------------------
    -- Generate different patterns depending on the input configuration
    -----------------------------------------------------------------------------------------------
    -- TODO: case and choose functions according to the config
    -----------------------------------------------------------------------------------------------
    pattern_o <= 
      (others=>'0')                                                            when (patternID_i = c_p_default)    else -- 0: defaut                 
      f_pattern_port_down (endpoints_i,g_pattern_width)                        when (patternID_i = c_p_port_down)  else -- 1: eRSTP
      f_pattern_quick_fwd (endpoints_i,config_i,g_pattern_width)               when (patternID_i = c_p_quick_fwd)  else -- 2: eRSTP:
      f_pattern_quick_blk (endpoints_i,config_i,g_pattern_width)               when (patternID_i = c_p_quick_blk)  else -- 3: eRSTP:
      f_pattern_aggr_gr_id(endpoints_i,tru_req_i, portID_i,config_i,g_pattern_width,g_num_ports)   when (patternID_i = c_p_aggr_gr_id) else -- 4: eLACP: 
      f_pattern_rx_port   (tru_req_i, g_pattern_width)                         when (patternID_i = c_p_rx_port)    else -- 5: eLACP
      (others=>'0');

end rtl;
