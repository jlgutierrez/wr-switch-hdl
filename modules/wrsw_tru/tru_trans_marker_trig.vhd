-------------------------------------------------------------------------------
-- Title      : Topology Resolution Unit: marker triggered transition
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : tru_trans_marker_trig.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-09-05
-- Last update: 2012-09-13
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: This module implements transition (switching) between redundant
-- links. The transition is triggered by special Ethernet Frames (markers)
-- sent over WR Network by root switch
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- We assume that:
-- * we switch from port A which is now forwarding (active) to port B which is now blocking 
-- * port A provides "slower" path to our switch
-- * port B provides "faster" path to our switch
-- * the time difference between the A-provided "slower" path and B-provided "faster" path
--   is known (figured out by S/W) and provided to the module
-- * single transition is done at a time 

-- The module uses:
-- * HW-based detection of frames (e.g. by Endpoint)
-- * pause mechanism in Endpoint
-- * information (time diff, from which to which port to switch) provided by S/W
-- 
-- Module needs to be enabled to start working. once it performs the switch-over, it will
-- not attempt to perform another one until it is reseted by configuration
-- 
-- Works more or less like this:
-- 1. wait for marker on port B (on faster path, so receives the marker braodcasted from Root
--    switch faster then port A)
-- 2. on reception of marker on port B do:
--    - send HW-generated (in Endpoint) pause with the set pauseTime=diff provided by S/W
--    - start counting how many messages of the configured priority we receive on this port 
--      (it will take some time for the pause to get to the other side of the link prevent
--       the other switch from sending stuff)
--    -  blocks output queues of both ports (this is not entirely good solution, working
--       on better)
-- 3. wait for marker on port A (on slower path)
-- 4. on reception of marker on port A:
--    - start counting frames received on this port
--    - when the number of frames received on port A is equal the number of frames received on
--      port B, perform transition
-- 5. on transition
--    - swap banks of TRU (we assume that in the new bank a new and proper cnfiguration
--      is available, in this configuration port A is active and port be is backup)
--    - set bit finished
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
use work.wrsw_shared_types_pkg.all;
use work.gencores_pkg.all;          -- for f_rr_arbitrate
use work.wrsw_tru_pkg.all;

entity tru_trans_marker_trig is
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
    ports_req_strobe_i : in std_logic_vector(g_num_ports - 1 downto 0);
    ep_o               : out t_trans2tru_array(g_num_ports - 1 downto 0)
    );
end tru_trans_marker_trig;

architecture rtl of tru_trans_marker_trig is
  type t_tru_trans_state is(S_IDLE,    
                            S_WAIT_PA_MARKER, 
                            S_WAIT_PB_MARKER, 
                            S_WAIT_WITH_TRANS,
                            S_TRANSITIONED);
                             
  signal s_tru_trans_state   : t_tru_trans_state;
  signal s_start_transition  : std_logic;
  signal s_portA_frame_cnt   : unsigned(integer(CEIL(LOG2(real(g_mt_trans_max_fr_cnt-1)))) -1 downto 0);
  signal s_portB_frame_cnt   : unsigned(integer(CEIL(LOG2(real(g_mt_trans_max_fr_cnt-1)))) -1 downto 0);
  signal s_statTransActive   : std_logic;
  signal s_statTransFinished : std_logic;
  signal s_port_A_mask       : std_logic_vector(g_num_ports-1 downto 0);
  signal s_port_B_mask       : std_logic_vector(g_num_ports-1 downto 0);
  signal s_port_A_prio       : std_logic_vector(g_prio_width-1 downto 0);
  signal s_port_B_prio       : std_logic_vector(g_prio_width-1 downto 0);
  signal s_port_A_has_prio   : std_logic;
  signal s_port_B_has_prio   : std_logic;

  signal s_port_A_prio_mask  : std_logic_vector(2**g_prio_width-1 downto 0);
  signal s_port_B_prio_mask  : std_logic_vector(2**g_prio_width-1 downto 0);

  signal s_port_A_rtu_srobe  : std_logic;
  signal s_port_B_rtu_srobe  : std_logic;
  signal s_ep_ctr_A          : t_trans2ep;
  signal s_ep_ctr_B          : t_trans2ep;
  signal s_ep_zero           : t_trans2ep;

