-------------------------------------------------------------------------------
-- Title      : Routing Table Unit's Port Representation (RTU_PORT)
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_rtu_port.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-05-08
-- Last update: 2012-01-26
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- It represents each switch's port (endpoint), it
-- - take requests from a give port
-- - forwards the request to request FIFO (access governed by Round Robin Alg)
-- - awaits the answer from RTU engine
-- - outputs response to the port which requested it (endpoint)
--
-------------------------------------------------------------------------------
--
-- Copyright (c) 2010 Maciej Lipinski / CERN
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
--
-------------------------------------------------------------------------------
--TODO:
--1) configure whether to drop or fast forward on full_match fifo_full (rq_fifo_full_i)
--2) add handling the "impossible" situation when the full_match is read and the
--   fast_match is not ready (port_state=S_FAST_MATCH)
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2010-05-08  1.0      lipinskimm      Created
-- 2010-05-29  1.1      lipinskimm     modified FSM, added rtu_gcr_g_ena_i
-- 2010-12-05  1.2      twlostow        added independent output FIFOs
-- 2012-05-20  1.3      mlipinsk        making this stuff deterministic !!!
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rtu_private_pkg.all;
use work.genram_pkg.all;
use work.wrsw_shared_types_pkg.all;
use work.pack_unpack_pkg.all;

entity rtu_port_new is
  generic(
    g_num_ports        : integer;
    g_port_mask_bits   : integer; -- usually: g_num_ports + 1 for CPU
    g_port_index       : integer
    );
  port(

    -- clock (62.5 MHz refclk/2)
    clk_i                    : in std_logic;
    -- reset (synchronous, active low)
    rst_n_i                  : in std_logic;

    -------------------------------------------------------------------------------
    -- N-port RTU input interface (from the endpoint)
    -------------------------------------------------------------------------------
    -- 1 indicates that coresponding RTU port is idle and ready to accept requests
    rtu_idle_o               : out std_logic;
    rtu_rq_i                 : in  t_rtu_request;
    rtu_rq_aboard_i          : in  std_logic;
    rtu_rsp_o                : out t_rtu_response;
    rtu_rsp_ack_i            : in std_logic;

    -------------------------------------------------------------------------------
    -- request FIFO interfacing
    -------------------------------------------------------------------------------

    rq_fifo_wr_access_o      : out std_logic;
    rq_fifo_wr_data_o        : out std_logic_vector(c_PACKED_REQUEST_WIDTH - 1 downto 0);
    rq_fifo_wr_done_i        : in  std_logic;
    rq_fifo_full_i           : in  std_logic;
    -------------------------------------------------------------------------------
    -- response FIFO interfacing
    -------------------------------------------------------------------------------
    
    match_data_i             : in std_logic_vector(g_num_ports + c_PACKED_RESPONSE_WIDTH - 1 downto 0);
    match_data_valid_i       : in std_logic;

    -------------------------------------------------------------------------------
    -- VLAN read
    -------------------------------------------------------------------------------
    -- request access
    vtab_rd_addr_o            : out std_logic_vector(c_wrsw_vid_width-1 downto 0);
    vtab_rd_req_o             : out std_logic;
    vtab_rd_entry_i           : in  t_rtu_vlan_tab_entry;
    vtab_rd_valid_i           : in  std_logic;
    -------------------------------------------------------------------------------
    -- REQUEST COUNTER 
    -------------------------------------------------------------------------------

    port_almost_full_o        : out std_logic;
    port_full_o               : out std_logic;

    -------------------------------------------------------------------------------
    -- REQUEST COUNTER 
    -------------------------------------------------------------------------------

    tru_req_o                 : out  t_tru_request;
    tru_rsp_i                 : in   t_tru_response;  
    tru_enabled_i             : in   std_logic;
    
    -------------------------------------------------------------------------------
    -- control register
    ------------------------------------------------------------------------------- 
    rtu_str_config_i          : in t_rtu_special_traffic_config;

    rtu_gcr_g_ena_i           : in std_logic;  
    rtu_pcr_pass_bpdu_i       : in std_logic_vector(c_rtu_max_ports -1 downto 0);
    rtu_pcr_pass_all_i        : in std_logic_vector(c_rtu_max_ports -1 downto 0);
    rtu_pcr_fix_prio_i        : in std_logic;
    rtu_pcr_prio_val_i        : in std_logic_vector(c_wrsw_prio_width - 1 downto 0)
    );

