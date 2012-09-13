-------------------------------------------------------------------------------
-- Title      : Topology Resolution Unit: port
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : tru_port.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-08-28
-- Last update: 2012-09-13
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: This module is a main request-to-TRU handler. 
--
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
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
-- use work.wrsw_shared_types_pkg.all; -- need this for:
--                                     -- * t_tru_request

-- use work.rtu_private_pkg.all;       -- we need it for RTU's datatypes (records):
--                                     -- * t_rtu_vlan_tab_entry

use work.gencores_pkg.all;          -- for f_rr_arbitrate
use work.wrsw_tru_pkg.all;

entity tru_port is
  generic(     
     g_num_ports        : integer; 
     g_tru_subentry_num : integer;
     g_patternID_width  : integer;
     g_pattern_width    : integer;
     g_tru_addr_width   : integer -- fid
    );
  port (
    clk_i              : in  std_logic;
    rst_n_i            : in  std_logic;
    
    ------------------------------- I/F with RTU ----------------------------------
    tru_req_i          : in  t_tru_request;
    tru_resp_o         : out t_tru_response;   

    ------------------------------- I/F with TRU TAB ----------------------------------
    -- request 
    tru_tab_addr_o     : out std_logic_vector(g_tru_addr_width-1 downto 0);
    tru_tab_entry_i    : in  t_tru_tab_entry(g_tru_subentry_num - 1 downto 0);
    
    ------------------------------- I/F with tru_endpoint ----------------------------------
    endpoints_i        : in  t_tru_endpoints;
    
    ----------------------------------------------------------------------------------
    config_i           : in  t_tru_config;
    txFrameMask_o      : out std_logic_vector(g_num_ports - 1 downto 0)
    );
end tru_port;

architecture rtl of tru_port is
 
  signal s_zeros             : std_logic_vector(g_num_ports - 1 downto 0);
  signal s_patternRep        : std_logic_vector(g_pattern_width-1 downto 0);
  signal s_patternAdd        : std_logic_vector(g_pattern_width-1 downto 0);
  signal s_patternRep_d0     : std_logic_vector(g_pattern_width-1 downto 0);
  signal s_patternAdd_d0     : std_logic_vector(g_pattern_width-1 downto 0);

  signal s_resp_masks        : t_resp_masks;
  signal s_self_mask         : std_logic_vector(g_num_ports - 1 downto 0);
  signal s_port_mask         : std_logic_vector(g_num_ports - 1 downto 0);
  signal s_valid_d0          : std_logic;
  signal s_valid_d1          : std_logic;
  signal s_reqMask_d0        : std_logic_vector(g_num_ports - 1 downto 0);
  signal s_reqMask_d1        : std_logic_vector(g_num_ports - 1 downto 0);
  signal s_portID_vec        : std_logic_vector(integer(CEIL(LOG2(real(g_num_ports + 1))))-1 downto 0);
  signal s_drop              : std_logic;
  signal s_status_mask       : std_logic_vector(g_num_ports - 1 downto 0);
  signal s_ingress_mask      : std_logic_vector(g_num_ports - 1 downto 0);
  signal s_egress_mask       : std_logic_vector(g_num_ports - 1 downto 0);
  


