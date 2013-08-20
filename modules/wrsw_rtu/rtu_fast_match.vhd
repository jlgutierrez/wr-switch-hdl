-------------------------------------------------------------------------------
-- Title      : Routing Table Unit's Fast Matching Component (RTU_FAST_MATCH)
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : rtu_fast_match.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2012-10-30
-- Last update: 2012-11-06
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- This module implements deterministic matching of requests from ports.
-- It provides forwarding decision based on:
-- * VLAN table (for broadcast and multicast)
-- * TRU decision (topology resolution unit for RSTP/MSTP/LACP)
-- * link-limited (non-forward) traffic (e.g. BPUD)
-- * some predefined addresses
-- 
-- it is generally meant for traffic which is broadcasted (within VLAN and TRU
-- restrictions) and has few purposes:
-- * to recognize and forward fast "special traffic" which is expected to be broadcast/multicast
-- * to provide TRU mask for the full match
-- * to provide fast forwarding decision if full_match takes too match time
-- 
-- The rising edge of response VALID signal is expected max after N+5 cycles after
-- the rising edge of request, where N is -- the number of ports (23 cycles for 18 ports)
-- 
-- It is expected that the input data (rtu_req) is valid throughout the request (except first
-- cycle).
-- 
-- The request (valid up of the input rtu_req) shall be a strobe
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
-- Date        Version  Author          Description
-- 2012-10-30  1.0      lipinskimm          Created
-------------------------------------------------------------------------------
-- known problems:
-- * HP priority mask: reversed bit order
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.genram_pkg.all;
use work.gencores_pkg.all;
use work.pack_unpack_pkg.all;
use work.wrsw_shared_types_pkg.all;
use work.rtu_private_pkg.all;

entity rtu_fast_match is
  generic (
    g_num_ports : integer;
    g_port_mask_bits : integer);
  port(

    -----------------------------------------------------------------
    --| General IOs
    -----------------------------------------------------------------
    clk_i                       : in std_logic;
    rst_n_i                     : in std_logic;

    match_req_i                 : in std_logic_vector(g_num_ports-1 downto 0);
    match_req_data_i            : in  t_rtu_request_array(g_num_ports-1 downto 0);
    
    -- fast forward response
    match_rsp_data_o            : out t_match_response;
    match_rsp_valid_o           : out std_logic_vector(g_num_ports-1 downto 0);
       
    vtab_rd_addr_o            : out std_logic_vector(c_wrsw_vid_width-1 downto 0);
    vtab_rd_entry_i           : in  t_rtu_vlan_tab_entry;
    
    tru_req_o                 : out  t_tru_request;
    tru_rsp_i                 : in   t_tru_response;  
    tru_enabled_i             : in   std_logic;

    rtu_str_config_i          : in t_rtu_special_traffic_config;
    rtu_pcr_pass_all_i        : in std_logic_vector(c_rtu_max_ports -1 downto 0)
    );

end rtu_fast_match;

architecture behavioral of rtu_fast_match is

  constant pipeline_depth       : integer := 4;
  type   t_std_vector_array is array(0 to pipeline_depth-1) of std_logic_vector(g_num_ports-1 downto 0);
  type   t_match_rsp_array is array(0 to 1) of t_match_response;
  signal req_strobe             : std_logic_vector(g_num_ports-1 downto 0);
  signal req_masked, req, grant : std_logic_vector(g_num_ports-1 downto 0);
  signal pipeline_grant         : t_std_vector_array;
  signal pipeline_valid         : std_logic_vector(pipeline_depth-1 downto 0);
  signal zeros                  : std_logic_vector(47 downto 0);
  signal ones                   : std_logic_vector(47 downto 0);
  signal pipeline_match_rsp     : t_match_rsp_array;
  signal rsp_fast_match         : t_match_response;
  signal rtu_req_stage_g        : t_rtu_request;
  signal rtu_req_stage_0        : t_rtu_request;
  signal rtu_req_stage_1        : t_rtu_request;
  signal rq_prio_mask           : std_logic_vector(7 downto 0);
  signal traffic_ptp            : std_logic; -- ptp traffic
  signal traffic_nf             : std_logic; -- non-forward (link-limited) traffic
  signal traffic_br             : std_logic; -- broadcast traffic
  signal traffic_ff             : std_logic; -- fast forward (special) traffic
  signal traffic_hp             : std_logic; -- high priority
  -- registered signals
  signal traffic_nf_d           : std_logic; 
  signal traffic_ff_d           : std_logic; 
  signal traffic_br_d           : std_logic; 
  signal traffic_hp_d           : std_logic; 
  
  signal rtu_pcr_nonvlan_drop_at_ingress : std_logic_vector(c_rtu_max_ports -1 downto 0);
  
  constant match_rsp_zero       : t_match_response := (
    valid     => '0',
    port_mask => (others => '0'),
    prio      => (others => '0'),
    drop      => '0',
    nf        => '0',
    ff        => '0',
    hp        => '0');
