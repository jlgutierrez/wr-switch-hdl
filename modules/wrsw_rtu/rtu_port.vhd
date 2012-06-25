-------------------------------------------------------------------------------
-- Title      : Routing Table Unit's Port Representation (RTU_PORT)
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_rtu_port.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-05-08
-- Last update: 2012-06-25
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
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2010-05-08  1.0      lipinskimm      Created
-- 2010-05-29  1.1      lipinskimm     modified FSM, added rtu_gcr_g_ena_i
-- 2010-12-05  1.2      twlostow        added independent output FIFOs
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.genram_pkg.all;
use work.wrsw_shared_types_pkg.all;
use work.pack_unpack_pkg.all;
use work.rtu_private_pkg.all;

entity rtu_port is
  generic(
    g_num_ports  : integer;
    g_port_index : integer);
  port(

    -- clock (62.5 MHz refclk/2)
    clk_i           : in std_logic;
    -- reset (synchronous, active low)
    rst_n_i         : in std_logic;
    -- RTU Global Enable : Global RTU enable bit. Overrides all port settings. 
    --   0: RTU is disabled. All packets are dropped.
    ---  1: RTU is enabled.
    rtu_gcr_g_ena_i : in std_logic;
    -------------------------------------------------------------------------------
    -- N-port RTU input interface (from the endpoint)
    -------------------------------------------------------------------------------

    -- 1 indicates that coresponding RTU port is idle and ready to accept requests
    rtu_idle_o : out std_logic;

    -- request strobe, single HI pulse begins evaluation of the request. All
    -- request input lines have to be valid when rq_strobe_p_i is asserted.
    rq_strobe_p_i : in std_logic;

    -- source and destination MAC addresses extracted from the packet header
    rq_smac_i : in std_logic_vector(c_wrsw_mac_addr_width - 1 downto 0);
    rq_dmac_i : in std_logic_vector(c_wrsw_mac_addr_width - 1 downto 0);

    -- VLAN id (extracted from the header for TRUNK ports and assigned by the port
    -- for ACCESS ports)
    rq_vid_i : in std_logic_vector(c_wrsw_vid_width - 1 downto 0);

    -- HI means that packet has valid assigned a valid VID (low - packet is untagged)
    rq_has_vid_i : in std_logic;

    -- packet priority (either extracted from the header or assigned per port).
    rq_prio_i     : in std_logic_vector(c_wrsw_prio_width -1 downto 0);
    -- HI indicates that packet has assigned priority.
    rq_has_prio_i : in std_logic;

    -------------------------------------------------------------------------------
    -- N-port RTU output interface (to the packet buffer
    -------------------------------------------------------------------------------

    -- response strobe. Single HI pulse indicates that a valid response for port N
    -- request is available on rsp_dst_port_mask_o, rsp_drop_o and rsp_prio_o.
    rsp_valid_o : out std_logic;

    -- destination port mask. HI bits indicate that packet should be routed to
    -- the corresponding port(s).
    rsp_dst_port_mask_o : out std_logic_vector(c_rtu_max_ports - 1 downto 0);

    -- HI -> packet must be dropped
    rsp_drop_o : out std_logic;

    -- Final packet priority (evaluated from port priority, tag priority, VLAN
    -- priority or source/destination priority).
    rsp_prio_o : out std_logic_vector (c_wrsw_prio_width-1 downto 0);

    -- acknowledge response reception
    rsp_ack_i : in std_logic;

    -------------------------------------------------------------------------------
    -- request FIFO interfacing
    -------------------------------------------------------------------------------

    rq_fifo_write_o : out std_logic;
    rq_fifo_full_i  : in  std_logic;
    rq_fifo_data_o  : out std_logic_vector(c_PACKED_REQUEST_WIDTH - 1 downto 0);

    -------------------------------------------------------------------------------
    -- response FIFO interfacing
    -------------------------------------------------------------------------------

    rsp_write_i      : in std_logic;
    rsp_match_data_i : in std_logic_vector(g_num_ports + c_PACKED_RESPONSE_WIDTH - 1 downto 0);

    -------------------------------------------------------------------------------
    -- interface RoundRobin arbiter
    -------------------------------------------------------------------------------
    -- request access
    rr_request_wr_access_o : out std_logic;

    -- access granted
    rr_access_ena_i : in std_logic;

    -------------------------------------------------------------------------------
    -- REQUEST COUNTER 
    -------------------------------------------------------------------------------

    port_almost_full_o : out std_logic;
    port_full_o        : out std_logic;

    rq_rsp_cnt_dec_i : in std_logic;

    -------------------------------------------------------------------------------
    -- control register
    -------------------------------------------------------------------------------   
    rtu_pcr_pass_bpdu_i : in std_logic;
    rtu_pcr_pass_all_i  : in std_logic;
    rtu_pcr_fix_prio_i  : in std_logic;
    rtu_pcr_prio_val_i  : in std_logic_vector(c_wrsw_prio_width - 1 downto 0)
    );

end rtu_port;

architecture behavioral of rtu_port is

--- RTU FSM state definitions
  type t_rtu_port_rq_states is (RQS_IDLE, RQS_REQ_WRITE, RQS_WRITE_FIFO);
  type t_rtu_port_rsp_states is (RSPS_IDLE, RSPS_RESPONSE, RSPS_WAIT_ACK);


  constant c_port_full_threshold       : integer := 30;
  constant c_port_almostfull_threshold : integer := 20;

  signal rqf_state  : t_rtu_port_rq_states;
  signal rspf_state : t_rtu_port_rsp_states;

  signal rq_fifo_d_reg, rq_fifo_d : std_logic_vector(c_PACKED_REQUEST_WIDTH - 1 downto 0);

  signal rq_fifo_write        : std_logic;
  signal rr_request_wr_access : std_logic;
  signal rtu_idle             : std_logic;

  signal ififo_clear : std_logic;
  signal ififo_write : std_logic;
  signal ififo_read  : std_logic;
  signal ififo_empty : std_logic;

  signal ififo_d, ififo_q : std_logic_vector(c_PACKED_RESPONSE_WIDTH-1 downto 0);

  signal rsp_requesting_port   : std_logic_vector(g_num_ports-1 downto 0);
  signal rsp_dst_port_mask_int : std_logic_vector(c_rtu_max_ports-1 downto 0);

  signal count_inc, count_dec : std_logic;
  signal req_count            : unsigned(5 downto 0);

  function f_pick (
    condition : boolean;
    w_true: std_logic_vector;
    w_false: std_logic_vector) return std_logic_vector is

  begin
    if(condition) then
      return w_true;
      else
        return w_false;
      end if;
  end function;
  
begin


  -- create request fifo input data
  rq_fifo_d <=
    rq_has_vid_i
    & f_pick(rtu_pcr_fix_prio_i = '0', rq_prio_i, rtu_pcr_prio_val_i)
    & (rtu_pcr_fix_prio_i or rq_has_prio_i)
    & rq_vid_i
    & rq_dmac_i
    & rq_smac_i;

  rq_fifo_data_o <= rq_fifo_d_reg;

  -------------------------------------------------------------------------------------
  -- Begining of PORT REQUEST MATCH FSM
  -- (state transitions)       
  -------------------------------------------------------------------------------------

  port_rq_fsm_state : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --------------- 
        -- RESET
        ---------------     

        -- request    
        rq_fifo_d_reg <= (others => '0');

        -- FSM state
        rqf_state <= RQS_IDLE;

        rq_fifo_write        <= '0';
        rr_request_wr_access <= '0';
        rtu_idle             <= '1';    -- indecate idle state of the port
        count_inc            <= '0';
        
      else
        -- FSM
        case rqf_state is
          ---------------------------------------------------- 
          -- IDLE: waiting for the request from a port
          ---------------------------------------------------- 
          when RQS_IDLE =>
            
            rtu_idle <= '1';
            -- there is request
            if (rq_strobe_p_i = '1') then
              
              rqf_state     <= RQS_REQ_WRITE;
              -- remember input data 
              rq_fifo_d_reg <= rq_fifo_d;


              rr_request_wr_access <= '1';
              rtu_idle             <= '0';
              

            end if;

            ------------------------------------------------------------------------------ 
            -- REQUEST WRITE: request write access to request FIFO (RoundRobin arbiter)
            ------------------------------------------------------------------------------ 
          when RQS_REQ_WRITE =>
            
            if(rr_access_ena_i = '1' and rq_fifo_full_i = '0') then  -- access to FIFO granted by arbiter
              rqf_state <= RQS_WRITE_FIFO;

              rq_fifo_write        <= '1';
              rr_request_wr_access <= '1';
              rtu_idle             <= '0';
              count_inc            <= '1';
            end if;


            ------------------------------------------------------ 
            -- WRITE FIFO: write request data to request FIFO
            ------------------------------------------------------             
          when RQS_WRITE_FIFO =>
            
            rqf_state <= RQS_IDLE;

            rq_fifo_write        <= '0';
            rr_request_wr_access <= '0';
            rtu_idle             <= '1';
            count_inc            <= '0';

        end case;
      end if;
    end if;
  end process port_rq_fsm_state;

  rq_fifo_write_o        <= rq_fifo_write;
  rr_request_wr_access_o <= rr_request_wr_access;
  rtu_idle_o             <= rtu_idle;

  -------------------------------------------------------------------------------------------------------------------------
  --| Begining of PORT RESPONSE MATCH FSM
  --| (state transitions)       
  ----------------------------------------------------------------------------------------------
---------------------------

  rsp_requesting_port <= rsp_match_data_i(g_num_ports-1 downto 0);

  ififo_clear <= not rst_n_i;
  ififo_write <= rsp_requesting_port(g_port_index) and rsp_write_i;
  ififo_d     <= rsp_match_data_i(c_PACKED_RESPONSE_WIDTH + g_num_ports - 1 downto g_num_ports);


  -- fixme: consider shiftreg fifos
  U_RESPONSE_FIFO : generic_sync_fifo
    generic map (
      g_data_width => c_PACKED_RESPONSE_WIDTH,
      g_size       => 32)
    port map (
      clk_i   => clk_i,
      rst_n_i => rst_n_i,
      we_i    => ififo_write,
      d_i     => ififo_d,
      rd_i    => ififo_read,
      q_o     => ififo_q,
      empty_o => ififo_empty,
      full_o  => open,
      count_o => open);

  ififo_read <= '1' when (rspf_state = RSPS_IDLE) and ififo_empty = '0' else '0';

  f_unpack3(ififo_q, rsp_dst_port_mask_int, rsp_drop_o, rsp_prio_o);

  p_mask_loopback : process(rsp_dst_port_mask_int)
    variable tmp : std_logic_vector(c_rtu_max_ports-1 downto 0);
  begin
    tmp                 := rsp_dst_port_mask_int;
    tmp(g_port_index)   := '0';
    rsp_dst_port_mask_o <= tmp;
  end process;

  p_response_output : process (clk_i)
  begin
    if rising_edge(clk_i) then

      if rst_n_i = '0' then
        rsp_valid_o <= '0';
        rspf_state  <= RSPS_IDLE;
        count_dec   <= '0';
      else
        case rspf_state is
          when RSPS_IDLE =>
            count_dec <= '0';
            if(ififo_empty = '0') then
              rsp_valid_o <= '1';
              rspf_state  <= RSPS_WAIT_ACK;
            end if;
          when RSPS_WAIT_ACK =>
            if(rsp_ack_i = '1') then
              rsp_valid_o <= '0';
              count_dec   <= '1';
              rspf_state  <= RSPS_IDLE;
            end if;
          when others => null;
        end case;
      end if;
    end if;
  end process;

  p_request_counter : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        req_count          <= (others => '0');
        port_almost_full_o <= '0';
        port_full_o        <= '0';
      else


        -- almost full check  
        if(unsigned(req_count) >= c_port_almostfull_threshold) then
          port_almost_full_o <= '1';
        else
          port_almost_full_o <= '0';
        end if;

        -- full check
        if(unsigned(req_count) >= c_port_full_threshold) then
          port_full_o <= '1';
        else
          port_full_o <= '0';
        end if;

        if(count_inc = '1' and count_dec = '0') then
          req_count <= req_count + 1;
        elsif(count_inc = '0' and count_dec = '1') then
          req_count <= req_count - 1;
        end if;
      end if;
    end if;
  end process p_request_counter;
  

  
  
end architecture;  --wrsw_rtu_port