end rtu_port_new;

architecture behavioral of rtu_port_new is

--- RTU FSM state definitions
  type t_fast_match_state   is (S_IDLE, 
                                S_VLAN_ACCESS_REQ,
                                S_VLAN_RSP_TRU_ACCESS, 
                                S_TRU_PROCESSING, 
                                S_FAST_MATCH_READY);

  type t_rtu_port_rq_states is (S_IDLE, 
                                S_FULL_MATCH, 
                                S_WAIT_FULL_MATCH,
                                S_FAST_MATCH, 
                                S_BPDU_MATCH, 
                                S_FINAL_MASK,
                                S_RESPONSE);

  signal fast_match_state            : t_fast_match_state;
  signal port_state                  : t_rtu_port_rq_states;
  
  -- port control:
  signal port_pcr_pass_bpdu          : std_logic;
  signal port_pcr_pass_all           : std_logic;
  
  -- full match input modified by port config (if necessary)
  signal rq_fifo_d                   : std_logic_vector(c_PACKED_REQUEST_WIDTH - 1 downto 0);
  signal rq_fifo_d1                  : std_logic_vector(c_PACKED_REQUEST_WIDTH - 1 downto 0);
  signal rq_prio                     : std_logic_vector(2 downto 0); 
  signal rq_has_prio                 : std_logic;
  signal rq_prio_mask                : std_logic_vector(7 downto 0);
  signal rq_fifo_wr_access           : std_logic;            -- control input fifo
  signal rq_fifo_wr_access_int       : std_logic; -- this is just to know when we have request, 
                                                  -- to mask unwanted match_engine responses 
                                                  -- (they should not happen, but they do due 
                                                  -- to bugs...)
  signal rq_rsp_cnt                  : unsigned(2 downto 0); -- count rq/rsp

  --- fast match stuff
  signal vtab_rd_req                 : std_logic; -- request access to VLAN tabl
  signal vtab_rd_entry_d             : t_rtu_vlan_tab_entry; -- VLAN tab response
  signal rsp_fast_match              : t_match_response;     -- fast match response
  signal rsp_full_match              : t_match_response;     -- full match response
  signal tru_rsp                     : t_tru_response;       -- response from tru
  signal tru_rsp_valid               : std_logic;
  -------------  final response
  signal rsp_raw                     : t_match_response;     -- intermedaite stage to final response
  signal rsp                         : t_rtu_response;       -- final response -- output to SWcore

  --- controlling the process
  signal special_address             : std_logic; -- address which is considered for fast match
  signal nofw_traffic                : std_logic; -- no-forward traffic
  signal hp_traffic                  : std_logic; -- indicates that the processed frame
                                                  -- is recognzied as High Priority    : std_logic;
  signal hp_traffic_d                : std_logic;
  signal ptp_traffic                 : std_logic;
  signal br_traffic                  : std_logic; -- indicates that the frame is braodcast
  signal port_enabled                : std_logic; -- port enabled
  signal port_nofw_enabled           : std_logic; -- port enabled for no-forward traffic :
                                                  -- fully enabled or enabled only for BPDU
  signal start_no_match              : std_logic; -- port disabled on request from SWcore
  signal start_nofw_match            : std_logic; -- we perform a quick match for no-forward-traffic
                                                  -- the NIC's port is indicated by config
  signal start_fast_match            : std_logic; -- frame quilifies for fast match
  signal start_full_match            : std_logic; -- frame qualifies for full match
  signal wait_full_match             : std_logic;
