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

entity xswc_core is
  generic
	( 
	  g_swc_num_ports      : integer := c_swc_num_ports;
	  g_swc_prio_width     : integer := c_swc_prio_width
	  
        );
  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

-------------------------------------------------------------------------------
-- pWB  : input (comes from the Endpoint)
-------------------------------------------------------------------------------

    snk_i : in  t_wrf_sink_in_array(g_swc_num_ports-1 downto 0);
    snk_o : out t_wrf_sink_out_array(g_swc_num_ports-1 downto 0);

 
-------------------------------------------------------------------------------
-- pWB : output (goes to the Endpoint)
-------------------------------------------------------------------------------  

    src_i : in  t_wrf_source_in_array(g_swc_num_ports-1 downto 0);
    src_o : out t_wrf_source_out_array(g_swc_num_ports-1 downto 0);

    
-------------------------------------------------------------------------------
-- I/F with Routing Table Unit (RTU)
-------------------------------------------------------------------------------      
    
    rtu_rsp_valid_i     : in  std_logic_vector(g_swc_num_ports  - 1 downto 0);
    rtu_rsp_ack_o       : out std_logic_vector(g_swc_num_ports  - 1 downto 0);
    rtu_dst_port_mask_i : in  std_logic_vector(g_swc_num_ports * g_swc_num_ports  - 1 downto 0);
    rtu_drop_i          : in  std_logic_vector(g_swc_num_ports  - 1 downto 0);
    rtu_prio_i          : in  std_logic_vector(g_swc_num_ports * g_swc_prio_width - 1 downto 0)

    );
end xswc_core;

architecture rtl of xswc_core is

 component swc_core is

  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

    -------------------------------------------------------------------------------
    -- Fabric I/F : input (comes from the Endpoint)
    -------------------------------------------------------------------------------

--     tx_sof_p1_i         : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
--     tx_eof_p1_i         : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
--     tx_data_i           : in  std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
--     tx_ctrl_i           : in  std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0);
--     tx_valid_i          : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
--     tx_bytesel_i        : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
--     tx_dreq_o           : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
--     tx_abort_p1_i       : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
--     tx_rerror_p1_i      : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);

    -------------------------------------------------------------------------------
    -- pWB  : input (comes from the Endpoint)
    -------------------------------------------------------------------------------

    snk_i : in  t_wrf_sink_in_array(g_swc_num_ports-1 downto 0);
    snk_o : out t_wrf_sink_out_array(g_swc_num_ports-1 downto 0);

    -------------------------------------------------------------------------------
    -- Fabric I/F : output (goes to the Endpoint)
    -------------------------------------------------------------------------------  

--     rx_sof_p1_o         : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
--     rx_eof_p1_o         : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
--     rx_dreq_i           : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
--     rx_ctrl_o           : out std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0);
--     rx_data_o           : out std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
--     rx_valid_o          : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
--     rx_bytesel_o        : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
--     rx_idle_o           : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
--     rx_rerror_p1_o      : out std_logic_vector(c_swc_num_ports  - 1 downto 0);    
--     rx_terror_p1_i      : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
--     rx_tabort_p1_i      : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);

    -------------------------------------------------------------------------------
    -- pWB : output (goes to the Endpoint)
    -------------------------------------------------------------------------------  

    src_i : in  t_wrf_source_in_array(g_swc_num_ports-1 downto 0);
    src_o : out t_wrf_source_out_array(g_swc_num_ports-1 downto 0);
    
    -------------------------------------------------------------------------------
    -- I/F with Routing Table Unit (RTU)
    -------------------------------------------------------------------------------      
    
    rtu_rsp_valid_i     : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
    rtu_rsp_ack_o       : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
    rtu_dst_port_mask_i : in  std_logic_vector(c_swc_num_ports * c_swc_num_ports  - 1 downto 0);
    rtu_drop_i          : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
    rtu_prio_i          : in  std_logic_vector(c_swc_num_ports * c_swc_prio_width - 1 downto 0)

    );
   end component;

  component xwb_fabric_sink is
  
    port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

    -- Wishbone Fabric Interface I/O
    snk_i : in  t_wrf_sink_in;
    snk_o : out t_wrf_sink_out;

    -- Decoded & buffered fabric
    addr_o    : out std_logic_vector(1 downto 0);
    data_o    : out std_logic_vector(15 downto 0);
    dvalid_o  : out std_logic;
    sof_o     : out std_logic;
    eof_o     : out std_logic;
    error_o   : out std_logic;
    bytesel_o : out std_logic;
    dreq_i    : in  std_logic
    );

  end component;


  component xwb_fabric_source is
  
    port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

    -- Wishbone Fabric Interface I/O
    src_i : in  t_wrf_source_in;
    src_o : out t_wrf_source_out;

    -- Decoded & buffered fabric
    addr_i    : in  std_logic_vector(1 downto 0);
    data_i    : in  std_logic_vector(15 downto 0);
    dvalid_i  : in  std_logic;
    sof_i     : in  std_logic;
    eof_i     : in  std_logic;
    error_i   : in  std_logic;
    bytesel_i : in  std_logic;
    dreq_o    : out std_logic
    );

  end component ;

--   signal swc_snk_sof_p1         : std_logic_vector(c_swc_num_ports - 1 downto 0);
--   signal swc_snk_eof_p1         : std_logic_vector(c_swc_num_ports - 1 downto 0);
--   signal swc_snk_dreq           : std_logic_vector(c_swc_num_ports - 1 downto 0);
--   signal swc_snk_ctrl           : std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0);
--   signal swc_snk_data           : std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
--   signal swc_snk_valid          : std_logic_vector(c_swc_num_ports - 1 downto 0);
--   signal swc_snk_bytesel        : std_logic_vector(c_swc_num_ports - 1 downto 0);
--   signal swc_snk_idle           : std_logic_vector(c_swc_num_ports - 1 downto 0);
--   signal swc_snk_rerror_p1      : std_logic_vector(c_swc_num_ports - 1 downto 0);
--   signal swc_snk_terror_p1      : std_logic_vector(c_swc_num_ports - 1 downto 0);
--   signal swc_snk_tabort_p1      : std_logic_vector(c_swc_num_ports - 1 downto 0);


