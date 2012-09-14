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
    ep_o               : out t_trans2tru_array(g_num_ports - 1 downto 0)
    );
end tru_trans_marker_trig;

architecture rtl of tru_trans_marker_trig is
  type t_tru_trans_state is(S_IDLE,    
                            S_WAIT_PA_MARKER, 
                            S_WAIT_PB_MARKER, 
                            S_WAIT_WITH_TRANS,
                            S_TRANSITIONED);
                             
  signal s_tru_trans_state: t_tru_trans_state;
  signal s_start_transition: std_logic;
  signal s_portA_frame_cnt : unsigned(integer(CEIL(LOG2(real(g_mt_trans_max_fr_cnt-1)))) -1 downto 0);
  signal s_portB_frame_cnt : unsigned(integer(CEIL(LOG2(real(g_mt_trans_max_fr_cnt-1)))) -1 downto 0);
  signal s_statTransActive   : std_logic;
  signal s_statTransFinished : std_logic;
  signal s_port_A_mask       : std_logic_vector(g_num_ports-1 downto 0);
  signal s_port_B_mask       : std_logic_vector(g_num_ports-1 downto 0);
  signal s_port_A_prio       : std_logic_vector(g_prio_width-1 downto 0);
  signal s_port_B_prio       : std_logic_vector(g_prio_width-1 downto 0);

  signal s_port_A_prio_mask  : std_logic_vector(2**g_prio_width-1 downto 0);
  signal s_port_B_prio_mask  : std_logic_vector(2**g_prio_width-1 downto 0);

  signal s_port_A_rtu_srobe  : std_logic;
  signal s_port_B_rtu_srobe  : std_logic;
  signal s_ep_ctr_A          : t_trans2ep;
  signal s_ep_ctr_B          : t_trans2ep;
  signal s_ep_zero           : t_trans2ep;

begin --rtl
   
   s_start_transition  <= config_i.tcr_trans_ena          and 
                          config_i.tcr_trans_port_a_valid and 
                          config_i.tcr_trans_port_b_valid;

   G_PRIO_MASK: for i in 0 to 2**g_prio_width-1 generate
      s_port_A_prio_mask(i) <= '1' when(i = to_integer(unsigned(s_port_A_prio))) else '0';
      s_port_B_prio_mask(i) <= '1' when(i = to_integer(unsigned(s_port_B_prio))) else '0';
   end generate G_PRIO_MASK;
   
   G_MASK: for i in 0 to g_num_ports-1 generate
      s_port_A_mask(i) <= '1' when (i = to_integer(unsigned(config_i.tcr_trans_port_a_id)) and config_i.tcr_trans_port_a_valid ='1') else '0';
      s_port_B_mask(i) <= '1' when (i = to_integer(unsigned(config_i.tcr_trans_port_b_id)) and config_i.tcr_trans_port_a_valid ='1') else '0';
   end generate G_MASK;
  
  s_port_A_prio       <= rtu_i.priorities(to_integer(unsigned(config_i.tcr_trans_port_a_id)));
  s_port_B_prio       <= rtu_i.priorities(to_integer(unsigned(config_i.tcr_trans_port_b_id)));
  s_port_A_rtu_srobe  <= '1' when ((s_port_A_mask and rtu_i.request_valid(g_num_ports-1 downto 0)) = s_port_A_mask and 
                                    s_port_A_prio = config_i.tcr_trans_prio) else '0';
  s_port_B_rtu_srobe  <= '1' when ((s_port_B_mask and rtu_i.request_valid(g_num_ports-1 downto 0)) = s_port_B_mask and
                                    s_port_B_prio = config_i.tcr_trans_prio) else '0';
  s_ep_zero.pauseSend          <= '0';
  s_ep_zero.pauseTime          <= (others => '0');
  s_ep_zero.outQueueBlockMask  <= (others => '0');
  CTRL: process(clk_i, rst_n_i)
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
            
             if(s_start_transition = '1' and s_statTransFinished ='0' and s_statTransActive = '0') then --
               s_tru_trans_state   <= S_WAIT_PA_MARKER;
               s_portA_frame_cnt   <= (others => '0');
               s_portB_frame_cnt   <= (others => '0');
               s_statTransActive   <= '1';
               s_statTransFinished <= '0';
             end if;
             
          --====================================================================================
          when S_WAIT_PA_MARKER =>
          --====================================================================================
            if((s_port_A_mask and rxFrameMask_i) = s_port_A_mask) then
              s_tru_trans_state            <= S_WAIT_PB_MARKER;
              s_ep_ctr_A.pauseSend         <= '1';
              s_ep_ctr_A.pauseTime         <= config_i.tcr_trans_port_a_pause;
              s_ep_ctr_A.outQueueBlockMask <= s_port_A_prio_mask;
              s_ep_ctr_B.outQueueBlockMask <= s_port_B_prio_mask;
            end if;
          --====================================================================================
          when S_WAIT_PB_MARKER =>
          --====================================================================================
            s_ep_ctr_A.pauseSend         <= '0';

            if((s_port_B_mask and rxFrameMask_i) = s_port_B_mask) then
              s_tru_trans_state    <= S_WAIT_WITH_TRANS;
            else
              if(s_port_A_rtu_srobe = '1') then
                s_portA_frame_cnt <=  s_portA_frame_cnt+1;
              end if;              
            end if;          
          --====================================================================================
          when S_WAIT_WITH_TRANS =>
          --====================================================================================
            if(s_portA_frame_cnt = s_portB_frame_cnt) then
              s_tru_trans_state    <= S_TRANSITIONED;
              tru_tab_bank_o       <= '1';
            else
              if(s_port_B_rtu_srobe = '1') then
                s_portB_frame_cnt <=  s_portB_frame_cnt+1;
              end if;              
            end if;          

          --====================================================================================
          when S_TRANSITIONED =>
          --====================================================================================
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
        
        if(s_statTransFinished = '1' and s_statTransActive ='1' and config_i.tcr_trans_clr = '1') then
          s_statTransFinished <= '0';
        end if;        
                  
      end if;
    end if;
  end process;  
  
  statTransActive_o   <= s_statTransActive;
  statTransFinished_o <= s_statTransFinished;

  EP_OUT: for i in 0 to g_num_ports-1 generate
      ep_o(i)<= s_ep_ctr_A when (i = to_integer(unsigned(config_i.tcr_trans_port_a_id))) else
                s_ep_ctr_B when (i = to_integer(unsigned(config_i.tcr_trans_port_b_id))) else
                s_ep_zero;
  end generate EP_OUT;

end rtl;
