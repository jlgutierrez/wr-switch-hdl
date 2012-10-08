-------------------------------------------------------------------------------
-- Title      : Topology Resolution Unit: Link Aggregation protocol, marker, distribution
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : tru_trans_lacp_dist.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-09-10
-- Last update: 2012-09-13
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: This module supports transition of "message stream" between 
-- links (connections) of "link aggregation" on the switch being a collector.
--[to be implemented]
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
-- 2012-09-10  1.0      mlipinsk Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

library work;
use work.wrsw_shared_types_pkg.all;
use work.gencores_pkg.all;          -- for f_rr_arbitrate
use work.wrsw_tru_pkg.all;

entity tru_trans_lacp_colect is
  generic(     
     g_num_ports        : integer; 
     g_mt_trans_max_fr_cnt : integer;
     g_prio_width       : integer
    );
  port (
    clk_i              : in  std_logic;
    rst_n_i            : in  std_logic;
        ------------------------------- I/F with tru_endpoint ----------------------------------
    endpoints_i        : in  t_tru_endpoints;
    
    config_i           : in  t_tru_config;
    tru_tab_bank_i     : in  std_logic;
    tru_tab_bank_o     : out std_logic;
    statTransActive_o  : out std_logic;
    statTransFinished_o: out std_logic;
    rxFrameMask_i      : in std_logic_vector(g_num_ports - 1 downto 0);
    rtu_i              : in  t_rtu2tru;
    ep_o               : out t_trans2tru_array(g_num_ports - 1 downto 0)
    );
end tru_trans_lacp_colect;

architecture rtl of tru_trans_lacp_colect is
 
   signal s_ep          : t_trans2ep;

begin --rtl
   
   -- TODO

  statTransActive_o      <= '0';
  statTransFinished_o    <= '0';
  tru_tab_bank_o         <= '0';
  s_ep.pauseSend         <= '0';
  s_ep.pauseTime         <= (others => '0');
  s_ep.outQueueBlockMask <= (others => '0');  

  EP_OUT: for i in 0 to g_num_ports-1 generate
      ep_o(i)<= s_ep;
  end generate EP_OUT;

end rtl;
