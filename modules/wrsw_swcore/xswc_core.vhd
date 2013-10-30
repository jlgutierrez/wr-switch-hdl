-------------------------------------------------------------------------------
-- Title      : (Extended) Switch Core 
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : xswc_core.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-10-29
-- Last update: 2012-03-18
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
use work.mpm_pkg.all;

entity xswc_core is
  generic( 

    g_prio_num                         : integer ;--:= c_swc_output_prio_num; [works only for value of 8, output_block-causes problem]
    g_output_queue_num                 : integer ;
    g_max_pck_size                     : integer ;-- in 16bits words --:= c_swc_max_pck_size
    g_max_oob_size                     : integer ;
    g_num_ports                        : integer ;--:= c_swc_num_ports
    g_pck_pg_free_fifo_size            : integer ; --:= c_swc_freeing_fifo_size (in pck_pg_free_module.vhd)
    g_input_block_cannot_accept_data   : string  ;--:= "drop_pck"; --"stall_o", "rty_o" -- (xswc_input_block) Don't CHANGE !
    g_output_block_per_queue_fifo_size  : integer ; --:= c_swc_output_fifo_size    (xswc_output_block)

    -- new
    g_wb_data_width                    : integer ;
    g_wb_addr_width                    : integer ;
    g_wb_sel_width                     : integer ;
    g_wb_ob_ignore_ack                 : boolean := true ;
    g_mpm_mem_size                     : integer ; -- in 16bits words 
    g_mpm_page_size                    : integer ; -- in 16bits words 
    g_mpm_ratio                        : integer ;
    g_mpm_fifo_size                    : integer ;
    g_mpm_fetch_next_pg_in_advance     : boolean ;
    g_drop_outqueue_head_on_full       : boolean ;
    g_num_global_pause                 : integer := 2;
    g_num_dbg_vector_width             : integer := 8
    );
  port (
    clk_i          : in std_logic;
    clk_mpm_core_i : in std_logic;
    rst_n_i        : in std_logic;

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
-- I/F with Traffich shaper
-------------------------------------------------------------------------------     
    
    global_pause_i            : in  t_global_pause_request_array(g_num_global_pause-1 downto 0);
    
    shaper_drop_at_hp_ena_i   : in  std_logic := '0';

-------------------------------------------------------------------------------
-- I/F with Tx PAUSE triggers (i.e. Endpoints)
-------------------------------------------------------------------------------   

    perport_pause_i           : in  t_pause_request_array(g_num_ports-1 downto 0);

-------------------------------------------------------------------------------
-- Debug vector
-------------------------------------------------------------------------------      
  
   dbg_o                      : out std_logic_vector(g_num_dbg_vector_width - 1 downto 0);
   
-------------------------------------------------------------------------------
-- I/F with Routing Table Unit (RTU)
-------------------------------------------------------------------------------      
    
    rtu_rsp_i                 : in t_rtu_response_array(g_num_ports  - 1 downto 0);
    rtu_ack_o                 : out std_logic_vector(g_num_ports  - 1 downto 0)

    );
end xswc_core;

