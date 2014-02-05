-------------------------------------------------------------------------------
-- Title      : Switch Core V3
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_core_wrapper_7ports.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2012-01-15
-- Last update: 2012-02-07
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
-- 2012-02-07  1.1      mlipinsk changed name

-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.swc_swcore_pkg.all;
use work.wr_fabric_pkg.all;
use work.wrsw_shared_types_pkg.all;

entity swc_core_wrapper_7ports is
  generic
	( 
	  g_swc_num_ports      : integer := 7;
	  g_swc_prio_width     : integer := 3
	  
        );
  port (
    clk_i          : in std_logic;
    clk_mpm_core_i : in std_logic;
    rst_n_i        : in std_logic;

-------------------------------------------------------------------------------
-- Fabric I/F : input (comes from the Endpoint)
-------------------------------------------------------------------------------

    snk_dat_0_i   : in  std_logic_vector(15 downto 0);
    snk_adr_0_i   : in  std_logic_vector(1 downto 0);
    snk_sel_0_i   : in  std_logic_vector(1 downto 0);
    snk_cyc_0_i   : in  std_logic;
    snk_stb_0_i   : in  std_logic;
    snk_we_0_i    : in  std_logic;
    snk_stall_0_o : out std_logic;
    snk_ack_0_o   : out std_logic;
    snk_err_0_o   : out std_logic;
    snk_rty_0_o   : out std_logic;

    snk_dat_1_i   : in  std_logic_vector(15 downto 0);
    snk_adr_1_i   : in  std_logic_vector(1 downto 0);
    snk_sel_1_i   : in  std_logic_vector(1 downto 0);
    snk_cyc_1_i   : in  std_logic;
    snk_stb_1_i   : in  std_logic;
    snk_we_1_i    : in  std_logic;
    snk_stall_1_o : out std_logic;
    snk_ack_1_o   : out std_logic;
    snk_err_1_o   : out std_logic;
    snk_rty_1_o   : out std_logic;

    snk_dat_2_i   : in  std_logic_vector(15 downto 0);
    snk_adr_2_i   : in  std_logic_vector(1 downto 0);
    snk_sel_2_i   : in  std_logic_vector(1 downto 0);
    snk_cyc_2_i   : in  std_logic;
    snk_stb_2_i   : in  std_logic;
    snk_we_2_i    : in  std_logic;
    snk_stall_2_o : out std_logic;
    snk_ack_2_o   : out std_logic;
    snk_err_2_o   : out std_logic;
    snk_rty_2_o   : out std_logic;



    snk_dat_3_i   : in  std_logic_vector(15 downto 0);
    snk_adr_3_i   : in  std_logic_vector(1 downto 0);
    snk_sel_3_i   : in  std_logic_vector(1 downto 0);
    snk_cyc_3_i   : in  std_logic;
    snk_stb_3_i   : in  std_logic;
    snk_we_3_i    : in  std_logic;
    snk_stall_3_o : out std_logic;
    snk_ack_3_o   : out std_logic;
    snk_err_3_o   : out std_logic;
    snk_rty_3_o   : out std_logic;

    snk_dat_4_i   : in  std_logic_vector(15 downto 0);
    snk_adr_4_i   : in  std_logic_vector(1 downto 0);
    snk_sel_4_i   : in  std_logic_vector(1 downto 0);
    snk_cyc_4_i   : in  std_logic;
    snk_stb_4_i   : in  std_logic;
    snk_we_4_i    : in  std_logic;
    snk_stall_4_o : out std_logic;
    snk_ack_4_o   : out std_logic;
    snk_err_4_o   : out std_logic;
    snk_rty_4_o   : out std_logic;

    snk_dat_5_i   : in  std_logic_vector(15 downto 0);
    snk_adr_5_i   : in  std_logic_vector(1 downto 0);
    snk_sel_5_i   : in  std_logic_vector(1 downto 0);
    snk_cyc_5_i   : in  std_logic;
    snk_stb_5_i   : in  std_logic;
    snk_we_5_i    : in  std_logic;
    snk_stall_5_o : out std_logic;
    snk_ack_5_o   : out std_logic;
    snk_err_5_o   : out std_logic;
    snk_rty_5_o   : out std_logic;

    snk_dat_6_i   : in  std_logic_vector(15 downto 0);
    snk_adr_6_i   : in  std_logic_vector(1 downto 0);
    snk_sel_6_i   : in  std_logic_vector(1 downto 0);
    snk_cyc_6_i   : in  std_logic;
    snk_stb_6_i   : in  std_logic;
    snk_we_6_i    : in  std_logic;
    snk_stall_6_o : out std_logic;
    snk_ack_6_o   : out std_logic;
    snk_err_6_o   : out std_logic;
    snk_rty_6_o   : out std_logic;
 
-------------------------------------------------------------------------------
-- Fabric I/F : output (goes to the Endpoint)
-------------------------------------------------------------------------------  

    src_dat_0_o   : out std_logic_vector(15 downto 0);
    src_adr_0_o   : out std_logic_vector(1 downto 0);
    src_sel_0_o   : out std_logic_vector(1 downto 0);
    src_cyc_0_o   : out std_logic;
    src_stb_0_o   : out std_logic;
    src_we_0_o    : out std_logic;
    src_stall_0_i : in  std_logic;
    src_ack_0_i   : in  std_logic;
    src_err_0_i : in std_logic;

    src_dat_1_o   : out std_logic_vector(15 downto 0);
    src_adr_1_o   : out std_logic_vector(1 downto 0);
    src_sel_1_o   : out std_logic_vector(1 downto 0);
    src_cyc_1_o   : out std_logic;
    src_stb_1_o   : out std_logic;
    src_we_1_o    : out std_logic;
    src_stall_1_i : in  std_logic;
    src_ack_1_i   : in  std_logic;
    src_err_1_i : in std_logic;


    src_dat_2_o   : out std_logic_vector(15 downto 0);
    src_adr_2_o   : out std_logic_vector(1 downto 0);
    src_sel_2_o   : out std_logic_vector(1 downto 0);
    src_cyc_2_o   : out std_logic;
    src_stb_2_o   : out std_logic;
    src_we_2_o    : out std_logic;
    src_stall_2_i : in  std_logic;
    src_ack_2_i   : in  std_logic;
    src_err_2_i : in std_logic;

    src_dat_3_o   : out std_logic_vector(15 downto 0);
    src_adr_3_o   : out std_logic_vector(1 downto 0);
    src_sel_3_o   : out std_logic_vector(1 downto 0);
    src_cyc_3_o   : out std_logic;
    src_stb_3_o   : out std_logic;
    src_we_3_o    : out std_logic;
    src_stall_3_i : in  std_logic;
    src_ack_3_i   : in  std_logic;
    src_err_3_i : in std_logic;

    src_dat_4_o   : out std_logic_vector(15 downto 0);
    src_adr_4_o   : out std_logic_vector(1 downto 0);
    src_sel_4_o   : out std_logic_vector(1 downto 0);
    src_cyc_4_o   : out std_logic;
    src_stb_4_o   : out std_logic;
    src_we_4_o    : out std_logic;
    src_stall_4_i : in  std_logic;
    src_ack_4_i   : in  std_logic;
    src_err_4_i : in std_logic;

    src_dat_5_o   : out std_logic_vector(15 downto 0);
    src_adr_5_o   : out std_logic_vector(1 downto 0);
    src_sel_5_o   : out std_logic_vector(1 downto 0);
    src_cyc_5_o   : out std_logic;
    src_stb_5_o   : out std_logic;
    src_we_5_o    : out std_logic;
    src_stall_5_i : in  std_logic;
    src_ack_5_i   : in  std_logic;
    src_err_5_i : in std_logic;


    src_dat_6_o   : out std_logic_vector(15 downto 0);
    src_adr_6_o   : out std_logic_vector(1 downto 0);
    src_sel_6_o   : out std_logic_vector(1 downto 0);
    src_cyc_6_o   : out std_logic;
    src_stb_6_o   : out std_logic;
    src_we_6_o    : out std_logic;
    src_stall_6_i : in  std_logic;
    src_ack_6_i   : in  std_logic;
    src_err_6_i : in std_logic;

    
-------------------------------------------------------------------------------
-- I/F with Routing Table Unit (RTU)
-------------------------------------------------------------------------------      
    
    rtu_rsp_valid_i     : in  std_logic_vector(g_swc_num_ports  - 1 downto 0);
    rtu_rsp_ack_o       : out std_logic_vector(g_swc_num_ports  - 1 downto 0);
    rtu_dst_port_mask_i : in  std_logic_vector(g_swc_num_ports * g_swc_num_ports  - 1 downto 0);
    rtu_drop_i          : in  std_logic_vector(g_swc_num_ports  - 1 downto 0);
    rtu_prio_i          : in  std_logic_vector(g_swc_num_ports * g_swc_prio_width - 1 downto 0)

    );