--   signal swc_src_sof_p1         : std_logic_vector(c_swc_num_ports - 1 downto 0);
--   signal swc_src_eof_p1         : std_logic_vector(c_swc_num_ports - 1 downto 0);
--   signal swc_src_dreq           : std_logic_vector(c_swc_num_ports - 1 downto 0);
--   signal swc_src_ctrl           : std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0);
--   signal swc_src_data           : std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
--   signal swc_src_valid          : std_logic_vector(c_swc_num_ports - 1 downto 0);
--   signal swc_src_bytesel        : std_logic_vector(c_swc_num_ports - 1 downto 0);
--   signal swc_src_idle           : std_logic_vector(c_swc_num_ports - 1 downto 0);
--   signal swc_src_rerror_p1      : std_logic_vector(c_swc_num_ports - 1 downto 0);
--   signal swc_src_terror_p1      : std_logic_vector(c_swc_num_ports - 1 downto 0);
--   signal swc_src_tabort_p1      : std_logic_vector(c_swc_num_ports - 1 downto 0);

begin



--     gen_port_connections : for i in 0 to g_swc_num_ports-1 generate

--      swc_snk_ctrl((i+1)*c_swc_ctrl_width - 1 downto i*c_swc_ctrl_width + 2) <= (others => '0');

--      CONV_wb_to_wrf: xwb_fabric_sink 
--       
-- 	port map(
-- 	clk_i     => clk_i,
-- 	rst_n_i   => rst_n_i,
-- 	snk_i     => snk_i(i),
-- 	snk_o     => snk_o(i),
-- 	addr_o    => swc_snk_ctrl((i+1)*c_swc_ctrl_width - 3 downto i*c_swc_ctrl_width),
-- 	data_o    => swc_snk_data((i+1)*c_swc_data_width - 1 downto i*c_swc_data_width),
-- 	dvalid_o  => swc_snk_valid(i),
-- 	sof_o     => swc_snk_sof_p1(i),
-- 	eof_o     => swc_snk_eof_p1(i),
-- 	error_o   => swc_snk_rerror_p1(i),
-- 	bytesel_o => swc_snk_bytesel(i),
-- 	dreq_i    => swc_snk_dreq(i)
-- 	);

--      CONV_wrf_to_wb: xwb_fabric_source
--       
-- 	port map(
-- 	clk_i     => clk_i,
-- 	rst_n_i   => rst_n_i,
-- 	src_i     => src_i(i),
-- 	src_o     => src_o(i),
-- 	addr_i    => swc_src_ctrl((i+1)*c_swc_ctrl_width - 3 downto i*c_swc_ctrl_width),
-- 	data_i    => swc_src_data((i+1)*c_swc_data_width - 1 downto i*c_swc_data_width),
-- 	dvalid_i  => swc_src_valid(i),
-- 	sof_i     => swc_src_sof_p1(i),
-- 	eof_i     => swc_src_eof_p1(i),
-- 	error_i   => swc_src_rerror_p1(i),
-- 	bytesel_i => swc_src_bytesel(i),
-- 	dreq_o    => swc_src_dreq(i)
-- 	);

--     end generate;

--  swc_snk_tabort_p1 <= (others => '0');

--   swc_src_terror_p1 <= (others => '0');
--   swc_src_tabort_p1 <= (others => '0');

  U_swc_core: swc_core
    port map (
      clk_i               => clk_i,
      rst_n_i             => rst_n_i,

      -- this is swc_sink (input data)
--       tx_sof_p1_i         => swc_snk_sof_p1,
--       tx_eof_p1_i         => swc_snk_eof_p1,
--       tx_data_i           => swc_snk_data,
--       tx_ctrl_i           => swc_snk_ctrl,
--       tx_valid_i          => swc_snk_valid,
--       tx_bytesel_i        => swc_snk_bytesel,
--       tx_dreq_o           => swc_snk_dreq,
--       tx_abort_p1_i       => swc_snk_tabort_p1, -- fake
--       tx_rerror_p1_i      => swc_snk_rerror_p1,
      
      snk_i               => snk_i,
      snk_o               => snk_o,

      --this is swc_source (itput data)
--       rx_sof_p1_o         => swc_src_sof_p1,
--       rx_eof_p1_o         => swc_src_eof_p1,
--       rx_dreq_i           => swc_src_dreq,
--       rx_ctrl_o           => swc_src_ctrl,
--       rx_data_o           => swc_src_data,
--       rx_valid_o          => swc_src_valid,
--       rx_bytesel_o        => swc_src_bytesel,
--       rx_idle_o           => open,
--       rx_rerror_p1_o      => swc_src_rerror_p1,
--       rx_terror_p1_i      => swc_src_terror_p1,  -- fake
--       rx_tabort_p1_i      => swc_src_tabort_p1,  -- fake

      src_i               => src_i,
      src_o               => src_o,

      rtu_rsp_valid_i     => rtu_rsp_valid_i,
      rtu_rsp_ack_o       => rtu_rsp_ack_o,
      rtu_dst_port_mask_i => rtu_dst_port_mask_i,
      rtu_drop_i          => rtu_drop_i,
      rtu_prio_i          => rtu_prio_i);   

end rtl;
