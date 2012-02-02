-------------------------------------------------------------------------------
-- Title      : Packet Transfer Output
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_pck_transfer_output.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-11-03
-- Last update: 2012-02-02
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
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
-- Date        Version  Author   Description
-- 2010-11-03  1.0      mlipinsk created
-- 2012-02-02  2.0      mlipinsk generic-azed

-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.swc_swcore_pkg.all;


entity swc_pck_transfer_output is
  generic(
    g_page_addr_width    : integer ;--:= c_swc_page_addr_width;
    g_prio_width         : integer ;--:= c_swc_prio_width;
    g_max_pck_size_width : integer --:= c_swc_max_pck_size_width
  );
  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

-------------------------------------------------------------------------------
-- I/F with output blocks (OB)
-------------------------------------------------------------------------------

    ob_transfer_data_valid_o : out  std_logic;
    ob_pageaddr_o            : out  std_logic_vector(g_page_addr_width - 1 downto 0);
    ob_prio_o                : out  std_logic_vector(g_prio_width - 1 downto 0);
    ob_pck_size_o            : out  std_logic_vector(g_max_pck_size_width - 1 downto 0);
    ob_transfer_data_ack_i   : in  std_logic;
-------------------------------------------------------------------------------
-- I/F with Page Transfer Input (PTI)
-------------------------------------------------------------------------------     

    pti_transfer_data_valid_i  : in   std_logic;
    pti_transfer_data_ack_o    : out  std_logic;
    pti_pageaddr_i             : in   std_logic_vector(g_page_addr_width - 1 downto 0);
    pti_prio_i                 : in   std_logic_vector(g_prio_width - 1 downto 0);
    pti_pck_size_i             : in   std_logic_vector(g_max_pck_size_width - 1 downto 0)
    
    );
end swc_pck_transfer_output;
    
architecture syn of swc_pck_transfer_output is   

    signal pti_transfer_data_ack  : std_logic;
    signal ob_transfer_data_valid : std_logic;
    signal ob_pageaddr            : std_logic_vector(g_page_addr_width - 1 downto 0);
    signal ob_prio                : std_logic_vector(g_prio_width - 1      downto 0);
    signal ob_pck_size            : std_logic_vector(g_max_pck_size_width - 1 downto 0);
    
begin --arch


  output: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
       
      
      if(rst_n_i = '0') then
      --===================================================
      ob_pageaddr               <= (others => '0');
      ob_prio                   <= (others => '0');
      ob_pck_size               <= (others => '0');
      ob_transfer_data_valid    <= '0';
      pti_transfer_data_ack     <= '0';
      --===================================================
      else
        
        if(pti_transfer_data_valid_i = '1' and ( ob_transfer_data_valid = '0' or ob_transfer_data_ack_i = '1')) then 

          ob_pageaddr <= pti_pageaddr_i;
          ob_prio     <= pti_prio_i;
          ob_pck_size <= pti_pck_size_i;
          
        end if;        

        if(pti_transfer_data_valid_i = '1' and ( ob_transfer_data_valid = '0' or ob_transfer_data_ack_i = '1')) then 
          pti_transfer_data_ack <= '1';
        else
          pti_transfer_data_ack <= '0';
        end if;
        

        if(ob_transfer_data_ack_i = '1' and pti_transfer_data_valid_i = '0') then 
          ob_transfer_data_valid <= '0';
        elsif (pti_transfer_data_valid_i = '1') then 
          ob_transfer_data_valid <= '1';
        end if;
        
      --===================================================
      end if;
    end if;
  end process;

  pti_transfer_data_ack_o   <= pti_transfer_data_ack;
  ob_transfer_data_valid_o  <= ob_transfer_data_valid;
  ob_pageaddr_o             <= ob_pageaddr;
  ob_prio_o                 <= ob_prio;
  ob_pck_size_o             <= ob_pck_size;
  
end syn; -- arch