begin

  zeros <= (others => '0');
  ones  <= (others => '1');
  rtu_pcr_nonvlan_drop_at_ingress <= (others =>'0'); -- make it configurable from WB
  
  -- round robin arbitration stuff (stolen from Toms module)
  gen_inputs : for i in 0 to g_num_ports-1 generate
    req_strobe(i) <= match_req_i(i) and not req(i);
    p_input_reg : process(clk_i)
    begin
      if rising_edge(clk_i) then
        if rst_n_i = '0' then
          req(i) <= '0';
        else
          if(grant(i) = '1') then
            req(i) <= '0';
          elsif(req_strobe(i) = '1') then
            req(i)   <= '1';
          end if;
        end if;
      end if;
    end process;
  end generate gen_inputs;
  
  req_masked       <= req and not grant;
  
  -- using the ipnut data from (rtu_req) in different stages
  rtu_req_stage_g  <= match_req_data_i(f_onehot_decode(grant));
  rtu_req_stage_0  <= match_req_data_i(f_onehot_decode(pipeline_grant(0)));
  rtu_req_stage_1  <= match_req_data_i(f_onehot_decode(pipeline_grant(1)));
 
  ----------------------------- stage: 0     -------------------------------------------------
  -- in this stage we have the following data registered:
  -- * VTAB address to read
  -- We decide many things and register it for next stage
  -- * traffic kind, can we recognize the address ?
  --------------------------------------------------------------------------------------------  
  rq_prio_mask     <= f_set_bit(zeros(7 downto 0),'1',to_integer(unsigned(rtu_req_stage_0.prio)));  
  traffic_ptp      <= '0' when (rtu_str_config_i.ff_mac_ptp_ena = '0') else -- stuff disabled
                      '1' when (rtu_req_stage_0.dmac = x"011b19000000")     else -- the other is no-forward (link-limted)
                      '0';
  traffic_nf       <= '0'         when (rtu_str_config_i.ff_mac_ll_ena  = '0' and 
                                        rtu_str_config_i.ff_mac_ptp_ena = '0')   else -- stuff disabled
                      traffic_ptp when (rtu_str_config_i.ff_mac_ll_ena  = '0' and 
                                        rtu_str_config_i.ff_mac_ptp_ena = '1')   else -- stuff disabled 
                      f_mac_in_range(rtu_req_stage_0.dmac,c_bpd_range_lower,c_bpd_range_upper) or traffic_ptp;

  traffic_br       <= '0' when (rtu_str_config_i.ff_mac_br_ena ='0')   else -- stuff disabled
                      '1' when (rtu_req_stage_0.dmac = x"FFFFFFFFFFFF")     else
                      '0';
                      
                      -- the fast_match_mac_lookup function includes disabled/enabled future check
  traffic_ff       <= traffic_br or f_fast_match_mac_lookup(rtu_str_config_i, rtu_req_stage_0.dmac);

  traffic_hp       <= '1' when (traffic_ff='1' and rtu_req_stage_0.has_prio = '1' and 
                                (rtu_str_config_i.hp_prio and rq_prio_mask) /= zeros(7 downto 0) ) else
                      '1' when  traffic_ff='1' and rtu_req_stage_0.has_prio = '0' and 
                                (rtu_str_config_i.hp_prio = ones(7 downto 0)) else
                      '0';
  -- something is wrong here... HP works only for un-taggged traffic and if we set hp_prio to =0x1...
  -- for any other value does not work... shit
  ----------------------------- stage: 1     -------------------------------------------------
  -- reading VLAN, we have FID 
  -- * we request TRU decision if necessary (forward traffic)
  -- * we use the VLAN tab data to prepare fast match decision
  --------------------------------------------------------------------------------------------  
  
  rsp_fast_match   <= f_fast_match_response(vtab_rd_entry_i,
                                            rtu_req_stage_1.prio,
                                            rtu_req_stage_1.has_prio,
                                            pipeline_grant(1),
                                            traffic_br_d,
                                            rtu_pcr_pass_all_i,
                                            rtu_pcr_nonvlan_drop_at_ingress,
                                            g_num_ports);

  --------------------------------------------------------------------------------------------
  -- process controlling fast match:
  -- * arbitration
  -- * registering proper stuff in proper stage
  -- * 
  --------------------------------------------------------------------------------------------
  p_fast_match_ctr : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        grant                 <= (others => '0');
        RES_LOOP: for i in pipeline_depth-1 downto 0 loop
          pipeline_grant(i)     <= (others => '0');
          pipeline_valid(i)     <= '0';
        end loop RES_LOOP;             
        pipeline_match_rsp(0)   <= match_rsp_zero;             
        pipeline_match_rsp(1)   <= match_rsp_zero;             
        traffic_nf_d            <= '0';
        traffic_ff_d            <= '0';
        traffic_hp_d            <= '0';
        traffic_br_d            <= '0';        
      else
        
        -- round robin arbiter
        f_rr_arbitrate(req_masked , grant, grant);

        --------------------------------------------------------------------------------------
        -- register for stage 0: VLAN table address out
        --------------------------------------------------------------------------------------
        if(unsigned(grant) /= 0) then
          -- VLAN access
          vtab_rd_addr_o    <= rtu_req_stage_g.vid;
          pipeline_grant(0) <= grant;
          pipeline_valid(0) <= '1';
        else
