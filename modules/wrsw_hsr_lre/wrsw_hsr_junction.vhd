-------------------------------------------------------------------------------
-- Title      : HSR Link Redundancy Entity - Junction
-- Project    : White Rabbit
-------------------------------------------------------------------------------
-- File       : wrsw_hsr_junction.vhd
-- Author     : 
-- Company    :  
-- Department : 
-- Created    : 2016-02-22
-- Last update: 2016-02-22
-- Platform   : FPGA-generic
-- Standard   : VHDL '93
-------------------------------------------------------------------------------
-- Description: this module acts as a carrefour where outbound traffic from
-- different data flows is routed and prioritised:
--   - Traffic from one HSR tagger will be sent through both HSR enabled EPs.
--   - Traffic from one Forwarding unit will be sent through the opposite
--     HSR enabled EP.
--   - Priority is given to traffic coming from Forwarding units
-------------------------------------------------------------------------------
--
-- Copyright (c) 2011 - 2012 CERN / BE-CO-HT
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
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

library work;
use work.swc_swcore_pkg.all;
use work.wr_fabric_pkg.all;
use work.wrsw_shared_types_pkg.all;
use work.mpm_pkg.all;
use work.wrsw_hsr_lre_pkg.all;

entity wrsw_hsr_junction is

  generic(
    g_adr_width : integer := 2;
    g_dat_width : integer :=16
    );
  port(
  
	 	rst_n_i			: in	std_logic;
		clk_i				: in	std_logic;
		
		-- Towards endpoints Tx
		ep_src_o		: out	t_wrf_source_out_array(1 downto 0);
		ep_src_i		: in	t_wrf_source_in_array(1 downto 0);
		
		-- From hsr taggers
		tagger_snk_i	: in	t_wrf_sink_in_array(1 downto 0);
		tagger_snk_o	: out t_wrf_sink_out_array(1 downto 0);
		
		-- From HSR forwarding units
		fwd_snk_i	: in	t_wrf_sink_in_array(1 downto 0);
		fwd_snk_o	: out t_wrf_sink_out_array(1 downto 0)

    );
end wrsw_hsr_junction;

architecture behavioral of wrsw_hsr_junction is

  constant c_NUM_PORTS     : integer := 8; 
  
  component chipscope_icon
    port (
      CONTROL0 : inout std_logic_vector(35 downto 0));
  end component;
  component chipscope_ila
    port (
      CONTROL : inout std_logic_vector(35 downto 0);
      CLK     : in    std_logic;
      TRIG0   : in    std_logic_vector(31 downto 0);
      TRIG1   : in    std_logic_vector(31 downto 0);
      TRIG2   : in    std_logic_vector(31 downto 0);
      TRIG3   : in    std_logic_vector(31 downto 0));
  end component;
  
  component wrsw_hsr_arbfromtaggers
	port(
		rst_n_i			: in	std_logic;
		clk_i				: in	std_logic;
		
		-- Towards endpoints Tx
		ep_src_o		: out	t_wrf_source_out_array(1 downto 0);
		ep_src_i		: in	t_wrf_source_in_array(1 downto 0);
		
		-- From hsr taggers
		tagger_snk_i	: in	t_wrf_sink_in_array(1 downto 0);
		tagger_snk_o	: out t_wrf_sink_out_array(1 downto 0));
	end component;
	

  signal CONTROL0 : std_logic_vector(35 downto 0);
  signal TRIG0		: std_logic_vector(31 downto 0);
  signal TRIG1		: std_logic_vector(31 downto 0);
  signal TRIG2		: std_logic_vector(31 downto 0);
  signal TRIG3		: std_logic_vector(31 downto 0);
  
  signal tagger_snk_in		: t_wrf_source_out_array(1 downto 0);
  signal ep_src_in			: t_wrf_source_in_array(1 downto 0);

  begin --rtl
	
	U_from_taggers : wrsw_hsr_arbfromtaggers
	port map(
		rst_n_i  		=> rst_n_i,
		clk_i				=> clk_i,
		ep_src_o 		=> ep_src_o,
		ep_src_i 		=> ep_src_i,
		tagger_snk_i 	=> tagger_snk_i,
		tagger_snk_o 	=> tagger_snk_o
	);


end behavioral;
