-------------------------------------------------------------------------------
-- Title      : (Extended) Switch Core 
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : xswc_core.vhd
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

entity xswc_core is
  generic( 
    g_mem_size                         : integer ;--:= c_swc_packet_mem_size
    g_page_size                        : integer ;--:= c_swc_page_size
    g_prio_num                         : integer ;--:= c_swc_output_prio_num;
    g_max_pck_size                     : integer ;--:= c_swc_max_pck_size
    g_num_ports                        : integer ;--:= c_swc_num_ports
    g_data_width                       : integer ;--:= c_swc_data_width
    g_ctrl_width                       : integer ; --:= c_swc_ctrl_width
    g_pck_pg_free_fifo_size            : integer ; --:= c_swc_freeing_fifo_size (in pck_pg_free_module.vhd)
    g_input_block_cannot_accept_data   : string  ;--:= "drop_pck"; --"stall_o", "rty_o" -- (xswc_input_block) Don't CHANGE !
    g_output_block_per_prio_fifo_size  : integer ; --:= c_swc_output_fifo_size    (xswc_output_block)

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
    
    rtu_rsp_i          : in t_rtu_response_array(g_num_ports  - 1 downto 0);
    rtu_ack_o          : out std_logic_vector(g_num_ports  - 1 downto 0)

    );
end xswc_core;

