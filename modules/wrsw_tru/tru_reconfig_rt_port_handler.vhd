-------------------------------------------------------------------------------
-- Title      : Topology Resolution Unit: reconfiguration real-time port handler
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : tru_reconfig_rt_port_handler.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-08-28
-- Last update: 2012-09-13
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: This module tracks changes of topology due to boren links and,
-- if necessary, takes action i.e. sends "quick forward" messages to other 
-- switches to switch port to forwarding state
--
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- 
-- 
-- 
-- 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 Maciej Lipinski / CERN
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

entity tru_reconfig_rt_port_handler is
  generic(     
     g_num_ports        : integer; 
     g_tru_subentry_num : integer
    );
  port (
    clk_i              : in std_logic;
    rst_n_i            : in std_logic;
     
    read_valid_i       : in std_logic;
    read_data_i        : in t_tru_tab_entry(g_tru_subentry_num - 1 downto 0);
    resp_masks_i       : in t_resp_masks;    
    config_i           : in  t_tru_config;
    txFrameMask_o      : out std_logic_vector(g_num_ports-1 downto 0)
    );
end tru_reconfig_rt_port_handler;

architecture rtl of tru_reconfig_rt_port_handler is

signal s_globIngMask      : std_logic_vector(g_num_ports-1 downto 0);
signal s_globIngMask_d0   : std_logic_vector(g_num_ports-1 downto 0);
signal s_globIngMask_or   : std_logic_vector(g_num_ports-1 downto 0);
signal s_txFrameMask      : std_logic_vector(g_num_ports-1 downto 0);

begin --rtl

s_globIngMask <= ((read_data_i(0).ports_ingress(g_num_ports-1 downto 0) xor 
                   resp_masks_i.ingress(g_num_ports-1 downto 0))        and
                  (resp_masks_i.ingress(g_num_ports-1 downto 0)))   and
                  (not s_globIngMask_d0);
s_globIngMask_or <= s_globIngMask or s_globIngMask_d0;


txFrameMask_o    <= s_txFrameMask;

  FSM: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0' or config_i.rtrcr_rtr_ena='0') then

         s_globIngMask_d0   <= (others =>'0');
         s_txFrameMask      <= (others=> '0');
         
      else
        
        case config_i.rtrcr_rtr_mode is
        --------------------------------------------------------------------------------------------
        when std_logic_vector(to_unsigned(0,4))=> -- default
        --------------------------------------------------------------------------------------------
           s_globIngMask_d0 <= (others => '0');
           s_txFrameMask    <= (others=> '0');    
        --------------------------------------------------------------------------------------------
        when std_logic_vector(to_unsigned(1,4))=>
        --------------------------------------------------------------------------------------------
           
           s_txFrameMask      <= (others=> '0'); 
           
           if(config_i.rtrcr_rtr_reset = '1') then
              s_globIngMask_d0 <= (others => '0');
           elsif(read_valid_i = '1') then
              s_globIngMask_d0 <= s_globIngMask_or;
              s_txFrameMask    <= s_globIngMask_d0 xor s_globIngMask_or;

           end if;
        --------------------------------------------------------------------------------------------  
        when others =>
        --------------------------------------------------------------------------------------------
           s_globIngMask_d0   <= (others => '0');
           s_txFrameMask      <= (others => '0');           
        
        end case;            
      end if;
    end if;
  end process;  
end rtl;
