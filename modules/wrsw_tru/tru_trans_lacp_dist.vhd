-------------------------------------------------------------------------------
-- Title      : Topology Resolution Unit: Link Aggregation protocol, marker, distribution
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : tru_trans_lacp_dist.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-09-10
-- Last update: 2013-08-01
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: This module supports transition of "message stream" between 
-- links (connections) of "link aggregation" on the switch being a distributor.
--[to be implemented]
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- 
-- 
-- 
-- 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 - 2013 CERN / BE-CO-HT
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

entity tru_trans_lacp_dist is
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
    sw_o               : out t_trans2sw;
    ep_o               : out t_trans2tru_array(g_num_ports - 1 downto 0)
    );
end tru_trans_lacp_dist;

architecture rtl of tru_trans_lacp_dist is
 
  type t_tru_trans_state is(S_IDLE,    
                            S_WAIT_RESP_MARKER, 
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

  signal s_port_prio_mask  : std_logic_vector(2**g_prio_width-1 downto 0);

  signal s_ep_ctr_A          : t_trans2ep;
  signal s_ep_ctr_B          : t_trans2ep;
  signal s_ep_zero           : t_trans2ep;
  
  signal s_sw_ctrl           : t_trans2sw;

begin --rtl
   
   -- to make code less messy - start transition only it is enabled by config and all necessary 
   -- config is valid
   s_start_transition  <= config_i.tcr_trans_ena          and 
                          config_i.tcr_trans_port_a_valid and 
                          config_i.tcr_trans_port_b_valid;

   -- generating mask with 1 at the priority for with we perform transition (configured value)
   -- TODO: we would need more options here
   G_PRIO_MASK: for i in 0 to 2**g_prio_width-1 generate
      s_port_prio_mask(i) <= '1' when(i = to_integer(unsigned(config_i.tcr_trans_prio))) else '0';
   end generate G_PRIO_MASK;
   
   -- generating mask with 1 at the port to which we transition ... TODO: we need more then one
   G_MASK: for i in 0 to g_num_ports-1 generate
      s_port_A_mask(i) <= '1' when (i = to_integer(unsigned(config_i.tcr_trans_port_a_id)) and config_i.tcr_trans_port_a_valid ='1') else '0';
      s_port_B_mask(i) <= '1' when (i = to_integer(unsigned(config_i.tcr_trans_port_b_id)) and config_i.tcr_trans_port_b_valid ='1') else '0';
   end generate G_MASK;
  
   -- preparing masks
   s_sw_ctrl.blockPortsMask(g_num_ports-1 downto 0)      <= s_port_B_mask;
   s_sw_ctrl.blockQueuesMask(2**g_prio_width-1 downto 0) <= s_port_prio_mask;

   -- filling in not-used bits
   s_sw_ctrl.blockPortsMask(s_sw_ctrl.blockPortsMask'length -1 downto g_num_ports)      <= (others =>'0');
   s_sw_ctrl.blockQueuesMask(s_sw_ctrl.blockQueuesMask'length-1 downto 2**g_prio_width) <= (others =>'0');
                                 
  -- an empty entry
  s_ep_zero.pauseSend          <= '0';
  s_ep_zero.pauseTime          <= (others => '0');
  s_ep_zero.outQueueBlockMask  <= (others => '0');
  s_ep_zero.outQueueBlockReq   <= '0';
  s_ep_zero.hwframe_fwd        <= '0';
  s_ep_zero.hwframe_blk        <= '0';
  
  TRANS_FSM: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
         
        s_tru_trans_state   <= S_IDLE;
        s_statTransActive   <= '0';
        s_statTransFinished <= '0';
        tru_tab_bank_o      <= '0';

        s_ep_ctr_A          <= s_ep_zero;
        s_ep_ctr_B          <= s_ep_zero;
        
        s_sw_ctrl.blockTime <= (others => '0');
        s_sw_ctrl.blockReq  <= '0';

      else
        
        case s_tru_trans_state is
           
          --====================================================================================
          when S_IDLE =>
          --====================================================================================
             s_portA_frame_cnt            <= (others => '0');
             s_portB_frame_cnt            <= (others => '0');
             s_statTransActive            <= '0';              
             s_sw_ctrl.blockTime          <= (others => '0');
             s_sw_ctrl.blockReq           <= '0';
            
             -- new transition is not started until the previous has been cleared/finished
             if(s_start_transition = '1' and s_statTransFinished ='0' and s_statTransActive = '0') then --
               s_tru_trans_state   <= S_WAIT_RESP_MARKER;
               s_portA_frame_cnt   <= (others => '0');
               s_portB_frame_cnt   <= (others => '0');
               s_statTransActive   <= '1';   -- indicate that transition is active (goes to the WBgen
                                             -- status reg read by SW)
               s_statTransFinished <= '0';

               -- block Port_B
               s_sw_ctrl.blockReq  <= '1';
               s_sw_ctrl.blockTime <= config_i.tcr_trans_block_time;               
               
               -- change distribution
                tru_tab_bank_o     <= '1';   -- request bank swap of TRU TAB
             end if;
             
          --====================================================================================
          when S_WAIT_RESP_MARKER =>  -- block the output queue of port_B and wait to receive
                                      -- Marker Response on port_A
          --====================================================================================
            
            tru_tab_bank_o         <= '0'; 
            s_sw_ctrl.blockReq     <= '0';
            -- Marker Response on port A detected, can unblock the port
            if((s_port_A_mask and rxFrameMask_i) = s_port_A_mask) then
              s_tru_trans_state    <= S_TRANSITIONED;
              
              -- stop pause
              s_sw_ctrl.blockReq   <= '1';
              s_sw_ctrl.blockTime  <= (others => '0');  

            end if;
          --====================================================================================
          when S_TRANSITIONED =>  -- swap banks (assuming proper config in the TRU TAB)
          --====================================================================================
            
            -- transition: done
            s_tru_trans_state     <= S_IDLE;
            s_portA_frame_cnt     <= (others => '0');
            s_portB_frame_cnt     <= (others => '0');
            s_statTransActive     <= '0';
            s_statTransFinished   <= '1';               
            tru_tab_bank_o        <= '0';
            s_sw_ctrl.blockReq    <= '1';
              
          --====================================================================================
          when others =>
          --====================================================================================
            s_portA_frame_cnt            <= (others => '0');
            s_portB_frame_cnt            <= (others => '0');
            s_statTransActive            <= '0';
            s_statTransFinished          <= '0';               
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
  sw_o                <= s_sw_ctrl;
  -- MUX of Port A/B control (outputs) to appropraite ports
  EP_OUT: for i in 0 to g_num_ports-1 generate
      ep_o(i)<= s_ep_ctr_A when (i = to_integer(unsigned(config_i.tcr_trans_port_a_id))) else
                s_ep_ctr_B when (i = to_integer(unsigned(config_i.tcr_trans_port_b_id))) else
                s_ep_zero;
  end generate EP_OUT;



--    -- TODO
-- 
--   statTransActive_o      <= '0';
--   statTransFinished_o    <= '0';
--   tru_tab_bank_o         <= '0';
--   s_ep.pauseSend         <= '0';
--   s_ep.pauseTime         <= (others => '0');
--   s_sw.blockTime         <= (others => '0');
--   s_sw.blockQueuesMask   <= (others => '0');
--   s_sw.blockPortsMask    <= (others => '0');
--   s_sw.blockReq          <= '0';
--   
--   EP_OUT: for i in 0 to g_num_ports-1 generate
--     ep_o(i)              <= s_ep;
--   end generate EP_OUT;
--   
--   sw_o                   <= s_sw;

end rtl;
