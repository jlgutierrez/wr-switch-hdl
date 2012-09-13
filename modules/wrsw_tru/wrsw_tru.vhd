-------------------------------------------------------------------------------
-- Title      : Topology Resolution Unit (wrapper)
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
-- Description: wrapper of xwrsw_tru module to be used with simulation
--
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- This wrapper does not need WB interface to access configuration/TRU Tab
-- (currently not supported but can be useful)
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

entity wrsw_tru is
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
    ------------------------------- I/F with TRU tab -----------------------------------
    tru_tab_addr_o          : out std_logic_vector(g_tru_addr_width-1 downto 0);
    tru_tab_entry_i         : in  std_logic_vector(g_tru_subentry_num*g_tru_subentry_width-1 downto 0);
        
    -------------------------------global config/variable ----------------------------------
    gcr_g_ena_i             : in std_logic;
    gcr_tru_bank_i          : in std_logic;
    gcr_rx_frame_reset_i    : in std_logic_vector(23 downto 0);
    -- pattern match config
    mcr_pattern_mode_rep_i  : in std_logic_vector(3 downto 0);
    mcr_pattern_mode_add_i  : in std_logic_vector(3 downto 0);
    -- linc aggregation config
    lacr_agg_gr_num_i       : in std_logic_vector(3 downto 0);
    lacr_agg_df_br_id_i     : in std_logic_vector(3 downto 0);
    lacr_agg_df_un_id_i     : in std_logic_vector(3 downto 0);
    lagt_gr_id_mask_i       : in std_logic_vector(8*4-1 downto 0);
    -- transition config
    tcr_trans_ena_i         : in std_logic;
    tcr_trans_clr_i         : in std_logic;
    tcr_trans_mode_i        : in std_logic_vector(2 downto 0);
    tcr_trans_rx_id_i       : in std_logic_vector(2 downto 0);
    tcr_trans_prio_i        : in std_logic_vector(2 downto 0);
    tcr_trans_port_a_id_i   : in std_logic_vector(5 downto 0);
    tcr_trans_port_a_pause_i: in std_logic_vector(15 downto 0);
    tcr_trans_port_a_valid_i: in std_logic;
    tcr_trans_port_b_id_i   : in std_logic_vector(5 downto 0);
    tcr_trans_port_b_pause_i: in std_logic_vector(15 downto 0);
    tcr_trans_port_b_valid_i: in std_logic;
    -- real time reconfiguration config
    rtrcr_rtr_ena_i         : in std_logic;
    rtrcr_rtr_reset_i       : in std_logic;
    rtrcr_rtr_mode_i        : in std_logic_vector(3 downto 0);
    rtrcr_rtr_rx_i          : in std_logic_vector(3 downto 0)
    );
end wrsw_tru;

architecture rtl of wrsw_tru is
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
    ------------------------------------------
    tmp_tru_tab_addr_o  => tru_tab_addr_o,
    tmp_tru_tab_entry_i => s_tru_tab_entry,
    tmp_config_i        => s_config
    );

    s_tru_req     <= f_unpack_tru_request (tru_req_i,  g_num_ports);
    tru_resp_o    <= f_pack_tru_response  (s_tru_resp, g_num_ports);
    s_rtu         <= f_unpack_rtu         (rtu_i,      g_num_ports);
 -- 
-- 
-- 

    G1: for i in 0 to g_tru_subentry_num-1 generate
       s_tru_tab_subentry_arr(i) <= tru_tab_entry_i((i+1)*g_tru_subentry_width-1 downto 
                                                     i   *g_tru_subentry_width);
       s_tru_tab_entry(i)     <= f_unpack_tru_subentry(s_tru_tab_subentry_arr(i),g_num_ports);
    end generate G1;

    s_config.gcr_g_ena             <= gcr_g_ena_i;
    s_config.gcr_tru_bank          <= gcr_tru_bank_i;
    s_config.gcr_rx_frame_reset    <= gcr_rx_frame_reset_i;
    s_config.mcr_pattern_mode_rep  <= mcr_pattern_mode_rep_i;
    s_config.mcr_pattern_mode_add  <= mcr_pattern_mode_add_i;
    s_config.lacr_agg_gr_num       <= lacr_agg_gr_num_i;
    s_config.lacr_agg_df_br_id     <= lacr_agg_df_br_id_i;
    s_config.lacr_agg_df_un_id     <= lacr_agg_df_un_id_i;
    
    G2: for i in 0 to 7 generate
      s_config.lagt_gr_id_mask(i)  <= lagt_gr_id_mask_i((i+1)*4 -1 downto i*4);
    end generate;

    s_config.tcr_trans_ena         <= tcr_trans_ena_i;
    s_config.tcr_trans_clr         <= tcr_trans_clr_i;
    s_config.tcr_trans_mode        <= tcr_trans_mode_i;
    s_config.tcr_trans_rx_id       <= tcr_trans_rx_id_i;
    s_config.tcr_trans_prio        <= tcr_trans_prio_i;
    s_config.tcr_trans_port_a_id   <= tcr_trans_port_a_id_i;
    s_config.tcr_trans_port_a_valid<= tcr_trans_port_a_valid_i;
    s_config.tcr_trans_port_a_pause<= tcr_trans_port_a_pause_i;
    s_config.tcr_trans_port_b_id   <= tcr_trans_port_b_id_i;
    s_config.tcr_trans_port_b_valid<= tcr_trans_port_b_valid_i;
    s_config.tcr_trans_port_b_pause<= tcr_trans_port_b_pause_i;
    s_config.rtrcr_rtr_ena         <= rtrcr_rtr_ena_i;
    s_config.rtrcr_rtr_reset       <= rtrcr_rtr_reset_i;
    s_config.rtrcr_rtr_mode        <= rtrcr_rtr_mode_i;
    s_config.rtrcr_rtr_rx          <= rtrcr_rtr_rx_i;
    
    G3: for i in 0 to g_num_ports-1 generate
       s_ep_arr(i)                    <= ep_i((i+1)*g_ep2tru_record_width-1 downto i*g_ep2tru_record_width);
       s_ep_in(i)                  <= f_unpack_ep2tru(s_ep_arr(i));
       ep_o((i+1)*g_tru2ep_record_width-1 downto i*g_tru2ep_record_width) <= f_pack_tru2ep(s_ep_out(i));
    end generate G3;

end rtl;