architecture rtl of xswc_core is
   constant c_usecount_width        : integer := integer(CEIL(LOG2(real(g_num_ports-1))));
   constant c_prio_width            : integer := integer(CEIL(LOG2(real(g_prio_num-1)))); -- g_prio_width

   constant c_page_num              : integer := (g_mem_size / g_page_size); -- 65536/64 = 1024 -- c_swc_packet_mem_num_pages
   constant c_page_addr_width       : integer := integer(CEIL(LOG2(real(c_page_num-1)))); --c_swc_page_addr_width
   constant c_max_pck_size_width    : integer := integer(CEIL(LOG2(real(g_max_pck_size-1)))); -- c_swc_max_pck_size_width 
   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Input Block<< with >>Memory Management Unit<<
   ----------------------------------------------------------------------------------------------------
   -- Input Block -> Memory Management Unit
   signal ib_page_alloc_req   : std_logic_vector(g_num_ports - 1 downto 0);
   signal ib_pageaddr_output  : std_logic_vector(g_num_ports * c_page_addr_width - 1 downto 0);
   signal ib_set_usecnt       : std_logic_vector(g_num_ports - 1 downto 0);
   signal ib_usecnt           : std_logic_vector(g_num_ports * c_usecount_width - 1 downto 0);
   
   -- Memory Management Unit -> Input Block 
   signal mmu_page_alloc_done  : std_logic_vector(g_num_ports - 1 downto 0);
   signal mmu_pageaddr_input   : std_logic_vector(      1         * c_page_addr_width - 1 downto 0);   
   signal mmu_set_usecnt_done  : std_logic_vector(g_num_ports - 1 downto 0);
   signal mmu_nomem            : std_logic;

   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Input Block<< with >>Multiport Memory<<
   ----------------------------------------------------------------------------------------------------
   -- Input Block -> Multiport Memory
   signal ib_pckstart         : std_logic_vector(g_num_ports - 1 downto 0);
   signal ib_pageaddr_to_mpm  : std_logic_vector(g_num_ports * c_page_addr_width - 1 downto 0);
   signal ib_pagereq          : std_logic_vector(g_num_ports - 1 downto 0);
   signal ib_data             : std_logic_vector(g_num_ports * g_data_width - 1 downto 0);
   signal ib_ctrl             : std_logic_vector(g_num_ports * g_ctrl_width - 1 downto 0);
   signal ib_drdy             : std_logic_vector(g_num_ports - 1 downto 0);
   signal ib_flush            : std_logic_vector(g_num_ports - 1 downto 0);
   
   -- Multiport Memory -> Input Block
   signal mpm_pageend          : std_logic_vector(g_num_ports - 1 downto 0);
   signal mpm_full             : std_logic_vector(g_num_ports - 1 downto 0);
   signal mpm_wr_sync          : std_logic_vector(g_num_ports - 1 downto 0);
   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Input Block<< with >>Pck Transfer Arbiter<<
   ----------------------------------------------------------------------------------------------------
   -- Input Block -> Pck Transfer Arbiter
   signal ib_transfer_pck     : std_logic_vector(g_num_ports - 1 downto 0);

   signal ib_pageaddr_to_pta  : std_logic_vector(g_num_ports * c_page_addr_width - 1 downto 0);
   signal ib_mask             : std_logic_vector(g_num_ports * g_num_ports - 1 downto 0);
   signal ib_prio             : std_logic_vector(g_num_ports * c_prio_width - 1 downto 0);
   signal ib_pck_size         : std_logic_vector(g_num_ports * c_max_pck_size_width - 1 downto 0);
   
   -- Pck Transfer Arbiter -> Input Block       
   signal pta_transfer_ack    : std_logic_vector(g_num_ports - 1 downto 0);  

   
   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Output Block<< with >>Pck Transfer Arbiter<< 
   ----------------------------------------------------------------------------------------------------
   -- Input Block -> Pck Transfer Arbiter
   signal pta_data_valid             : std_logic_vector(g_num_ports -1 downto 0);
   signal pta_pageaddr               : std_logic_vector(g_num_ports * c_page_addr_width    - 1 downto 0);
   signal pta_prio                   : std_logic_vector(g_num_ports * c_prio_width         - 1 downto 0);
   signal pta_pck_size               : std_logic_vector(g_num_ports * c_max_pck_size_width - 1 downto 0);

   -- Input Block -> Pck Transfer Arbiter
   signal ob_ack                    : std_logic_vector(g_num_ports -1 downto 0);


   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Output Block<< with >>Multiport Memory<<
   ----------------------------------------------------------------------------------------------------
   -- Output Block -> Multiport Memory
   signal ob_pgreq                 : std_logic_vector(g_num_ports - 1 downto 0);
   signal ob_pgaddr                : std_logic_vector(g_num_ports * c_page_addr_width - 1 downto 0);
   signal ob_dreq                  : std_logic_vector(g_num_ports - 1 downto 0);

   -- Multiport Memory -> Output Block 
   signal mpm_pckend                : std_logic_vector(g_num_ports - 1 downto 0);
   signal mpm_pgend                 : std_logic_vector(g_num_ports - 1 downto 0);
   signal mpm_drdy                  : std_logic_vector(g_num_ports - 1 downto 0);
   
   signal mpm_data                  : std_logic_vector(g_num_ports * g_data_width - 1 downto 0);
   signal mpm_ctrl                  : std_logic_vector(g_num_ports * g_ctrl_width - 1 downto 0); 
      
   signal mpm_rd_sync               : std_logic_vector(g_num_ports - 1 downto 0);  
   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Muliport Memory<< with >>Linked List<<
   ----------------------------------------------------------------------------------------------------   
   -- Multiport Memory -> Linked List 
   signal mpm_write               : std_logic_vector(g_num_ports - 1 downto 0);
   signal mpm_write_addr          : std_logic_vector(g_num_ports * c_page_addr_width - 1 downto 0);
   signal mpm_write_data          : std_logic_vector(g_num_ports * c_page_addr_width - 1 downto 0);
  
   signal mpm_read_pump_read      : std_logic_vector(g_num_ports - 1 downto 0);
   signal mpm_read_pump_addr      : std_logic_vector(g_num_ports * c_page_addr_width - 1 downto 0);
   
   -- Linked List -> Multiport memory