begin --rtl
   
   -- to make code less messy - start transition only it is enabled by config and all necessary 
   -- config is valid
   s_start_transition  <= config_i.tcr_trans_ena          and 
                          config_i.tcr_trans_port_a_valid and 
                          config_i.tcr_trans_port_b_valid;

   -- generating mask with 1 at the priority for with we perform transition (configured value)
   G_PRIO_MASK: for i in 0 to 2**g_prio_width-1 generate
      s_port_A_prio_mask(i) <= '1' when(i = to_integer(unsigned(config_i.tcr_trans_prio))) else '0';
      s_port_B_prio_mask(i) <= '1' when(i = to_integer(unsigned(config_i.tcr_trans_prio))) else '0';
   end generate G_PRIO_MASK;
   
   -- generating mask with 1 at the port for with we perform transition
   G_MASK: for i in 0 to g_num_ports-1 generate
      s_port_A_mask(i) <= '1' when (i = to_integer(unsigned(config_i.tcr_trans_port_a_id)) and config_i.tcr_trans_port_a_valid ='1') else '0';
      s_port_B_mask(i) <= '1' when (i = to_integer(unsigned(config_i.tcr_trans_port_b_id)) and config_i.tcr_trans_port_a_valid ='1') else '0';
   end generate G_MASK;
  
  -- to make the code less messy
--   s_port_A_prio       <= rtu_i.priorities(to_integer(unsigned(config_i.tcr_trans_port_a_id)));
--   s_port_B_prio       <= rtu_i.priorities(to_integer(unsigned(config_i.tcr_trans_port_b_id)));

--    s_port_A_prio       <= rtu_i.priorities(to_integer(unsigned(config_i.tcr_trans_port_a_id)));
--    s_port_A_has_prio   <= rtu_i.has_prio(to_integer(unsigned(config_i.tcr_trans_port_a_id)));
--    s_port_B_prio       <= rtu_i.priorities(to_integer(unsigned(config_i.tcr_trans_port_b_id)));
--    s_port_B_has_prio   <= rtu_i.has_prio(to_integer(unsigned(config_i.tcr_trans_port_b_id)));