architecture rtl of xswc_core is
   constant c_usecount_width        : integer := integer(CEIL(LOG2(real(g_num_ports+1))));
   constant c_prio_width            : integer := integer(CEIL(LOG2(real(g_prio_num-1)))); -- g_prio_width
   constant c_output_queue_num_width: integer := integer(CEIL(LOG2(real(g_output_queue_num-1))));
   constant c_max_pck_size_width    : integer := integer(CEIL(LOG2(real(g_max_pck_size-1)))); -- c_swc_max_pck_size_width 
   constant c_max_oob_size_width    : integer := integer(CEIL(LOG2(real(g_max_oob_size + 1))));

   constant c_mpm_page_num          : integer := integer(CEIL(real(g_mpm_mem_size / g_mpm_page_size))); -- 65536/64 = 1024 -- c_swc_packet_mem_num_pages
   constant c_mpm_page_addr_width   : integer := integer(CEIL(LOG2(real(c_mpm_page_num-1)))); --c_swc_page_addr_width
   constant c_mpm_data_width        : integer := integer(g_wb_data_width + g_wb_addr_width);
   constant c_mpm_partial_sel_width : integer := integer(g_wb_sel_width-1);
   constant c_mpm_page_size_width   : integer := integer(CEIL(LOG2(real(g_mpm_page_size-1))));

   constant c_ll_addr_width         : integer := c_mpm_page_addr_width;
   constant c_ll_data_width         : integer := c_mpm_page_addr_width + c_max_oob_size_width + 3;

   -- resource management -----------------------
   constant c_res_mmu_max_pck_size            : integer := 759; -- in 16 bit words (1518 [octets])/(2 [octets])
   constant c_res_mmu_special_res_num_pages   : integer := 256; 
   constant c_res_mmu_resource_num            : integer := 3;   -- (1) unknown; (2) special; (3) normal
   constant c_res_mmu_resource_num_width      : integer := 2;
   ----------------------------------------------
   constant c_hwdu_input_block_width          : integer := 16;
   constant c_hwdu_mmu_width                  : integer := 10*3;

   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Input Block<< with >>Memory Management Unit<<
   ----------------------------------------------------------------------------------------------------
   -- Input Block -> Memory Management Unit
   signal ib_page_alloc_req   : std_logic_vector(g_num_ports - 1 downto 0);
   signal ib_pageaddr_output  : std_logic_vector(g_num_ports * c_mpm_page_addr_width - 1 downto 0);
   signal ib_set_usecnt       : std_logic_vector(g_num_ports - 1 downto 0);
   signal ib_usecnt_set       : std_logic_vector(g_num_ports * c_usecount_width - 1 downto 0);
   signal ib_usecnt_alloc     : std_logic_vector(g_num_ports * c_usecount_width - 1 downto 0);
   
   -- Memory Management Unit -> Input Block 
   signal mmu_page_alloc_done  : std_logic_vector(g_num_ports - 1 downto 0);
   signal mmu_pageaddr_input   : std_logic_vector(      1         * c_mpm_page_addr_width - 1 downto 0);   
   signal mmu_set_usecnt_done  : std_logic_vector(g_num_ports - 1 downto 0);
   signal mmu_nomem            : std_logic;

   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Input Block<< with >>Multiport Memory<<
   ----------------------------------------------------------------------------------------------------
   -- Input Block -> Multiport Memory (new)
   signal ib2mpm_data         : std_logic_vector(g_num_ports * c_mpm_data_width - 1 downto 0);
   signal ib2mpm_dvalid       : std_logic_vector(g_num_ports - 1 downto 0);
   signal ib2mpm_dlast        : std_logic_vector(g_num_ports - 1 downto 0);
   signal ib2mpm_pg_addr      : std_logic_vector(g_num_ports * c_mpm_page_addr_width - 1 downto 0);
   -- Multiport Memory -> Input Block (new)
   signal mpm2ib_pg_req       : std_logic_vector(g_num_ports - 1 downto 0);
   signal mpm2ib_dreq         : std_logic_vector(g_num_ports - 1 downto 0);
   
   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Input Block<< with >>Pck Transfer Arbiter<<
   ----------------------------------------------------------------------------------------------------
   -- Input Block -> Pck Transfer Arbiter
   signal ib_transfer_pck     : std_logic_vector(g_num_ports - 1 downto 0);

   signal ib_pageaddr_to_pta  : std_logic_vector(g_num_ports * c_mpm_page_addr_width - 1 downto 0);
   signal ib_mask             : std_logic_vector(g_num_ports * g_num_ports - 1 downto 0);
   signal ib_prio             : std_logic_vector(g_num_ports * c_prio_width - 1 downto 0);
--    signal ib_pck_size         : std_logic_vector(g_num_ports * c_max_pck_size_width - 1 downto 0);
   signal ib_hp               : std_logic_vector(g_num_ports  -1 downto 0);
   
   -- Pck Transfer Arbiter -> Input Block       
   signal pta_transfer_ack    : std_logic_vector(g_num_ports - 1 downto 0);  

   
   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Output Block<< with >>Pck Transfer Arbiter<< 
   ----------------------------------------------------------------------------------------------------
   -- Input Block -> Pck Transfer Arbiter
   signal pta_data_valid             : std_logic_vector(g_num_ports -1 downto 0);
   signal pta_pageaddr               : std_logic_vector(g_num_ports * c_mpm_page_addr_width- 1 downto 0);
   signal pta_prio                   : std_logic_vector(g_num_ports * c_prio_width         - 1 downto 0);
