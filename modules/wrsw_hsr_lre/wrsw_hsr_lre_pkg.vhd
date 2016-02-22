-------------------------------------------------------------------------------
-- Title      : HSR LRE top level package
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_hsr_lre_pkg.vhd
-- Author     : José Luis Gutiérrez
-- Company    : University of Granada
-- Created    : 2016-02-08
-- Last update: 2016-02-08
-- Platform   : FPGA-generic
-- Standard   : VHDL
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


library ieee;
use ieee.STD_LOGIC_1164.all;

use work.wr_fabric_pkg.all;
use work.wishbone_pkg.all;
use work.wrsw_txtsu_pkg.all;
use work.wrsw_shared_types_pkg.all;
use work.endpoint_pkg.all;

package wrsw_hsr_lre_pkg is


  component xhsr_tagger
    generic (
	  g_adr_width : integer := 2;
	  g_dat_width : integer :=16
	  --g_num_ports : integer
	  );
    port (

    rst_n_i : in  std_logic;
    clk_i	: in  std_logic;
    snk_i	: in  t_wrf_sink_in;
    snk_o 	: out  t_wrf_sink_out;
    src_i 	: in  t_wrf_source_in;
    src_o 	: out  t_wrf_source_out);
  end component;
  
  
  
  component wrsw_hsr_junction
	generic(
		g_adr_width : integer := 2;
		g_dat_width : integer := 16
		);
	port(
		rst_n_i			: in	std_logic;
		clk_i				: in	std_logic;
		
		ep_src_o		: out	t_wrf_source_out_array(1 downto 0);
		ep_src_i		: in	t_wrf_source_in_array(1 downto 0);

		tagger_snk_i	: in	t_wrf_sink_in_array(1 downto 0);
		tagger_snk_o	: out t_wrf_sink_out_array(1 downto 0);
		
		fwd_snk_i	: in	t_wrf_sink_in_array(1 downto 0);
		fwd_snk_o	: out t_wrf_sink_out_array(1 downto 0));
	end component;

end wrsw_hsr_lre_pkg;
