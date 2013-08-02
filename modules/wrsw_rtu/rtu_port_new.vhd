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
--1) change drop/flood - drop by default
--2) might need to change RR of full match (change to strobe)
--3) fill in aboard from extrnal (SWcore) source
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2010-05-08  1.0      lipinskimm      Created
-- 2010-05-29  1.1      lipinskimm      modified FSM, added rtu_gcr_g_ena_i
-- 2010-12-05  1.2      twlostow        added independent output FIFOs
-- 2012-05-20  1.3      mlipinsk        making this stuff deterministic !!!
-- 2012-11-06  1.4      mlipinsk        literally, re-writing: adding i/f with fast_match, mirroring...
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;
use ieee.numeric_std.all;

use work.rtu_private_pkg.all;
use work.genram_pkg.all;
use work.wrsw_shared_types_pkg.all;
use work.pack_unpack_pkg.all;

entity rtu_port_new is
  generic(
    g_num_ports        : integer;
    g_port_mask_bits   : integer; -- usually: g_num_ports + 1 for CPU
    g_match_req_fifo_size : integer;
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
    rtu_rq_aboard_i          : in  std_logic;     -- not used yet
    rtu_rsp_o                : out t_rtu_response;
    rtu_rsp_ack_i            : in std_logic;

    -------------------------------------------------------------------------------
    -- Full Match I/F
    -------------------------------------------------------------------------------
    -- request
    full_match_wr_req_o      : out std_logic;  -- shall be high till done (supressed by done)
    full_match_wr_data_o     : out std_logic_vector(c_PACKED_REQUEST_WIDTH - 1 downto 0);
    full_match_wr_done_i     : in  std_logic;
    full_match_wr_full_i     : in  std_logic;
    -- response
    full_match_rd_data_i     : in std_logic_vector(g_num_ports + c_PACKED_RESPONSE_WIDTH - 1 downto 0);
    full_match_rd_valid_i    : in std_logic;

    -------------------------------------------------------------------------------
    -- Fast Match
    -------------------------------------------------------------------------------
    -- request
    fast_match_wr_req_o      : out std_logic;   -- shall be a strobe
    fast_match_wr_data_o     : out t_rtu_request;
    -- response
    fast_match_rd_valid_i    : in std_logic;
    fast_match_rd_data_i     : in t_match_response;
    -------------------------------------------------------------------------------
    -- REQUEST COUNTER 
    -------------------------------------------------------------------------------
    port_almost_full_o        : out std_logic;
    port_full_o               : out std_logic;

    -------------------------------------------------------------------------------
    -- info to TRU
    ------------------------------------------------------------------------------- 
--     tru_o                     : out t_rtu2tru;
    -------------------------------------------------------------------------------
    -- control register
    ------------------------------------------------------------------------------- 
    rtu_str_config_i          : in t_rtu_special_traffic_config;

    rtu_gcr_g_ena_i           : in std_logic;  
--     rtu_pcr_pass_bpdu_i       : in std_logic_vector(c_rtu_max_ports -1 downto 0);
--     rtu_pcr_pass_all_i        : in std_logic_vector(c_rtu_max_ports -1 downto 0);
    rtu_pcr_pass_bpdu_i       : in std_logic;
    rtu_pcr_pass_all_i        : in std_logic;
    rtu_pcr_fix_prio_i        : in std_logic;
    rtu_pcr_prio_val_i        : in std_logic_vector(c_wrsw_prio_width - 1 downto 0)
    );

end rtu_port_new;

