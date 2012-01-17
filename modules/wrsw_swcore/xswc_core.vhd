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
-- Fabric I/F : input (comes from the Endpoint)
-------------------------------------------------------------------------------

    snk_i : in  a_wrf_sink_in(g_swc_num_ports-1 downto 0);
    snk_o : out a_wrf_sink_out(g_swc_num_ports-1 downto 0);

 
-------------------------------------------------------------------------------
-- Fabric I/F : output (goes to the Endpoint)
-------------------------------------------------------------------------------  

    src_i : in  a_wrf_source_in(g_swc_num_ports-1 downto 0);
    src_o : out a_wrf_source_out(g_swc_num_ports-1 downto 0);

    
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

    tx_sof_p1_i         : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
    tx_eof_p1_i         : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
    tx_data_i           : in  std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
    tx_ctrl_i           : in  std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0);
    tx_valid_i          : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
    tx_bytesel_i        : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
    tx_dreq_o           : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
    tx_abort_p1_i       : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
    tx_rerror_p1_i      : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);

    -------------------------------------------------------------------------------
    -- Fabric I/F : output (goes to the Endpoint)
    -------------------------------------------------------------------------------  

   rx_sof_p1_o         : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
   rx_eof_p1_o         : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
   rx_dreq_i           : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
   rx_ctrl_o           : out std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0);
   rx_data_o           : out std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
   rx_valid_o          : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
   rx_bytesel_o        : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
   rx_idle_o           : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
   rx_rerror_p1_o      : out std_logic_vector(c_swc_num_ports  - 1 downto 0);    
   rx_terror_p1_i      : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
   rx_tabort_p1_i      : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);

    
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

  component wr_wb_to_wrf is
  port(
    clk_sys_i : in std_logic;
    rst_n_i   : in std_logic;

    -- WRF source
    src_data_o     : out std_logic_vector(15 downto 0);
    src_ctrl_o     : out std_logic_vector(3 downto 0);
    src_bytesel_o  : out std_logic;
    src_dreq_i     : in  std_logic;
    src_valid_o    : out std_logic;
    src_sof_p1_o   : out std_logic;
    src_eof_p1_o   : out std_logic;
    src_error_p1_i : in  std_logic;
    src_abort_p1_o : out std_logic;

    -- Pipelined Wishbone slave
    wb_dat_i   : in  std_logic_vector(15 downto 0);
    wb_adr_i   : in  std_logic_vector(1 downto 0);
    wb_sel_i   : in  std_logic_vector(1 downto 0);
    wb_cyc_i   : in  std_logic;
    wb_stb_i   : in  std_logic;
    wb_we_i    : in  std_logic;
    wb_stall_o : out std_logic;
    wb_ack_o   : out std_logic;
    wb_err_o   : out std_logic;
    wb_rty_o   : out std_logic

    );

end component;


  --signal snk_in                  : a_wrf_sink_in(g_swc_num_ports-1 downto 0);
  --signal snk_out                  : a_wrf_sink_out(g_swc_num_ports-1 downto 0);

  --signal src_in                  : a_wrf_source_in(g_swc_num_ports-1 downto 0);
  --signal src_out                  : a_wrf_source_out(g_swc_num_ports-1 downto 0);


  signal swc_snk_sof_p1         : std_logic_vector(c_swc_num_ports - 1 downto 0);
  signal swc_snk_eof_p1         : std_logic_vector(c_swc_num_ports - 1 downto 0);
  signal swc_snk_dreq           : std_logic_vector(c_swc_num_ports - 1 downto 0);
  signal swc_snk_ctrl           : std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0);
  signal swc_snk_data           : std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
  signal swc_snk_valid          : std_logic_vector(c_swc_num_ports - 1 downto 0);
  signal swc_snk_bytesel        : std_logic_vector(c_swc_num_ports - 1 downto 0);
  signal swc_snk_idle           : std_logic_vector(c_swc_num_ports - 1 downto 0);
  signal swc_snk_rerror_p1      : std_logic_vector(c_swc_num_ports - 1 downto 0);
  signal swc_snk_terror_p1      : std_logic_vector(c_swc_num_ports - 1 downto 0);
  signal swc_snk_tabort_p1      : std_logic_vector(c_swc_num_ports - 1 downto 0);


  signal swc_src_dreq           : std_logic_vector(c_swc_num_ports - 1 downto 0);
  signal swc_src_ctrl           : std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0);
  signal swc_src_data           : std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
  signal swc_src_rerror_p1      : std_logic_vector(c_swc_num_ports - 1 downto 0);
  signal swc_src_terror_p1      : std_logic_vector(c_swc_num_ports - 1 downto 0);
  signal swc_src_tabort_p1      : std_logic_vector(c_swc_num_ports - 1 downto 0);