--   signal ll_free_done            : std_logic_vector(g_num_ports - 1 downto 0);
   signal ll_write_done           : std_logic_vector(g_num_ports - 1 downto 0);
   signal ll_read_pump_read_done  : std_logic_vector(g_num_ports - 1 downto 0);
   signal ll_data                 : std_logic_vector(c_page_addr_width - 1 downto 0);
   
  
   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Input Block<< with >>Pck's pages freeeing module<<
   ----------------------------------------------------------------------------------------------------   
   -- Input block -> Lost pck dealloc
   signal ib_force_free         : std_logic_vector(g_num_ports - 1 downto 0);
   signal ib_force_free_pgaddr  : std_logic_vector(g_num_ports * c_page_addr_width - 1 downto 0);
      
   -- lost pck dealloc -> input block
   signal ppfm_force_free_done_to_ib  : std_logic_vector(g_num_ports - 1 downto 0);


   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Output Block<< with >>Pck's Pages Freeing Module (PPFM)<<
   ----------------------------------------------------------------------------------------------------   
   -- output block -> Lost pck dealloc
   signal ob_free         : std_logic_vector(g_num_ports - 1 downto 0);
   signal ob_free_pgaddr  : std_logic_vector(g_num_ports * c_page_addr_width - 1 downto 0);
      
   -- lost pck dealloc -> output block
   signal ppfm_free_done_to_ob  : std_logic_vector(g_num_ports - 1 downto 0);

   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Pck's pages freeeing module<< with >>Linkded List<<
   ----------------------------------------------------------------------------------------------------   
   -- LPD -> LL
   signal ppfm_read_addr         : std_logic_vector(g_num_ports * c_page_addr_width -1 downto 0);
   signal ppfm_read_req          : std_logic_vector(g_num_ports-1 downto 0);

   -- LL -> LPD
     signal ll_read_valid_data    : std_logic_vector(g_num_ports-1 downto 0);

   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Pck's pages freeing module (PPFM)<< with >>Page allocator (MMU)<<
   ----------------------------------------------------------------------------------------------------   
  -- PPFM -> MMU
   signal ppfm_force_free        : std_logic_vector(g_num_ports-1 downto 0);
   signal ppfm_force_free_pgaddr : std_logic_vector(g_num_ports * c_page_addr_width -1 downto 0);
   signal ppfm_free              : std_logic_vector(g_num_ports-1 downto 0);
   signal ppfm_free_pgaddr       : std_logic_vector(g_num_ports * c_page_addr_width -1 downto 0);
   
   -- MMU -> PPFM
   signal mmu_force_free_done   : std_logic_vector(g_num_ports-1 downto 0);
   signal mmu_free_done         : std_logic_vector(g_num_ports-1 downto 0);   
   
  
   ---- end tmp      
 
  begin --rtl
   
   ---- end timp

   
   
  gen_blocks : for i in 0 to g_num_ports-1 generate
    INPUT_BLOCK : xswc_input_block
    generic map( 
        g_page_addr_width                  => c_page_addr_width,
        g_num_ports                        => g_num_ports,
        g_prio_width                       => c_prio_width,
        g_max_pck_size_width               => c_max_pck_size_width,
        g_usecount_width                   => c_usecount_width,
        g_data_width                       => g_data_width,
        g_ctrl_width                       => g_ctrl_width,
        g_input_block_cannot_accept_data   => g_input_block_cannot_accept_data,
        g_packet_mem_multiply              => g_packet_mem_multiply,
        g_input_block_fifo_size            => g_input_block_fifo_size,
        g_input_block_fifo_full_in_advance => g_input_block_fifo_full_in_advance
      )
      port map (
        clk_i                    => clk_i,
        rst_n_i                  => rst_n_i,

        -------------------------------------------------------------------------------
        -- pWB  : input (comes from the Endpoint)
        -------------------------------------------------------------------------------
        snk_i                    => snk_i(i),
        snk_o                    => snk_o(i),

        -------------------------------------------------------------------------------
        -- I/F with Page allocator (MMU)
        -------------------------------------------------------------------------------    
        mmu_page_alloc_req_o     => ib_page_alloc_req(i),
        mmu_page_alloc_done_i    => mmu_page_alloc_done(i),
        mmu_pageaddr_i           => mmu_pageaddr_input,
                
        mmu_set_usecnt_o         => ib_set_usecnt(i),
        mmu_set_usecnt_done_i    => mmu_set_usecnt_done(i),
        mmu_usecnt_o             => ib_usecnt((i + 1) * c_usecount_width -1 downto i * c_usecount_width),
        mmu_nomem_i              => mmu_nomem,
        mmu_pageaddr_o           => ib_pageaddr_output((i + 1) * c_page_addr_width - 1 downto i * c_page_addr_width),
                
        -------------------------------------------------------------------------------
        -- I/F with Pck's Pages Freeing Module (PPFM)
        -------------------------------------------------------------------------------      
        mmu_force_free_o         => ib_force_free(i),
        mmu_force_free_done_i    => ppfm_force_free_done_to_ib(i),
        mmu_force_free_addr_o    => ib_force_free_pgaddr((i + 1) * c_page_addr_width - 1 downto i * c_page_addr_width),

        -------------------------------------------------------------------------------
        -- I/F with Routing Table Unit (RTU)
        -------------------------------------------------------------------------------      
        rtu_rsp_ack_o            => rtu_ack_o(i),        
	rtu_rsp_valid_i          => rtu_rsp_i(i).valid,
        rtu_dst_port_mask_i      => rtu_rsp_i(i).port_mask(g_num_ports  - 1 downto 0),
        rtu_drop_i               => rtu_rsp_i(i).drop,
        rtu_prio_i               => rtu_rsp_i(i).prio(c_prio_width - 1 downto 0),

        -------------------------------------------------------------------------------
        -- I/F with Multiport Memory (MPU)
        -------------------------------------------------------------------------------    
        mpm_pckstart_o           => ib_pckstart(i),
        mpm_pageaddr_o           => ib_pageaddr_to_mpm((i + 1) * c_page_addr_width - 1 downto i * c_page_addr_width),
        mpm_pagereq_o            => ib_pagereq(i),
        mpm_pageend_i            => mpm_pageend(i),
        mpm_data_o               => ib_data((i + 1) * g_data_width - 1 downto i * g_data_width),
        mpm_ctrl_o               => ib_ctrl((i + 1) * g_ctrl_width - 1 downto i * g_ctrl_width),
        mpm_drdy_o               => ib_drdy(i),
        mpm_full_i               => mpm_full(i),
        mpm_flush_o              => ib_flush(i),
        mpm_wr_sync_i            => mpm_wr_sync(i),
        -------------------------------------------------------------------------------
        -- I/F with Page Transfer Arbiter (PTA)
        -------------------------------------------------------------------------------     
        pta_transfer_pck_o       => ib_transfer_pck(i),
        pta_transfer_ack_i       => pta_transfer_ack(i),
        pta_pageaddr_o           => ib_pageaddr_to_pta((i + 1) * c_page_addr_width    -1 downto i * c_page_addr_width),
        pta_mask_o               => ib_mask           ((i + 1) * g_num_ports          -1 downto i * g_num_ports),
        pta_prio_o               => ib_prio           ((i + 1) * c_prio_width         -1 downto i * c_prio_width),
        pta_pck_size_o           => ib_pck_size       ((i + 1) * c_max_pck_size_width -1 downto i * c_max_pck_size_width)
       
        );
        
        