end swc_core_wrapper_7ports;

architecture rtl of swc_core_wrapper_7ports is


    signal snk_i : t_wrf_sink_in_array(g_swc_num_ports-1 downto 0);
    signal snk_o : t_wrf_sink_out_array(g_swc_num_ports-1 downto 0);

    signal src_i : t_wrf_source_in_array(g_swc_num_ports-1 downto 0);
    signal src_o : t_wrf_source_out_array(g_swc_num_ports-1 downto 0);

    signal rtu_rsp_i     : t_rtu_response_array(g_swc_num_ports  - 1 downto 0);

begin

U_xswc_core: xswc_core
  generic map(
    g_prio_num                         => 8,
    g_output_queue_num                 => 8,
    g_max_pck_size                     => 10 * 1024,
    g_max_oob_size                     => 3,
    g_num_ports                        => 7,
    g_pck_pg_free_fifo_size            => ((65536/64)/2) ,
    g_input_block_cannot_accept_data   => "drop_pck",
    g_output_block_per_queue_fifo_size => 64,
    
    g_wb_data_width                    => 16,
    g_wb_addr_width                    => 2,
    g_wb_sel_width                     => 2,
    g_wb_ob_ignore_ack                 => false,
    
    g_mpm_mem_size                     => 65536,
    g_mpm_page_size                    => 64,
    g_mpm_ratio                        => 2,
    g_mpm_fifo_size                    => 4,
    g_mpm_fetch_next_pg_in_advance     => false,
    g_drop_outqueue_head_on_full       => true
  )
  port map(
    clk_i               => clk_i,
    clk_mpm_core_i      => clk_mpm_core_i,
    rst_n_i             => rst_n_i,

    snk_i               => snk_i,
    snk_o               => snk_o,

    src_i               => src_i,
    src_o               => src_o,

    rtu_rsp_i           => rtu_rsp_i,
    rtu_ack_o       => rtu_rsp_ack_o
    );

    rtu: for i in 0 to g_swc_num_ports -1 generate
      rtu_rsp_i(i).valid                                    <= rtu_rsp_valid_i(i);
      rtu_rsp_i(i).port_mask( c_RTU_MAX_PORTS- 1 downto  g_swc_num_ports)<= (others => '0');
      rtu_rsp_i(i).port_mask(g_swc_num_ports - 1 downto 0)  <= rtu_dst_port_mask_i((i+1)*g_swc_num_ports - 1 downto i*g_swc_num_ports);
      rtu_rsp_i(i).prio                                     <= rtu_prio_i((i+1)*g_swc_prio_width -1 downto i*g_swc_prio_width);
      rtu_rsp_i(i).drop                                     <= rtu_drop_i(i);
    end generate;
  
    snk_i(0).dat  <= snk_dat_0_i;   
    snk_i(0).adr  <= snk_adr_0_i;   
    snk_i(0).sel  <= snk_sel_0_i;   
    snk_i(0).cyc  <= snk_cyc_0_i;   
    snk_i(0).stb  <= snk_stb_0_i;   
    snk_i(0).we   <= snk_we_0_i;    
    snk_stall_0_o <= snk_o(0).stall;
    snk_ack_0_o   <= snk_o(0).ack;
    snk_err_0_o   <= snk_o(0).err;
    snk_rty_0_o   <= snk_o(0).rty;

    snk_i(1).dat  <= snk_dat_1_i;   
    snk_i(1).adr  <= snk_adr_1_i;   
    snk_i(1).sel  <= snk_sel_1_i;   
    snk_i(1).cyc  <= snk_cyc_1_i;   
    snk_i(1).stb  <= snk_stb_1_i;   
    snk_i(1).we  <= snk_we_1_i;    
    snk_stall_1_o <= snk_o(1).stall;
    snk_ack_1_o   <= snk_o(1).ack;
    snk_err_1_o   <= snk_o(1).err;
    snk_rty_1_o   <= snk_o(1).rty;

    snk_i(2).dat  <= snk_dat_2_i;   
    snk_i(2).adr  <= snk_adr_2_i;   
    snk_i(2).sel  <= snk_sel_2_i;   
    snk_i(2).cyc  <= snk_cyc_2_i;   
    snk_i(2).stb  <= snk_stb_2_i;   
    snk_i(2).we  <= snk_we_2_i;    
    snk_stall_2_o <= snk_o(2).stall;
    snk_ack_2_o   <= snk_o(2).ack;
    snk_err_2_o   <= snk_o(2).err;
    snk_rty_2_o   <= snk_o(2).rty;

    snk_i(3).dat  <= snk_dat_3_i;   
    snk_i(3).adr  <= snk_adr_3_i;   
    snk_i(3).sel  <= snk_sel_3_i;   
    snk_i(3).cyc  <= snk_cyc_3_i;   
    snk_i(3).stb  <= snk_stb_3_i;   
    snk_i(3).we  <= snk_we_3_i;    
    snk_stall_3_o <= snk_o(3).stall;
    snk_ack_3_o   <= snk_o(3).ack;
    snk_err_3_o   <= snk_o(3).err;
    snk_rty_3_o   <= snk_o(3).rty;

    snk_i(4).dat  <= snk_dat_4_i;   
    snk_i(4).adr  <= snk_adr_4_i;   
    snk_i(4).sel  <= snk_sel_4_i;   
    snk_i(4).cyc  <= snk_cyc_4_i;   
    snk_i(4).stb  <= snk_stb_4_i;   
    snk_i(4).we   <= snk_we_4_i;    
    snk_stall_4_o <= snk_o(4).stall;
    snk_ack_4_o   <= snk_o(4).ack;
    snk_err_4_o   <= snk_o(4).err;
    snk_rty_4_o   <= snk_o(4).rty;

    snk_i(5).dat  <= snk_dat_5_i;   
    snk_i(5).adr  <= snk_adr_5_i;   
    snk_i(5).sel  <= snk_sel_5_i;   
    snk_i(5).cyc  <= snk_cyc_5_i;   
    snk_i(5).stb  <= snk_stb_5_i;   
    snk_i(5).we  <= snk_we_5_i;    
    snk_stall_5_o <= snk_o(5).stall;
    snk_ack_5_o   <= snk_o(5).ack;
    snk_err_5_o   <= snk_o(5).err;
    snk_rty_5_o   <= snk_o(5).rty;

    snk_i(6).dat  <= snk_dat_6_i;   
    snk_i(6).adr  <= snk_adr_6_i;   
    snk_i(6).sel  <= snk_sel_6_i;   
    snk_i(6).cyc  <= snk_cyc_6_i;   
    snk_i(6).stb  <= snk_stb_6_i;   
    snk_i(6).we  <= snk_we_6_i;    
    snk_stall_6_o <= snk_o(6).stall;
    snk_ack_6_o   <= snk_o(6).ack;
    snk_err_6_o   <= snk_o(6).err;
    snk_rty_6_o   <= snk_o(6).rty;


    src_dat_0_o <= src_o(0).dat;   
    src_adr_0_o <= src_o(0).adr;
    src_sel_0_o <= src_o(0).sel;   
    src_cyc_0_o <= src_o(0).cyc;   
    src_stb_0_o <= src_o(0).stb;   
    src_we_0_o  <= src_o(0).we;    
    src_i(0).stall <= src_stall_0_i;
    src_i(0).ack   <= src_ack_0_i;
    src_i(0).err   <= src_err_0_i;
