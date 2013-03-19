-------------------------------------------------------------------------------
-- Title      : Switch Core 
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_core.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-10-29
-- Last update: 2012-02-02
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
--
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
-- 2010-10-29  1.0      mlipinsk Created
-- 2012-02-02  2.0      mlipinsk generic-azed
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

entity swc_core is
  generic( 
    g_prio_num                         : integer ;--:= c_swc_output_prio_num;
    g_output_queue_num                 : integer ;
    g_max_pck_size                     : integer ;--:= 2^c_swc_max_pck_size
    g_max_oob_size                     : integer ;
    g_num_ports                        : integer ;--:= c_swc_num_ports
    g_pck_pg_free_fifo_size            : integer ; --:= c_swc_freeing_fifo_size (in pck_pg_free_module.vhd)
    g_input_block_cannot_accept_data   : string  ;--:= "drop_pck"; --"stall_o", "rty_o" -- (xswc_input_block) Don't CHANGE !
    g_output_block_per_queue_fifo_size : integer ; --:= c_swc_output_fifo_size    (xswc_output_block)
    -- new
    g_wb_data_width                    : integer ;
    g_wb_addr_width                    : integer ;
    g_wb_sel_width                     : integer ;
    g_wb_ob_ignore_ack                 : boolean ;
    g_mpm_mem_size                     : integer ;
    g_mpm_page_size                    : integer ;
    g_mpm_ratio                        : integer ;
    g_mpm_fifo_size                    : integer ;
    g_mpm_fetch_next_pg_in_advance     : boolean ;
    g_drop_outqueue_head_on_full       : boolean ;
    g_num_global_pause                 : integer ;
    g_num_dbg_vector_width             : integer
    );
  port (
    clk_i          : in std_logic;
    clk_mpm_core_i : in std_logic;
    rst_n_i        : in std_logic;

-------------------------------------------------------------------------------
-- pWB  : input (comes from the Endpoint)
-------------------------------------------------------------------------------

    snk_dat_i   : in  std_logic_vector(g_wb_data_width*g_num_ports-1 downto 0);
    snk_adr_i   : in  std_logic_vector(g_wb_addr_width*g_num_ports-1 downto 0);
    snk_sel_i   : in  std_logic_vector(g_wb_sel_width *g_num_ports-1 downto 0);
    snk_cyc_i   : in  std_logic_vector(                g_num_ports-1 downto 0);
    snk_stb_i   : in  std_logic_vector(                g_num_ports-1 downto 0);
    snk_we_i    : in  std_logic_vector(                g_num_ports-1 downto 0);
    snk_stall_o : out std_logic_vector(                g_num_ports-1 downto 0);
    snk_ack_o   : out std_logic_vector(                g_num_ports-1 downto 0);
    snk_err_o   : out std_logic_vector(                g_num_ports-1 downto 0);
    snk_rty_o   : out std_logic_vector(                g_num_ports-1 downto 0);
   
-------------------------------------------------------------------------------
-- pWB : output (goes to the Endpoint)
-------------------------------------------------------------------------------  
    src_dat_o   : out std_logic_vector(g_wb_data_width*g_num_ports-1  downto 0);
    src_adr_o   : out std_logic_vector(g_wb_addr_width*g_num_ports-1 downto 0);
    src_sel_o   : out std_logic_vector(g_wb_sel_width *g_num_ports-1 downto 0);
    src_cyc_o   : out std_logic_vector(                g_num_ports-1 downto 0);
    src_stb_o   : out std_logic_vector(                g_num_ports-1 downto 0);
    src_we_o    : out std_logic_vector(                g_num_ports-1 downto 0);
    src_stall_i : in  std_logic_vector(                g_num_ports-1 downto 0);
    src_ack_i   : in  std_logic_vector(                g_num_ports-1 downto 0);
    src_err_i   : in  std_logic_vector(                g_num_ports-1 downto 0);

------------------------------------------------------------------------------
-- I/F with Routing Table Unit (RTU)
-------------------------------------------------------------------------------      

    rtu_rsp_valid_i     : in  std_logic_vector(g_num_ports               - 1 downto 0);
    rtu_rsp_ack_o       : out std_logic_vector(g_num_ports               - 1 downto 0);
    rtu_dst_port_mask_i : in  std_logic_vector(g_num_ports * g_num_ports - 1 downto 0);
    rtu_drop_i          : in  std_logic_vector(g_num_ports               - 1 downto 0);
    rtu_prio_i          : in  std_logic_vector(g_num_ports * integer(CEIL(LOG2(real(g_prio_num-1)))) - 1 downto 0);

------------------------------------------------------------------------------
-- I/F global pause
-------------------------------------------------------------------------------      
    
    gp_req_i            : in  std_logic_vector(g_num_global_pause        - 1 downto 0);
    gp_quanta_i         : in  std_logic_vector(g_num_global_pause*16     - 1 downto 0);
    gp_classes_i        : in  std_logic_vector(g_num_global_pause*8      - 1 downto 0);
    gp_ports_i          : in  std_logic_vector(g_num_global_pause*g_num_ports- 1 downto 0);
------------------------------------------------------------------------------
-- I/F per port
-------------------------------------------------------------------------------      
    pp_req_i            : in  std_logic_vector(g_num_ports               - 1 downto 0);
    pp_quanta_i         : in  std_logic_vector(g_num_ports*16            - 1 downto 0);
    pp_classes_i        : in  std_logic_vector(g_num_ports*8             - 1 downto 0);

------------------------------------------------------------------------------
-- I/F misc
-------------------------------------------------------------------------------      

    dbg_o               : out std_logic_vector(g_num_dbg_vector_width  -1 downto 0);
    shaper_drop_at_hp_ena_i : in std_logic
    );