architecture behavioral of rtu_port_new is

  type t_rtu_port_rq_states is (S_IDLE, 
                                S_FAST_MATCH, 
                                S_FULL_MATCH,                                 
                                S_FINAL_MASK,
                                S_RESPONSE);

  signal port_pcr_pass_bpdu          : std_logic;
  signal port_pcr_pass_all           : std_logic;
  signal rq_fifo_d                   : std_logic_vector(c_PACKED_REQUEST_WIDTH - 1 downto 0);
  signal src_port_mask               : std_logic_vector(c_rtu_max_ports-1 downto 0);  --helper   
  signal fast_and_full_mask          : std_logic_vector(c_rtu_max_ports-1 downto 0);  --helper   
  signal mirror_port_dst             : std_logic;
  signal mirror_port_src_rx          : std_logic;
  signal mirror_port_src_tx          : std_logic;
  signal match_required              : std_logic;
  signal port_nofw_only              : std_logic;
  signal full_match_in               : t_match_response;
  signal fast_match                  : t_match_response;
  signal full_match                  : t_match_response;  
  signal fast_match_wr_req           : std_logic;
  signal full_match_wr_req           : std_logic;
  signal none_match_wr_req           : std_logic;
  signal full_match_valid            : std_logic;
  signal fast_match_rd_valid         : std_logic;
  signal rq_prio                     : std_logic_vector(2 downto 0); 
  signal rq_has_prio                 : std_logic;
  signal rtu_req_d                   : t_rtu_request;
  signal full_match_wr_req_d         : std_logic;
  signal fast_match_wr_req_d         : std_logic;
  signal delayed_full_match_wr_req   : std_logic;
  signal rq_rsp_cnt                  : unsigned(integer(CEIL(LOG2(real(g_match_req_fifo_size ))))-1 downto 0);
  signal rsp                         : t_rtu_response;
  signal rtu_idle                    : std_logic;
  signal forwarding_mask             : std_logic_vector(c_rtu_max_ports-1 downto 0);  --helper 
  signal forwarding_mask_CPU_filtered: std_logic_vector(c_rtu_max_ports-1 downto 0);  --helper 
  signal forwarding_and_mirror_mask  : std_logic_vector(c_rtu_max_ports-1 downto 0);  --helper 
  signal forwarding_without_mr_dst_mask : std_logic_vector(c_rtu_max_ports-1 downto 0);  --helper 
  signal drop                        : std_logic;
  signal prio                        : std_logic_vector(2 downto 0); 
  signal hp                          : std_logic;
  signal nf                          : std_logic;
  signal port_state                  : t_rtu_port_rq_states;
  signal full_match_rsp_port         : std_logic_vector(g_num_ports-1 downto 0);
  signal full_match_rsp_prio         : std_logic_vector(c_wrsw_prio_width-1 downto 0);
  signal full_match_req_in_progress  : std_logic;
  signal full_match_aboard           : std_logic;
  signal full_match_aboard_d         : std_logic;
  signal aboard_possible      : std_logic;
  -- VHDL -- lovn' it
  signal zeros                       : std_logic_vector(47 downto 0);
  
  constant c_match_zero: t_match_response := (
    valid     => '0',
    port_mask => (others =>'0'),
    prio      => (others =>'0'),
    drop      => '0',
    nf        => '0',
    ff        => '0',
    hp        => '0');

  constant c_rtu_rsp_zero : t_rtu_response := (
    valid     => '0',
    port_mask => (others =>'0'),
    prio      => (others =>'0'),
    drop      => '0',
    hp        => '0');

  constant c_rtu_rsp_drop : t_rtu_response := (
    valid     => '1',
    port_mask => (others =>'0'),
    prio      => (others =>'0'),
    drop      => '1',
    hp        => '0');


begin

  zeros              <= (others => '0');

  
