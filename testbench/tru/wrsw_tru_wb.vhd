-------------------------------------------------------------------------------
-- Title      : Topology Resolution Unit (wrapper with WB I/F)
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : tru_port_wrapper.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-08-28
-- Last update: 2012-09-13
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: Wrapper of the xwrsw_tru top entity to be used for simulation.
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
-- 2012-08-31  1.0      mlipinsk Created
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

entity wrsw_tru_wb is
  generic(     
     g_num_ports           : integer;
     g_tru_subentry_num    : integer;
     g_tru_subentry_width  : integer;
     g_pattern_mode_width  : integer;
     g_patternID_width     : integer;
     g_stableUP_treshold   : integer;
     g_tru_addr_width      : integer;
     g_pclass_number       : integer;
     g_tru2ep_record_width : integer;
     g_ep2tru_record_width : integer;
     g_rtu2tru_record_width: integer;
     g_tru_req_record_width: integer;
     g_tru_resp_record_width:integer;
     g_mt_trans_max_fr_cnt : integer;
     g_prio_width          : integer;
     g_tru_entry_num       : integer      
    );
  port (
    clk_i                   : in  std_logic;
    rst_n_i                 : in  std_logic;
 
    ------------------------------- I/F with RTU ----------------------------------
    --t_tru_request
    tru_req_i               : in  std_logic_vector(g_tru_req_record_width-1 downto 0);

    --rtu_resp_o         
    tru_resp_o              : out std_logic_vector(g_tru_resp_record_width-1 downto 0);

    rtu_i                   : in  std_logic_vector(g_rtu2tru_record_width-1 downto 0);
    
    ep_i                    : in  std_logic_vector(g_num_ports*g_ep2tru_record_width-1 downto 0);
    ep_o                    : out std_logic_vector(g_num_ports*g_tru2ep_record_width-1 downto 0);
    
    swc_o                   : out std_logic_vector(g_num_ports-1 downto 0); -- for pausing
    
    wb_addr_i          : in     std_logic_vector(3 downto 0);
    wb_data_i          : in     std_logic_vector(31 downto 0);
    wb_data_o          : out    std_logic_vector(31 downto 0);
    wb_cyc_i           : in     std_logic;
    wb_sel_i           : in     std_logic_vector(3 downto 0);
    wb_stb_i           : in     std_logic;
    wb_we_i            : in     std_logic;
    wb_ack_o           : out    std_logic
    );
end wrsw_tru_wb;

architecture rtl of wrsw_tru_wb is
    type t_tru_tab_subentry_array is array(integer range <>) of 
                                     std_logic_vector(g_tru_subentry_width-1 downto 0); 
    type t_ep_array is array(integer range <>) of std_logic_vector(g_ep2tru_record_width-1 downto 0); 

    signal s_tru_req               : t_tru_request;
    signal s_tru_resp              : t_tru_response;  
    signal s_tru_tab_entry         : t_tru_tab_entry(g_tru_subentry_num-1 downto 0);
    signal s_config                : t_tru_config;
    signal s_tru_tab_subentry_arr  : t_tru_tab_subentry_array(g_tru_subentry_num-1 downto 0);
    signal s_rtu                   : t_rtu2tru;
    signal s_ep_in                 : t_ep2tru_array(g_num_ports-1 downto 0);
    signal s_ep_out                : t_tru2ep_array(g_num_ports-1 downto 0);
    signal s_ep_arr                : t_ep_array(g_num_ports-1 downto 0);
begin

  X_TRU: xwrsw_tru
  generic map(     
     g_num_ports        => g_num_ports,
     g_tru_subentry_num => g_tru_subentry_num,
     g_patternID_width  => g_patternID_width,
     g_pattern_width    => g_num_ports,
     g_stableUP_treshold=> g_stableUP_treshold,
     g_tru_addr_width   => g_tru_addr_width,
     g_pclass_number    => g_pclass_number,
     g_mt_trans_max_fr_cnt=> g_mt_trans_max_fr_cnt,
     g_prio_width       => g_prio_width,
     g_pattern_mode_width => g_pattern_mode_width,
     g_tru_entry_num    => g_tru_entry_num     
    )
  port map(
    clk_i               => clk_i,
    rst_n_i             => rst_n_i,
    req_i               => s_tru_req,
    resp_o              => s_tru_resp,
    rtu_i               => s_rtu, 
    ep_i                => s_ep_in,
    ep_o                => s_ep_out,
    swc_o               => swc_o,
    
    wb_addr_i          => wb_addr_i,
    wb_data_i          => wb_data_i,
    wb_data_o          => wb_data_o,
    wb_cyc_i           => wb_cyc_i,
    wb_sel_i           => wb_sel_i,
    wb_stb_i           => wb_stb_i,
    wb_we_i            => wb_we_i,
    wb_ack_o           => wb_ack_o

    );

    s_tru_req     <= f_unpack_tru_request (tru_req_i,  g_num_ports);
    tru_resp_o    <= f_pack_tru_response  (s_tru_resp, g_num_ports);
    s_rtu         <= f_unpack_rtu         (rtu_i,      g_num_ports);
  
    G3: for i in 0 to g_num_ports-1 generate
       s_ep_arr(i)                    <= ep_i((i+1)*g_ep2tru_record_width-1 downto i*g_ep2tru_record_width);
       s_ep_in(i)                     <= f_unpack_ep2tru(s_ep_arr(i));
       ep_o((i+1)*g_tru2ep_record_width-1 downto i*g_tru2ep_record_width) <= f_pack_tru2ep(s_ep_out(i));
    end generate G3;

end rtl;
