-------------------------------------------------------------------------------
-- Title      : HSR Link Redundancy Entity - top level
-- Project    : White Rabbit
-------------------------------------------------------------------------------
-- File       : xwrsw_hsr_lre.vhd
-- Author     : José Luis Gutiérrez
-- Company    : University of Granada 
-- Department : Computer Architecture and Technology
-- Created    : 2016-01-18
-- Last update: 2016-01-18
-- Platform   : FPGA-generic
-- Standard   : VHDL '93
-------------------------------------------------------------------------------
-- Description: Struct-ized wrapper for WR HSR Link Redundancy Entity (HSR-LRE)
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

entity xwrsw_hsr_lre is

  generic(
    g_adr_width : integer := 2;
    g_dat_width : integer :=16;
    g_num_ports : integer
    );
  port(

    rst_n_i : in  std_logic;
    clk_i   : in  std_logic;

-------------------------------------------------------------------------------
-- pWB  : input (comes from the Endpoint)
-------------------------------------------------------------------------------

    ep_snk_i : in  t_wrf_sink_in_array(g_num_ports-1 downto 0);
    ep_src_i : in  t_wrf_source_in_array(g_num_ports-1 downto 0);
  

-------------------------------------------------------------------------------
-- pWB : output (goes to the Endpoint)
-------------------------------------------------------------------------------  

    ep_snk_o : out t_wrf_sink_out_array(g_num_ports-1 downto 0);
    ep_src_o : out t_wrf_source_out_array(g_num_ports-1 downto 0);
    
-------------------------------------------------------------------------------
-- pWB  : output (goes from SWCORE)
-------------------------------------------------------------------------------

    swc_src_o : out t_wrf_source_out_array(g_num_ports-1 downto 0);
    swc_snk_o : out t_wrf_sink_out_array(g_num_ports-1 downto 0);

-------------------------------------------------------------------------------
-- pWB : input (comes from SWCORE)
-------------------------------------------------------------------------------  

    swc_src_i : in  t_wrf_source_in_array(g_num_ports-1 downto 0);
    swc_snk_i : in  t_wrf_sink_in_array(g_num_ports-1 downto 0)
   

    );
end xwrsw_hsr_lre;

architecture behavioral of xwrsw_hsr_lre is

  constant c_NUM_PORTS     : integer := 8; --GUTI: to be fix
  
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

  signal CONTROL0 : std_logic_vector(35 downto 0);
  
  signal tagger_src_out	: t_wrf_source_out_array(C_NUM_PORTS downto 0);
  signal tagger_src_in	: t_wrf_source_in_array(C_NUM_PORTS downto 0);
  signal tagger_snk_out	: t_wrf_sink_out_array(C_NUM_PORTS downto 0);
  signal tagger_snk_in	: t_wrf_sink_in_array(C_NUM_PORTS downto 0);

  begin --rtl

   process(clk_i)
     begin
    --if rising_edge(clk_i) then	  
      
      -- first try
      --ep_snk_o <= swc_src_i;
      ep_src_o <= swc_snk_i;
      
      swc_snk_o <= ep_src_i;
      --swc_src_o <= ep_snk_i;
      -- end first try
      
      --ep_snk_o <= tagger_snk_out;
      --ep_src_o <= tagger_src_out;
      
      --swc_snk_o <= tagger_src_in;
      --swc_src_o <= tagger_snk_in;
      
    --end if;
  end process;
	  
	--ep_snk_o <= tagger_snk_out;
	--ep_src_o <= tagger_src_out;

	--swc_snk_o <= tagger_src_in;
	--swc_src_o <= tagger_snk_in;
  
  GEN_TAGGERS: for I in 0 to C_NUM_PORTS generate
      -- Insert HSR tag
      U_XHSR_TAGGER: xhsr_tagger
        port map (
          rst_n_i => rst_n_i,
          clk_i   => clk_i,
          snk_i   => ep_snk_i(i),
          snk_o   => ep_snk_o(i),
          src_o	  => swc_src_o(i),
          src_i   => swc_src_i(i));
    end generate;

end behavioral;