--   port_pcr_pass_bpdu <= rtu_pcr_pass_bpdu_i(g_port_index);
--   port_pcr_pass_all  <= rtu_pcr_pass_all_i(g_port_index);

  port_pcr_pass_bpdu <= rtu_pcr_pass_bpdu_i;
  port_pcr_pass_all  <= rtu_pcr_pass_all_i;

  -- create request fifo input data (registered data)
  rq_fifo_d        <=
    rtu_req_d.has_vid  &
    rtu_req_d.prio     &  -- modified by per-port config
    rtu_req_d.has_prio &  -- modified by per-port config
    rtu_req_d.vid      &
    rtu_req_d.dmac     &
    rtu_req_d.smac;

  -- turn port number into bit vector
  src_port_mask       <= f_set_bit(zeros(c_rtu_max_ports-1 downto 0),'1',g_port_index);

  -- check whether this port is a port which mirrors other port(s). In such case any incoming
  -- traffic is not allowed and forwarded is only mirror traffic     
  mirror_port_dst     <= '0' when (rtu_str_config_i.mr_ena = '0') else  -- disabled
                         '1' when ((src_port_mask and rtu_str_config_i.mirror_port_dst) /= 
                                      zeros(c_rtu_max_ports-1 downto 0)) else
                         '0';

  -- ingress traffic to this port (rx) is forwarded to mirror port if such port exists 
  mirror_port_src_rx  <= '0' when (rtu_str_config_i.mr_ena = '0') else  -- disabled
                         '1' when ((src_port_mask and rtu_str_config_i.mirror_port_src_rx) /=
                                     zeros(c_rtu_max_ports-1 downto 0)  ) else
                         '0';

  -- traffic from this port is forwarded (tx) to the port being mirrord , so we forward it
  -- also to mirror port (mirror_port_dst)
  -- REMARK: if we have broadcast, the forwarding decision will show that we want to transmit
  --         (tx) frame to the reception port... we don't mirror this traffic, this is why we 
  --         apply below the f_set_bit() mask 
  mirror_port_src_tx  <= '0' when (rtu_str_config_i.mr_ena = '0') else  -- disabled
                         '1' when ((f_set_bit(forwarding_mask,'0',g_port_index) and --no to myself
                                    rtu_str_config_i.mirror_port_src_tx) /=
                                     zeros(c_rtu_max_ports-1 downto 0)  ) else
                         '0';
  
  -- port enabled for all traffic (forward-able and link-limited)
  match_required      <= '0' when (rtu_gcr_g_ena_i     = '0' or     -- drop ingress traffic if RTU disabled
                                   mirror_port_dst     = '1')  else -- drop ingress traffic if this is mirror port
                         '1';

  -- port enabled only for link-limited traffic
