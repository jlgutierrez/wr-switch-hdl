-------------------------------------------------------------------------------
-- Title      : Output Traffic Shaper
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_output_traffic_shaper.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2013-02-26
-- Last update: 2013-04-26
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: This module produces masks used for blocking output traffic
-- on different output queues (classes). It implements two functionalities:
-- * per-priority (CoS) PAUSE
-- * time-aware-shaping (allow only chosen output queues for given time)
-------------------------------------------------------------------------------
--
-- Copyright (c) 2013 Maciej Lipinski / CERN
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
-- 2013-02-026  1.0      mlipinsk Created
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.swc_swcore_pkg.all;
use work.wrsw_shared_types_pkg.all;

entity swc_output_traffic_shaper is
  
  generic (
    g_num_ports      : natural := 32
    );

  port (
    rst_n_i                   : in  std_logic;
    clk_i                     : in  std_logic;
    
    -------------------------------------------------------------------------------
    -- Request from Time-Aware shaper, it indicates which classes shall be allowed
    -- at output in the window ('1' in classes vector inducates the class is allowed). 
    -- It also indicates on which ports this should be applied
    -------------------------------------------------------------------------------
    shaper_request_i          : in  t_pause_request ;
    shaper_ports_i            : in  std_logic_vector(g_num_ports-1 downto 0);

    -------------------------------------------------------------------------------
    -- PAUSE request (e.g. from TRU->transition but more modules can control it).
    -- * it is per-port
    -- * '1' on classes vector indicates which classes shall be blocked
    -------------------------------------------------------------------------------
    pause_requests_i          : in  t_pause_request_array(g_num_ports-1 downto 0);

    -------------------------------------------------------------------------------
    -- Masks (per-port) which are used to block the output queues:
    -- * '1' indicates that a queue of class X shall be blocked
    -- * 'by default 0000...00 (no queues blocked)
    -------------------------------------------------------------------------------
    output_masks_o            : out t_classes_array(g_num_ports-1 downto 0)
    );
end swc_output_traffic_shaper;

architecture syn of swc_output_traffic_shaper is

  type t_pause_array is array(g_num_ports-1 downto 0) of unsigned(15 downto 0);
  
  signal div512           : unsigned(4 downto 0);
  signal advance_counter  : std_logic; 
  
  signal pause_counters   : t_pause_array;
  signal pause_masks      : t_classes_array(g_num_ports-1 downto 0);

  signal shaper_counter   : unsigned(15 downto 0);
  signal shaper_ports     : std_logic_vector(g_num_ports-1 downto 0);
  signal shaper_mask      : std_logic_vector(7 downto 0);


begin -- behavioral

  -- process to generate "tic" every  "quanta" whic is equal to 512 bit times 
  -- (62.5MHz => 16ns cycle, each processing 16 bit word, 512/16 = 32 = 2^5.
  -- This tic is used by the rest of processes
  gen_pause_timing : process (clk_i, rst_n_i)
  begin  -- process
    if rising_edge(clk_i) then
      if (rst_n_i = '0') then
        div512          <= (others => '0');
        advance_counter <= '0';
      else
        div512 <= div512 + 1;
        if(div512 = to_unsigned(0, div512'length)) then
          advance_counter <= '1';
        else
          advance_counter <= '0';
        end if;
      end if;
    end if;
  end process;

  per_port_pause: for i in 0 to g_num_ports-1  generate
    -- per-port process to handle (class selectable) pause =
    pause_proc : process (clk_i, rst_n_i)
    begin
      if rising_edge(clk_i) then
        if(rst_n_i = '0') then
          pause_counters(i)  <= (others => '0');
          pause_masks(i)     <= (others => '0');
        else 
          if (pause_requests_i(i).req = '1') then
            pause_counters(i)  <= unsigned(pause_requests_i(i).quanta);
            pause_masks(i)     <= pause_requests_i(i).classes;
          elsif (advance_counter = '1') then
            if(pause_counters(i) = to_unsigned(0, pause_counters(i)'length)) then
              pause_masks(i)   <= (others => '0');
            else
              pause_counters(i) <= pause_counters(i) - 1;
            end if;  
          end if;  
        end if;
      end if;
    end process;
  end generate PER_PORT_PAUSE;

  -- global pause for time-aware taffic shaping: 
  -- * we say which class(es) are allowed for quanta-long window
  -- * we say for which ports this window works
  global_shaper : process (clk_i, rst_n_i)
  begin  
    if rising_edge(clk_i) then
      if (rst_n_i = '0') then
        shaper_mask    <= (others => '0');
        shaper_ports   <= (others => '0');
        shaper_counter <= (others => '0');
      else
        if(shaper_request_i.req = '1') then
          shaper_counter <= unsigned(shaper_request_i.quanta);
          shaper_mask    <= shaper_request_i.classes;
          shaper_ports   <= shaper_ports_i;
        elsif (advance_counter = '1') then
          if(shaper_counter = to_unsigned(0, shaper_counter'length)) then
            shaper_mask  <= (others => '0');
            shaper_ports <= (others => '0');
          else
            shaper_counter <= shaper_counter - 1;
          end if; 
        end if;
      end if;
    end if;
  end process; 

  -- generating final masks to be used on different swcore's ports to decide which
  -- queue shall be used for next forward
  gen_output_masks: for i in 0 to g_num_ports-1  generate
    output_masks_o(i) <= (pause_masks(i) or (not shaper_mask)) when (shaper_ports(i) = '1') else
                         pause_masks(i);
  end generate gen_output_masks;

end syn;
