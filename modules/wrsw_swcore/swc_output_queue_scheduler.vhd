-------------------------------------------------------------------------------
-- Title      : Output queue scheduler
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_output_queue_scheduler.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2012-04-19
-- Last update: 2012-04-19
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: this module implements output queue scheduling algorithms
-- currently the strict priority policy is used
-- 
-- This module schedules two "processes":
-- 1) sending  - decides the queue from which the next frame shall be sent
-- 2) dropping - decides the queue from which the oldest frame shall be dropped if more then 
--               single queue is full (very unlikely)
--               
-- ---------------
-- ad 1 (sending)              
-- ---------------
-- On the input we receive a vector which indicates which output queues are not empty
-- if the vector is 010100, it means that output queues number 2 and 4 have something to be sent.
-- 
-- the mapping of queues (so, what actually goes to each queue) is defined elsewhere, in 
-- swc_swcore_pkg.vhd in function: f_map_rtu_rsp_to_mmu_res().
-- 
-- > currenlty the strict scheduling policy is implemented: we always send the next frame from the < 
-- > higherst queue (presumably, with the higherst priority, but this depends on mapping)          <
-- 
-- ---------------
-- ad 2 (dropping)              
-- ---------------
-- on the input we receive a vector which indicates which output queues are full
-- if the vector is 010100, it means that output queues 2 and 4 are full
-- 
-- > currently, we always drop in the first place a frame from the lowest full queue, this means   <
-- > that for dropping we use also strict scheduling but reverse order compared to the sending     <
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 CERN / BE-CO-HT
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
-- 2012-04-19  1.0      mlipinsk Created
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


library work;
use work.swc_swcore_pkg.all;

entity swc_output_queue_scheduler is
  
  generic (
    g_queue_num       : integer range 2 to 64 := 32;
    g_queue_num_width : integer range 1 to 6  := 5);
  port (
  
    -- not needed in the simple implementation of strict priority 
    clk_i              : in std_logic; 
    rst_n_i            : in std_logic; 
    
    ----------------- reading head of the queue -----------------------    
    -- indicates which output queues are not empty
    not_empty_array_i  : in  std_logic_vector(g_queue_num-1 downto 0);
    
    -- index of the next output queue to read
    read_queue_index_o : out std_logic_vector(g_queue_num_width-1 downto 0);
    
    -- vector with '1' at the position of the output queue to read
    read_queue_onehot_o: out std_logic_vector(g_queue_num-1 downto 0);

    ----------------- dropping head of the queue -----------------------
    full_array_i       : in  std_logic_vector(g_queue_num-1 downto 0);
    
    -- index of the queue in which the first (head) data shall be dropped
    drop_queue_index_o : out std_logic_vector(g_queue_num_width-1 downto 0);
    
    -- vector with '1' at the possition(index) of the queue in which the first (head) 
    -- data shall be dropped
    drop_queue_onehot_o: out std_logic_vector(g_queue_num-1 downto 0)
    );

end swc_output_queue_scheduler;

architecture syn of swc_output_queue_scheduler is

  signal not_empty_array  : std_logic_vector(g_queue_num-1 downto 0);
  signal queue_index      : std_logic_vector(g_queue_num_width-1 downto 0);
  signal queue_onehot     : std_logic_vector(g_queue_num-1 downto 0);
 
begin 

  ------------------------------------------------------------------------------------------
  ------------------------------------- READ -----------------------------------------------
  ------------------------------------------------------------------------------------------

  -- converting so that I can use the swc_prio_encoder module as-is
  L0: for i in 0 to g_queue_num-1 generate
    not_empty_array(i)     <= not_empty_array_i(g_queue_num - 1 - i);
    read_queue_onehot_o(i) <= queue_onehot     (g_queue_num - 1 - i);   
  end generate;

  read_queue_index_o       <= not queue_index;

  --  strict priority scheduling for reading from output queues
  READ_STRICT_PRIORIY_POLICY : swc_prio_encoder
    generic map (
      g_num_inputs  => g_queue_num,
      g_output_bits => g_queue_num_width)
    port map (
      in_i     => not_empty_array,
      onehot_o => queue_onehot,
      out_o    => queue_index);

  ------------------------------------------------------------------------------------------
  ------------------------------------- DROP -----------------------------------------------
  ------------------------------------------------------------------------------------------

  --  (reverted) strict priority scheduling for dropping frames if output queues    
  --  are full. It means that if all the queues are full, we will first drop frames from the 
  --  lowest (priority) queue. this is because, this one will get emptied by the sedning 
  --  mechanims in the last place..
  DROP_STRICT_PRIORIY_POLICY  : swc_prio_encoder
    generic map (
      g_num_inputs  => g_queue_num,
      g_output_bits => g_queue_num_width)
    port map (
      in_i     => full_array_i,
      onehot_o => drop_queue_onehot_o,
      out_o    => drop_queue_index_o);      

end syn;