--    OUTPUT_BLOCK: swc_output_block 
    OUTPUT_BLOCK: xswc_output_block
      generic map( 
        g_page_addr_width                  => c_page_addr_width,
        g_max_pck_size_width               => c_max_pck_size_width,
        g_data_width                       => g_data_width,
        g_ctrl_width                       => g_ctrl_width,
        g_output_block_per_prio_fifo_size  => g_output_block_per_prio_fifo_size,
        g_prio_width                       => c_prio_width,
        g_prio_num                         => g_prio_num
      )
      port map (
        clk_i                    => clk_i,
        rst_n_i                  => rst_n_i,
        -------------------------------------------------------------------------------
        -- I/F with Page Transfer Arbiter (PTA)
        -------------------------------------------------------------------------------  
        pta_transfer_data_valid_i=> pta_data_valid(i),
        pta_pageaddr_i           => pta_pageaddr((i + 1) * c_page_addr_width    -1 downto i * c_page_addr_width),
        pta_prio_i               => pta_prio    ((i + 1) * c_prio_width         -1 downto i * c_prio_width),
        pta_pck_size_i           => pta_pck_size((i + 1) * c_max_pck_size_width -1 downto i * c_max_pck_size_width),
        pta_transfer_data_ack_o  => ob_ack(i),
        -------------------------------------------------------------------------------
        -- I/F with Multiport Memory (MPM)
        -------------------------------------------------------------------------------        
        mpm_pgreq_o              => ob_pgreq(i),
        mpm_pgaddr_o             => ob_pgaddr((i + 1) * c_page_addr_width    -1 downto i * c_page_addr_width),
        mpm_pckend_i             => mpm_pckend(i),
        mpm_pgend_i              => mpm_pgend(i),
        mpm_drdy_i               => mpm_drdy(i),
        mpm_dreq_o               => ob_dreq(i),
        mpm_data_i               => mpm_data((i + 1) * g_data_width - 1 downto i * g_data_width),
        mpm_ctrl_i               => mpm_ctrl((i + 1) * g_ctrl_width - 1 downto i * g_ctrl_width),
        mpm_sync_i               => mpm_rd_sync(i),
        -------------------------------------------------------------------------------
        -- I/F with Pck's Pages Freeing Module (PPFM)
        -------------------------------------------------------------------------------  
        ppfm_free_o              => ob_free(i),
        ppfm_free_done_i         => ppfm_free_done_to_ob(i),
        ppfm_free_pgaddr_o       => ob_free_pgaddr((i + 1) * c_page_addr_width    -1 downto i * c_page_addr_width),

        -------------------------------------------------------------------------------
        -- pWB : output (goes to the Endpoint)
        -------------------------------------------------------------------------------  

        src_i                    => src_i(i),
        src_o                    => src_o(i)
      );        
        
  end generate gen_blocks;


  PCK_PAGES_FREEEING_MODULE: swc_multiport_pck_pg_free_module
    generic map( 
      g_num_ports             => g_num_ports,
      g_page_addr_width       => c_page_addr_width,
      g_pck_pg_free_fifo_size => g_pck_pg_free_fifo_size
      )
    port map(
      clk_i                   => clk_i,
      rst_n_i                 => rst_n_i,
  
      ib_force_free_i         => ib_force_free,
      ib_force_free_done_o    => ppfm_force_free_done_to_ib,
      ib_force_free_pgaddr_i  => ib_force_free_pgaddr,
  
      ob_free_i               => ob_free,
      ob_free_done_o          => ppfm_free_done_to_ob,
      ob_free_pgaddr_i        => ob_free_pgaddr,
      
      ll_read_addr_o          => ppfm_read_addr,
      ll_read_data_i          => ll_data,
      ll_read_req_o           => ppfm_read_req,
      ll_read_valid_data_i    => ll_read_valid_data,
      
      mmu_force_free_o        => ppfm_force_free,
      mmu_force_free_done_i   => mmu_force_free_done,
      mmu_force_free_pgaddr_o => ppfm_force_free_pgaddr,
      
      mmu_free_o              => ppfm_free,
      mmu_free_done_i         => mmu_free_done,
      mmu_free_pgaddr_o       => ppfm_free_pgaddr

      );

 
 LINKED_LIST:  swc_multiport_linked_list
   generic map( 
    g_num_ports                 => g_num_ports,
    g_page_addr_width           => c_page_addr_width,
    g_page_num                  => c_page_num
    )
   port map(
     rst_n_i                    => rst_n_i,
     clk_i                      => clk_i,
 
     write_i                    => mpm_write,
     write_done_o               => ll_write_done,
     write_addr_i               => mpm_write_addr,
     write_data_i               => mpm_write_data,
       
     -- not used for the time being          
     free_i                     => (others => '0'), 
     free_done_o                => open,            
     free_addr_i                => (others => '0'), 

     read_pump_read_i           => mpm_read_pump_read,
     read_pump_read_done_o      => ll_read_pump_read_done,
     read_pump_addr_i           => mpm_read_pump_addr,

     free_pck_read_i            => ppfm_read_req,
     free_pck_read_done_o       => ll_read_valid_data,    
     free_pck_addr_i            => ppfm_read_addr,

     
     data_o                     => ll_data
 
     );
 
 ----------------------------------------------------------------------
 -- Memory Mangement Unit (MMU) 
 ----------------------------------------------------------------------
  MEMORY_MANAGEMENT_UNIT: swc_multiport_page_allocator 
    generic map( 
      g_page_addr_width         => c_page_addr_width,
      g_num_ports               => g_num_ports,
      g_page_num                => c_page_num,
      g_usecount_width          => c_usecount_width
    )
    port map (
      rst_n_i                    => rst_n_i,   
      clk_i                      => clk_i,
      
      alloc_i                    => ib_page_alloc_req,
      alloc_done_o               => mmu_page_alloc_done,
      pgaddr_alloc_o             => mmu_pageaddr_input,
      
      set_usecnt_i               => ib_set_usecnt,
      set_usecnt_done_o          => mmu_set_usecnt_done,
      usecnt_i                   => ib_usecnt,
      pgaddr_usecnt_i            => ib_pageaddr_output,  
            
      free_i                     => ppfm_free,
      free_done_o                => mmu_free_done,
      pgaddr_free_i              => ppfm_free_pgaddr,
      
      
      force_free_i               => ppfm_force_free,
      force_free_done_o          => mmu_force_free_done,
      pgaddr_force_free_i        => ppfm_force_free_pgaddr,
      
      nomem_o                    => mmu_nomem
      );
  
  
  ----------------------------------------------------------------------
  -- MultiPort Memory (MPM) [ 1 module]
  ----------------------------------------------------------------------
  MUPTIPORT_MEMORY: swc_packet_mem
    generic map( 
      g_mem_size                 => g_mem_size,
      g_num_ports                => g_num_ports,
      g_page_num                 => c_page_num,
      g_page_addr_width          => c_page_addr_width,
      g_data_width               => g_data_width,
      g_ctrl_width               => g_ctrl_width,
      g_page_size                => g_page_size,
      g_packet_mem_multiply      => g_packet_mem_multiply
      )
    port map(
      clk_i                      => clk_i,
      rst_n_i                    => rst_n_i,
      -------------------------------------------------------------------------------
      -- I/F with Input Block (IB)
      ------------------------------------------------------------------------------- 
      wr_pagereq_i               => ib_pagereq,
      wr_pckstart_i              => ib_pckstart,
      wr_pageaddr_i              => ib_pageaddr_to_mpm,
      wr_pageend_o               => mpm_pageend,
      wr_ctrl_i                  => ib_ctrl,
      wr_data_i                  => ib_data,
      wr_drdy_i                  => ib_drdy,
      wr_full_o                  => mpm_full,
      wr_flush_i                 => ib_flush,
      wr_sync_o                  => mpm_wr_sync,
      -------------------------------------------------------------------------------
      -- I/F with Output Block
      ------------------------------------------------------------------------------- 
      rd_pagereq_i               => ob_pgreq,
      rd_pageaddr_i              => ob_pgaddr,
      rd_pageend_o               => mpm_pgend,
      rd_pckend_o                => mpm_pckend,
      rd_drdy_o                  => mpm_drdy,
      rd_dreq_i                  => ob_dreq,
      --!!!!!!!!!!
      rd_sync_read_i             => ob_pgreq, -- TODO ???
      --!!!!!!!!!!!!!!!!!!
      rd_data_o                  => mpm_data,
      rd_ctrl_o                  => mpm_ctrl,
      rd_sync_o                  => mpm_rd_sync,
      
      write_o                    => mpm_write,
      write_done_i               => ll_write_done,
      write_addr_o               => mpm_write_addr,
      write_data_o               => mpm_write_data,
      
      read_pump_read_o           => mpm_read_pump_read,
      read_pump_read_done_i      => ll_read_pump_read_done,
      read_pump_addr_o           => mpm_read_pump_addr,
  
      data_i                     => ll_data
  
      );
      

  
  ----------------------------------------------------------------------
  -- Page Transfer Arbiter [ 1 module]
  ----------------------------------------------------------------------
  TRANSER_ARBITER: swc_pck_transfer_arbiter 
    generic map(
      g_page_addr_width    => c_page_addr_width,
      g_prio_width         => c_prio_width,    
      g_max_pck_size_width => c_max_pck_size_width,
      g_num_ports          => g_num_ports
      )
    port map(
      clk_i                      => clk_i,
      rst_n_i                    => rst_n_i,
      -------------------------------------------------------------------------------
      -- I/F with Output Block (OB)
      ------------------------------------------------------------------------------- 
      ob_data_valid_o            => pta_data_valid,
      ob_ack_i                   => ob_ack,
      ob_pageaddr_o              => pta_pageaddr,
      ob_prio_o                  => pta_prio,
      ob_pck_size_o              => pta_pck_size,
      -------------------------------------------------------------------------------
      -- I/F with Input Block (IB)
      ------------------------------------------------------------------------------- 
      ib_transfer_pck_i          => ib_transfer_pck,
      ib_transfer_ack_o          => pta_transfer_ack,
      ib_busy_o                  => open,
      ib_pageaddr_i              => ib_pageaddr_to_pta,
      ib_mask_i                  => ib_mask,
      ib_prio_i                  => ib_prio,
      ib_pck_size_i              => ib_pck_size
      );  



end rtl;