--    src_i(0).rty   <= src_rty_0_i;   

    src_dat_1_o <= src_o(1).dat;   
    src_adr_1_o <= src_o(1).adr;
    src_sel_1_o <= src_o(1).sel;   
    src_cyc_1_o <= src_o(1).cyc;   
    src_stb_1_o <= src_o(1).stb;   
    src_we_1_o  <= src_o(1).we;    
    src_i(1).stall <= src_stall_1_i;
    src_i(1).ack   <= src_ack_1_i;
    src_i(1).err   <= src_err_1_i;
--    src_i(1).rty   <= src_rty_1_i;

    src_dat_2_o <= src_o(2).dat;   
    src_adr_2_o <= src_o(2).adr;
    src_sel_2_o <= src_o(2).sel;   
    src_cyc_2_o <= src_o(2).cyc;   
    src_stb_2_o <= src_o(2).stb;   
    src_we_2_o  <= src_o(2).we;    
    src_i(2).stall <= src_stall_2_i;
    src_i(2).ack   <= src_ack_2_i;
    src_i(2).err   <= src_err_2_i;
--    src_i(2).rty   <= src_rty_2_i;

    src_dat_3_o <= src_o(3).dat;   
    src_adr_3_o <= src_o(3).adr;
    src_sel_3_o <= src_o(3).sel;   
    src_cyc_3_o <= src_o(3).cyc;   
    src_stb_3_o <= src_o(3).stb;   
    src_we_3_o  <= src_o(3).we;    
    src_i(3).stall <= src_stall_3_i;
    src_i(3).ack   <= src_ack_3_i;
    src_i(3).err   <= src_err_3_i;
