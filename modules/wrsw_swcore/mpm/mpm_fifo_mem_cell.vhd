-------------------------------------------------------------------------------
-- Title        : Distributed RAM/LUTRAM FIFO Memory Cell
-- Project      : White Rabbit Switch
-------------------------------------------------------------------------------
-- File         : mpm_fifo_mem_cell.vhd
-- Author       : Tomasz Włostowski
-- Company      : CERN BE-CO-HT
-- Created      : 2012-01-30
-- Last update  : 2012-07-17
-- Platform     : FPGA-generic
-- Standard     : VHDL'93
-- Dependencies : genram_pkg
-------------------------------------------------------------------------------
-- Description: Small RAM block inferrable as Distributed RAM.
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
-- Date        Version  Author          Description
-- 2012-01-30  1.0      twlostow        Created
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.genram_pkg.all;

entity mpm_fifo_mem_cell is
  
  generic (
    g_width : integer := 128;
    g_size  : integer := 8);

  port (
    -- write port clock
    clk_i : in std_logic;
    wa_i  : in std_logic_vector(f_log2_size(g_size)-1 downto 0);
    wd_i  : in std_logic_vector(g_width-1 downto 0);
    we_i  : in std_logic;

    -- combinatorial read port (rd_o <= mem[ra_i])
    ra_i : in  std_logic_vector(f_log2_size(g_size)-1 downto 0);
    rd_o : out std_logic_vector(g_width-1 downto 0));

end mpm_fifo_mem_cell;

architecture rtl of mpm_fifo_mem_cell is
  type t_mem_array is array(0 to g_size-1) of std_logic_vector(g_width-1 downto 0);

  signal mem : t_mem_array;

  attribute ram_style        : string;
  attribute ram_style of mem : signal is "distributed";
begin  -- rtl

  rd_o <= mem(to_integer(unsigned(ra_i)));
  p_write : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(we_i = '1') then
        mem(to_integer(unsigned(wa_i))) <= wd_i;
      end if;
    end if;
  end process;
end rtl;