--    signal pta_pck_size               : std_logic_vector(g_num_ports * c_max_pck_size_width - 1 downto 0);

   signal pta2ob_hp                  : std_logic_vector(g_num_ports -1 downto 0);
   signal pta2ob_resource            : std_logic_vector(g_num_ports *c_res_mmu_resource_num_width -1 downto 0);

   -- Input Block -> Pck Transfer Arbiter
   signal ob_ack                    : std_logic_vector(g_num_ports -1 downto 0);


   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Output Block<< with >>Multiport Memory<<
   ----------------------------------------------------------------------------------------------------
   -- Output Block -> Multiport Memory
   signal mpm2ob_d                  : std_logic_vector (g_num_ports * c_mpm_data_width -1 downto 0);
   signal mpm2ob_dvalid             : std_logic_vector (g_num_ports-1 downto 0);
   signal mpm2ob_dlast              : std_logic_vector (g_num_ports-1 downto 0);
   signal mpm2ob_dsel               : std_logic_vector (g_num_ports * c_mpm_partial_sel_width -1 downto 0);
   signal mpm2ob_pg_req             : std_logic_vector (g_num_ports-1 downto 0);   
   signal ob2mpm_dreq               : std_logic_vector (g_num_ports-1 downto 0);
   signal ob2mpm_abort              : std_logic_vector (g_num_ports-1 downto 0);
   signal ob2mpm_pg_addr            : std_logic_vector (g_num_ports * c_mpm_page_addr_width -1 downto 0);
   signal ob2mpm_pg_valid           : std_logic_vector (g_num_ports-1 downto 0);

   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Muliport Memory<< with >>Linked List<< (old)
   ----------------------------------------------------------------------------------------------------   
   -- Multiport Memory -> Linked List 
   signal mpm_write               : std_logic_vector(g_num_ports - 1 downto 0);
   signal mpm_write_addr          : std_logic_vector(g_num_ports * c_mpm_page_addr_width - 1 downto 0);
   signal mpm_write_data          : std_logic_vector(g_num_ports * c_mpm_page_addr_width - 1 downto 0);
  
   signal mpm_read_pump_read      : std_logic_vector(g_num_ports - 1 downto 0);
   signal mpm_read_pump_addr      : std_logic_vector(g_num_ports * c_mpm_page_addr_width - 1 downto 0);
   
   signal mpm2ll_addr             : std_logic_vector(c_ll_addr_width - 1 downto 0);
   signal ll2mpm_data             : std_logic_vector(c_ll_data_width - 1 downto 0);
   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Input Block<< with >>Linked List<< (new)
   ----------------------------------------------------------------------------------------------------   
   signal ib2ll_addr              : std_logic_vector(g_num_ports*c_ll_addr_width - 1 downto 0);
   signal ib2ll_data              : std_logic_vector(g_num_ports*c_ll_data_width - 1 downto 0);
   
   signal ib2ll_next_addr         : std_logic_vector(g_num_ports*c_ll_addr_width - 1 downto 0);
   signal ib2ll_next_addr_valid   : std_logic_vector(g_num_ports                 - 1 downto 0);

   signal ib2ll_wr_req            : std_logic_vector(g_num_ports                 - 1 downto 0);
   signal ll2ib_wr_done           : std_logic_vector(g_num_ports                 - 1 downto 0);   
  
   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Input Block<< with >>Pck's pages freeeing module<<
   ----------------------------------------------------------------------------------------------------   
   -- Input block -> Lost pck dealloc
   signal ib_force_free         : std_logic_vector(g_num_ports - 1 downto 0);
   signal ib_force_free_pgaddr  : std_logic_vector(g_num_ports * c_mpm_page_addr_width - 1 downto 0);
      
   -- lost pck dealloc -> input block
   signal ppfm_force_free_done_to_ib  : std_logic_vector(g_num_ports - 1 downto 0);


   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Output Block<< with >>Pck's Pages Freeing Module (PPFM)<<
   ----------------------------------------------------------------------------------------------------   
   -- output block -> Lost pck dealloc
   signal ob_free         : std_logic_vector(g_num_ports - 1 downto 0);
   signal ob_free_pgaddr  : std_logic_vector(g_num_ports * c_mpm_page_addr_width - 1 downto 0);
      
   -- lost pck dealloc -> output block
   signal ppfm_free_done_to_ob  : std_logic_vector(g_num_ports - 1 downto 0);

   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Pck's pages freeeing module<< with >>Linkded List<<
   ----------------------------------------------------------------------------------------------------   
   -- LPD -> LL
   signal ppfm_read_addr         : std_logic_vector(g_num_ports * c_mpm_page_addr_width -1 downto 0);
   signal ppfm_read_req          : std_logic_vector(g_num_ports-1 downto 0);

   -- LL -> LPD
   signal ll_read_valid_data    : std_logic_vector(g_num_ports-1 downto 0);

   -- new Free Pck (FP) module <-> Linked List (LL)
   signal fp2ll_rd_req          : std_logic_vector(g_num_ports - 1 downto 0);
   signal fp2ll_addr            : std_logic_vector(g_num_ports * c_ll_addr_width - 1 downto 0);
   signal ll2fp_read_done       : std_logic_vector(g_num_ports - 1 downto 0);
   signal ll2fp_data            : std_logic_vector(g_num_ports * c_ll_data_width - 1 downto 0);

   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Pck's pages freeing module (PPFM)<< with >>Page allocator (MMU)<<
   ----------------------------------------------------------------------------------------------------   
  -- PPFM -> MMU
   signal ppfm_force_free        : std_logic_vector(g_num_ports-1 downto 0);
   signal ppfm_force_free_pgaddr : std_logic_vector(g_num_ports * c_mpm_page_addr_width -1 downto 0);
   signal ppfm_free              : std_logic_vector(g_num_ports-1 downto 0);
   signal ppfm_free_pgaddr       : std_logic_vector(g_num_ports * c_mpm_page_addr_width -1 downto 0);
   
   -- MMU -> PPFM
   signal mmu_force_free_done   : std_logic_vector(g_num_ports-1 downto 0);
   signal mmu_free_done         : std_logic_vector(g_num_ports-1 downto 0);   
   signal mmu2ppfm_free_last_usecnt : std_logic_vector(g_num_ports-1 downto 0);   
  
   -- output_traffic_shaper -> output_block
   signal ots2ob_output_masks   : t_classes_array(g_num_ports-1 downto 0);
 
   -- 
   type t_tap_ib_array is array(0 to g_num_ports-1) of std_logic_vector(49+62 downto 0);
   type t_tap_ob_array is array(0 to g_num_ports-1) of std_logic_vector(15 downto 0);
   signal tap_mpm : std_logic_vector(61 downto 0);
   

   signal tap_ib : t_tap_ib_array;
   signal tap_ob : t_tap_ob_array;
   signal tap_alloc : std_logic_vector(62 + 49 downto 0);
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
   signal tap : std_logic_vector(127 downto 0);


   signal ppfm2mmu_free_resource              : std_logic_vector(g_num_ports*c_res_mmu_resource_num_width -1 downto 0);
   signal ppfm2mmu_free_resource_valid        : std_logic_vector(g_num_ports                              -1 downto 0);
   signal ppfm2mmu_force_free_resource        : std_logic_vector(g_num_ports*c_res_mmu_resource_num_width -1 downto 0);
   signal ppfm2mmu_force_free_resource_valid  : std_logic_vector(g_num_ports                              -1 downto 0);

   signal mmu2ppfm_resource                   : std_logic_vector(g_num_ports*c_res_mmu_resource_num_width   -1 downto 0);
   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Input Block (IB) << with >>Page allocator (MMU)<< -- resource management 
   ----------------------------------------------------------------------------------------------------   

   signal mmu2ib_resource             : std_logic_vector(g_num_ports*c_res_mmu_resource_num_width   -1 downto 0);
   signal ib2mmu_resource             : std_logic_vector(g_num_ports*c_res_mmu_resource_num_width   -1 downto 0);
   signal ib2mmu_rescnt_page_num      : std_logic_vector(g_num_ports*c_mpm_page_addr_width          -1 downto 0);
   signal mmu2ib_res_full             : std_logic_vector(g_num_ports*c_res_mmu_resource_num         -1 downto 0);
   signal mmu2ib_res_almost_full      : std_logic_vector(g_num_ports*c_res_mmu_resource_num         -1 downto 0);
   signal mmu2ib_set_usecnt_succeeded : std_logic_vector(g_num_ports                                -1 downto 0);
   
   type t_hwdu_input_block_array is array(0 to g_num_ports-1) of std_logic_vector(c_hwdu_input_block_width-1 downto 0);
  
   signal hwdu_input_block            : t_hwdu_input_block_array;
   signal hwdu_mmu                    : std_logic_vector(c_hwdu_mmu_width                           -1 downto 0);
  begin --rtl
   
  --chipscope_icon_1: chipscope_icon
  --  port map (
  --    CONTROL0 => CONTROL0);

  --chipscope_ila_1: chipscope_ila
  --  port map (
  --    CONTROL => CONTROL0,
  --    CLK     => clk_i,
  --    TRIG0   => tap(31 downto 0),
  --    TRIG1   => tap(63 downto 32),
  --    TRIG2   => tap(95 downto 64),
  --    TRIG3   => tap(127 downto 96));

  tap <= tap_alloc & tap_ob(2);
    
  gen_blocks : for i in 0 to g_num_ports-1 generate

    INPUT_BLOCK : xswc_input_block
    generic map( 
        g_page_addr_width                  => c_mpm_page_addr_width,
        g_num_ports                        => g_num_ports,
        g_prio_width                       => c_prio_width,
        g_max_pck_size_width               => c_max_pck_size_width,
        g_max_oob_size                     => g_max_oob_size,
        g_usecount_width                   => c_usecount_width,
        g_input_block_cannot_accept_data   => g_input_block_cannot_accept_data,
        --new
        g_mpm_data_width                   => c_mpm_data_width, 
        g_page_size                        => g_mpm_page_size,
        g_partial_select_width             => c_mpm_partial_sel_width,
        g_ll_data_width                    => c_ll_data_width,
        g_port_index                       => i, 
        -- resource management
        g_resource_num                     => c_res_mmu_resource_num,
        g_resource_num_width               => c_res_mmu_resource_num_width
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
        mmu_usecnt_set_o         => ib_usecnt_set((i + 1) * c_usecount_width -1 downto i * c_usecount_width),
        mmu_usecnt_alloc_o       => ib_usecnt_alloc((i + 1) * c_usecount_width -1 downto i * c_usecount_width),
        mmu_nomem_i              => mmu_nomem,
        mmu_pageaddr_o           => ib_pageaddr_output((i + 1) * c_mpm_page_addr_width - 1 downto i * c_mpm_page_addr_width),
                
        -- resource management         
--        mmu_resource_i           => mmu2ib_resource          ((i+1)*c_res_mmu_resource_num_width -1 downto i*c_res_mmu_resource_num_width),
        mmu_resource_o           => ib2mmu_resource          ((i+1)*c_res_mmu_resource_num_width -1 downto i*c_res_mmu_resource_num_width),
        mmu_rescnt_page_num_o    => ib2mmu_rescnt_page_num   ((i+1)*c_mpm_page_addr_width        -1 downto i*c_mpm_page_addr_width),
        mmu_set_usecnt_succeeded_i => mmu2ib_set_usecnt_succeeded(i),
        mmu_res_full_i           => mmu2ib_res_full          ((i+1)*c_res_mmu_resource_num       -1 downto i*c_res_mmu_resource_num),
        mmu_res_almost_full_i    => mmu2ib_res_almost_full   ((i+1)*c_res_mmu_resource_num       -1 downto i*c_res_mmu_resource_num),
        
        -------------------------------------------------------------------------------
        -- I/F with Pck's Pages Freeing Module (PPFM)
        -------------------------------------------------------------------------------      
        mmu_force_free_o         => ib_force_free(i),
        mmu_force_free_done_i    => ppfm_force_free_done_to_ib(i),
        mmu_force_free_addr_o    => ib_force_free_pgaddr((i + 1) * c_mpm_page_addr_width - 1 downto i * c_mpm_page_addr_width),

        -------------------------------------------------------------------------------
        -- I/F with Routing Table Unit (RTU)
        -------------------------------------------------------------------------------      
        rtu_rsp_ack_o            => rtu_ack_o(i),        
        rtu_rsp_valid_i          => rtu_rsp_i(i).valid,
        rtu_dst_port_mask_i      => rtu_rsp_i(i).port_mask(g_num_ports  - 1 downto 0),
        rtu_hp_i                 => rtu_rsp_i(i).hp, --'0', -- TODO: add stuff to RTU
        rtu_drop_i               => rtu_rsp_i(i).drop,
        rtu_prio_i               => rtu_rsp_i(i).prio(c_prio_width - 1 downto 0),

        -------------------------------------------------------------------------------
        -- new I/F with Multiport Memory (MPU)
        -------------------------------------------------------------------------------    

        mpm_data_o               => ib2mpm_data((i+1)*c_mpm_data_width-1 downto i*c_mpm_data_width),
        mpm_dvalid_o             => ib2mpm_dvalid(i),
        mpm_dlast_o              => ib2mpm_dlast(i),
        mpm_pg_addr_o            => ib2mpm_pg_addr((i+1)*c_mpm_page_addr_width-1 downto i*c_mpm_page_addr_width),
        mpm_pg_req_i             => mpm2ib_pg_req(i),
        mpm_dreq_i               => mpm2ib_dreq(i),

        -------------------------------------------------------------------------------
        -- I/F with Linked List
        -------------------------------------------------------------------------------     

        ll_addr_o                => ib2ll_addr((i+1)* c_ll_addr_width - 1 downto i* c_ll_addr_width), 
        ll_data_o                => ib2ll_data((i+1)* c_ll_data_width - 1 downto i *c_ll_data_width),

        ll_next_addr_o           => ib2ll_next_addr((i+1)* c_ll_addr_width - 1 downto i* c_ll_addr_width),
        ll_next_addr_valid_o     => ib2ll_next_addr_valid(i),

        ll_wr_req_o              => ib2ll_wr_req(i),
        ll_wr_done_i             => ll2ib_wr_done(i),

        -------------------------------------------------------------------------------
        -- I/F with Page Transfer Arbiter (PTA)
        -------------------------------------------------------------------------------     
        pta_transfer_pck_o       => ib_transfer_pck(i),
        pta_transfer_ack_i       => pta_transfer_ack(i),
        pta_pageaddr_o           => ib_pageaddr_to_pta((i + 1) * c_mpm_page_addr_width-1 downto i * c_mpm_page_addr_width),
        pta_mask_o               => ib_mask           ((i + 1) * g_num_ports          -1 downto i * g_num_ports),
        pta_prio_o               => ib_prio           ((i + 1) * c_prio_width         -1 downto i * c_prio_width),
--         pta_pck_size_o           => ib_pck_size       ((i + 1) * c_max_pck_size_width -1 downto i * c_max_pck_size_width),
--         pta_resource_o           => open,
        pta_hp_o                 => ib_hp (i),
        dbg_hwdu_o               => hwdu_input_block(i),
        tap_out_o => tap_ib(i)
        );
        
        
    OUTPUT_BLOCK: xswc_output_block_new 
