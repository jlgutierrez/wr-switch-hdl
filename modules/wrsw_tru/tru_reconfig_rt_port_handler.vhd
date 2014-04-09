-------------------------------------------------------------------------------
-- Title      : Topology Resolution Unit: reconfiguration real-time port handler
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : tru_reconfig_rt_port_handler.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-08-28
-- Last update: 2013-02-06
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
    endpoints_i        : in  t_tru_endpoints;   
    config_i           : in  t_tru_config;
    tru_tab_bank_swap_i: in  std_logic;
    globIngMask_dbg_o  : out std_logic_vector(g_num_ports-1 downto 0);
    txFrameMask_o      : out std_logic_vector(g_num_ports-1 downto 0)
    );
end tru_reconfig_rt_port_handler;

architecture rtl of tru_reconfig_rt_port_handler is

  signal s_globIngMask      : std_logic_vector(g_num_ports-1 downto 0);
  signal s_globIngMask_d0   : std_logic_vector(g_num_ports-1 downto 0);
  signal s_globIngMask_or   : std_logic_vector(g_num_ports-1 downto 0);
  signal s_txFrameMask      : std_logic_vector(g_num_ports-1 downto 0);
  signal s_globIngMask_xor  : std_logic_vector(g_num_ports-1 downto 0);
  signal s_inject_ready     : std_logic_vector(g_num_ports-1 downto 0);
  signal s_zeros            : std_logic_vector(g_num_ports-1 downto 0);
begin --rtl

  s_zeros <= (others =>'0');
  -------------------------------------------------------------------------------------------------
  -- The below code is used to send HW-generated "quick forwrad" frames to request the neighbour
  -- port to open (for ingress) port connected to the port which has just been made "active" on 
  -- "our switch" (the one the code is run). 
  -- This is used in the case if we've just enabled for ingress "backup" port and we want
  -- that the neighbour-switch did the same on the same link very quickly.
  ------------------------------------------------------------------------------------------------- 
  -- Here we assume that the first subentry in the TRU TAB (for a given FID) is the default
  -- entry (read_data_i(0).ports_ingress). Therefore, any ingress decision (resp_masks_i.ingress)
  -- which is different then the first (number 0) TRU subentry means that there has been some 
  -- change (most probably port was opened as a backup for a port which went down). 
  -- Then we check this changes against the changes in of portIngres mask which we
  -- have already remembered/detected and stored in the past: s_globIngMask_d0. 
  -- Finally, what we get are (if any) new changes to the port ingress mask. 
  s_globIngMask <= ((read_data_i(0).ports_ingress(g_num_ports-1 downto 0) xor 
                     resp_masks_i.ingress(g_num_ports-1 downto 0))        and
                    (resp_masks_i.ingress(g_num_ports-1 downto 0)))       and
                    (not s_globIngMask_d0);
  
  -- to make the code less messy
  s_globIngMask_or  <= s_globIngMask or s_globIngMask_d0;
  s_globIngMask_xor <= s_globIngMask_d0 xor s_globIngMask_or;
  s_inject_ready    <= endpoints_i.inject_ready(g_num_ports-1 downto 0);
  
  -- send HW-generated frame
  txFrameMask_o    <= s_txFrameMask;

  -- process which generate requests to send HW-generated frames (rx)
  RX: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0' or config_i.rtrcr_rtr_ena='0') then

         s_globIngMask_d0   <= (others =>'0');
         s_txFrameMask      <= (others=> '0');
         
      else
        
        case config_i.rtrcr_rtr_mode is  -- many configs possible, only single available at the moment
        --------------------------------------------------------------------------------------------
        when std_logic_vector(to_unsigned(0,4))=> -- default
        --------------------------------------------------------------------------------------------
           s_globIngMask_d0 <= (others => '0');
           s_txFrameMask    <= (others=> '0');    
        --------------------------------------------------------------------------------------------
        when std_logic_vector(to_unsigned(1,4))=> -- eRSTP
        --------------------------------------------------------------------------------------------
           
           s_txFrameMask      <= (others=> '0'); 
           
           -- if we swap the bank of the memory (new configuration) or reset the RT module, 
           -- then we need to clear the remembered chagnes. 
           if(config_i.rtrcr_rtr_reset = '1' or tru_tab_bank_swap_i = '1') then
              s_globIngMask_d0 <= (others => '0');
           
           -- Generate signal to send HW-generated frames based on the remembered info and
           -- newly generated mask
--            elsif(read_valid_i = '1') then
--            else
           elsif((s_inject_ready and s_globIngMask_xor) /= s_zeros) then
              s_globIngMask_d0 <= s_globIngMask_or;
              s_txFrameMask    <= s_globIngMask_xor;
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
  
  -- debugging
  globIngMask_dbg_o <= s_globIngMask_d0;

end rtl;
