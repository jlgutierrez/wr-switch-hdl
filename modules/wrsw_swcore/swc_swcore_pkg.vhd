-------------------------------------------------------------------------------
-- Title      : Switching Core Package
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_swcore_pkg.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-08
-- Last update: 2012-03-18
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2010 Tomasz Wlostowski, Maciej Lipinski / CERN
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
-- 2010-04-08  1.0      twlostow Created
-- 2010-11-22  2.0      mlipinsk added staff
-- 2012-02-02  3.0      mlipinsk generic-azed
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

library work;
use work.wr_fabric_pkg.all;
use work.wrsw_shared_types_pkg.all;
use work.genram_pkg.all;


package swc_swcore_pkg is

  type t_swcore_gen_parameters is record
    num_ports: integer;
    mem_pages: integer;
    page_size: integer;
  end record;

  type t_slv_array is array(integer range <>, integer range <>) of std_logic;

  component swc_prio_encoder
    generic (
      g_num_inputs  : integer range 2 to 64;
      g_output_bits : integer range 1 to 6);
    port (
      in_i     : in  std_logic_vector(g_num_inputs-1 downto 0);
      out_o    : out std_logic_vector(g_output_bits-1 downto 0);
      onehot_o : out std_logic_vector(g_num_inputs-1 downto 0);
      mask_o   : out std_logic_vector(g_num_inputs-1 downto 0);
      zero_o   : out std_logic);
  end component;

  component swc_rd_wr_ram
    generic (
      g_data_width : integer;
      g_size       : integer;
      g_use_native : boolean := true);
    port (
      clk_i : in  std_logic;
      rst_n_i : in std_logic := '1';
      we_i  : in  std_logic;
      wa_i  : in  std_logic_vector(f_log2_size(g_size)-1 downto 0);
      wd_i  : in  std_logic_vector(g_data_width-1 downto 0);
      ra_i  : in  std_logic_vector(f_log2_size(g_size)-1 downto 0);
      rd_o  : out std_logic_vector(g_data_width-1 downto 0));
  end component;

  component swc_page_allocator
    generic (
      g_num_pages       : integer;
      g_page_addr_width : integer;
      g_num_ports       : integer;
      g_usecount_width  : integer);
    port (
      clk_i              : in  std_logic;
      rst_n_i            : in  std_logic;
      alloc_i            : in  std_logic;
      free_i             : in  std_logic;
      force_free_i       : in  std_logic;
      set_usecnt_i       : in  std_logic;
      usecnt_i           : in  std_logic_vector(g_usecount_width-1 downto 0);
      pgaddr_i           : in  std_logic_vector(g_page_addr_width -1 downto 0);
      pgaddr_o           : out std_logic_vector(g_page_addr_width -1 downto 0);
      pgaddr_valid_o     : out std_logic;
      free_last_usecnt_o : out std_logic;
      idle_o             : out std_logic;
      done_o             : out std_logic;
      nomem_o            : out std_logic);
  end component;

  --component swc_page_allocator
  component swc_page_allocator_new
    generic (
      g_num_pages      : integer;
      g_page_addr_width: integer;
      g_num_ports      : integer ;
      g_usecount_width : integer);
    port (
      clk_i          : in  std_logic;
      rst_n_i        : in  std_logic;
      alloc_i        : in  std_logic;
      free_i         : in  std_logic;
      force_free_i   : in std_logic;
      set_usecnt_i   : in std_logic;
      usecnt_i       : in  std_logic_vector(g_usecount_width-1 downto 0);
      pgaddr_i       : in  std_logic_vector(g_page_addr_width -1 downto 0);
      pgaddr_o       : out std_logic_vector(g_page_addr_width -1 downto 0);
      free_last_usecnt_o : out std_logic;
      done_o         : out std_logic;
      nomem_o        : out std_logic);
  end component;

  component swc_rr_arbiter
    generic (
      g_num_ports      : natural;
      g_num_ports_log2 : natural);
    port (
      rst_n_i       : in  std_logic;
      clk_i         : in  std_logic;
      next_i        : in  std_logic;
      request_i     : in  std_logic_vector(g_num_ports -1 downto 0);
      grant_o       : out std_logic_vector(g_num_ports_log2 - 1 downto 0);
      grant_valid_o : out std_logic);
  end component;
 
  component swc_multiport_linked_list is
    generic ( 
      g_num_ports                        : integer; --:= c_swc_num_ports
      g_addr_width                       : integer; --:= c_swc_page_addr_width;
      g_page_num                         : integer;  --:= c_swc_packet_mem_num_pages
      g_size_width                       : integer ;
      g_partial_select_width             : integer ;
      g_data_width                       : integer
    );
    port (
      rst_n_i                : in std_logic;
      clk_i                  : in std_logic;

      write_i                : in  std_logic_vector(g_num_ports - 1 downto 0);
      write_done_o           : out std_logic_vector(g_num_ports - 1 downto 0);
      write_addr_i           : in  std_logic_vector(g_num_ports * g_addr_width - 1 downto 0);
      write_data_i           : in  std_logic_vector(g_num_ports * g_data_width - 1 downto 0);
      write_next_addr_i      : in  std_logic_vector(g_num_ports * g_addr_width - 1 downto 0);
      write_next_addr_valid_i: in  std_logic_vector(g_num_ports - 1 downto 0);

      free_pck_rd_req_i      : in  std_logic_vector(g_num_ports - 1 downto 0);
      free_pck_addr_i        : in  std_logic_vector(g_num_ports * g_addr_width - 1 downto 0);
      free_pck_read_done_o   : out std_logic_vector(g_num_ports - 1 downto 0);
      free_pck_data_o        : out std_logic_vector(g_num_ports * g_data_width - 1 downto 0);
    
      mpm_rpath_addr_i       : in  std_logic_vector(g_addr_width - 1 downto 0);
      mpm_rpath_data_o       : out std_logic_vector(g_data_width - 1 downto 0)
    );
  end component;
  
  component xswc_input_block is
  generic ( 
    g_page_addr_width                  : integer ;--:= c_swc_page_addr_width;
    g_num_ports                        : integer ;--:= c_swc_num_ports
    g_prio_width                       : integer ;--:= c_swc_prio_width;
    g_max_pck_size_width               : integer ;--:= c_swc_max_pck_size_width  
    g_max_oob_size                     : integer ;
    g_usecount_width                   : integer ;--:= c_swc_usecount_width
    g_input_block_cannot_accept_data   : string  ;--:= "drop_pck"; --"stall_o", "rty_o" -- Don't CHANGE !

    -- new
    g_mpm_data_width                   : integer ; -- it needs to be wb_data_width + wb_addr_width
    g_page_size                        : integer ;
    g_partial_select_width             : integer ;
    g_ll_data_width                    : integer ;
    g_port_index : integer
  );
  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

    snk_i : in  t_wrf_sink_in;
    snk_o : out t_wrf_sink_out;

    mmu_page_alloc_req_o : out std_logic;
    mmu_page_alloc_done_i : in std_logic;
    mmu_pageaddr_i : in std_logic_vector(g_page_addr_width - 1 downto 0);
    mmu_pageaddr_o : out std_logic_vector(g_page_addr_width - 1 downto 0);
    mmu_force_free_o     : out std_logic;
    mmu_force_free_done_i : in std_logic;
    mmu_force_free_addr_o : out std_logic_vector(g_page_addr_width - 1 downto 0);
    mmu_set_usecnt_o     : out std_logic;
    mmu_set_usecnt_done_i : in std_logic;
    mmu_usecnt_o        : out std_logic_vector(g_usecount_width - 1 downto 0);
    mmu_nomem_i         : in std_logic;

    rtu_rsp_valid_i     : in  std_logic;
    rtu_rsp_ack_o       : out std_logic;
    rtu_dst_port_mask_i : in  std_logic_vector(g_num_ports - 1 downto 0);
    rtu_drop_i          : in  std_logic;
    rtu_prio_i          : in  std_logic_vector(g_prio_width - 1 downto 0);

    mpm_data_o           : out std_logic_vector(g_mpm_data_width - 1 downto 0);
    mpm_dvalid_o         : out std_logic;
    mpm_dlast_o          : out std_logic;
    mpm_pg_addr_o        : out std_logic_vector(g_page_addr_width - 1 downto 0);
    mpm_pg_req_i         : in std_logic;
    mpm_dreq_i           : in std_logic;

    ll_addr_o : out std_logic_vector(g_page_addr_width -1 downto 0);
    ll_data_o    : out std_logic_vector(g_ll_data_width-1 downto 0);
    ll_next_addr_o : out std_logic_vector(g_page_addr_width -1 downto 0);
    ll_next_addr_valid_o   : out std_logic;
    ll_wr_req_o   : out std_logic;
    ll_wr_done_i  : in std_logic;

    pta_transfer_pck_o : out std_logic;
    pta_transfer_ack_i : in std_logic;
    pta_pageaddr_o : out std_logic_vector(g_page_addr_width - 1 downto 0);
    pta_mask_o : out std_logic_vector(g_num_ports - 1 downto 0);
    pta_pck_size_o : out std_logic_vector(g_max_pck_size_width - 1 downto 0);
    pta_prio_o : out std_logic_vector(g_prio_width - 1 downto 0);

    tap_out_o : out std_logic_vector(49+62 downto 0)

    );
  end component;

  component swc_multiport_page_allocator is
    generic ( 
      g_page_addr_width                  : integer ;--:= c_swc_page_addr_width;
      g_num_ports                        : integer ;--:= c_swc_num_ports
      g_page_num                         : integer ;--:= c_swc_packet_mem_num_pages
      g_usecount_width                   : integer --:= c_swc_usecount_width
    );  
    port (
      rst_n_i             : in std_logic;
      clk_i               : in std_logic;
      alloc_i             : in  std_logic_vector(g_num_ports - 1 downto 0);
      free_i              : in  std_logic_vector(g_num_ports - 1 downto 0);
      force_free_i        : in  std_logic_vector(g_num_ports - 1 downto 0);
      set_usecnt_i        : in  std_logic_vector(g_num_ports - 1 downto 0);
      alloc_done_o        : out std_logic_vector(g_num_ports - 1 downto 0);
      free_done_o         : out std_logic_vector(g_num_ports - 1 downto 0);
      force_free_done_o   : out std_logic_vector(g_num_ports - 1 downto 0);
      set_usecnt_done_o   : out std_logic_vector(g_num_ports - 1 downto 0);
      pgaddr_free_i       : in  std_logic_vector(g_num_ports * g_page_addr_width - 1 downto 0);
      pgaddr_force_free_i : in  std_logic_vector(g_num_ports * g_page_addr_width - 1 downto 0);
      pgaddr_usecnt_i     : in  std_logic_vector(g_num_ports * g_page_addr_width - 1 downto 0);
      usecnt_i            : in  std_logic_vector(g_num_ports * g_usecount_width - 1 downto 0);
      pgaddr_alloc_o      : out std_logic_vector(g_page_addr_width-1 downto 0);
      free_last_usecnt_o  : out std_logic_vector(g_num_ports - 1 downto 0);
      nomem_o             : out std_logic;
      tap_out_o :out std_logic_vector(62 + 49 downto 0)
      );
  
  end component;
    
  component swc_pck_transfer_input is
    generic(
      g_page_addr_width    : integer ;--:= c_swc_page_addr_width;
      g_prio_width         : integer ;--:= c_swc_prio_width;
      g_max_pck_size_width : integer ;--:= c_swc_max_pck_size_width    
      g_num_ports          : integer  --:= c_swc_num_ports
    );
    port (
      clk_i              : in std_logic;
      rst_n_i            : in std_logic;
      
      pto_transfer_pck_o : out  std_logic;
      pto_pageaddr_o     : out  std_logic_vector(g_page_addr_width - 1 downto 0);
      pto_output_mask_o  : out  std_logic_vector(g_num_ports - 1 downto 0);
      pto_read_mask_i    : in  std_logic_vector(g_num_ports - 1 downto 0);
      pto_prio_o         : out  std_logic_vector(g_prio_width - 1 downto 0);
      pto_pck_size_o     : out  std_logic_vector(g_max_pck_size_width - 1 downto 0);
      
      ib_transfer_pck_i  : in  std_logic;
      ib_pageaddr_i      : in  std_logic_vector(g_page_addr_width - 1 downto 0);
      ib_mask_i          : in  std_logic_vector(g_num_ports - 1 downto 0);
      ib_prio_i          : in  std_logic_vector(g_prio_width - 1 downto 0);
      ib_pck_size_i      : in  std_logic_vector(g_max_pck_size_width - 1 downto 0);
      ib_transfer_ack_o  : out std_logic;
      ib_busy_o          : out std_logic
      
      );
  end component;  
  
  component swc_pck_transfer_output is
    generic(
      g_page_addr_width    : integer ;--:= g_page_addr_width;
      g_prio_width         : integer ;--:= c_swc_prio_width;
      g_max_pck_size_width : integer --:= c_swc_max_pck_size_width
      );
    port (
      clk_i                    : in  std_logic;
      rst_n_i                  : in  std_logic;
      
      ob_transfer_data_valid_o : out std_logic;
      ob_pageaddr_o            : out std_logic_vector(g_page_addr_width - 1 downto 0);
      ob_prio_o                : out std_logic_vector(g_prio_width - 1 downto 0);
      ob_pck_size_o            : out std_logic_vector(g_max_pck_size_width - 1 downto 0);
      ob_transfer_data_ack_i   : in  std_logic;
      
      pti_transfer_data_valid_i: in  std_logic;
      pti_transfer_data_ack_o  : out std_logic;
      pti_pageaddr_i           : in  std_logic_vector(g_page_addr_width - 1 downto 0);
      pti_prio_i               : in  std_logic_vector(g_prio_width - 1 downto 0);
      pti_pck_size_i           : in  std_logic_vector(g_max_pck_size_width - 1 downto 0)
      
      );
  end component;
  
  component swc_pck_transfer_arbiter is
    generic(
      g_page_addr_width    : integer ;--:= c_swc_page_addr_width;
      g_prio_width         : integer ;--:= c_swc_prio_width;
      g_max_pck_size_width : integer ;--:= c_swc_max_pck_size_width    
      g_num_ports          : integer  --:= c_swc_num_ports
      );
    port (
      clk_i              : in  std_logic;
      rst_n_i            : in  std_logic;
      
      ob_data_valid_o    : out std_logic_vector(g_num_ports - 1 downto 0);
      ob_ack_i           : in  std_logic_vector(g_num_ports - 1 downto 0);
      ob_pageaddr_o      : out std_logic_vector(g_num_ports * g_page_addr_width    - 1 downto 0);
      ob_prio_o          : out std_logic_vector(g_num_ports * g_prio_width         - 1 downto 0);
      ob_pck_size_o      : out std_logic_vector(g_num_ports * g_max_pck_size_width - 1 downto 0);
      
      ib_transfer_pck_i  : in  std_logic_vector(g_num_ports - 1 downto 0);
      ib_transfer_ack_o  : out std_logic_vector(g_num_ports - 1 downto 0);
      ib_busy_o          : out std_logic_vector(g_num_ports - 1 downto 0);  
      ib_pageaddr_i      : in  std_logic_vector(g_num_ports * g_page_addr_width    - 1 downto 0);
      ib_mask_i          : in  std_logic_vector(g_num_ports * g_num_ports          - 1 downto 0);
      ib_prio_i          : in  std_logic_vector(g_num_ports * g_prio_width         - 1 downto 0);
      ib_pck_size_i      : in  std_logic_vector(g_num_ports * g_max_pck_size_width - 1 downto 0)
      );  
  end component;
  
  component swc_ob_prio_queue is
    generic(
      g_per_prio_fifo_size_width : integer --:= c_swc_output_fifo_addr_width
      );
    port (
      clk_i             : in   std_logic;
      rst_n_i           : in   std_logic;
      write_i           : in   std_logic;
      read_i            : in   std_logic;
      not_full_o        : out  std_logic;
      not_empty_o       : out  std_logic;
      wr_en_o           : out  std_logic;
      wr_addr_o         : out  std_logic_vector(g_per_prio_fifo_size_width - 1 downto 0);
      rd_addr_o         : out  std_logic_vector(g_per_prio_fifo_size_width - 1 downto 0)
      );
  end component;
  
  component xswc_output_block is
    generic ( 
      g_max_pck_size_width               : integer ;--:= c_swc_max_pck_size_width  
      g_output_block_per_prio_fifo_size  : integer ;--:= c_swc_output_fifo_size
      g_prio_width                       : integer ;--:= c_swc_prio_width;, c_swc_output_prio_num_width
      g_prio_num                         : integer ;--:= c_swc_output_prio_num
      -- new stuff
      g_mpm_page_addr_width              : integer ;--:= c_swc_page_addr_width;
      g_mpm_data_width                   : integer ;--:= c_swc_page_addr_width;
      g_mpm_partial_select_width         : integer ;
      g_mpm_fetch_next_pg_in_advance     : boolean := false;
      g_wb_data_width                    : integer ;
      g_wb_addr_width                    : integer ;
      g_wb_sel_width                     : integer ;
      g_wb_ob_ignore_ack                 : boolean := true                 
    );
    port (
      clk_i   : in std_logic;
      rst_n_i : in std_logic;
      pta_transfer_data_valid_i : in   std_logic;
      pta_pageaddr_i            : in   std_logic_vector(g_mpm_page_addr_width - 1 downto 0);
      pta_prio_i                : in   std_logic_vector(g_prio_width - 1 downto 0);
      pta_transfer_data_ack_o   : out  std_logic;
      mpm_d_i        : in  std_logic_vector (g_mpm_data_width -1 downto 0);
      mpm_dvalid_i   : in  std_logic;
      mpm_dlast_i    : in  std_logic;
      mpm_dsel_i     : in  std_logic_vector (g_mpm_partial_select_width -1 downto 0);
      mpm_dreq_o     : out std_logic;
      mpm_abort_o    : out std_logic;
      mpm_pg_addr_o  : out std_logic_vector (g_mpm_page_addr_width -1 downto 0);
      mpm_pg_valid_o : out std_logic;
      mpm_pg_req_i   : in  std_logic;   
      ppfm_free_o            : out  std_logic;
      ppfm_free_done_i       : in   std_logic;
      ppfm_free_pgaddr_o     : out  std_logic_vector(g_mpm_page_addr_width - 1 downto 0);
      src_i : in  t_wrf_source_in;
      src_o : out t_wrf_source_out;
      tap_out_o : out std_logic_vector(15 downto 0)

      );
  end component;

