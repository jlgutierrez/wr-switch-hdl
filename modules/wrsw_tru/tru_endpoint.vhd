-------------------------------------------------------------------------------
-- Title      : Topology Resolution Unit: endpoint
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : tru_endpoint.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-08-28
-- Last update: 2012-08-13
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: This module interfaces endpoints and provides information
-- useful for TRU module in a TRU-friendly way.
--
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- It takes care that a port which goes down is killed (turned off) and 
-- prevents throttling of port (going up and down againa and again due to 
-- e.g. bad connection) from affecting TRU.
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
-- 2012-08-30  1.0      mlipinsk Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

library work;
use work.wrsw_shared_types_pkg.all; -- need this for:
                                    -- * t_tru_request


use work.gencores_pkg.all;          -- for f_rr_arbitrate
use work.wrsw_tru_pkg.all;

entity tru_endpoint is
  generic(     
     g_num_ports        : integer; 
     g_pclass_number    : integer;
     g_tru_subentry_num : integer;
     g_patternID_width  : integer;
     g_pattern_width    : integer;
     g_stableUP_treshold: integer
    );
  port (
    clk_i              : in  std_logic;
    rst_n_i            : in  std_logic;
    
    port_if_i          : in  t_ep2tru;
    port_if_ctrl_o     : out std_logic;
    
    
    ------------------------------- I/F with tru_endpoint ----------------------------------
    rtu_pass_all_i     : in  std_logic;
    
    ------------------------------- I/F with tru_endpoint ----------------------------------
    endpoint_o         : out  t_tru_endpoint;
    
    -------------------------------global config/variable ----------------------------------
    reset_rxFlag_i     : in  std_logic
    );
end tru_endpoint;

architecture rtl of tru_endpoint is
  type t_tru_port_state is(S_DISABLED,    
                           S_WORKING, 
                           S_BROKEN_LINK);

 
  signal s_zeros             : std_logic_vector(31 downto 0);
  signal s_port_status_d0    : std_logic;
  signal s_port_down         : std_logic;
  signal s_stableUp_cnt      : unsigned(7 downto 0);  
  signal s_tru_port_state    : t_tru_port_state;
  signal s_rxFrameMaskReg    : std_logic_vector(g_pclass_number-1 downto 0);
  signal s_rxFrameMask       : std_logic_vector(g_pclass_number-1 downto 0);
  
begin --rtl
   
  s_zeros <= (others => '0');
  
  FSM: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
         
         s_tru_port_state           <= S_DISABLED;
         endpoint_o.status          <= '0';
         port_if_ctrl_o             <= '0';
         
      else
        
         case s_tru_port_state is
           
            --====================================================================================
             when S_DISABLED =>
            --====================================================================================
               
               if(rtu_pass_all_i = '0' and port_if_i.status = '1') then
                 s_tru_port_state           <= S_WORKING;
               end if;
               endpoint_o.status          <= port_if_i.status;
               port_if_ctrl_o             <= '1';
               
            --====================================================================================
            when S_WORKING =>
            --====================================================================================
               
               if(s_port_down = '1') then
                 endpoint_o.status        <= '0';
                 port_if_ctrl_o           <= '0';
                 s_tru_port_state         <= S_BROKEN_LINK;
               end if;
               
            --====================================================================================
            when S_BROKEN_LINK =>
            --====================================================================================
                if(rtu_pass_all_i = '0' ) then
                   s_tru_port_state       <= S_DISABLED;
                   port_if_ctrl_o         <= '1';
                end if;
            --====================================================================================
            when others =>
            --====================================================================================
               s_tru_port_state           <= S_DISABLED;
               endpoint_o.status          <=  '0';
               port_if_ctrl_o             <= '0';
           
         end case; 
      end if;
    end if;
  end process;  

  regs: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
         s_port_status_d0                <= '0';
         s_rxFrameMaskReg                <= (others => '0');         
         s_rxFrameMask                   <= (others => '0');         
      else
        
         s_port_status_d0                <= port_if_i.status;
        
         if(s_tru_port_state = S_WORKING and reset_rxFlag_i = '0' and port_if_i.rx_pck = '1') then         
            s_rxFrameMaskReg             <= s_rxFrameMaskReg or port_if_i.rx_pck_class;
            s_rxFrameMask                <= port_if_i.rx_pck_class;
         elsif(s_tru_port_state = S_WORKING and reset_rxFlag_i = '1' and port_if_i.rx_pck = '1') then 
            s_rxFrameMaskReg             <= port_if_i.rx_pck_class;
            s_rxFrameMask                <= port_if_i.rx_pck_class; 
         elsif(reset_rxFlag_i = '1') then
            s_rxFrameMaskReg             <= (others => '0');
            s_rxFrameMask                <= (others => '0');        
         end if;
      end if;
    end if;
  end process;    

  stableUP: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
         endpoint_o.stableUp             <= '0';
         s_stableUp_cnt                  <= (others => '0');
      else
      
         if(s_port_down = '1') then
           s_stableUp_cnt                <= (others =>'0');
           endpoint_o.stableUp           <= '0';
         elsif(port_if_i.status = '1') then
           if(s_stableUp_cnt > to_unsigned(g_stableUP_treshold,s_stableUp_cnt'length )) then
              endpoint_o.stableUp        <= '1';
           else
              s_stableUp_cnt             <= s_stableUp_cnt + 1;
           end if;
         end if;   
      end if;
    end if;
  end process;  

  endpoint_o.rxFrameMask(g_pclass_number-1 downto 0)        <= port_if_i.rx_pck_class(g_pclass_number-1 downto 0) when (port_if_i.rx_pck='1') else (others => '0');--s_rxFrameMask;
  endpoint_o.rxFrameMaskReg(g_pclass_number-1 downto 0)     <= s_rxFrameMaskReg(g_pclass_number-1 downto 0);
  
  -- detect link down event (edge of input status signal while the control info says port should
  -- be UP);
  s_port_down                   <= (not port_if_i.status) and s_port_status_d0 and port_if_i.ctrlRd; 

end rtl;