--           vtab_rd_addr_o    <= (others => 'X'); -- remember address as at some point we read
                                                   -- data from VID=0, i.e. drop
          pipeline_grant(0) <= (others => '0');
          pipeline_valid(0) <= '0';
        end if;

        --------------------------------------------------------------------------------------
        -- register for stage 1: VLAN entry in  
        --------------------------------------------------------------------------------------
        if(unsigned(pipeline_grant(0)) /= 0) then
          traffic_nf_d      <= traffic_nf;
          traffic_ff_d      <= traffic_ff ;
          traffic_hp_d      <= traffic_hp;
          traffic_br_d      <= traffic_br;
        else
          traffic_nf_d      <= '0';
          traffic_ff_d      <= '0';
          traffic_hp_d      <= '0';
          traffic_br_d      <= '0';
        end if;      
  
        --------------------------------------------------------------------------------------
        -- register for stage 2: register fast forward decision
        --------------------------------------------------------------------------------------
        if(unsigned(pipeline_grant(1)) /= 0) then
          --================== FAST MATCH  =================================
          pipeline_match_rsp(0).valid      <= '1';
          if(traffic_nf_d = '1' and traffic_ff_d = '1') then -- special markers
            pipeline_match_rsp(0).port_mask<= rtu_str_config_i.cpu_forward_mask or 
                                              rsp_fast_match.port_mask; -- for sure zeros when drop
            pipeline_match_rsp(0).drop     <= '0';          
          elsif(traffic_nf_d = '1') then -- only non-forward traffic
            pipeline_match_rsp(0).port_mask<= rtu_str_config_i.cpu_forward_mask;
            pipeline_match_rsp(0).drop     <= '0';
          else
            pipeline_match_rsp(0).port_mask<= rsp_fast_match.port_mask;
            pipeline_match_rsp(0).drop     <= rsp_fast_match.drop;
          end if;
          pipeline_match_rsp(0).prio       <= rsp_fast_match.prio;
  
          pipeline_match_rsp(0).nf         <= traffic_nf_d;   
          pipeline_match_rsp(0).ff         <= traffic_ff_d;   
          pipeline_match_rsp(0).hp         <= traffic_hp_d;   
          ---================================================================
        else
          pipeline_match_rsp(0)             <= match_rsp_zero;
        end if; 

        -- shifting
        PIPELINE_SHIFT: for i in pipeline_depth-1 downto 1 loop
          pipeline_valid(i)          <= pipeline_valid(i-1);
          pipeline_grant(i)          <= pipeline_grant(i-1);          
        end loop PIPELINE_SHIFT;
        pipeline_match_rsp(1)        <= pipeline_match_rsp(0);
      end if;
    end if;
  end process;
  
  -- TRU request