begin



    gen_port_connections : for i in 0 to g_swc_num_ports-1 generate

    CONV: wr_wb_to_wrf
    port map (
       clk_sys_i      => clk_i,
       rst_n_i        => rst_n_i,
  
       -- WRF source
       src_data_o     => swc_snk_data((i+1)*c_swc_data_width - 1 downto i*c_swc_data_width),
       src_ctrl_o     => swc_snk_ctrl((i+1)*c_swc_ctrl_width - 1 downto i*c_swc_ctrl_width),
       src_bytesel_o  => swc_snk_bytesel(i),
       src_dreq_i     => swc_snk_dreq(i),
       src_valid_o    => swc_snk_valid(i),
       src_sof_p1_o   => swc_snk_sof_p1(i),
       src_eof_p1_o   => swc_snk_eof_p1(i),
       src_error_p1_i => swc_snk_rerror_p1(i),
       src_abort_p1_o => swc_snk_tabort_p1(i),
  
      -- Pipelined Wishbone slave
       wb_dat_i       => snk_i(i).dat,
       wb_adr_i       => snk_i(i).adr,
       wb_sel_i       => snk_i(i).sel,
       wb_cyc_i       => snk_i(i).cyc,
       wb_stb_i       => snk_i(i).stb,
       wb_we_i        => snk_i(i).we,
       wb_stall_o     => snk_o(i).stall,
       wb_ack_o       => snk_o(i).ack,
       wb_err_o       => snk_o(i).err,
       wb_rty_o       => snk_o(i).rty
      );   

      -- it's bad, I know
      swc_src_dreq(i)       <= src_i(i).ack;
      swc_src_rerror_p1(i)  <= src_i(i).err;
      swc_src_tabort_p1(i)  <= src_i(i).err;
--      src_o(i).adr    <= swc_src_ctrl((i+1)*c_swc_ctrl_width - 1 downto i*c_swc_ctrl_width);     
--      src_o(i).dat    <= swc_src_data((i+1)*c_swc_data_width - 1 downto i*c_swc_data_width);

  end generate;



  U_SWCORE: swc_core
    port map (
      clk_i               => clk_i,
      rst_n_i             => rst_n_i,

      -- this is swc_sink (input data)
      tx_sof_p1_i         => swc_snk_sof_p1,
      tx_eof_p1_i         => swc_snk_eof_p1,
      tx_data_i           => swc_snk_data,
      tx_ctrl_i           => swc_snk_ctrl,
      tx_valid_i          => swc_snk_valid,
      tx_bytesel_i        => swc_snk_bytesel,
      tx_dreq_o           => swc_snk_dreq,
      tx_abort_p1_i       => swc_snk_tabort_p1,
      tx_rerror_p1_i      => swc_snk_rerror_p1,
      
      --this is swc_source (itput data)
      rx_sof_p1_o         => open,
      rx_eof_p1_o         => open,
      rx_dreq_i           => swc_src_dreq,  -- it's bad, I know
      rx_ctrl_o           => open, --swc_src_ctrl,
      rx_data_o           => open, --swc_src_data,
      rx_valid_o          => open,
      rx_bytesel_o        => open,
      rx_idle_o           => open,
      rx_rerror_p1_o      => open,
      rx_terror_p1_i      => swc_src_rerror_p1,
      rx_tabort_p1_i      => swc_src_tabort_p1,

      rtu_rsp_valid_i     => rtu_rsp_valid_i,
      rtu_rsp_ack_o       => rtu_rsp_ack_o,
      rtu_dst_port_mask_i => rtu_dst_port_mask_i,
      rtu_drop_i          => rtu_drop_i,
      rtu_prio_i          => rtu_prio_i);   




end rtl;
