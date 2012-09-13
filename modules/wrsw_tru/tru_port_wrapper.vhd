-------------------------------------------------------------------------------
-- Title      : Topology Resolution Unit: port wrapper
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : tru_port_wrapper.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-08-28
-- Last update: 2012-08-28
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
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

entity tru_port_wrapper is
  generic(     
     g_num_ports        : integer; 
     g_tru_subentry_width  : integer;  -- in RTU this is: 
     g_tru_subentry_num : integer;
     g_endp_entry_width : integer;
     g_patternID_width  : integer;
     g_pattern_width    : integer;
     g_tru_addr_width   : integer
    );
  port (
    clk_i                   : in  std_logic;
    rst_n_i                 : in  std_logic;
 
    ------------------------------- I/F with RTU ----------------------------------
    --t_tru_request
    tru_req_i               : in  std_logic_vector(1+48+48+8+1+1+g_num_ports-1 downto 0);

    --rtu_resp_o         
    tru_resp_o              : out std_logic_vector(1+2*g_num_ports+1-1 downto 0);

    ------------------------------- I/F with TRU tab -----------------------------------
    tru_tab_addr_o          : out std_logic_vector(g_tru_addr_width-1 downto 0);
    tru_tab_entry_i         : in  std_logic_vector(g_tru_subentry_num*g_tru_subentry_width-1 downto 0);
    
    ------------------------------- I/F with tru_endpoint ----------------------------------
    endpoints_i             : in std_logic_vector(g_num_ports*g_endp_entry_width-1 downto 0);
    
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
    tcr_trans_mode_i        : in std_logic_vector(2 downto 0);
    tcr_trans_rx_id_i       : in std_logic_vector(2 downto 0);
    tcr_trans_port_a_id_i   : in std_logic_vector(5 downto 0);
    tcr_trans_port_a_valid_i: in std_logic;
    tcr_trans_port_b_id_i   : in std_logic_vector(5 downto 0);
    tcr_trans_port_b_valid_i: in std_logic;
    -- real time reconfiguration config
    rtrcr_rtr_ena_i         : in std_logic;
    rtrcr_rtr_reset_i       : in std_logic;
    rtrcr_rtr_mode_i        : in std_logic_vector(3 downto 0);
    rtrcr_rtr_rx_i          : in std_logic_vector(3 downto 0)
    );
end tru_port_wrapper;

architecture rtl of tru_port_wrapper is
    signal s_tru_req          : t_tru_request;
    signal s_tru_resp         : t_tru_response;  
    signal s_tru_tab_entry    : t_tru_tab_entry(g_tru_subentry_num-1 downto 0);
    signal s_endpoints        : t_tru_endpoint;
    signal s_config           : t_tru_config;
    type t_tru_tab_subentry_arr is array(integer range <>) of std_logic_vector(g_tru_subentry_width-1 downto 0); 

    signal s_tru_tab_subentry_arr    : t_tru_tab_subentry_arr(g_tru_subentry_num-1 downto 0);
begin

  tru_p: tru_port
  generic map(     
     g_num_ports        => g_num_ports,
     g_tru_subentry_num => g_tru_subentry_num,
     g_patternID_width  => g_patternID_width,
     g_pattern_width    => g_pattern_width,
     g_tru_addr_width   => g_tru_addr_width
    )
  port map(
    clk_i               => clk_i,
    rst_n_i             => rst_n_i,
    tru_req_i           => s_tru_req,
    tru_resp_o          => s_tru_resp,
    tru_tab_addr_o      => tru_tab_addr_o,
    tru_tab_entry_i     => s_tru_tab_entry,
    endpoints_i         => s_endpoints,
    config_i            => s_config
    );

    s_tru_req     <= f_unpack_tru_request (tru_req_i,  g_num_ports);
    tru_resp_o    <= f_pack_tru_response  (s_tru_resp, g_num_ports);

    G0: for i in g_num_ports-1 generate
       s_endpoints(i)<= f_unpack_tru_endpoint(endpoints_i((i+1)*g_endp_entry_width downto i*g_endp_entry_width));
    end generate G0;

     G1: for i in 0 to g_tru_subentry_num-1 generate
       s_tru_tab_subentry_arr(i) <= tru_tab_entry_i((i+1)*g_tru_subentry_width-1 downto i*g_tru_subentry_width);
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
    s_config.tcr_trans_mode        <= tcr_trans_mode_i;
    s_config.tcr_trans_rx_id       <= tcr_trans_rx_id_i;
    s_config.tcr_trans_port_a_id   <= tcr_trans_port_a_id_i;
    s_config.tcr_trans_port_a_valid<= tcr_trans_port_a_valid_i;
    s_config.tcr_trans_port_b_id   <= tcr_trans_port_b_id_i;
    s_config.tcr_trans_port_b_valid<= tcr_trans_port_b_valid_i;
    s_config.rtrcr_rtr_ena         <= rtrcr_rtr_ena_i;
    s_config.rtrcr_rtr_reset       <= rtrcr_rtr_reset_i;
    s_config.rtrcr_rtr_mode        <= rtrcr_rtr_mode_i;
    s_config.rtrcr_rtr_rx          <= rtrcr_rtr_rx_i;

end rtl;
