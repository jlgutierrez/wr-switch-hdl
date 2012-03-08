-------------------------------------------------------------------------------
-- Title        : Asynchronous Multi Port Memory - private package
-- Project      : White Rabbit Switch
-------------------------------------------------------------------------------
-- File         : mpm_private_pkg.vhd
-- Author       : Tomasz Włostowski
-- Company      : CERN BE-CO-HT
-- Created      : 2012-01-30
-- Last update  : 2012-01-30
-- Platform     : FPGA-generic
-- Standard     : VHDL'93
-- Dependencies : genram_pkg
-------------------------------------------------------------------------------
-- Description: Commonly used private components and functions.
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

package mpm_private_pkg is

  -----------------------------------------------------------------------------
  -- Components
  -----------------------------------------------------------------------------

  component mpm_pipelined_mux
    generic (
      g_width  : integer;
      g_inputs : integer);
    port (
      clk_i   : in  std_logic;
      rst_n_i : in  std_logic;
      d_i     : in  std_logic_vector(g_inputs * g_width-1 downto 0);
      q_o     : out std_logic_vector(g_width-1 downto 0);
      sel_i   : in  std_logic_vector(g_inputs-1 downto 0));
  end component;

  component mpm_async_grow_fifo
    generic (
      g_width          : integer;
      g_ratio          : integer;
      g_size           : integer;
      g_sideband_width : integer);
    port (
      rst_n_a_i    : in  std_logic;
      clk_wr_i     : in  std_logic;
      clk_rd_i     : in  std_logic;
      we_i         : in  std_logic;
      align_i      : in  std_logic;
      d_i          : in  std_logic_vector(g_width-1 downto 0);
      rd_i         : in  std_logic;
      q_o          : out std_logic_vector(g_width * g_ratio-1 downto 0);
      side_i       : in  std_logic_vector(g_sideband_width-1 downto 0);
      side_o       : out std_logic_vector(g_sideband_width-1 downto 0);
      full_o       : out std_logic;
      empty_o      : out std_logic);
  end component;

  component mpm_async_shrink_fifo
    generic (
      g_width          : integer;
      g_ratio          : integer;
      g_size           : integer;
      g_sideband_width : integer);
    port (
      rst_n_a_i : in  std_logic;
      clk_wr_i  : in  std_logic;
      clk_rd_i  : in  std_logic;
      we_i      : in  std_logic;
      d_i       : in  std_logic_vector(g_width*g_ratio-1 downto 0);
      rd_i      : in  std_logic;
      q_o       : out std_logic_vector(g_width-1 downto 0);
      side_i    : in  std_logic_vector(g_sideband_width-1 downto 0);
      side_o    : out std_logic_vector(g_sideband_width-1 downto 0);
      flush_i   : in  std_logic := '0';
      full_o    : out std_logic;
      empty_o   : out std_logic);
  end component;

  component mpm_async_fifo
    generic (
      g_width : integer;
      g_size  : integer);
    port (
      rst_n_a_i : in  std_logic;
      clk_wr_i  : in  std_logic;
      clk_rd_i  : in  std_logic;
      we_i      : in  std_logic;
      d_i       : in  std_logic_vector(g_width-1 downto 0);
      rd_i      : in  std_logic;
      q_o       : out std_logic_vector(g_width-1 downto 0);
      full_o    : out std_logic;
      empty_o   : out std_logic);
  end component;
  
  function f_slice (
    x     : std_logic_vector;
    index : integer;
    len   : integer) return std_logic_vector;

end mpm_private_pkg;

package body mpm_private_pkg is

  function f_slice (
    x     : std_logic_vector;
    index : integer;
    len   : integer) return std_logic_vector is
  begin
    return x((index + 1) * len - 1 downto index * len);
  end f_slice;


end mpm_private_pkg;