end swc_core;

architecture rtl of swc_core is
  
    signal snk_i : t_wrf_sink_in_array(g_num_ports-1 downto 0);
    signal snk_o : t_wrf_sink_out_array(g_num_ports-1 downto 0);

    signal src_i : t_wrf_source_in_array(g_num_ports-1 downto 0);
    signal src_o : t_wrf_source_out_array(g_num_ports-1 downto 0);

    signal rtu_rsp_i               : t_rtu_response_array(g_num_ports  - 1 downto 0);
    signal global_pause_i          : t_global_pause_request_array(g_num_global_pause-1 downto 0);
    signal perport_pause_i         : t_pause_request_array(g_num_ports-1 downto 0);
  begin --rtl
 

  xswcore: xswc_core
    generic map( 
      g_prio_num                         => g_prio_num,
      g_output_queue_num                 => g_output_queue_num,
      g_max_pck_size                     => g_max_pck_size,
      g_max_oob_size                     => g_max_oob_size,
      g_num_ports                        => g_num_ports,
      g_pck_pg_free_fifo_size            => g_pck_pg_free_fifo_size,
      g_input_block_cannot_accept_data   => g_input_block_cannot_accept_data,
      g_output_block_per_queue_fifo_size => g_output_block_per_queue_fifo_size,

      g_wb_data_width                    => g_wb_data_width,
      g_wb_addr_width                    => g_wb_addr_width,
      g_wb_sel_width                     => g_wb_sel_width,
      g_wb_ob_ignore_ack                 => g_wb_ob_ignore_ack,
      g_mpm_mem_size                     => g_mpm_mem_size,
      g_mpm_page_size                    => g_mpm_page_size,
      g_mpm_ratio                        => g_mpm_ratio,
      g_mpm_fifo_size                    => g_mpm_fifo_size,
      g_mpm_fetch_next_pg_in_advance     => g_mpm_fetch_next_pg_in_advance,
      g_drop_outqueue_head_on_full       => g_drop_outqueue_head_on_full,
      g_num_global_pause                 => g_num_global_pause,
      g_num_dbg_vector_width             => g_num_dbg_vector_width
      )
    port map(
      clk_i          => clk_i,
      clk_mpm_core_i => clk_mpm_core_i,
      rst_n_i        => rst_n_i,

      snk_i          => snk_i,
      snk_o          => snk_o,
  
      src_i          => src_i,
      src_o          => src_o,

      shaper_drop_at_hp_ena_i   => shaper_drop_at_hp_ena_i,
        
      global_pause_i => global_pause_i,
      perport_pause_i=> perport_pause_i,

      dbg_o          => dbg_o,       

      rtu_rsp_i      => rtu_rsp_i,
      rtu_ack_o      => rtu_rsp_ack_o
      );


    vectorize : for i in 0 to g_num_ports-1 generate
      snk_i(i).dat  <= snk_dat_i((i+1)*g_wb_data_width - 1 downto i*g_wb_data_width);   
      snk_i(i).adr  <= snk_adr_i((i+1)*g_wb_addr_width - 1 downto i*g_wb_addr_width);   
      snk_i(i).sel  <= snk_sel_i((i+1)*g_wb_sel_width  - 1 downto i*g_wb_sel_width);   
      snk_i(i).cyc  <= snk_cyc_i(i);   
      snk_i(i).stb  <= snk_stb_i(i);   
      snk_i(i).we   <= snk_we_i(i);    
      snk_stall_o(i)<= snk_o(i).stall;
      snk_ack_o(i)  <= snk_o(i).ack;
      snk_err_o(i)  <= snk_o(i).err;
      snk_rty_o(i)  <= snk_o(i).rty;
  
      src_dat_o((i+1)*g_wb_data_width - 1 downto i*g_wb_data_width) <= src_o(i).dat;   
      src_adr_o((i+1)*g_wb_addr_width - 1 downto i*g_wb_addr_width)  <= src_o(i).adr;
      src_sel_o((i+1)*g_wb_sel_width  - 1 downto i*g_wb_sel_width )  <= src_o(i).sel;   
      src_cyc_o(i)                        <= src_o(i).cyc;   
      src_stb_o(i)                        <= src_o(i).stb;   
      src_we_o(i)                         <= src_o(i).we;    
      src_i(i).stall                      <= src_stall_i(i);
      src_i(i).ack                        <= src_ack_i(i);
      src_i(i).err                        <= src_err_i(i);
      
      rtu_rsp_i(i).valid                                                       <= rtu_rsp_valid_i(i);
      rtu_rsp_i(i).port_mask(g_num_ports - 1 downto 0)                         <= rtu_dst_port_mask_i((i+1)*g_num_ports - 1 downto i*g_num_ports);
      rtu_rsp_i(i).drop                                                        <= rtu_drop_i(i);
      rtu_rsp_i(i).prio(integer(CEIL(LOG2(real(g_prio_num-1)))) - 1 downto 0) <= rtu_prio_i((i+1)*integer(CEIL(LOG2(real(g_prio_num-1)))) -1 downto i*integer(CEIL(LOG2(real(g_prio_num-1)))));
 
      perport_pause_i(i).req     <= pp_req_i(i);
      perport_pause_i(i).quanta  <= pp_quanta_i((i+1)*16-1 downto i*16);
      perport_pause_i(i).classes <= pp_classes_i((i+1)*8-1 downto i*8);
      
    end generate;
   
   vectorize_gp: for i in 0 to g_num_global_pause-1 generate
     
     global_pause_i(i).req                           <= gp_req_i(i);
     global_pause_i(i).quanta                        <= gp_quanta_i((i+1)*16-1 downto i*16);
     global_pause_i(i).classes                       <= gp_classes_i((i+1)*8-1 downto i*8);
     global_pause_i(i).ports(g_num_ports-1 downto 0) <= gp_ports_i((i+1)*g_num_ports-1 downto i*g_num_ports);
   
   end generate;
   
end rtl;