--    src_i(3).rty   <= src_rty_3_i;

    src_dat_4_o <= src_o(4).dat;   
    src_adr_4_o <= src_o(4).adr;
    src_sel_4_o <= src_o(4).sel;   
    src_cyc_4_o <= src_o(4).cyc;   
    src_stb_4_o <= src_o(4).stb;   
    src_we_4_o  <= src_o(4).we;    
    src_i(4).stall <= src_stall_4_i;
    src_i(4).ack   <= src_ack_4_i;
    src_i(4).err   <= src_err_4_i;
--    src_i(4).rty   <= src_rty_4_i;

    src_dat_5_o <= src_o(5).dat;   
    src_adr_5_o <= src_o(5).adr;
    src_sel_5_o <= src_o(5).sel;   
    src_cyc_5_o <= src_o(5).cyc;   
    src_stb_5_o <= src_o(5).stb;   
    src_we_5_o  <= src_o(5).we;    
    src_i(5).stall <= src_stall_5_i;
    src_i(5).ack   <= src_ack_5_i;
    src_i(5).err   <= src_err_5_i;
--    src_i(5).rty   <= src_rty_5_i;

    src_dat_6_o <= src_o(6).dat;   
    src_adr_6_o <= src_o(6).adr;
    src_sel_6_o <= src_o(6).sel;   
    src_cyc_6_o <= src_o(6).cyc;   
    src_stb_6_o <= src_o(6).stb;   
    src_we_6_o  <= src_o(6).we;    
    src_i(6).stall <= src_stall_6_i;
    src_i(6).ack   <= src_ack_6_i;
    src_i(6).err   <= src_err_6_i;
--    src_i(6).rty   <= src_rty_6_i;

end rtl;