--    OUTPUT_BLOCK: xswc_output_block
      generic map( 
        g_max_pck_size_width               => c_max_pck_size_width,
        g_output_block_per_queue_fifo_size => g_output_block_per_queue_fifo_size,
        g_queue_num_width                  => c_output_queue_num_width,
        g_queue_num                        => g_output_queue_num,
        
        g_prio_num_width                   => c_prio_width,
        
        g_mpm_page_addr_width              => c_mpm_page_addr_width,
        g_mpm_data_width                   => c_mpm_data_width,
        g_mpm_partial_select_width         => c_mpm_partial_sel_width,
        g_mpm_fetch_next_pg_in_advance     => g_mpm_fetch_next_pg_in_advance,

        g_mmu_resource_num_width           => c_res_mmu_resource_num_width,

        g_wb_data_width                    => g_wb_data_width,
        g_wb_addr_width                    => g_wb_addr_width,
        g_wb_sel_width                     => g_wb_sel_width,
        g_wb_ob_ignore_ack                 => g_wb_ob_ignore_ack,
        g_drop_outqueue_head_on_full       => g_drop_outqueue_head_on_full
      )
      port map (
        clk_i                    => clk_i,
        rst_n_i                  => rst_n_i,
        -------------------------------------------------------------------------------
        -- I/F with Page Transfer Arbiter (PTA)
        -------------------------------------------------------------------------------  
        pta_transfer_data_valid_i=> pta_data_valid(i),
        pta_pageaddr_i           => pta_pageaddr((i + 1) * c_mpm_page_addr_width-1 downto i * c_mpm_page_addr_width),
        pta_prio_i               => pta_prio    ((i + 1) * c_prio_width         -1 downto i * c_prio_width),
        
        pta_hp_i                 => pta2ob_hp(i),
--         pta_resource_i           => pta2ob_resource((i + 1) * c_res_mmu_resource_num_width -1 downto i * c_res_mmu_resource_num_width),
--        pta_pck_size_i           => pta_pck_size((i + 1) * c_max_pck_size_width -1 downto i * c_max_pck_size_width),
        pta_transfer_data_ack_o  => ob_ack(i),
        -------------------------------------------------------------------------------
        -- I/F with Multiport Memory (MPM)
        -------------------------------------------------------------------------------        

        mpm_d_i                  => mpm2ob_d((i+1)*c_mpm_data_width-1 downto i*c_mpm_data_width),
        mpm_dvalid_i             => mpm2ob_dvalid(i),
        mpm_dlast_i              => mpm2ob_dlast(i),
--dsel--        mpm_dsel_i               => mpm2ob_dsel((i+1)*c_mpm_partial_sel_width -1 downto i*c_mpm_partial_sel_width),
        mpm_dreq_o               => ob2mpm_dreq(i),
        mpm_abort_o              => ob2mpm_abort(i),
        mpm_pg_addr_o            => ob2mpm_pg_addr((i+1)*c_mpm_page_addr_width -1 downto i*c_mpm_page_addr_width),
        mpm_pg_valid_o           => ob2mpm_pg_valid(i),
        mpm_pg_req_i             => mpm2ob_pg_req(i),
        -------------------------------------------------------------------------------
        -- I/F with Pck's Pages Freeing Module (PPFM)
        -------------------------------------------------------------------------------  
        ppfm_free_o              => ob_free(i),
        ppfm_free_done_i         => ppfm_free_done_to_ob(i),
        ppfm_free_pgaddr_o       => ob_free_pgaddr((i + 1) * c_mpm_page_addr_width    -1 downto i * c_mpm_page_addr_width),

        -------------------------------------------------------------------------------
        --: output traffic shaper (PAUSE + time-aware-shaper)
        -------------------------------------------------------------------------------  
        ots_output_mask_i         => ots2ob_output_masks(i),
        ots_output_drop_at_rx_hp_i=> shaper_drop_at_hp_ena_i,

        -------------------------------------------------------------------------------
        -- pWB : output (goes to the Endpoint)
        -------------------------------------------------------------------------------  

        src_i                    => src_i(i),
        src_o                    => src_o(i),

        tap_out_o => tap_ob(i)
      );        
        
  end generate gen_blocks;

  OUTPUT_TRAFFIC_SHAPER: swc_output_traffic_shaper
    generic map (
      g_num_ports                     => g_num_ports,
      g_num_global_pause              => g_num_global_pause)
    port map(
      rst_n_i                         => rst_n_i,
      clk_i                           => clk_i,
--       shaper_request_i                => shaper_request_i,
--       shaper_ports_i                  => shaper_ports_i,
--       pause_requests_i                => pause_requests_i,
      global_pause_i                  => global_pause_i,
      perport_pause_i                 => perport_pause_i,                
      output_masks_o                  => ots2ob_output_masks
    );

  PCK_PAGES_FREEEING_MODULE: swc_multiport_pck_pg_free_module
    generic map( 
      g_num_ports                     => g_num_ports,
      g_page_addr_width               => c_mpm_page_addr_width,
      g_pck_pg_free_fifo_size         => g_pck_pg_free_fifo_size,
      g_data_width                    => c_ll_data_width,
      g_resource_num_width            => c_res_mmu_resource_num_width
      )
    port map(
      clk_i                           => clk_i,
      rst_n_i                         => rst_n_i,
  
      ib_force_free_i                 => ib_force_free,
      ib_force_free_done_o            => ppfm_force_free_done_to_ib,
      ib_force_free_pgaddr_i          => ib_force_free_pgaddr,
  
      ob_free_i                       => ob_free,
      ob_free_done_o                  => ppfm_free_done_to_ob,
      ob_free_pgaddr_i                => ob_free_pgaddr,
      
      ll_read_addr_o                  => fp2ll_addr, --ppfm_read_addr,
      ll_read_data_i                  => ll2fp_data, --ll_data,
      ll_read_req_o                   => fp2ll_rd_req, --ppfm_read_req,
      ll_read_valid_data_i            => ll2fp_read_done, --ll_read_valid_data,
      
      mmu_resource_i                  => mmu2ppfm_resource,

      mmu_force_free_o                => ppfm_force_free,
      mmu_force_free_done_i           => mmu_force_free_done,
      mmu_force_free_pgaddr_o         => ppfm_force_free_pgaddr,
      mmu_free_resource_o             => ppfm2mmu_free_resource,
      mmu_free_resource_valid_o       => ppfm2mmu_free_resource_valid,
      
      mmu_free_o                      => ppfm_free,
      mmu_free_done_i                 => mmu_free_done,
      mmu_free_pgaddr_o               => ppfm_free_pgaddr,
      mmu_free_last_usecnt_i          => mmu2ppfm_free_last_usecnt,
      mmu_force_free_resource_o       => ppfm2mmu_force_free_resource,
      mmu_force_free_resource_valid_o => ppfm2mmu_force_free_resource_valid

      );

 
 LINKED_LIST:  swc_multiport_linked_list
   generic map( 
    g_num_ports                 => g_num_ports,
    g_addr_width                => c_ll_addr_width,
    g_page_num                  => c_mpm_page_num,
    g_size_width                => c_mpm_page_size_width,
    g_partial_select_width      => c_mpm_partial_sel_width,
    g_data_width                => c_ll_data_width
    )
   port map(
     rst_n_i                    => rst_n_i,
     clk_i                      => clk_i,
 
     write_i                    => ib2ll_wr_req,
     write_done_o               => ll2ib_wr_done,

     write_next_addr_i          => ib2ll_next_addr,
     write_next_addr_valid_i    => ib2ll_next_addr_valid,

     write_addr_i               => ib2ll_addr,
     write_data_i               => ib2ll_data,
       
     mpm_rpath_addr_i           => mpm2ll_addr,
     mpm_rpath_data_o           => ll2mpm_data,

     free_pck_rd_req_i          => fp2ll_rd_req,
     free_pck_addr_i            => fp2ll_addr,
     free_pck_read_done_o       => ll2fp_read_done,
     free_pck_data_o            => ll2fp_data
      
     );
 
 -- tmp
 --fp2ll_rd_req <= (others => '0');
 --fp2ll_addr   <= (others => '0');
 ----------------------------------------------------------------------
 -- Memory Mangement Unit (MMU) 
 ----------------------------------------------------------------------
  MEMORY_MANAGEMENT_UNIT: swc_multiport_page_allocator 
    generic map( 
      g_page_addr_width         => c_mpm_page_addr_width,
      g_num_ports               => g_num_ports,
      g_page_num                => c_mpm_page_num,
      g_usecount_width          => c_usecount_width,
      -- management
      g_with_RESOURCE_MGR       => true,
      g_max_pck_size            => c_res_mmu_max_pck_size,
      g_page_size               => g_mpm_page_size,
      g_special_res_num_pages   => c_res_mmu_special_res_num_pages,
      g_resource_num            => c_res_mmu_resource_num,
      g_resource_num_width      => c_res_mmu_resource_num_width,
      g_num_dbg_vector_width    => c_hwdu_mmu_width
    )
    port map (
      rst_n_i                    => rst_n_i,   
      clk_i                      => clk_i,
      
      alloc_i                    => ib_page_alloc_req,
      alloc_done_o               => mmu_page_alloc_done,
      pgaddr_alloc_o             => mmu_pageaddr_input,
      
      set_usecnt_i               => ib_set_usecnt,
      set_usecnt_done_o          => mmu_set_usecnt_done,
      
      usecnt_set_i               => ib_usecnt_set,
      usecnt_alloc_i             => ib_usecnt_alloc,
      
      pgaddr_usecnt_i            => ib_pageaddr_output,  
            
      free_i                     => ppfm_free,
      free_done_o                => mmu_free_done,
      pgaddr_free_i              => ppfm_free_pgaddr,
      free_last_usecnt_o             => mmu2ppfm_free_last_usecnt,
      
      force_free_i               => ppfm_force_free,
      force_free_done_o          => mmu_force_free_done,
      pgaddr_force_free_i        => ppfm_force_free_pgaddr,
      
      nomem_o                    => mmu_nomem,
      --------------------------- resource management ----------------------------------
      resource_i                 => ib2mmu_resource,
      resource_o                 => mmu2ppfm_resource,

      free_resource_i            => ppfm2mmu_free_resource,
      free_resource_valid_i      => ppfm2mmu_free_resource_valid,
      force_free_resource_i      => ppfm2mmu_force_free_resource,
      force_free_resource_valid_i=> ppfm2mmu_force_free_resource_valid,

      rescnt_page_num_i          => ib2mmu_rescnt_page_num,
      set_usecnt_succeeded_o     => mmu2ib_set_usecnt_succeeded, 
      
      res_full_o                 => mmu2ib_res_full,
      res_almost_full_o          => mmu2ib_res_almost_full,

      dbg_o                      => hwdu_mmu
--      tap_out_o => tap_alloc
      );
       
  MULTIPORT_MEMORY: mpm_top --(new)
  generic map(
    g_data_width           => c_mpm_data_width,
    g_ratio                => g_mpm_ratio,
    g_page_size            => g_mpm_page_size,
    g_num_pages            => c_mpm_page_num,
    g_num_ports            => g_num_ports,
    g_fifo_size            => g_mpm_fifo_size,
    g_page_addr_width      => c_mpm_page_addr_width,
    g_partial_select_width => c_mpm_partial_sel_width,
    g_max_oob_size         => g_max_oob_size,
    g_max_packet_size      => g_max_pck_size,
    g_ll_data_width        => c_ll_data_width
    )
  port map(
    clk_io_i               => clk_i,
    clk_core_i             => clk_mpm_core_i,
    rst_n_i                => rst_n_i,

    wport_d_i              => ib2mpm_data,
    wport_dvalid_i         => ib2mpm_dvalid,
    wport_dlast_i          => ib2mpm_dlast,
    wport_pg_addr_i        => ib2mpm_pg_addr,
    wport_pg_req_o         => mpm2ib_pg_req,
    wport_dreq_o           => mpm2ib_dreq,

    rport_d_o               => mpm2ob_d,
    rport_dvalid_o          => mpm2ob_dvalid,
    rport_dlast_o           => mpm2ob_dlast,
    rport_dsel_o            => mpm2ob_dsel,
    rport_dreq_i            => ob2mpm_dreq,
    rport_abort_i           => ob2mpm_abort,
    rport_pg_addr_i         => ob2mpm_pg_addr,
    rport_pg_valid_i        => ob2mpm_pg_valid,
    rport_pg_req_o          => mpm2ob_pg_req,

    ll_addr_o               => mpm2ll_addr, -- tmp mpm2ll_addr,
    ll_data_i               => ll2mpm_data
    );
  --mpm2ll_addr <= (others => '0');
  ----------------------------------------------------------------------
  -- Page Transfer Arbiter [ 1 module]
  ----------------------------------------------------------------------
  TRANSER_ARBITER: swc_pck_transfer_arbiter 
    generic map(
      g_page_addr_width    => c_mpm_page_addr_width,
      g_prio_width         => c_prio_width,    
--       g_max_pck_size_width => c_max_pck_size_width,
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
--       ob_pck_size_o              => pta_pck_size,
      ob_hp_o                    => pta2ob_hp,
      -------------------------------------------------------------------------------
      -- I/F with Input Block (IB)
      ------------------------------------------------------------------------------- 
      ib_transfer_pck_i          => ib_transfer_pck,
      ib_transfer_ack_o          => pta_transfer_ack,
      ib_busy_o                  => open,
      ib_pageaddr_i              => ib_pageaddr_to_pta,
      ib_mask_i                  => ib_mask,
      ib_prio_i                  => ib_prio,
--       ib_pck_size_i              => ib_pck_size
      ib_hp_i                    => ib_hp
      );  

  dbg_o(31 downto 0) <= "00" & hwdu_mmu;

  hwdu_gen: for i in 0 to (g_num_ports-1) generate
    dbg_o((i+1)*c_hwdu_input_block_width+32-1 downto i*c_hwdu_input_block_width+32) <= hwdu_input_block(i);
  end generate hwdu_gen;

end rtl;