--   port_nofw_only      <= '1' when (rtu_gcr_g_ena_i    = '1' and 
--                                    port_pcr_pass_all  = '0' and
--                                    port_pcr_pass_bpdu = '1' and 
--                                    mirror_port_dst    = '0')    else
--                          '0' ;

  -- unpack data from match engine into nice record
  f_unpack5(full_match_rd_data_i, 
           full_match_in.nf,
           full_match_in.port_mask, 
           full_match_in.drop,  
           full_match_rsp_prio,
           full_match_rsp_port);

  -- some bit optimization :)
  full_match_in.prio(c_wrsw_prio_width-1 downto 0)  <= full_match_rsp_prio;
  
  -- valid Match Engine response for this port
  full_match_in.valid                               <= full_match_rd_valid_i and 
                                                       full_match_rsp_port(g_port_index);
  full_match_in.ff   <= '0';  -- full mutch does not provide this info (reserved for fast match)
  full_match_in.hp   <= '0';  -- full mutch does not provide this info (reserved for fast match)
  
  -- requrest fast match (almost always)
  fast_match_wr_req <= match_required and rtu_rq_i.valid;
  
  -- request full match (only if:
  full_match_wr_req <= '1' when (fast_match_wr_req    = '1' and        -- fast match is required and
                                 full_match_wr_full_i = '0' and        -- full mtach is not stuck
                                 rq_rsp_cnt           =  0)       else -- we don't process already full mach for this port
                       '1' when (full_match_wr_req_d  = '1')      else -- registered request
                       '1' when (delayed_full_match_wr_req = '1') else -- full match was busy at the beginning, we requrestd when it freed (later the usual)
                       '0';

  -- the request is on disabled RTU /mirrored port so we don't bother with any match (full/fast)
  none_match_wr_req  <= (not match_required) and rtu_rq_i.valid;
  
  full_match_valid   <= '1' when (full_match_in.valid   = '1' and -- full mach resp valid
                                  rq_rsp_cnt            =  1  and 
                                  full_match_req_in_progress = '1') else-- it is the right resp
                        '0';
  
  -- filter out responses for other ports
  fast_match_rd_valid<= fast_match_rd_valid_i and fast_match_rd_data_i.valid;

  -- aboard signal (internal/external) shall take effect only in FULL_MATCH state, in other states:
  -- * IDLE/FINAL_MASK/RESPONSE - useless, we have nothing to aboard (in FINAL_MASK it can be 
  --                              disallowed when waiting for SWcore to ack response)
  -- * FAST_MATCH/FINAL_MASK (waiting for SWcore ack) - impossible
  aboard_possible  <= '1' when (port_state = S_FULL_MATCH) else '0';
  
  -- request to aboard full match
  full_match_aboard       <= (not full_match_valid) and    -- suppress when we have replay from full match
                            ((aboard_possible and fast_match_wr_req) or -- new request when full match busy
                             (rtu_rq_aboard_i)); -- other externa, e.g. from swcore, **not implemented yet
  --------------------------------------------------------------------------------------------
  -- register input request to make it available for both matches (full/fast)
  --------------------------------------------------------------------------------------------
  -- this gets registered for furthe processing (full/fast match)
--   rq_prio            <= f_pick(rtu_pcr_fix_prio_i = '0', rtu_req_d.prio, rtu_pcr_prio_val_i);
--   rq_has_prio        <= (rtu_pcr_fix_prio_i or rtu_req_d.has_prio);
  rq_prio            <= f_pick(rtu_pcr_fix_prio_i = '0', rtu_rq_i.prio, rtu_pcr_prio_val_i);
  rq_has_prio        <= (rtu_pcr_fix_prio_i or rtu_rq_i.has_prio);
  
--   -- NOTE: inside {fast,full}_match we also take into account the priority assigned to VLAN,
--   --       this value is not taken into account in TRU !!
--   tru_o.pass_all          <= rtu_pcr_pass_all_i and rtu_gcr_g_ena_i;
--   tru_o.forward_bpdu_only <= rtu_pcr_pass_bpdu_i;
--   tru_o.request_valid     <= rtu_rq_i.valid;
--   tru_o.priorities        <= rq_prio when (rq_has_prio = '1') else (others =>'0');
  
  p_register_req: process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        rtu_req_d.valid     <= '0';
        rtu_req_d.smac      <= (others =>'0');
        rtu_req_d.dmac      <= (others =>'0');
        rtu_req_d.vid       <= (others =>'0');
        rtu_req_d.has_vid   <= '0';
        rtu_req_d.prio      <= (others =>'0');
        rtu_req_d.has_prio  <= '0';
      else    
        if(fast_match_wr_req = '1') then
          rtu_req_d.valid     <= rtu_rq_i.valid;
          rtu_req_d.smac      <= rtu_rq_i.smac;
          rtu_req_d.dmac      <= rtu_rq_i.dmac;
          rtu_req_d.vid       <= rtu_rq_i.vid;
          rtu_req_d.has_vid   <= rtu_rq_i.has_vid;
          rtu_req_d.prio      <= rq_prio;
          rtu_req_d.has_prio  <= rq_has_prio;
        end if;
      end if;
    end if;
  end process p_register_req;
  
  --------------------------------------------------------------------------------------------
  -- The request to Fast Match is done directly from input rtu_req, her we just track
  -- current request (register req signal till response available)
  --------------------------------------------------------------------------------------------
  p_ctr_fast_match: process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
          fast_match_wr_req_d <= '0';
          fast_match                <= c_match_zero;
      else    
        if(fast_match_wr_req = '1') then
          fast_match_wr_req_d <= '1';
        elsif(fast_match_wr_req_d = '1' and fast_match_rd_valid = '1') then
          fast_match_wr_req_d <= '0';
          fast_match          <= fast_match_rd_data_i;
        end if;
        
        
        
      end if;
    end if;
  end process p_ctr_fast_match;

  --------------------------------------------------------------------------------------------
  -- Controlling full match, more tricky ...
  -- * we need  to have wr_req_o high till request is accepted (wr_done)
  -- * tracking (registering) aboard signal
  -- * tracking if the current full match is processed (or some old one)
  -- * registering valid full_match response
  --------------------------------------------------------------------------------------------
  p_ctr_full_match: process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        full_match_wr_req_d    <= '0';
        full_match_req_in_progress <= '0';
        full_match             <= c_match_zero;
        full_match_aboard_d    <= '0';
      else    
        if(full_match_aboard = '1') then
          full_match_aboard_d    <= '1';
        elsif(rsp.valid = '1' and rtu_rsp_ack_i ='1') then
          full_match_aboard_d    <= '0';
        end if;
        
        -- request access to fifo
        if(full_match_wr_req ='1' and full_match_wr_req_d = '0') then
          full_match_wr_req_d  <= '1';   
        elsif(full_match_wr_req_d = '1' and full_match_wr_done_i = '1') then 
          full_match_wr_req_d  <= '0';  
        end if;

        -- register response
        if(full_match_wr_req ='1' and full_match_wr_req_d = '0') then
          full_match_req_in_progress <= '1';
          full_match                 <= c_match_zero;
        elsif(full_match_valid = '1' ) then 
          full_match_req_in_progress <= '0';
          full_match                 <= full_match_in;
        elsif(port_state = S_FINAL_MASK) then 
          full_match_req_in_progress <= '0';
        end if;
      end if;
    end if;
  end process p_ctr_full_match;

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
        if(full_match_wr_req = '1' and full_match_wr_req_d ='0' and full_match_in.valid = '0') then
          rq_rsp_cnt <= rq_rsp_cnt + 1;
        elsif(full_match_in.valid = '1' ) then
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
        port_state                <= S_IDLE;
        rsp                       <= c_rtu_rsp_zero;
        delayed_full_match_wr_req <= '0';
        ------------------------------------------------------------------------------------------------------------     
      else
        -- FSM
        case port_state is        
          ------------------------------------------------------------------------------------------------------------ 
          --| IDLE: waiting for the request from a port
          ------------------------------------------------------------------------------------------------------------ 
          when S_IDLE =>
            
            if(fast_match_wr_req = '1') then
              port_state          <= S_FAST_MATCH;
            elsif(none_match_wr_req = '1') then
              rsp                 <= c_rtu_rsp_drop;
              port_state          <= S_RESPONSE;
            end if;

          ------------------------------------------------------------------------------------------------------------ 
          --| 
          ------------------------------------------------------------------------------------------------------------             
          when S_FAST_MATCH =>
            
            if(fast_match_rd_valid = '1' and fast_match_wr_req_d = '1') then
              -- response the current fast_match request, registered
             -- fast_match            <= fast_match_rd_data_i;
              if(fast_match_rd_data_i.nf   = '1'   or     -- non-forward (link-limited) e.g.: BPDU
                 fast_match_rd_data_i.ff   = '1'   or     -- fast forward recongized
                 fast_match_rd_data_i.drop = '1'   or     -- no point in further work (drop due to VLAN)
                 full_match_aboard         = '1')  then   -- aboard because next frame received
                -- if we recognizd special traffic or aboard request , we don't need full match
                port_state          <= S_FINAL_MASK;
              else
                -- go for full match (can be abanoned any time)
                port_state          <= S_FULL_MATCH;
                if(full_match_req_in_progress = '0' and full_match_wr_full_i = '0' and rq_rsp_cnt =  0) then 
                  -- if full_match was not requested at the very beginning (directly from input requests)
                  -- it means that at that time old full_request was handled, check whether we can do 
                  -- full request now, if yes, go for it
                  delayed_full_match_wr_req <= '1';
                end if;
              end if;
            elsif(rtu_rq_aboard_i = '1' and fast_match.valid = '0') then
              -- TODO: this should not happen -> handle exeption  
              port_state     <= S_FINAL_MASK;
              rsp            <= c_rtu_rsp_drop;
              delayed_full_match_wr_req <= '0';
            end if;

          ------------------------------------------------------------------------------------------------------------ 
          --| Full match :
          --| * if not requested yet, wait for it to be possible to request
          --| * wait for answer from Full match engine
          --| * be ready to aboard at any moment
          ------------------------------------------------------------------------------------------------------------          
          when S_FULL_MATCH =>
          
            if(full_match_aboard = '0'  and full_match_req_in_progress = '0' and full_match_wr_full_i = '0' and rq_rsp_cnt =  0) then 
              -- request full match access
              delayed_full_match_wr_req <= '1';
            else
              delayed_full_match_wr_req <= '0';
            end if;            

            if(full_match_valid = '1') then -- 
              -- full match done (input data registered in separate process)
              port_state          <= S_FINAL_MASK; 
            elsif(full_match_aboard = '1' and fast_match.valid = '1') then
              -- aboard waiting for full match
              port_state          <= S_FINAL_MASK;
            elsif(full_match_aboard = '1' and fast_match.valid = '0') then
               -- TODO: this should not happen -> handle exeption
               port_state         <= S_FAST_MATCH;               
            end if;
             
          ------------------------------------------------------------------------------------------------------------ 
          --| prepare final mask based on :
          --| * fast 
          --| * (if available) full match
          --| * (some config settings)
          ------------------------------------------------------------------------------------------------------------             
          when S_FINAL_MASK =>
            
            if(rsp.valid   = '0') then
              rsp.valid             <= '1';
              rsp.prio              <= prio;
              rsp.hp                <= hp;   
              
              if(mirror_port_src_rx = '1' or mirror_port_src_tx = '1') then
                -- if mirroring is enabled, and this port is source of mirror traffic, we don't drop
                -- the traffic, 
                if(drop = '1' and mirror_port_src_rx = '1') then
                  -- forward only to the mirror (dst) port
                  -- (eliminate self-forward)
                  rsp.port_mask     <= f_set_bit(rtu_str_config_i.mirror_port_dst,'0',g_port_index) ;
                  rsp.drop          <= '0';
                else
                  -- forward to "normal forwarding ports" + mirror (dst) port
                  -- (eliminate self-forward)
                  rsp.drop          <= drop;
                  if(drop = '1') then
                    rsp.port_mask    <= (others=> '0');
                  else
                   rsp.port_mask     <= f_set_bit(forwarding_and_mirror_mask,'0',g_port_index); 
                  end if;                    
                end if;
                
              else
                -- normal forwarding
                -- (eliminate self-forward)
                
                if(f_set_bit(forwarding_without_mr_dst_mask,'0',g_port_index) = zeros(c_RTU_MAX_PORTS-1 downto 0)) then
                   rsp.drop         <= '1';
                   rsp.port_mask    <= (others=> '0');
                else
                  rsp.drop          <= drop;
                  if(drop = '1') then
                    rsp.port_mask    <= (others=> '0');
                  else
                    rsp.port_mask       <= f_set_bit(forwarding_without_mr_dst_mask,'0',g_port_index) ;
                  end if;              
                end if;
              end if;
            
              port_state          <= S_RESPONSE;
             end if;
          ------------------------------------------------------------------------------------------------------------ 
          --| in this state the answer is made available on the output (rtu_rsp_o). it is available until
          --| the reception is acked by SWcore. However, new request from Endpoint can be handled in this time.
          --| So, S_RESPONSE state is single-cyccle onliy
          ------------------------------------------------------------------------------------------------------------             
          when S_RESPONSE =>
              
            if(full_match_aboard_d = '1' and match_required ='1') then
              -- if we are in this state because we received abanddon request  and match is 
              -- required (RTU enabled/no mirroring), we go straight to FAST_MATCH
              port_state      <= S_FAST_MATCH;
            elsif(full_match_aboard_d = '1' and match_required ='0') then
              -- aboard, but no match required, so drop
              rsp             <= c_rtu_rsp_drop;
              port_state      <= S_RESPONSE;
            else
              -- go and wait for new requests
              port_state      <= S_IDLE;
            end if;
          ------------------------------------------------------------------------------------------------------------ 
          --| OTHER: 
          ------------------------------------------------------------------------------------------------------------                       
          when others => 
              port_state     <= S_IDLE;
              rsp            <= c_rtu_rsp_zero;
              delayed_full_match_wr_req <= '0';         
        ------------------------------------------------------------------------------------------------------------
        end case;
          if(rtu_rsp_ack_i = '1' and rsp.valid ='1') then            
            rsp.valid         <= '0';
            rsp.port_mask     <= (others =>'0');
            rsp.prio          <= (others =>'0');
            rsp.drop          <= '0';
            rsp.hp            <= '0';
          end if;        
        
      end if;
    end if;
  end process port_fsm_state;

  -- we concatenate separately Switch's ports (g_num_ports-1 downto 0) and the rest (NIC) so that
  -- frames go to NIC based on any of the decisions (fast or full match)
  fast_and_full_mask  <= (fast_match.port_mask(c_RTU_MAX_PORTS-1 downto g_num_ports) or full_match.port_mask(c_RTU_MAX_PORTS-1 downto g_num_ports)) &
                         (fast_match.port_mask(g_num_ports-1 downto 0)              and full_match.port_mask(g_num_ports-1 downto  0));

  -- TODO: HACK: FUCK
  -- stupid temporary hack, the problem is that FAST MATCH does not read (for some reason) masks of VIDs different then 0...
  -- this is only for the latency tests, later needs to be changee
--   fast_and_full_mask  <= full_match.port_mask;

  -- the above solution migh not be the best - eventually, we don't really want so much traffic 
  -- to go to NIC...(this is mainly to prevent the "unrecognized" traffic to be forwarded to NIC)
  -- fast_and_full_mask  <= fast_match.port_mask and full_match.port_mask;

  -- forming final mask: 
  --                  1) full match available, full match says that we have non-forward traffic<
  --                     to such traffic we don't apply fast_match (TRU and stuff)
  forwarding_mask     <= full_match.port_mask when (full_match.valid = '1' and full_match.nf ='1') else
  --                  2) full match available and it's normal traffic, so we apply both asks
                         fast_and_full_mask when (full_match.valid = '1') else
  --                  3) we received aboard request and the setting indicates to drop ingressf rame in such case
                         c_rtu_rsp_drop.port_mask  when (full_match_aboard_d = '1' and rtu_str_config_i.dop_on_fmatch_full = '0' ) else
  --                  4) fast match decision only 
                         fast_match.port_mask;

  -- forming final drop:
  --                  1) drop from one of two matches, don't drop if we have non-forward traffic
  drop                <= (full_match.drop or fast_match.drop) and (not full_match.nf) when (full_match.valid    = '1') else
  --                  2) when aboarding and set to drop, 
                         '1'           when (full_match_aboard_d = '1' and rtu_str_config_i.dop_on_fmatch_full = '0' ) else
  --                  3) if only fast match available, is it
                         fast_match.drop;
  -- forming final prio:
  --                  1) when full match available, use it
  prio                <= full_match.prio when (full_match.valid = '1') else
  --                  2) if aboard and set to drop, set it to zero
                         c_rtu_rsp_drop.prio when (full_match_aboard_d = '1' and rtu_str_config_i.dop_on_fmatch_full = '0' ) else
                         fast_match.prio;
  -- forming final hp: decided by fast match, only 
  hp                  <= fast_match.hp;
  
  nf                  <= fast_match.nf;

  -- to make sure that HP traffic is not disturbed due to the fact that it's fowarded to slow NIC... just not 
  -- foward it there... (NIC should have it's own mechanism to prevent such situation, but precautions are not bad).
  -- In case that some diagnostics is required, we can enable forwarding of HP traffic to NIC.
  forwarding_mask_CPU_filtered   <= forwarding_mask or rtu_str_config_i.cpu_forward_mask 
                                                    when (rtu_str_config_i.hp_fw_cpu_ena = '1' and hp = '1') else
                                    forwarding_mask when                                          (hp = '0') else
                                    forwarding_mask when                                          (nf = '1') else
                                    forwarding_mask and (not rtu_str_config_i.cpu_forward_mask);-- this is HP, not link-limited (nf) and
                                                                                                -- forwarding of HP to NIC is disabled
--                                     f_set_bit(forwarding_mask,'0',g_num_ports) ;  -- this is HP, not link-limited (nf) and
--                                                                                   -- forwarding of HP to NIC is disabled

  -- forwarding mask without mirror destination port
  -- it prevents sending traffic to mirror port from ports which are not mirrored (e.g.: when 
  -- we handle braodcast). If mirroring is disabled but the mask is set, we don't apply the
  -- filtering.
  forwarding_without_mr_dst_mask <=forwarding_mask_CPU_filtered when (rtu_str_config_i.mr_ena = '0') else 
                                   forwarding_mask_CPU_filtered and (not rtu_str_config_i.mirror_port_dst);

  -- adding mirror port (dst) port to the mask
  forwarding_and_mirror_mask <= forwarding_mask_CPU_filtered or rtu_str_config_i.mirror_port_dst;

  -- decideing whe RTU can accept new request (if RTU port is not idle, and Endpoint has new 
  -- requests, it ignores incoming frame)
  rtu_idle <= '0' when (port_state = S_FAST_MATCH) else
              '0' when (port_state = S_FINAL_MASK and rsp.valid = '1') else 
              '0' when (port_state = S_FULL_MATCH and full_match_aboard_d = '1') else
              '1';
   
  rtu_idle_o          <= rtu_idle;
  rtu_rsp_o           <= rsp;
  full_match_wr_req_o <= full_match_wr_req and not full_match_wr_done_i;
  full_match_wr_data_o<= rq_fifo_d;
  fast_match_wr_req_o <= fast_match_wr_req;
  fast_match_wr_data_o<= rtu_req_d;   

end architecture;  --wrsw_rtu_port
