-------------------------------------------------------------------------------
-- Title      : Packet Transfer Input
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_pck_transfer_input.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-11-03
-- Last update: 2013-03-05
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
-- 2013-03-05  2.1      mlipinsk added hp, removed pck_size
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--library work;
--use work.swc_swcore_pkg.all;


entity swc_pck_transfer_input is
  generic(
     g_page_addr_width    : integer ;--:= c_swc_page_addr_width;
     g_prio_width         : integer ;--:= c_swc_prio_width;
--      g_max_pck_size_width : integer ;--:= c_swc_max_pck_size_width    
     g_num_ports          : integer  --:= c_swc_num_ports
  );
  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

-------------------------------------------------------------------------------
-- I/F with pck transfer output (PTO)
-------------------------------------------------------------------------------

    pto_transfer_pck_o : out  std_logic;
       
    pto_pageaddr_o : out  std_logic_vector(g_page_addr_width - 1 downto 0);
    
    pto_output_mask_o     : out  std_logic_vector(g_num_ports - 1 downto 0);
    
    pto_read_mask_i     : in  std_logic_vector(g_num_ports - 1 downto 0);

    pto_prio_o     : out  std_logic_vector(g_prio_width - 1 downto 0);

--     pto_pck_size_o : out  std_logic_vector(g_max_pck_size_width - 1 downto 0);
    
    pto_hp_o       : out std_logic;

-------------------------------------------------------------------------------
-- I/F with Input Block (IB)
-------------------------------------------------------------------------------     
    -- indicates the beginning of the package, strobe
    ib_transfer_pck_i : in  std_logic;
       
    -- array of pages' addresses to which ports want to write
    ib_pageaddr_i : in  std_logic_vector(g_page_addr_width - 1 downto 0);
    
    -- destination mask - indicates to which ports the packet should be
    -- forwarded
    ib_mask_i     : in  std_logic_vector(g_num_ports - 1 downto 0);

    ib_prio_i     : in  std_logic_vector(g_prio_width - 1 downto 0);
    
--     ib_pck_size_i : in  std_logic_vector(g_max_pck_size_width - 1 downto 0);
    
    ib_hp_i       : in  std_logic;
    
    ib_transfer_ack_o : out std_logic;
    
    ib_busy_o         : out std_logic
    
    );
end swc_pck_transfer_input;
    
architecture syn of swc_pck_transfer_input is   

    signal ib_transfer_ack: std_logic;
    signal ib_pageaddr    : std_logic_vector(g_page_addr_width - 1 downto 0);
    signal ib_prio        : std_logic_vector(g_prio_width - 1      downto 0);
--     signal ib_pck_size    : std_logic_vector(g_max_pck_size_width - 1 downto 0);
    signal ib_hp          : std_logic;
    signal ib_mask        : std_logic_vector(g_num_ports - 1       downto 0);
    --signal pto_read_mask    : std_logic_vector(g_num_ports - 1       downto 0);
    signal pto_output_mask  : std_logic_vector(g_num_ports - 1       downto 0);
    signal zeros           : std_logic_vector(g_num_ports - 1       downto 0);

begin --arch

  zeros <= (others => '0');

  input: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
       
      
      if(rst_n_i = '0') then
      --===================================================
      ib_mask               <= (others => '0');
      --pto_read_mask         <= (others => '0');
      pto_output_mask       <= (others => '0');
      ib_prio               <= (others => '0');
--       ib_pck_size           <= (others => '0');
      ib_hp                 <= '0';
      ib_pageaddr           <= (others => '0');
      ib_transfer_ack       <= '0';
      --===================================================
      else
        
        if(ib_transfer_pck_i = '1' and pto_output_mask = zeros) then 
        
          ib_mask         <= ib_mask_i;
          ib_prio         <= ib_prio_i;
          ib_pageaddr     <= ib_pageaddr_i;
--           ib_pck_size     <= ib_pck_size_i;
          ib_hp           <= ib_hp_i;
          
        end if;
        
        if(ib_transfer_pck_i = '1' and pto_output_mask = zeros) then         
          
          --pto_read_mask     <= (others => '0');
          pto_output_mask   <= ib_mask_i;--(others => '0');        
          
        else
          
--          pto_read_mask     <= pto_read_mask or (pto_read_mask_i and ib_mask);
--          pto_output_mask   <= (((pto_read_mask_i and ib_mask) -- filter read mask, if a port which 
--                                                            -- is not supposed to read the data, reads it
--                                                          -- we see no difference
--                           or pto_read_mask)               -- add to the mask of the outputs_block which
--                                                          -- already read the data, the one currently reading
--                           xor ib_mask);   
--
          pto_output_mask   <= (not(pto_read_mask_i and ib_mask) ) and pto_output_mask;   

        end if;        

        if(ib_transfer_ack = '1') then
          ib_transfer_ack <= '0';
        elsif(ib_transfer_pck_i = '1' and pto_output_mask = zeros) then 
          ib_transfer_ack <= '1';
        else
          ib_transfer_ack <= '0';
        end if;
        

            -- 
      --===================================================
      end if;
    end if;
  end process;

 pto_output_mask_o  <= pto_output_mask;
 pto_transfer_pck_o <= '0'; 
 pto_pageaddr_o     <= ib_pageaddr;
 pto_prio_o         <= ib_prio;
--  pto_pck_size_o     <= ib_pck_size;
 pto_hp_o           <= ib_hp;
 ib_transfer_ack_o  <= ib_transfer_ack;
 
 ib_busy_o       <= '0' when (pto_output_mask = zeros) else '1';
 
end syn; -- arch