--   s_port_A_rtu_srobe  <= '1' when ((s_port_A_mask and rtu_i.request_valid(g_num_ports-1 downto 0)) = s_port_A_mask and 
--                                     s_port_A_prio = config_i.tcr_trans_prio and s_port_A_has_prio = '1') else '0';
--   s_port_B_rtu_srobe  <= '1' when ((s_port_B_mask and rtu_i.request_valid(g_num_ports-1 downto 0)) = s_port_B_mask and
--                                     s_port_B_prio = config_i.tcr_trans_prio and s_port_B_has_prio = '1') else '0';
                               
  s_port_A_rtu_srobe  <= ports_req_strobe_i(to_integer(unsigned(config_i.tcr_trans_port_a_id)));
  s_port_B_rtu_srobe  <= ports_req_strobe_i(to_integer(unsigned(config_i.tcr_trans_port_b_id)));


  -- an empty entry
  s_ep_zero.pauseSend          <= '0';
  s_ep_zero.pauseTime          <= (others => '0');
  s_ep_zero.outQueueBlockMask  <= (others => '0');
  
  -- this FSM tries to switch forwarding from port A to port B without loosing frames on a 
  -- defined priority. It waits for marker broadcasted from the topology root. 
  -- We assume here that the new path (through port B) is "faster/shorter/better". If we 
  -- switched between these paths without special attention, we would loose some frames which
  -- were in the "longer/slower" path and has been already dropped by port B (on faster/shorter path)
  -- Once the Marker is received on port B (sooner because it's faster), we send HW-generated
  -- pause on this port (it takes time for it to take effect) and count how many frames we receive
  -- (of specified priority).
  -- We also block output queues on ports A and B (this is for up-traffic nodes->root, but this idea
  -- needs revision)
  -- Once the Marker is received on port A, we start counting received frames (of specified priority)
  -- and as soon as we received the same number as on port B, we request to swap the bank of 
  -- TRU Tab. here we assume that the new configuration is appropraite (port A is not active any 
  -- more, port B is active)
  TRANS_FSM: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
         
        s_tru_trans_state   <= S_IDLE;
        s_portA_frame_cnt   <= (others => '0');
        s_portB_frame_cnt   <= (others => '0');
        s_statTransActive   <= '0';
        s_statTransFinished <= '0';
        tru_tab_bank_o      <= '0';

        s_ep_ctr_A.pauseSend         <= '0';
        s_ep_ctr_A.pauseTime         <= (others => '0');
        s_ep_ctr_A.outQueueBlockMask <= (others => '0');
        
        s_ep_ctr_B.pauseSend         <= '0';
        s_ep_ctr_B.pauseTime         <= (others => '0');
        s_ep_ctr_B.outQueueBlockMask <= (others => '0');

      else
        
        case s_tru_trans_state is
           
          --====================================================================================
          when S_IDLE =>
          --====================================================================================
             s_portA_frame_cnt            <= (others => '0');
             s_portB_frame_cnt            <= (others => '0');
             s_statTransActive            <= '0';              
             s_ep_ctr_A.outQueueBlockMask <= (others => '0');            
             s_ep_ctr_B.outQueueBlockMask <= (others => '0');
            
             -- new transition is not started until the previous has been cleared/finished
             if(s_start_transition = '1' and s_statTransFinished ='0' and s_statTransActive = '0') then --
               s_tru_trans_state   <= S_WAIT_PB_MARKER;
               s_portA_frame_cnt   <= (others => '0');
               s_portB_frame_cnt   <= (others => '0');
               s_statTransActive   <= '1';   -- indicate that transition is active (goes to the WBgen
                                             -- status reg read by SW)
               s_statTransFinished <= '0';
             end if;
             
          --====================================================================================
          when S_WAIT_PB_MARKER =>  -- wait for the marker on the "faster" port
          --====================================================================================
            
            -- marker frame on port B detected
            if((s_port_B_mask and rxFrameMask_i) = s_port_B_mask) then
              s_tru_trans_state            <= S_WAIT_PA_MARKER;
              
              -- send HW-generated paus
              s_ep_ctr_B.pauseSend         <= '1';  
              s_ep_ctr_B.pauseTime         <= config_i.tcr_trans_port_a_pause;
              
              -- block output queues (TODO: to be revised)
              s_ep_ctr_A.outQueueBlockMask <= s_port_A_prio_mask;
              s_ep_ctr_B.outQueueBlockMask <= s_port_B_prio_mask;
            end if;
          --====================================================================================
          when S_WAIT_PA_MARKER =>  -- wait for the marker on the "slower" port
          --====================================================================================
            s_ep_ctr_B.pauseSend         <= '0';

            -- marker frame on port A deteded
            if((s_port_A_mask and rxFrameMask_i) = s_port_A_mask) then
              s_tru_trans_state    <= S_WAIT_WITH_TRANS;
              
            -- until marker frame on port A is not detected, count rx frames of a defined priority
            else
              if(s_port_B_rtu_srobe = '1') then
                s_portB_frame_cnt <=  s_portB_frame_cnt+1;
              end if;              
            end if;          
          --====================================================================================
          when S_WAIT_WITH_TRANS =>  -- wait until the same number of frames is rx-ed on both ports
          --====================================================================================
            
            -- as soon as the number of frames received on port A equals the number of frames
            -- received on port B, transition
            -- "+ 1" => we change before the next packet - the things is that the strobe
            -- which increments the counter comes before the request is considered by 
            -- TRU so, instead of making some delay not to make the new TRU TAB configuration 
            -- too fast...  we change configuration before the request whic is to be 
            -- handled by new configuration (we have time to change)
            if(s_portA_frame_cnt = s_portB_frame_cnt) then
              s_tru_trans_state    <= S_TRANSITIONED;
              tru_tab_bank_o       <= '1';                 -- request bank swap of TRU TAB
              
            -- count the number of frames received on port A
            else
              if(s_port_A_rtu_srobe = '1') then
                s_portA_frame_cnt <=  s_portA_frame_cnt+1;
              end if;              
            end if;          

          --====================================================================================
          when S_TRANSITIONED =>  -- swap banks (assuming proper config in the TRU TAB)
          --====================================================================================
            
            -- transition: done
            s_tru_trans_state   <= S_IDLE;
            s_portA_frame_cnt   <= (others => '0');
            s_portB_frame_cnt   <= (others => '0');
            s_statTransActive   <= '0';
            s_statTransFinished <= '1';               
            s_ep_ctr_A.outQueueBlockMask <= (others => '0');            
            s_ep_ctr_B.outQueueBlockMask <= (others => '0');
            
            tru_tab_bank_o       <= '0';
              
          --====================================================================================
          when others =>
          --====================================================================================
            s_portA_frame_cnt            <= (others => '0');
            s_portB_frame_cnt            <= (others => '0');
            s_statTransActive            <= '0';
            s_statTransFinished          <= '0';               
            s_ep_ctr_A.outQueueBlockMask <= (others => '0');            
            s_ep_ctr_B.outQueueBlockMask <= (others => '0');
            s_tru_trans_state            <= S_IDLE;

        end case;      
        
        -- clearing of finished bit by configuration
        if(s_statTransFinished = '1' and s_statTransActive ='1' and config_i.tcr_trans_clr = '1') then
          s_statTransFinished <= '0';
        end if;        
                  
      end if;
    end if;
  end process;  
  
  statTransActive_o   <= s_statTransActive;
  statTransFinished_o <= s_statTransFinished;

  -- MUX of Port A/B control (outputs) to appropraite ports
  EP_OUT: for i in 0 to g_num_ports-1 generate
      ep_o(i)<= s_ep_ctr_A when (i = to_integer(unsigned(config_i.tcr_trans_port_a_id))) else
                s_ep_ctr_B when (i = to_integer(unsigned(config_i.tcr_trans_port_b_id))) else
                s_ep_zero;
  end generate EP_OUT;

end rtl;
