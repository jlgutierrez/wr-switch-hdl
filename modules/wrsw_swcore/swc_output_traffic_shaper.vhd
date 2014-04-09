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
-- Copyright (c) 2013 CERN / BE-CO-HT
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
    g_num_ports        : integer := 32;
    g_num_global_pause : integer := 2
    );

  port (
    rst_n_i                   : in  std_logic;
    clk_i                     : in  std_logic;
    
    -------------------------------------------------------------------------------
    -- per-port PAUSE request
    -- * semi-priority-based - defines which priorities (output queues) to  block
    -- * has the same pause time (quanta) for all priorities
    -- * expected to come from Endpoints which parse PAUSE frames and provide info
    -------------------------------------------------------------------------------
    perport_pause_i          : in  t_pause_request_array(g_num_ports-1 downto 0);

    -------------------------------------------------------------------------------
    -- global PAUSE request
    -- * semi-priority-based - defines which priorities (output queues) to  block
    -- * has the same pause time (quanta) for all priorities
    -- * a single pause for a number of indicated ports: 
    --   we say which priorities on which ports shall be blocked (globally)
    -- * many modules can huck to this - it's an array of global PAUSEs
    -------------------------------------------------------------------------------
    global_pause_i           : in  t_global_pause_request_array(g_num_global_pause-1 downto 0);
    
    -------------------------------------------------------------------------------
    -- Masks (per-port) which are used to block the output queues:
    -- * '1' indicates that a queue of class X shall be blocked
    -- * 'by default 0000...00 (no queues blocked)
    -------------------------------------------------------------------------------
    output_masks_o            : out t_classes_array(g_num_ports-1 downto 0)
    );
end swc_output_traffic_shaper;

architecture syn of swc_output_traffic_shaper is

  type t_pause_array is array(integer range <>) of unsigned(15 downto 0);
  
  signal div512            : unsigned(4 downto 0);
  signal advance_counter   : std_logic; 
  
  -- per-port pause
  signal pp_pause_counters : t_pause_array(g_num_ports-1 downto 0);
  signal pp_pause_classes  : t_classes_array(g_num_ports-1 downto 0);

  -- global pause
  signal gl_pause_counters : t_pause_array(g_num_global_pause-1 downto 0);
  signal gl_pause_classes  : t_classes_array(g_num_global_pause-1 downto 0);
  signal gl_pause_ports    : t_ports_masks(g_num_global_pause-1 downto 0);
  signal zeros             : std_logic_vector(15 downto 0);

begin -- behavioral

  zeros <= (others =>'0');
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

  -- generating per-port PAUSE
  per_port_pause: for i in 0 to g_num_ports-1  generate
    -- per-port process to handle (class selectable) pause =
    pp_pause_proc : process (clk_i, rst_n_i)
    begin
      if rising_edge(clk_i) then
        if(rst_n_i = '0') then
          pp_pause_counters(i)  <= (others => '0');
          pp_pause_classes(i)     <= (others => '0');
        else 
          if (perport_pause_i(i).req = '1') then
            pp_pause_counters(i)    <= unsigned(perport_pause_i(i).quanta);
            if(perport_pause_i(i).quanta = zeros) then -- resetting PAUSE
              pp_pause_classes(i)     <= (others =>'0');
            else
              pp_pause_classes(i)     <= perport_pause_i(i).classes;
            end if;
          elsif (advance_counter = '1') then
            if(pp_pause_counters(i) = to_unsigned(0, pp_pause_counters(i)'length)) then
              pp_pause_classes(i)   <= (others => '0');
            else
              pp_pause_counters(i) <= pp_pause_counters(i) - 1;
            end if;  
          end if;  
        end if;
      end if;
    end process;
  end generate per_port_pause;

  -- generating a configurable (generic) number of global pauses
  global_pause: for i in 0 to g_num_global_pause -1 generate
    gl_pause_proc : process (clk_i, rst_n_i)
    begin
      if rising_edge(clk_i) then
        if(rst_n_i = '0') then
          gl_pause_counters(i)  <= (others => '0');
          gl_pause_classes(i)   <= (others => '0');
          gl_pause_ports(i)     <= (others => '0');
        else 
          if (global_pause_i(i).req = '1') then
            gl_pause_counters(i)  <= unsigned(global_pause_i(i).quanta);
            if(global_pause_i(i).quanta = zeros) then -- resetting PAUSE
              gl_pause_classes(i)   <= (others => '0');
              gl_pause_ports(i)     <= (others => '0');
            else
              gl_pause_classes(i)   <= global_pause_i(i).classes;
              gl_pause_ports(i)     <= global_pause_i(i).ports;
            end if;
          elsif (advance_counter = '1') then
            if(gl_pause_counters(i) = to_unsigned(0, gl_pause_counters(i)'length)) then
              gl_pause_classes(i) <= (others => '0');
              gl_pause_ports(i)   <= (others => '0');
            else
              gl_pause_counters(i) <= gl_pause_counters(i) - 1;
            end if;  
          end if;  
        end if;
      end if;
    end process;  
  end generate global_pause;

  -- generating final masks to be used on different swcore's ports to decide which
  -- queue shall be used for next forward
  gen_output_masks: for i in 0 to g_num_ports-1  generate
    output_masks_o(i) <= pp_pause_classes(i) or 
                         f_global_pause_mask(gl_pause_classes,gl_pause_ports, i, g_num_global_pause);
  end generate gen_output_masks;

end syn;
