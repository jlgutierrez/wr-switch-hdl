-------------------------------------------------------------------------------
-- Title      : Switch Core V3
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : xswc_core.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2012-01-15
-- Last update: 2012-01-15
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
-- wrapper for the V2 swcore
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2010 Maciej Lipinski / CERN
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
-- 2012-01-15  1.0      mlipinsk Created

-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.swc_swcore_pkg.all;
use work.wr_fabric_pkg.all;
use work.wrsw_shared_types_pkg.all;

entity xswc_core is
  generic
    ( 
    g_num_ports             : integer := c_swc_num_ports
    );
  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

-------------------------------------------------------------------------------
-- pWB  : input (comes from the Endpoint)
-------------------------------------------------------------------------------

    snk_i : in  t_wrf_sink_in_array(g_num_ports-1 downto 0);
    snk_o : out t_wrf_sink_out_array(g_num_ports-1 downto 0);

 
-------------------------------------------------------------------------------
-- pWB : output (goes to the Endpoint)
-------------------------------------------------------------------------------  

    src_i : in  t_wrf_source_in_array(g_num_ports-1 downto 0);
    src_o : out t_wrf_source_out_array(g_num_ports-1 downto 0);

    
-------------------------------------------------------------------------------
-- I/F with Routing Table Unit (RTU)
-------------------------------------------------------------------------------      
    
    rtu_rsp_i           : in t_rtu_response_array(g_num_ports  - 1 downto 0);
    rtu_ack_o            : out std_logic_vector(g_num_ports  - 1 downto 0)

    );
end xswc_core;

architecture rtl of xswc_core is

 component swc_core is
  generic( 
    g_page_addr_width                  : integer ;--:= c_swc_page_addr_width;
    g_prio_width                       : integer ;--:= c_swc_prio_width;
    g_max_pck_size_width               : integer ;--:= c_swc_max_pck_size_width    
    g_num_ports                        : integer ;--:= c_swc_num_ports
    g_data_width                       : integer ;--:= c_swc_data_width
    g_ctrl_width                       : integer ; --:= c_swc_ctrl_width
    g_pck_pg_free_fifo_size            : integer ; --:= c_swc_freeing_fifo_size (in pck_pg_free_module.vhd)
    g_input_block_cannot_accept_data   : string  ;--:= "drop_pck"; --"stall_o", "rty_o" -- (xswc_input_block) Don't CHANGE !
    -- probably useless with new memory
    g_packet_mem_multiply              : integer ;--:= c_swc_packet_mem_multiply (xswc_input_block, )
    g_input_block_fifo_size            : integer ;--:= c_swc_input_fifo_size     (xswc_input_block)
    g_input_block_fifo_full_in_advance : integer  --:=c_swc_fifo_full_in_advance (xswc_input_block)
    );
  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

    -------------------------------------------------------------------------------
    -- pWB  : input (comes from the Endpoint)
    -------------------------------------------------------------------------------

    snk_i : in  t_wrf_sink_in_array(g_num_ports-1 downto 0);
    snk_o : out t_wrf_sink_out_array(g_num_ports-1 downto 0);


    -------------------------------------------------------------------------------
    -- pWB : output (goes to the Endpoint)
    -------------------------------------------------------------------------------  

    src_i : in  t_wrf_source_in_array(g_num_ports-1 downto 0);
    src_o : out t_wrf_source_out_array(g_num_ports-1 downto 0);
    
    -------------------------------------------------------------------------------
    -- I/F with Routing Table Unit (RTU)
    -------------------------------------------------------------------------------      
    
    rtu_rsp_i           : in t_rtu_response_array(g_num_ports  - 1 downto 0);
    rtu_ack_o            : out std_logic_vector(g_num_ports  - 1 downto 0)

    );
   end component;



begin





  U_swc_core: swc_core
    generic map( 
      g_page_addr_width                  => c_swc_page_addr_width,
      g_prio_width                       => c_swc_prio_width,
      g_max_pck_size_width               => c_swc_max_pck_size_width,
      g_num_ports                        => c_swc_num_ports,
      g_data_width                       => c_swc_data_width,
      g_ctrl_width                       => c_swc_ctrl_width,
      g_pck_pg_free_fifo_size            => c_swc_freeing_fifo_size,
      g_input_block_cannot_accept_data   => "drop_pck", --"stall_o", "rty_o" -- (xswc_input_block) Don't CHANGE !
      g_packet_mem_multiply              => c_swc_packet_mem_multiply,
      g_input_block_fifo_size            => c_swc_input_fifo_size,     
      g_input_block_fifo_full_in_advance => c_swc_fifo_full_in_advance
    )
    port map (
      clk_i               => clk_i,
      rst_n_i             => rst_n_i,

      snk_i               => snk_i,
      snk_o               => snk_o,

      src_i               => src_i,
      src_o               => src_o,

      rtu_rsp_i           => rtu_rsp_i,
      rtu_ack_o           => rtu_ack_o);   

end rtl;
