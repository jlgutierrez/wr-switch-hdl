-------------------------------------------------------------------------------
-- Title        : Dual clock (asynchronous) FIFO controller
-- Project      : White Rabbit Switch
-------------------------------------------------------------------------------
-- File         : mpm_async_fifo_ctrl.vhd
-- Author       : Tomasz Włostowski
-- Company      : CERN BE-CO-HT
-- Created      : 2012-01-30
-- Last update  : 2012-01-30
-- Platform     : FPGA-generic
-- Standard     : VHDL'93
-- Dependencies : genram_pkg
-------------------------------------------------------------------------------
-- Description: Gray-encoded dual clock FIFO controller and address generator.
-- Based on Xilinx Application Note "Asynchronous FIFO in Virtex-II FPGAs" by
-- P. Alfke & Generic FIFO project by Rudolf Usselmann.
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 CERN
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
use ieee.numeric_std.all;

use work.genram_pkg.all;

entity mpm_async_fifo_ctrl is
  
  generic (
    g_size : integer);

  port(
    rst_n_a_i : in std_logic;
    clk_wr_i  : in std_logic;
    clk_rd_i  : in std_logic;

    rd_i : in std_logic;
    wr_i : in std_logic;

    wr_addr_o : out std_logic_vector(f_log2_size(g_size)-1 downto 0);
    rd_addr_o : out std_logic_vector(f_log2_size(g_size)-1 downto 0);

    full_o       : out std_logic;
    going_full_o : out std_logic;
    empty_o      : out std_logic);

end mpm_async_fifo_ctrl;

architecture rtl of mpm_async_fifo_ctrl is

  function f_bin2gray(bin : unsigned) return unsigned is
  begin
    return bin(bin'left) & (bin(bin'left-1 downto 0) xor bin(bin'left downto 1));
  end f_bin2gray;

  function f_gray2bin(gray : unsigned) return unsigned is
    variable bin : unsigned(gray'left downto 0);
  begin
    -- gray to binary
    for i in 0 to gray'left loop
      bin(i) := '0';
      for j in i to gray'left loop
        bin(i) := bin(i) xor gray(j);
      end loop;  -- j 
    end loop;  -- i
    return bin;
  end f_gray2bin;

  subtype t_counter is unsigned(f_log2_size(g_size) downto 0);

  type t_counter_block is record
    bin, bin_next, gray, gray_next : t_counter;
    bin_x, gray_x                  : t_counter;
  end record;


  signal rcb, wcb            : t_counter_block;
  signal full_int, empty_int : std_logic;
  signal going_full          : std_logic;
  
begin  -- rtl

  wcb.bin_next  <= wcb.bin + 1;
  wcb.gray_next <= f_bin2gray(wcb.bin_next);

  p_write_ptr : process(clk_wr_i, rst_n_a_i)
  begin
    if rst_n_a_i = '0' then
      wcb.bin  <= (others => '0');
      wcb.gray <= (others => '0');
    elsif rising_edge(clk_wr_i) then
      if(wr_i = '1' and full_int = '0') then
        wcb.bin  <= wcb.bin_next;
        wcb.gray <= wcb.gray_next;
      end if;
    end if;
  end process;

  rcb.bin_next  <= rcb.bin + 1;
  rcb.gray_next <= f_bin2gray(rcb.bin_next);

  p_read_ptr : process(clk_rd_i, rst_n_a_i)
  begin
    if rst_n_a_i = '0' then
      rcb.bin  <= (others => '0');
      rcb.gray <= (others => '0');
    elsif rising_edge(clk_rd_i) then
      if(rd_i = '1' and empty_int = '0') then
        rcb.bin  <= rcb.bin_next;
        rcb.gray <= rcb.gray_next;
      end if;
    end if;
  end process;

  p_sync_read_ptr : process(clk_wr_i)
  begin
    if rising_edge(clk_wr_i) then
      rcb.gray_x <= rcb.gray;
    end if;
  end process;

  p_sync_write_ptr : process(clk_rd_i)
  begin
    if rising_edge(clk_rd_i) then
      wcb.gray_x <= wcb.gray;
    end if;
  end process;

  wcb.bin_x <= f_gray2bin(wcb.gray_x);
  rcb.bin_x <= f_gray2bin(rcb.gray_x);

  p_gen_empty : process(clk_rd_i, rst_n_a_i)
  begin
    if rst_n_a_i = '0' then
      empty_int <= '1';
    elsif rising_edge (clk_rd_i) then
      if(rcb.gray = wcb.gray_x or (rd_i = '1' and (wcb.gray_x = rcb.gray_next))) then
        empty_int <= '1';
      else
        empty_int <= '0';
      end if;
    end if;
  end process;

  p_gen_going_full : process(wr_i, wcb, rcb)
  begin
    if ((wcb.bin (wcb.bin'left-2 downto 0) = rcb.bin_x(rcb.bin_x'left-2 downto 0))
        and (wcb.bin(wcb.bin'left) /= rcb.bin_x(wcb.bin_x'left))) then
      going_full <= '1';
    elsif (wr_i = '1'
           and (wcb.bin_next(wcb.bin'left-2 downto 0) = rcb.bin_x(rcb.bin_x'left-2 downto 0))
           and (wcb.bin_next(wcb.bin'left) /= rcb.bin_x(rcb.bin_x'left))) then
      going_full <= '1';
    else
      going_full <= '0';
    end if;
  end process;

  p_register_full : process(clk_wr_i, rst_n_a_i)
  begin
    if rst_n_a_i = '0' then
      full_int <= '0';
    elsif rising_edge (clk_wr_i) then
      full_int <= going_full;
    end if;
  end process;

  full_o       <= full_int;
  empty_o      <= empty_int;
  going_full_o <= going_full;

  wr_addr_o <= std_logic_vector(wcb.bin(wcb.bin'left-1 downto 0));
  rd_addr_o <= std_logic_vector(rcb.bin(rcb.bin'left-1 downto 0));
end rtl;