--   signal mirrored_port               : std_logic; -- traffic on this port is mirrored onto 
                                                  -- another port (indicated by config mask)

  signal mirror_port_dst             : std_logic;
  signal mirror_port_src_rx          : std_logic;
  signal mirror_port_src_tx          : std_logic;

  signal start_full_match_delayed    : std_logic;
  signal src_port_mask               : std_logic_vector(c_rtu_max_ports-1 downto 0);  --helper 
  signal forwarding_mask             : std_logic_vector(c_rtu_max_ports-1 downto 0);  --helper 
  signal forwarding_and_mirror_mask  : std_logic_vector(c_rtu_max_ports-1 downto 0);  --helper 
  signal drop                        : std_logic;
  
  signal full_match_in               : t_match_response;
  signal full_match_rsp_port         : std_logic_vector(g_num_ports-1 downto 0);
  signal full_match_rsp_prio         : std_logic_vector(c_wrsw_prio_width-1 downto 0);
  
  signal rtu_idle                    : std_logic;
  
  signal tru_req                     : t_tru_request;
  -- VHDL -- lovn' it
  signal zeros                       : std_logic_vector(47 downto 0);
begin

  zeros              <= (others => '0');

  port_pcr_pass_bpdu <= rtu_pcr_pass_bpdu_i(g_port_index);
  port_pcr_pass_all  <= rtu_pcr_pass_all_i(g_port_index);

  rq_prio            <= f_pick(rtu_pcr_fix_prio_i = '0', rtu_rq_i.prio, rtu_pcr_prio_val_i);
  rq_has_prio        <= (rtu_pcr_fix_prio_i or rtu_rq_i.has_prio);
  rq_prio_mask       <= f_set_bit(zeros(7 downto 0),'1',to_integer(unsigned(rq_prio)));   
  -- create request fifo input data
  rq_fifo_d        <=	
    rtu_rq_i.has_vid	
    & rq_prio       -- modified by per-port config
    & rq_has_prio   -- modified by per-port config
    & rtu_rq_i.vid
    & rtu_rq_i.dmac
    & rtu_rq_i.smac;

  rq_fifo_wr_data_o   <= rq_fifo_d1;          --_reg;

  special_address  <=  f_fast_match_mac_lookup(rtu_str_config_i, rtu_rq_i.dmac);

  -- indicates that he frame's destination address is within the range of addresses
  -- which shall never be forwarded by the switch but it is also send on the ports
  -- which are not forwarding. 
  -- Here, we are msotly interested in BPDUs
  ptp_traffic      <= '1' when (rtu_rq_i.dmac = x"011b19000000") else '0';

  -- 
  nofw_traffic     <= f_mac_in_range(rtu_rq_i.dmac,bpd_range_lower,bpd_range_upper) or ptp_traffic; 

  -- indicates that the frame being handled is High Priority (broadcast/mutlicast + 
  -- proper priority/priorities  
  hp_traffic       <= '1' when (special_address='1' and rq_has_prio = '1' and 
                                (rtu_str_config_i.hp_prio and rq_prio_mask) /= zeros(7 downto 0) ) else
                      '1' when (special_address='1' and rtu_rq_i.has_prio = '0' and 
                                rtu_str_config_i.hp_prio = x"00") else
                      '0';
  br_traffic       <= '1' when (rtu_rq_i.dmac = x"FFFFFFFFFFFF") else '0';
  port_enabled     <= '0' when (rtu_gcr_g_ena_i     = '0' or 
                                port_pcr_pass_all   = '0' or 
                                mirror_port_dst     = '1')  else
                      '1';

  port_nofw_enabled<= '0' when (rtu_gcr_g_ena_i    ='0' or mirror_port_dst     = '1') else
                      '1' when (port_pcr_pass_bpdu ='0' or port_pcr_pass_all   = '0') else
                      '1';

  -- the port is disabled for normal traffic (excluding link-based == never-forwarded, bpdu)
  start_no_match   <= (not port_enabled) and rtu_rq_i.valid;

  -- the incoming frame matches the never-forwarded-frames characterstics and we have 
  -- special configuraiton for such frames (NIC port indicated)
  -- the frame is BPDU (in general no-forward-frames) and quick_bpdu_forwarding is defined 
  -- (mask in config), otherwise use "full match" - this is partly for backward compatibility 
  -- but also for being able
  -- to do some more magic
  start_nofw_match <= '1' when (port_nofw_enabled   ='1' and nofw_traffic = '1' and 
                                rtu_str_config_i.bpd_forward_mask /= zeros(c_rtu_max_ports-1 downto 0)) else
                      '0';
  -- the incoming frame match the fast_match characteristics
  --start_fast_match <= port_enabled and (not vtab_rd_req) and rtu_rq_i.valid and (not start_nofw_match);
  start_fast_match <= port_enabled and rtu_idle and rtu_rq_i.valid and (not start_nofw_match);
  
  -- the incoming frame qualifies for full match
  start_full_match <= '1' when (start_fast_match      = '1' and      -- fast match but match "free"
                                special_address       = '1' and 
                                rq_fifo_wr_access_int = '0' and
                                rq_fifo_full_i        = '0' and
                                rq_rsp_cnt            =  0)     else
                      '1' when (start_fast_match      = '1' and      -- not a fast match
                                special_address       = '0' and
                                rq_fifo_full_i        = '0')    else
                      '0';
  
  wait_full_match  <= '1' when (start_fast_match      = '1' and      -- need full match but 
                                special_address       = '0' and      -- reqFiFo full
                                rq_fifo_full_i        = '1')    else
                      '0';
  -- turn port number into bit vector
  src_port_mask    <= f_set_bit(zeros(c_rtu_max_ports-1 downto 0),'1',g_port_index);

  -- check whether this port is a port which mirrors other port(s). In such case any incoming
  -- traffic is not allowed and forwarded is only mirror traffic     
  mirror_port_dst     <= '1' when ((src_port_mask and rtu_str_config_i.mirror_port_dst) /= 
                                      zeros(c_rtu_max_ports-1 downto 0)) else
                         '0';
  -- ingress traffic to this port (rx) is forwarded to mirror port if such port exists 
  mirror_port_src_rx  <= '1' when ((src_port_mask and rtu_str_config_i.mirror_port_src_rx) /=
                                     zeros(c_rtu_max_ports-1 downto 0)  ) else
                         '0';
  -- traffic from this port is forwarded (tx) to the port being mirrord , so we forward it
  -- also to mirror port (mirror_port_dst)
  mirror_port_src_tx  <= '1' when ((forwarding_mask and rtu_str_config_i.mirror_port_src_tx) /=
                                     zeros(c_rtu_max_ports-1 downto 0)  ) else
                         '0';


  
  --
--   mirrored_port       <= '1' when ((src_port_mask and rtu_str_config_i.mirrored_port_src) /=
--                                      zeros(c_rtu_max_ports-1 downto 0) and 
--                                   (src_port_mask and rtu_str_config_i.mirrored_port_dst) = 
--                                       zeros(c_rtu_max_ports-1 downto 0) ) else
--                       '0';
  
  f_unpack5(match_data_i, 
           full_match_in.bpdu,
           full_match_in.port_mask, 
           full_match_in.drop,  
           full_match_rsp_prio,
           full_match_rsp_port);
  full_match_in.prio(c_wrsw_prio_width-1 downto 0)  <= full_match_rsp_prio;
  full_match_in.valid                               <= match_data_valid_i and full_match_rsp_port(g_port_index);
  
  
  vtab_rd_addr_o     <= rtu_rq_i.vid when (rtu_rq_i.has_vid = '1' and start_fast_match = '1') else
                        (others =>'0'); 
  vtab_rd_req        <= start_fast_match and rtu_idle;
  
  rtu_idle_o         <= rtu_idle;-- and not rq_fifo_full_i;
  
  tru_rsp_valid      <= tru_rsp_i.valid and tru_rsp_i.respMask(g_port_index);
  --------------------------------------------------------------------------------------------
  -- FSM: making FAST MATCH - reading VLAN and making forwarding decision based on this only
  -- + reading TRU, 
  --------------------------------------------------------------------------------------------
  p_ctr_fast_match: process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
--         vtab_rd_addr_o            <= (others =>'0');
--         vtab_rd_req               <= '0';
        rsp_fast_match.valid      <= '0';                 
        rsp_fast_match.port_mask  <= (others =>'0');
        rsp_fast_match.prio       <= (others =>'0');
        rsp_fast_match.drop       <= '0';
        rsp_fast_match.bpdu       <= '0';
        tru_req.valid           <= '0';
        tru_req.smac            <= (others=>'0');
        tru_req.dmac            <= (others=>'0');
        tru_req.fid             <= (others=>'0');
        tru_req.isHP            <= '0';
        tru_req.isBR            <= '0';
        tru_req.reqMask         <= (others=>'0');
        
        tru_rsp.valid           <= '0';
        tru_rsp.port_mask       <= (others=>'0');
        tru_rsp.drop            <= '0';
        tru_rsp.respMask        <= (others=>'0');
        
      else    
       case fast_match_state is
        
          ------------------------------------------------------------------------------------
          --| IDLE: 
          ------------------------------------------------------------------------------------
          when S_IDLE =>

             rsp_fast_match.valid      <= '0';                 
             rsp_fast_match.port_mask  <= (others =>'0');
             rsp_fast_match.prio       <= (others =>'0');
             rsp_fast_match.drop       <= '0';
             rsp_fast_match.bpdu       <= '0';

             if(start_nofw_match = '1') then

               rsp_fast_match.valid      <= '1';                 
               rsp_fast_match.port_mask  <= rtu_str_config_i.bpd_forward_mask;      
               rsp_fast_match.prio       <= (others =>'0');
               rsp_fast_match.drop       <= '0';
               rsp_fast_match.bpdu       <= '1';
               fast_match_state          <= S_FAST_MATCH_READY;
             
             elsif(start_fast_match = '1') then
               -- remember TRU stuff
               tru_req.valid      <= '0';             -- to be set later
               tru_req.smac       <= rtu_rq_i.smac;
               tru_req.dmac       <= rtu_rq_i.dmac;
               tru_req.fid        <= (others => '0'); -- to be set later
               tru_req.isHP       <= hp_traffic;
               tru_req.isBR       <= br_traffic;
               tru_req.reqMask    <= src_port_mask;
             
--                if(rtu_rq_i.has_vid = '1') then
--                  vtab_rd_addr_o     <= rtu_rq_i.vid;
--                else
--                  vtab_rd_addr_o     <= (others =>'0');
--                end if;
--                vtab_rd_req          <= '1';
               fast_match_state     <= S_VLAN_ACCESS_REQ;
             end if;

          ------------------------------------------------------------------------------------
          --| S_VLAN_ACCESS_REQ:
          ------------------------------------------------------------------------------------
          when S_VLAN_ACCESS_REQ =>
--             vtab_rd_req          <= '0';
            
            if(vtab_rd_valid_i = '1') then
              fast_match_state     <= S_VLAN_RSP_TRU_ACCESS;
               if(tru_enabled_i = '1') then  
                 tru_req.valid      <= '1';
               end if;
            end if;

          ------------------------------------------------------------------------------------
          --| S_VLAN_ACCESS:
          ------------------------------------------------------------------------------------
          when S_VLAN_RSP_TRU_ACCESS =>
            rsp_fast_match        <= f_fast_match_response(vtab_rd_entry_i,
                                                            rq_prio,rq_has_prio,
                                                            rtu_pcr_pass_all_i,
                                                            g_port_mask_bits);
            tru_req.valid          <= '0';
            if(tru_enabled_i = '1') then         
--               tru_req.fid        <= vtab_rd_entry_i.fid;
--               tru_req.valid      <= '1';    
              fast_match_state     <= S_TRU_PROCESSING;
            else
              rsp_fast_match.valid <= '1';   
              fast_match_state     <= S_FAST_MATCH_READY;
            end if;

          ------------------------------------------------------------------------------------
          --| S_TRU_ACCESS: 
          ------------------------------------------------------------------------------------
          when S_TRU_PROCESSING =>
            if(tru_rsp_valid = '1') then
              tru_rsp               <= tru_rsp_i;
              fast_match_state      <= S_FAST_MATCH_READY;
              rsp_fast_match.valid  <= '1'; 
            end if;
             
          ------------------------------------------------------------------------------------
          --| IDLE: waiting for the request from a port
          ------------------------------------------------------------------------------------
          when S_FAST_MATCH_READY =>
            if(rtu_rsp_ack_i = '1') then
              fast_match_state     <= S_IDLE;  
            end if;
          ------------------------------------------------------------------------------------
          --| OTHER: 
          ------------------------------------------------------------------------------------
          when others => null;
--             vtab_rd_addr_o            <= (others =>'0');
--             vtab_rd_req               <= '0';
            rsp_fast_match.valid      <= '0';                 
            rsp_fast_match.port_mask  <= (others =>'0');
            rsp_fast_match.prio       <= (others =>'0');
            rsp_fast_match.drop       <= '0';
            rsp_fast_match.bpdu       <= '0';
            tru_req.valid           <= '0';
            tru_req.smac            <= (others=>'0');
            tru_req.dmac            <= (others=>'0');
            tru_req.fid             <= (others=>'0');
            tru_req.isHP            <= '0';
            tru_req.isBR            <= '0';
            tru_req.reqMask         <= (others=>'0');       
            fast_match_state          <= S_IDLE;  
        --------------------------------------------------------------------------------------
        end case;
      end if;
    end if;
  end process p_ctr_fast_match;

--   tru_req_o <= tru_req;
  tru_req_o.valid      <= tru_req.valid;
  tru_req_o.smac       <= tru_req.smac;
  tru_req_o.dmac       <= tru_req.dmac;
  tru_req_o.fid        <= vtab_rd_entry_i.fid; -- directly from VLAN TABLE
  tru_req_o.isHP       <= tru_req.isHP;
  tru_req_o.isBR       <= tru_req.isBR;
  tru_req_o.reqMask    <= tru_req.reqMask;  
  --------------------------------------------------------------------------------------------
  -- making requests to match engine and waiting for responses (FULL MATCH)
  --------------------------------------------------------------------------------------------
  p_ctr_full_match: process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        rq_fifo_wr_access      <='0';
        rq_fifo_wr_access_int  <='0'; -- this is just to know when we have request, to mask
                                      -- unwanted match_engine responses (they should not 
                                      -- happen, but they do due to bugs...)
      else    
        rq_fifo_wr_access    <='0';  
        
        if(start_full_match = '1' or wait_full_match ='1') then
          rq_fifo_d1             <= rq_fifo_d; -- that sucks !!
          if(start_full_match = '1') then
            rq_fifo_wr_access      <='1';  
            rq_fifo_wr_access_int  <='1';          
          end if;
        elsif(start_full_match_delayed = '1') then 
          rq_fifo_wr_access      <='1';  
          rq_fifo_wr_access_int  <='1';                  
        elsif(full_match_in.valid = '1' and rq_fifo_wr_access_int  ='1') then
          rq_fifo_wr_access_int  <='0';
          --------
        end if;
      end if;
    end if;
  end process p_ctr_full_match;

--   rq_fifo_wr_access <= start_full_match and rtu_idle;
  --------------------------------------------------------------------------------------------
  -- counting scheduled match requets and responses, this is for the case
  -- that we got aboard from SWcore, so that we don't take bad resonse from the match engine
  --------------------------------------------------------------------------------------------
  p_rq_rsp_cnt: process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        rq_rsp_cnt <= (others => '0');
      else    
        if(start_full_match = '1' and rq_fifo_wr_access ='0' and rq_fifo_wr_access_int  ='0') then
          rq_rsp_cnt <= rq_rsp_cnt + 1;
        elsif(full_match_in.valid = '1' and rq_fifo_wr_access_int  ='1') then
          rq_rsp_cnt <= rq_rsp_cnt - 1;
        end if;
      end if;
    end if;
  end process p_rq_rsp_cnt;

  -------------------------------------------------------------------------------------------------------------------------
  --| 
  --| (state transitions)       
  -------------------------------------------------------------------------------------------------------------------------

  port_fsm_state : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        ------------------------------------------------------------------------------------------------------------ 
        --| RESET
        ------------------------------------------------------------------------------------------------------------     

        -- FSM state
        port_state                <= S_IDLE;
        rtu_idle                <= '1';    -- indecate idle state of the port
        rsp_raw.valid             <= '0';
        rsp_raw.port_mask         <= (others=>'0');
        rsp_raw.prio              <= (others=>'0');
        rsp_raw.drop              <='0';
        rsp_raw.bpdu              <='0';
        rsp.valid                 <= '0';
        rsp.port_mask             <= (others =>'0');
        rsp.prio                  <= (others =>'0');
        rsp.drop                  <= '0';
        rsp.hp                    <= '0';
        hp_traffic_d              <= '0';
        start_full_match_delayed  <= '0';
      else
        -- FSM
        case port_state is
        
          ------------------------------------------------------------------------------------------------------------ 
          --| IDLE: waiting for the request from a port
          ------------------------------------------------------------------------------------------------------------ 
          when S_IDLE =>
            
            rtu_idle              <= '1';
            
            -- It is possible that the port accepts the incoming frame:
            -- * it is enabled and the forwarding decision is needed
            -- * it is disabled but the frame is BPDU
            if(start_fast_match = '1' or start_full_match = '1' or 
               start_nofw_match = '1' or wait_full_match  = '1') then
              
              if(start_nofw_match = '1') then
                port_state    <= S_BPDU_MATCH;
              elsif(special_address = '1') then
                port_state    <= S_FAST_MATCH;
              elsif(wait_full_match  = '1') then
                port_state    <= S_WAIT_FULL_MATCH;
              else
                port_state    <= S_FULL_MATCH;
              end if;
              rtu_idle            <= '0';
              hp_traffic_d        <= hp_traffic;
              
            -- The port is not accepting incoming frame:
            -- * the RTU is disabled entirely
            -- * the port is disabled and the incoming frame is not BPUD
            -- * the port is set to mirror other port, it transmit-only
            elsif(start_no_match = '1') then
              rsp.valid           <= '1';
              rsp.prio            <= (others=>'0');
              rsp.hp              <= '0';
              rsp.port_mask       <= (others=>'0');
              rsp.drop            <='1';   
              port_state          <= S_RESPONSE;
              rtu_idle            <= '0';
            end if;

          ------------------------------------------------------------------------------------------------------------ 
          --| in this case, the match_req FIFO is full, so we need to wait for it to be emptied.
          --| We don't simply indicate that the RTU is busy (idle='0') because that would make
          --| the things undeterministic. If we accept the request even if FIFO is full, the
          --| SWcore can aboard the request if waiting takes too long in order to avoid
          --| blocking incoming HP (to be low latency) frames
          ------------------------------------------------------------------------------------------------------------ 
          when S_WAIT_FULL_MATCH =>
            
            if(rtu_rq_aboard_i = '1') then
              port_state               <= S_FAST_MATCH; 
            elsif(rq_fifo_full_i = '0') then
              start_full_match_delayed <='0';
              port_state               <= S_FULL_MATCH;
            end if;
 
          ------------------------------------------------------------------------------------------------------------ 
          --| 
          ------------------------------------------------------------------------------------------------------------          
          when S_FULL_MATCH =>
            
--             if(rq_fifo_wr_access = '1' and rq_fifo_wr_done_i = '1' and full_match_in.valid = '1') then
            if(full_match_in.valid = '1' and rsp_fast_match.valid = '1') then -- TODO_2
              rsp_raw             <= full_match_in;
              port_state          <= S_FINAL_MASK; 
            elsif(rtu_rq_aboard_i = '1' and rsp_fast_match.valid = '1') then
              rsp_raw             <= rsp_fast_match; 
              port_state          <= S_FINAL_MASK;
            elsif(rtu_rq_aboard_i = '1' and rsp_fast_match.valid = '0') then
               -- this should not happen -> handle exeption
               port_state         <= S_FAST_MATCH;               
            end if;

          ------------------------------------------------------------------------------------------------------------ 
          --| 
          ------------------------------------------------------------------------------------------------------------             
          when S_FAST_MATCH =>
            
            if(rsp_fast_match.valid = '1') then
              rsp_raw               <= rsp_fast_match; 
              port_state            <= S_FINAL_MASK;              
            elsif(rtu_rq_aboard_i = '1' and rsp_fast_match.valid = '0') then
               -- this should not happen -> handle exeption
            end if;

          ------------------------------------------------------------------------------------------------------------ 
          --| 
          ------------------------------------------------------------------------------------------------------------             
          when S_BPDU_MATCH =>
            
            if(rsp_fast_match.valid = '1') then
              rsp_raw               <= rsp_fast_match; 
              port_state            <= S_FINAL_MASK;     
            end if;           
              
          ------------------------------------------------------------------------------------------------------------ 
          --| 
          ------------------------------------------------------------------------------------------------------------             
          when S_FINAL_MASK =>

            rsp.valid             <= '1';
            rsp.prio              <= rsp_raw.prio;
            rsp.hp                <= hp_traffic_d;   
            
            if(mirror_port_src_rx = '1' or mirror_port_src_tx = '1') then
              if(drop = '1') then
                rsp.port_mask     <= f_set_bit(rtu_str_config_i.mirror_port_dst,'0',g_port_index) ;
              else
                rsp.port_mask     <= f_set_bit(forwarding_and_mirror_mask,'0',g_port_index) ;
              end if;
              rsp.drop          <= '0';
            else
              rsp.port_mask       <= f_set_bit(forwarding_mask,'0',g_port_index) ;              
              rsp.drop            <= drop;            
            end if;
            
--             if(tru_enabled_i = '0' or rsp_raw.bpdu = '1') then
--               -- don't appply TRU decision if TRU is disabled or if it's BPDU frame
--               rsp.port_mask     <= forwarding_mask;
--               rsp.drop          <= rsp_raw.drop;
--             else
--               rsp.port_mask     <= forwarding_mask and tru_rsp.port_mask;
--               rsp.drop          <= rsp_raw.drop or tru_rsp.drop;
--             end if;
            port_state          <= S_RESPONSE;

          ------------------------------------------------------------------------------------------------------------ 
          --| 
          ------------------------------------------------------------------------------------------------------------             
          when S_RESPONSE =>
            if(rtu_rsp_ack_i = '1') then            
              rsp.valid         <= '0';
              rsp.port_mask     <= (others =>'0');
              rsp.prio          <= (others =>'0');
              rsp.drop          <= '0';
              rsp.hp            <= '0';
              rtu_idle          <= '1';
              port_state        <= S_IDLE;
            end if;

          ------------------------------------------------------------------------------------------------------------ 
          --| OTHER: 
          ------------------------------------------------------------------------------------------------------------                       
          when others => null;
        ------------------------------------------------------------------------------------------------------------
        end case;
      end if;
    end if;
  end process port_fsm_state;

  -- don't appply TRU decision if TRU is disabled or if it's BPDU frame
  forwarding_mask     <= rsp_raw.port_mask when (tru_enabled_i = '0' or rsp_raw.bpdu = '1') else
                         rsp_raw.port_mask and tru_rsp.port_mask;
  drop                <= rsp_raw.drop      when (tru_enabled_i = '0' or rsp_raw.bpdu = '1') else
                         rsp_raw.drop or tru_rsp.drop;
  
  forwarding_and_mirror_mask <= forwarding_mask or rtu_str_config_i.mirror_port_dst;
   
--   forwarding_mask     <= f_set_bit(rsp_raw.port_mask,'0',g_port_index) when (mirrored_port = '0') else
--                          f_set_bit(rsp_raw.port_mask,'0',g_port_index) or rtu_str_config_i.mirrored_port_dst;
   
  rtu_rsp_o               <= rsp;
  
  rq_fifo_wr_access_o<= rq_fifo_wr_access;
  vtab_rd_req_o      <= vtab_rd_req;
end architecture;  --wrsw_rtu_port