component  swc_multiport_pck_pg_free_module is
  generic( 
    g_num_ports             : integer ; --:= c_swc_num_ports
    g_page_addr_width       : integer ;--:= c_swc_page_addr_width;
    g_pck_pg_free_fifo_size : integer ;--:= c_swc_freeing_fifo_size
    g_data_width            : integer
      ); 
  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

    ib_force_free_i         : in  std_logic_vector(g_num_ports-1 downto 0);
    ib_force_free_done_o    : out std_logic_vector(g_num_ports-1 downto 0);
    ib_force_free_pgaddr_i  : in  std_logic_vector(g_num_ports * g_page_addr_width - 1 downto 0);

    ob_free_i               : in  std_logic_vector(g_num_ports-1 downto 0);
    ob_free_done_o          : out std_logic_vector(g_num_ports-1 downto 0);
    ob_free_pgaddr_i        : in  std_logic_vector(g_num_ports * g_page_addr_width - 1 downto 0);
    
    ll_read_addr_o          : out std_logic_vector(g_num_ports * g_page_addr_width -1 downto 0);
    ll_read_data_i          : in  std_logic_vector(g_num_ports * g_data_width      - 1 downto 0);
    --ll_read_data_i          : in  std_logic_vector(g_page_addr_width - 1 downto 0);
    ll_read_req_o           : out std_logic_vector(g_num_ports-1 downto 0);
    ll_read_valid_data_i    : in  std_logic_vector(g_num_ports-1 downto 0);

    mmu_free_o              : out std_logic_vector(g_num_ports-1 downto 0);
    mmu_free_done_i         : in  std_logic_vector(g_num_ports-1 downto 0);
    mmu_free_pgaddr_o       : out std_logic_vector(g_num_ports * g_page_addr_width -1 downto 0);
    mmu_free_last_usecnt_i  : in  std_logic_vector(g_num_ports-1 downto 0);

    mmu_force_free_o        : out std_logic_vector(g_num_ports-1 downto 0);
    mmu_force_free_done_i   : in  std_logic_vector(g_num_ports-1 downto 0);
    mmu_force_free_pgaddr_o : out std_logic_vector(g_num_ports * g_page_addr_width -1 downto 0)
    );
  end component;

  component swc_pck_pg_free_module is
    generic( 
      g_page_addr_width       : integer ;--:= c_swc_page_addr_width;
      g_pck_pg_free_fifo_size : integer ;--:= c_swc_freeing_fifo_size
      g_data_width            : integer
      );  
    port (
      clk_i   : in std_logic;
      rst_n_i : in std_logic;
  
      ib_force_free_i         : in  std_logic;
      ib_force_free_done_o    : out std_logic;
      ib_force_free_pgaddr_i  : in  std_logic_vector(g_page_addr_width - 1 downto 0);
  
      ob_free_i               : in  std_logic;
      ob_free_done_o          : out std_logic;
      ob_free_pgaddr_i        : in  std_logic_vector(g_page_addr_width - 1 downto 0);
      
      ll_read_addr_o          : out std_logic_vector(g_page_addr_width -1 downto 0);
      ll_read_data_i          : in  std_logic_vector(g_data_width      - 1 downto 0);
      ll_read_req_o           : out std_logic;
      ll_read_valid_data_i    : in  std_logic;
  
      mmu_free_o              : out std_logic;
      mmu_free_done_i         : in  std_logic;
      mmu_free_pgaddr_o       : out std_logic_vector(g_page_addr_width -1 downto 0);
      mmu_free_last_usecnt_i  : in  std_logic;
      
      mmu_force_free_o        : out std_logic;
      mmu_force_free_done_i   : in  std_logic;
      mmu_force_free_pgaddr_o : out std_logic_vector(g_page_addr_width -1 downto 0)
      );
  end component;
  
  component xswc_core is
    generic( 
      g_prio_num                         : integer ;--:= c_swc_output_prio_num;
      g_max_pck_size                     : integer ;--:= c_swc_max_pck_size
      g_max_oob_size                     : integer ;
      g_num_ports                        : integer ;--:= c_swc_num_ports
      g_pck_pg_free_fifo_size            : integer ; --:= c_swc_freeing_fifo_size (in pck_pg_free_module.vhd)
      g_input_block_cannot_accept_data   : string  ;--:= "drop_pck"; --"stall_o", "rty_o" -- (xswc_input_block) Don't CHANGE !
      g_output_block_per_prio_fifo_size  : integer ; --:= c_swc_output_fifo_size    (xswc_output_block)

      -- new
      g_wb_data_width                    : integer ;
      g_wb_addr_width                    : integer ;
      g_wb_sel_width                     : integer ;
      g_wb_ob_ignore_ack                 : boolean ;
      
      g_mpm_mem_size                     : integer ;
      g_mpm_page_size                    : integer ;
      g_mpm_ratio                        : integer ;
      g_mpm_fifo_size                    : integer ;
      g_mpm_fetch_next_pg_in_advance     : boolean
      );
   port (
      clk_i          : in std_logic;
      clk_mpm_core_i : in std_logic;
      rst_n_i        : in std_logic;
  
      snk_i          : in  t_wrf_sink_in_array(g_num_ports-1 downto 0);
      snk_o          : out t_wrf_sink_out_array(g_num_ports-1 downto 0);
  
      src_i          : in  t_wrf_source_in_array(g_num_ports-1 downto 0);
      src_o          : out t_wrf_source_out_array(g_num_ports-1 downto 0);
      
      rtu_rsp_i      : in t_rtu_response_array(g_num_ports  - 1 downto 0);
      rtu_ack_o      : out std_logic_vector(g_num_ports  - 1 downto 0)
      );
  end component;

  component swc_ll_read_data_validation is
    generic(
      g_addr_width : integer ;--:= c_swc_page_addr_width;
      g_data_width : integer --:= c_swc_page_addr_width
      );
    port(
      clk_i                 : in std_logic;
      rst_n_i               : in std_logic;

      read_req_i            : in std_logic;
      read_req_o            : out std_logic;
      read_addr_i           : in std_logic_vector(g_addr_width - 1 downto 0);
      read_data_i           : in std_logic_vector(g_data_width - 1 downto 0);
      read_data_valid_i     : in std_logic;
      read_data_ready_i     : in std_logic;
     
      write_addr_i          : in std_logic_vector(g_addr_width - 1 downto 0);
      write_data_i          : in std_logic_vector(g_data_width - 1 downto 0);
      write_data_valid_i    : in std_logic;
      write_data_ready_i    : in std_logic;

      read_data_o          : out std_logic_vector(g_data_width - 1 downto 0);
      read_data_valid_o    : out std_logic
  );
  end component;

  function f_sel2partialSel(sel       : std_logic_vector; partialSelWidth: integer) return std_logic_vector;
  function f_partialSel2sel(partialSel: std_logic_vector; selWidth       : integer) return std_logic_vector;

end swc_swcore_pkg;

package body swc_swcore_pkg is

  function f_sel2partialSel(sel : std_logic_vector; partialSelWidth: integer) return std_logic_vector is
    variable tmp : std_logic_vector(partialSelWidth -1 downto 0);
    variable ones: std_logic_vector(sel'length -1 downto 0);
  begin
    -- this function needs proper implementation
    ones := (others =>'1');
    if(sel = ones) then
      tmp := (others =>'1');
    else
      tmp := (others =>'0');
    end if;
    return tmp;
  end function;  

  function f_partialSel2sel(partialSel: std_logic_vector; selWidth       : integer) return std_logic_vector is
    variable tmp  : std_logic_vector(selWidth -1 downto 0);
    variable ones : std_logic_vector(partialSel'length -1 downto 0);
  begin
    -- this function needs proper implementation
    ones := (others =>'1');
    if(partialSel = ones) then
      tmp := (others =>'1');
    else
      tmp(selWidth-1)          := '1';
      tmp(selWidth-2 downto 0) := (others =>'0');
    end if;
    return tmp;
  end function; 

end swc_swcore_pkg;