begin --rtl
   
  -- inputs
  s_portID_vec   <= std_logic_vector(to_unsigned(f_one_hot_to_binary(tru_req_i.reqMask),s_portID_vec'length )) ;
  s_zeros        <= (others => '0');
  s_status_mask  <= endpoints_i.status(g_num_ports-1 downto 0);
  s_ingress_mask <= s_resp_masks.ingress(g_num_ports-1 downto 0);
  s_egress_mask  <= s_resp_masks.egress(g_num_ports-1 downto 0);
   
  REPLACE_PATTERN: tru_sub_vlan_pattern
  generic map(     
     g_num_ports       => g_num_ports,
     g_patternID_width => g_patternID_width,
     g_pattern_width   => g_pattern_width
    )
  port map(
    clk_i              => clk_i,
    rst_n_i            => rst_n_i,
    portID_i           => s_portID_vec,
    patternID_i        => config_i.mcr_pattern_mode_rep,
    tru_req_i          => tru_req_i,
    endpoints_i        => endpoints_i,
    config_i           => config_i,
    pattern_o          => s_patternRep
    );

  ADD_PATTERN: tru_sub_vlan_pattern
  generic map(     
     g_num_ports       => g_num_ports,
     g_patternID_width => g_patternID_width,
     g_pattern_width   => g_pattern_width
    )
  port map(
    clk_i              => clk_i,
    rst_n_i            => rst_n_i,
    portID_i           => s_portID_vec,
    patternID_i        => config_i.mcr_pattern_mode_add,
    tru_req_i          => tru_req_i,
    endpoints_i        => endpoints_i,
    config_i           => config_i,
    pattern_o          => s_patternAdd
    );
  
  RT_RECONFIG: tru_reconfig_rt_port_handler
  generic map(
     g_num_ports       => g_num_ports,
     g_tru_subentry_num=> g_tru_subentry_num
    )
  port map(
    clk_i              => clk_i,
    rst_n_i            => rst_n_i,
    read_valid_i       => s_valid_d0,
    read_data_i        => tru_tab_entry_i,
    resp_masks_i       => s_resp_masks,
    config_i           => config_i,
    txFrameMask_o      => txFrameMask_o
    );
  
  CTRL: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
         
         s_self_mask          <= (others =>'0');
         s_patternRep_d0      <= (others =>'0');
         s_patternAdd_d0      <= (others =>'0');
         s_valid_d0           <= '0';
         s_valid_d1           <= '0';
         s_reqMask_d0         <= (others =>'0');
         s_reqMask_d1         <= (others =>'0');
         s_port_mask          <= (others =>'0');
         s_drop               <= '0';
         
      else
        
         -- First stage
         s_patternRep_d0         <= s_patternRep;
         s_patternAdd_d0         <= s_patternAdd;
         s_self_mask             <= tru_req_i.reqMask(g_num_ports-1 downto 0);
         s_valid_d0              <= tru_req_i.valid;
         s_reqMask_d0            <= tru_req_i.reqMask(g_num_ports-1 downto 0);
         s_reqMask_d1            <= s_reqMask_d0;
         s_valid_d1              <= s_valid_d0;
               
         -- Second stage (output)
         if(config_i.gcr_g_ena = '1' and s_valid_d0 = '1') then
            s_port_mask          <= s_status_mask and s_egress_mask and (not s_self_mask);
            if((s_ingress_mask and s_self_mask) = s_zeros) then
              s_drop             <= '1';
            else
              s_drop             <= '0';
            end if;
         elsif(config_i.gcr_g_ena = '1' and s_valid_d0 = '0') then
            s_port_mask          <= (others =>'0');
            s_drop               <= '0';
         else
            s_port_mask          <= (others =>'1');
            s_drop               <= '0';
         end if;  
      end if;
    end if;
  end process;  
  
  s_resp_masks   <= f_gen_mask_with_patterns(tru_tab_entry_i, 
                                             s_patternRep_d0, 
                                             s_patternAdd_d0,
                                             g_tru_subentry_num);
  -- outputs
  tru_tab_addr_o(g_tru_addr_width-1 downto 0)  <= tru_req_i.fid(g_tru_addr_width-1 downto 0);
  tru_resp_o.port_mask(g_num_ports-1 downto 0) <= s_port_mask;
  tru_resp_o.respMask(g_num_ports-1 downto 0)  <= s_reqMask_d1;
  tru_resp_o.valid                             <= s_valid_d1;
  tru_resp_o.drop                              <= s_drop;
  tru_resp_o.respMask(tru_resp_o.respMask'length-1 downto g_num_ports) <= (others => '0');
  tru_resp_o.port_mask(tru_resp_o.port_mask'length-1 downto g_num_ports) <= (others => '0');

end rtl;
