-------------------------------------------------------------------------------
-- Title      : Topology Resolution Unit: marker triggered transition
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : tru_transition.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-09-10
-- Last update: 2012-09-13
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: A wrapper for different implementations of transition. Here 
-- we just instantiate modules implementiong different transitions and the 
-- sellection, based on configuration, is done
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
-- 2012-09-05  1.0      mlipinsk Created
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

use work.wrsw_shared_types_pkg.all;
use work.gencores_pkg.all;          -- for f_rr_arbitrate
use work.wrsw_tru_pkg.all;

entity tru_transition is
  generic(     
     g_num_ports           : integer; 
     g_mt_trans_max_fr_cnt : integer;
     g_prio_width          : integer
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
    ports_req_strobe_i : in std_logic_vector(g_num_ports - 1 downto 0);
    ep_o               : out t_trans2tru_array(g_num_ports - 1 downto 0)
    );
end tru_transition;

architecture rtl of tru_transition is
 
  constant c_trans_mode_num_max : integer := 16;
 
  type t_trans2tru_2array is array (c_trans_mode_num_max-1 downto 0) of t_trans2tru_array(g_num_ports - 1 downto 0);

  signal s_tru_tab_bank       : std_logic_vector(c_trans_mode_num_max-1 downto 0);
  signal s_statTransActive    : std_logic_vector(c_trans_mode_num_max-1 downto 0);
  signal s_statTransFinished  : std_logic_vector(c_trans_mode_num_max-1 downto 0);
  signal s_ep_array           : t_trans2tru_2array;
  signal s_rst_n              : std_logic_vector(c_trans_mode_num_max-1 downto 0);
  
  signal index         : integer range c_trans_mode_num_max-1 downto 0;
begin --rtl
   
  index              <= to_integer(unsigned(config_i.tcr_trans_mode));

  statTransActive_o  <= s_statTransActive(index);
  tru_tab_bank_o     <= s_tru_tab_bank(index);
  statTransFinished_o<= s_statTransFinished(index);
  ep_o               <= s_ep_array(index);
  
  -- a big and nasty MUX between different modules
   
  G_RST_N: for i in 0 to c_trans_mode_num_max-1 generate
     s_rst_n(i)         <= rst_n_i when (i = index) else '0';
  end generate G_RST_N;

  TRANS_MARKER_TRIG: tru_trans_marker_trig 
  generic map(     
     g_num_ports           => g_num_ports,
     g_mt_trans_max_fr_cnt => g_mt_trans_max_fr_cnt,
     g_prio_width          => g_prio_width
    )
  port map (
    clk_i                  => clk_i,
    rst_n_i                => s_rst_n(0),
    rxFrameMask_i          => rxFrameMask_i,
    rtu_i                  => rtu_i,
    endpoints_i            => endpoints_i,
    config_i               => config_i,
    tru_tab_bank_i         => tru_tab_bank_i,
    ports_req_strobe_i     => ports_req_strobe_i,
    tru_tab_bank_o         => s_tru_tab_bank(0),
    statTransActive_o      => s_statTransActive(0),
    statTransFinished_o    => s_statTransFinished(0),
    
    ep_o                   => s_ep_array(0)
    );

  TRANS_LACP_DIST: tru_trans_lacp_dist
  generic map(     
     g_num_ports           => g_num_ports,
     g_mt_trans_max_fr_cnt => g_mt_trans_max_fr_cnt,
     g_prio_width          => g_prio_width
    )
  port map (
    clk_i                  => clk_i,
    rst_n_i                => s_rst_n(1),
    rxFrameMask_i          => rxFrameMask_i,
    rtu_i                  => rtu_i,
    endpoints_i            => endpoints_i,
    config_i               => config_i,
    tru_tab_bank_i         => tru_tab_bank_i,
    
    tru_tab_bank_o         => s_tru_tab_bank(1),
    statTransActive_o      => s_statTransActive(1),
    statTransFinished_o    => s_statTransFinished(1),
    ep_o                   => s_ep_array(1)
    );

  TRANS_LACP_CALECT: tru_trans_lacp_colect
  generic map(     
     g_num_ports           => g_num_ports,
     g_mt_trans_max_fr_cnt => g_mt_trans_max_fr_cnt,
     g_prio_width          => g_prio_width
    )
  port map (
    clk_i                  => clk_i,
    rst_n_i                => s_rst_n(2),
    rxFrameMask_i          => rxFrameMask_i,
    rtu_i                  => rtu_i,
    endpoints_i            => endpoints_i,
    config_i               => config_i,
    tru_tab_bank_i         => tru_tab_bank_i,
    
    tru_tab_bank_o         => s_tru_tab_bank(2),
    statTransActive_o      => s_statTransActive(2),
    statTransFinished_o    => s_statTransFinished(2),
    ep_o                   => s_ep_array(2)
    );

end rtl;