--   tru_req_o.valid             <= pipeline_valid(1) and (not traffic_nf_d) and tru_enabled_i;
  tru_req_o.valid             <= pipeline_valid(1) and tru_enabled_i;
  tru_req_o.smac              <= rtu_req_stage_1.smac;
  tru_req_o.dmac              <= rtu_req_stage_1.dmac;
  tru_req_o.fid               <= vtab_rd_entry_i.fid; -- directly from VLAN TABLE
  tru_req_o.isHP              <= traffic_hp_d;
  tru_req_o.isBR              <= traffic_br_d;
  tru_req_o.reqMask(g_num_ports-1 downto 0)                <= pipeline_grant(1); 
  tru_req_o.reqMask(c_rtu_max_ports-1 downto g_num_ports)  <= (others => '0'); 
  -- this is more for testing then to be used
  tru_req_o.prio              <= rtu_req_stage_1.prio when(rtu_req_stage_1.has_prio = '1') else (others=>'0');
  
  -- fast match response
  -- 1) if TRU is disabled, we don't take TRU's decision in consideration and we can respond
  --    faster
  -- 2) if TRU is enabled, we responde on cycle later and we need to take TRU's decision in consideration
  match_rsp_data_o.valid      <= pipeline_match_rsp(0).valid     when (tru_enabled_i = '0') else
                                 pipeline_match_rsp(1).valid;
  match_rsp_data_o.port_mask  <= pipeline_match_rsp(0).port_mask when (tru_enabled_i = '0') else
                                 pipeline_match_rsp(1).port_mask(c_rtu_max_ports -1 downto g_num_ports) &
                                (pipeline_match_rsp(1).port_mask(g_num_ports-1 downto 0)   and -- in order not to affect CPU foreard (BPUD)
                                 tru_rsp_i.port_mask(g_num_ports-1 downto 0)) ;                -- we don't AND more ports then we have
  match_rsp_data_o.prio       <= pipeline_match_rsp(0).prio      when (tru_enabled_i = '0') else
                                 pipeline_match_rsp(1).prio ;
  match_rsp_data_o.drop       <= pipeline_match_rsp(0).drop      when (tru_enabled_i = '0') else
                                 pipeline_match_rsp(1).drop      when (pipeline_match_rsp(1).nf = '1') else -- if non-forward, dont drop even if TRU says so
                                 pipeline_match_rsp(1).drop or tru_rsp_i.drop;
  match_rsp_data_o.nf         <= pipeline_match_rsp(0).nf        when (tru_enabled_i = '0') else
                                 pipeline_match_rsp(1).nf;
  match_rsp_data_o.ff         <= pipeline_match_rsp(0).ff        when (tru_enabled_i = '0') else
                                 pipeline_match_rsp(1).ff;
  match_rsp_data_o.hp         <= pipeline_match_rsp(0).hp        when (tru_enabled_i = '0') else
                                 pipeline_match_rsp(1).hp;
  match_rsp_valid_o           <= pipeline_grant(2)               when (tru_enabled_i = '0') else
                                 pipeline_grant(3);
end architecture;

