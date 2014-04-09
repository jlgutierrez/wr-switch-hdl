
-------------------------------------------------------------------------------
-- Title        : Dual clock (asynchronous) asymmetric (1:N) FIFO
-- Project      : White Rabbit Switch
-------------------------------------------------------------------------------
-- File         : mpm_async_grow_fifo.vhd
-- Author       : Tomasz Włostowski
-- Company      : CERN BE-CO-HT
-- Created      : 2012-01-30
-- Last update  : 2014-02-19
-- Platform     : FPGA-generic
-- Standard     : VHDL'93
-- Dependencies : swc_fifo_mem_cell, swc_async_fifo_ctrl, genram_pkg
-------------------------------------------------------------------------------
-- Description: Asynchronous FIFO with asymmetric (deserializing) read/write
-- ports. g_ratio words written to  input port d_i are combined into a single
-- (g_ratio * g_width) word on port q_o. An additional symmetric
-- sideband channel (side_i/side_o) is provided for passing auxillary data.
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 - 2014 CERN / BE-CO-HT
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

use work.genram_pkg.all;                -- for f_log2_size

entity mpm_async_grow_fifo is
  
  generic (
    -- base data width (narrow port)
    g_width          : integer := 16;
    -- wide/narrow data width ratio
    g_ratio          : integer := 6;
    -- number of wide words in FIFO
    g_size           : integer := 4;
    -- sideband channel (side_i/side_o) width
    g_sideband_width : integer := 16);

  port (
    rst_n_a_i : in std_logic;
    clk_wr_i  : in std_logic;
    clk_rd_i  : in std_logic;

    -- 1: write word available on (d_i) to the FIFO
    we_i    : in std_logic;
    -- 1: perform an aligned write (i.e. at the beginning of the wide word)
    align_i : in std_logic;
    -- data input
    d_i     : in std_logic_vector(g_width-1 downto 0);

    -- 1: performs a read of a single wide word, outputted on q_o
    rd_i : in  std_logic;
    -- registered data output
    q_o  : out std_logic_vector(g_width * g_ratio-1 downto 0);

    -- "Sideband" channel (for passing auxillary data, such as page indices)
    side_i : in  std_logic_vector(g_sideband_width-1 downto 0);
    side_o : out std_logic_vector(g_sideband_width-1 downto 0);

    -- Full flag (clk_wr_i domain)
    full_o  : out std_logic;
    -- Empty flag (clk_rd_i domain)
    empty_o : out std_logic);

end mpm_async_grow_fifo;

architecture rtl of mpm_async_grow_fifo is

  component mpm_fifo_mem_cell
    generic (
      g_width : integer;
      g_size  : integer);
    port (
      clk_i : in  std_logic;
      wa_i  : in  std_logic_vector(f_log2_size(g_size)-1 downto 0);
      wd_i  : in  std_logic_vector(g_width-1 downto 0);
      we_i  : in  std_logic;
      ra_i  : in  std_logic_vector(f_log2_size(g_size)-1 downto 0);
      rd_o  : out std_logic_vector(g_width-1 downto 0));
  end component;

  component mpm_async_fifo_ctrl
    generic (
      g_size : integer);
    port (
      rst_n_a_i    : in  std_logic;
      clk_wr_i     : in  std_logic;
      clk_rd_i     : in  std_logic;
      rd_i         : in  std_logic;
      wr_i         : in  std_logic;
      wr_addr_o    : out std_logic_vector(f_log2_size(g_size)-1 downto 0);
      rd_addr_o    : out std_logic_vector(f_log2_size(g_size)-1 downto 0);
      full_o       : out std_logic;
      going_full_o : out std_logic;
      empty_o      : out std_logic);
  end component;

  signal wr_sreg          : std_logic_vector(g_ratio-1 downto 0);
  signal wr_cell          : std_logic_vector(g_ratio-1 downto 0);
  signal real_we          : std_logic;
  signal q_int            : std_logic_vector(g_width*g_ratio-1 downto 0);
  signal wr_addr, rd_addr : std_logic_vector(f_log2_size(g_size)-1 downto 0);
  signal full_int         : std_logic;
  signal side_comb        : std_logic_vector(g_sideband_width-1 downto 0);
  
  type t_check is array (0 to g_ratio-1) of std_logic_vector(g_width -1  downto 0);

  signal q_int_decoded: t_check;

begin  -- rtl

  -- Genrate g_ratio memory cells, which are written sequentially (each memory
  -- block corresponds to a bit in wr_cell shift register) and read all at
  -- once, forming a deserializer.
  gen_mem_cells : for i in 0 to g_ratio-1 generate

    wr_cell(i) <= wr_sreg(i) and we_i;

    q_int_decoded(i) <= q_int(g_width*(i+1) -1 downto g_width*i);

    U_Mem : mpm_fifo_mem_cell
      generic map (
        g_width => g_width,
        g_size  => g_size)
      port map (
        clk_i => clk_wr_i,
        wa_i  => wr_addr,
        wd_i  => d_i,
        we_i  => wr_cell(i),
        ra_i  => rd_addr,
        rd_o  => q_int(g_width*(i+1) -1 downto g_width*i));
  end generate gen_mem_cells;

  -- Extra memory cell for sideband channel
  U_Sideband_Mem : mpm_fifo_mem_cell
    generic map (
      g_width => g_sideband_width,
      g_size  => g_size)
    port map (
      clk_i => clk_wr_i,
      wa_i  => wr_addr,
      wd_i  => side_i,
      we_i  => real_we,
      ra_i  => rd_addr,
      rd_o  => side_comb);

  
  U_CTRL : mpm_async_fifo_ctrl
    generic map (
      g_size => g_size)
    port map (
      rst_n_a_i => rst_n_a_i,
      clk_wr_i  => clk_wr_i,
      clk_rd_i  => clk_rd_i,
      rd_i      => rd_i,
      wr_i      => real_we,
      wr_addr_o => wr_addr,
      rd_addr_o => rd_addr,
      going_full_o => full_int,
--      full_o    => full_int,
      empty_o   => empty_o);


  -- Per-cell write shift register control
  p_write_grow_sreg : process(clk_wr_i, rst_n_a_i)
  begin
    if rst_n_a_i = '0' then
      wr_sreg(0)                     <= '1';
      wr_sreg(wr_sreg'left downto 1) <= (others => '0');
    elsif rising_edge(clk_wr_i) then
      if(we_i = '1') then
        if(align_i = '1') then
          wr_sreg(0)                     <= '1';
          wr_sreg(wr_sreg'left downto 1) <= (others => '0');
        else
          wr_sreg <= wr_sreg(wr_sreg'left-1 downto 0) & wr_sreg(wr_sreg'left);
        end if;
      end if;
    end if;
  end process;

  real_we <= wr_cell(wr_cell'left) or (we_i and align_i);

  -- Output register on q_o. Memory cells are combinatorial, the register is
  -- here to improve the timing.
  p_output_reg : process(clk_rd_i)
  begin
  	if rising_edge(clk_rd_i) then
	  q_o    <= q_int;
	  side_o <= side_comb;
    end if;
  end process;

  -- full flag is only active when there's no space left in the highest memory
  -- cell
  full_o <= full_int;
  
end rtl;
