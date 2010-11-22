-------------------------------------------------------------------------------
-- Title      : Switch Core 
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_core.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-10-29
-- Last update: 2010-10-29
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

-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.swc_swcore_pkg.all;

entity swc_core is

  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

-------------------------------------------------------------------------------
-- Fabric I/F : input (comes from the Endpoint)
-------------------------------------------------------------------------------

    tx_sof_p1_i         : in  std_logic;
    tx_eof_p1_i         : in  std_logic;
    tx_data_i           : in  std_logic_vector(c_swc_data_width - 1 downto 0);
    tx_ctrl_i           : in  std_logic_vector(c_swc_ctrl_width - 1 downto 0);
    tx_valid_i          : in  std_logic;
    tx_bytesel_i        : in  std_logic;
    tx_dreq_o           : out std_logic;
    tx_abort_p1_i       : in  std_logic;
    tx_rerror_p1_i      : in  std_logic;

-------------------------------------------------------------------------------
-- Fabric I/F : output (goes to the Endpoint)
-------------------------------------------------------------------------------  
    
    rx_sof_p1_o         : out std_logic;
    rx_eof_p1_o         : out std_logic;
    rx_dreq_i           : in  std_logic;
    rx_ctrl_o           : out std_logic_vector(c_swc_ctrl_width - 1 downto 0);
    rx_data_o           : out std_logic_vector(c_swc_data_width - 1 downto 0);
    rx_valid_o          : out std_logic;
    rx_bytesel_o        : out std_logic;
    rx_idle_o           : out std_logic;
    rx_rerror_p1_o      : out std_logic;
    rx_terror_p1_i      : in  std_logic;
    rx_rabort_p1_i      : in  std_logic;


--    rx_sof_p1_o         : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
--    rx_eof_p1_o         : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
--    rx_dreq_i           : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
--    rx_ctrl_o           : out std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0);
--    rx_data_o           : out std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
--    rx_valid_o          : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
--    rx_bytesel_o        : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
--    rx_idle_o           : out std_logic_vector(c_swc_num_ports  - 1 downto 0);
--    rx_rerror_p1_o      : out std_logic_vector(c_swc_num_ports  - 1 downto 0);    
--    rx_terror_p1_i      : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);
 --   rx_rabort_p1_i      : in  std_logic_vector(c_swc_num_ports  - 1 downto 0);

    
-------------------------------------------------------------------------------
-- I/F with Routing Table Unit (RTU)
-------------------------------------------------------------------------------      
    
    rtu_rsp_valid_i     : in std_logic;
    rtu_rsp_ack_o       : out std_logic;
    rtu_dst_port_mask_i : in std_logic_vector(c_swc_num_ports  - 1 downto 0);
    rtu_drop_i          : in std_logic;
    rtu_prio_i          : in std_logic_vector(c_swc_prio_width - 1 downto 0)

    );
end swc_core;

architecture rtl of swc_core is


   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Input Block<< with >>Memory Management Unit<<
   ----------------------------------------------------------------------------------------------------
   -- Input Block -> Memory Management Unit
   signal ib_page_alloc_req   : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal ib_pageaddr_output  : std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
   signal ib_set_usecnt       : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal ib_usecnt           : std_logic_vector(c_swc_num_ports * c_swc_usecount_width - 1 downto 0);
   
   -- Memory Management Unit -> Input Block 
   signal mmu_page_alloc_done  : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal mmu_pageaddr_input   : std_logic_vector(      1         * c_swc_page_addr_width - 1 downto 0);   
   signal mmu_set_usecnt_done  : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal mmu_nomem            : std_logic;

   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Input Block<< with >>Multiport Memory<<
   ----------------------------------------------------------------------------------------------------
   -- Input Block -> Multiport Memory
   signal ib_pckstart         : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal ib_pageaddr_to_mpm  : std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
   signal ib_pagereq          : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal ib_data             : std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
   signal ib_ctrl             : std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0);
   signal ib_drdy             : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal ib_flush            : std_logic_vector(c_swc_num_ports - 1 downto 0);
   
   -- Multiport Memory -> Input Block
   signal mpm_pageend          : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal mpm_full             : std_logic_vector(c_swc_num_ports - 1 downto 0);

   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Input Block<< with >>Pck Transfer Arbiter<<
   ----------------------------------------------------------------------------------------------------
   -- Input Block -> Pck Transfer Arbiter
   signal ib_transfer_pck     : std_logic_vector(c_swc_num_ports - 1 downto 0);

   signal ib_pageaddr_to_pta  : std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
   signal ib_mask             : std_logic_vector(c_swc_num_ports * c_swc_num_ports - 1 downto 0);
   signal ib_prio             : std_logic_vector(c_swc_num_ports * c_swc_prio_width - 1 downto 0);
   signal ib_pck_size         : std_logic_vector(c_swc_num_ports * c_swc_max_pck_size_width - 1 downto 0);
   
   -- Pck Transfer Arbiter -> Input Block       
   signal pta_transfer_ack    : std_logic_vector(c_swc_num_ports - 1 downto 0);  

   
   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Output Block<< with >>Pck Transfer Arbiter<< 
   ----------------------------------------------------------------------------------------------------
   -- Input Block -> Pck Transfer Arbiter
   signal pta_data_valid             : std_logic_vector(c_swc_num_ports -1 downto 0);
   signal pta_pageaddr               : std_logic_vector(c_swc_num_ports * c_swc_page_addr_width    - 1 downto 0);
   signal pta_prio                   : std_logic_vector(c_swc_num_ports * c_swc_prio_width         - 1 downto 0);
   signal pta_pck_size               : std_logic_vector(c_swc_num_ports * c_swc_max_pck_size_width - 1 downto 0);

   -- Input Block -> Pck Transfer Arbiter
   signal ob_ack                    : std_logic_vector(c_swc_num_ports -1 downto 0);


   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Output Block<< with >>Multiport Memory<<
   ----------------------------------------------------------------------------------------------------
   -- Output Block -> Multiport Memory
   signal ob_pgreq                 : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal ob_pgaddr                : std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
   signal ob_dreq                  : std_logic_vector(c_swc_num_ports - 1 downto 0);

   -- Multiport Memory -> Output Block 
   signal mpm_pckend                : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal mpm_pgend                 : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal mpm_drdy                  : std_logic_vector(c_swc_num_ports - 1 downto 0);
   
   signal mpm_data                  : std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
   signal mpm_ctrl                  : std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0); 
      
     
   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Muliport Memory<< with >>Linked List<<
   ----------------------------------------------------------------------------------------------------   
   -- Multiport Memory -> Linked List 
   signal mpm_write               : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal mpm_write_addr          : std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
   signal mpm_write_data          : std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
  
   signal mpm_read_pump_read      : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal mpm_read_pump_addr      : std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
   
   -- Linked List -> Multiport memory
--   signal ll_free_done            : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal ll_write_done           : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal ll_read_pump_read_done  : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal ll_data                 : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
   
  
   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Input Block<< with >>Pck's pages freeeing module<<
   ----------------------------------------------------------------------------------------------------   
   -- Input block -> Lost pck dealloc
   signal ib_force_free         : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal ib_force_free_pgaddr  : std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
      
   -- lost pck dealloc -> input block
   signal ppfm_force_free_done_to_ib  : std_logic_vector(c_swc_num_ports - 1 downto 0);


   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Output Block<< with >>Pck's Pages Freeing Module (PPFM)<<
   ----------------------------------------------------------------------------------------------------   
   -- output block -> Lost pck dealloc
   signal ob_free         : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal ob_free_pgaddr  : std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
      
   -- lost pck dealloc -> output block
   signal ppfm_free_done_to_ob  : std_logic_vector(c_swc_num_ports - 1 downto 0);

   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Pck's pages freeeing module<< with >>Linkded List<<
   ----------------------------------------------------------------------------------------------------   
   -- LPD -> LL
   signal ppfm_read_addr         : std_logic_vector(c_swc_num_ports * c_swc_page_addr_width -1 downto 0);
   signal ppfm_read_req          : std_logic_vector(c_swc_num_ports-1 downto 0);

   -- LL -> LPD
     signal ll_read_valid_data    : std_logic_vector(c_swc_num_ports-1 downto 0);

   ----------------------------------------------------------------------------------------------------
   -- signals connecting >>Pck's pages freeing module (PPFM)<< with >>Page allocator (MMU)<<
   ----------------------------------------------------------------------------------------------------   
  -- PPFM -> MMU
   signal ppfm_force_free        : std_logic_vector(c_swc_num_ports-1 downto 0);
   signal ppfm_force_free_pgaddr : std_logic_vector(c_swc_num_ports * c_swc_page_addr_width -1 downto 0);
   signal ppfm_free              : std_logic_vector(c_swc_num_ports-1 downto 0);
   signal ppfm_free_pgaddr       : std_logic_vector(c_swc_num_ports * c_swc_page_addr_width -1 downto 0);
   
   -- MMU -> PPFM
   signal mmu_force_free_done   : std_logic_vector(c_swc_num_ports-1 downto 0);
   signal mmu_free_done         : std_logic_vector(c_swc_num_ports-1 downto 0);   
   
   ----------------------------------------------------------------------------------------------------
   -- tmp
   ----------------------------------------------------------------------------------------------------      

   signal tx_sof_p1             : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal tx_eof_p1             : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal tx_data               : std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
   signal tx_ctrl               : std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0);
   signal tx_valid              : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal tx_bytesel            : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal tx_dreq               : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal tx_abort_p1           : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal tx_rerror_p1          : std_logic_vector(c_swc_num_ports - 1 downto 0);
   
   signal rx_sof_p1             : std_logic_vector(c_swc_num_ports  - 1 downto 0);
   signal rx_eof_p1             : std_logic_vector(c_swc_num_ports  - 1 downto 0);
   signal rx_dreq               : std_logic_vector(c_swc_num_ports  - 1 downto 0);
   signal rx_ctrl               : std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0);
   signal rx_data               : std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
   signal rx_valid              : std_logic_vector(c_swc_num_ports  - 1 downto 0);
   signal rx_bytesel            : std_logic_vector(c_swc_num_ports  - 1 downto 0);
   signal rx_idle               : std_logic_vector(c_swc_num_ports  - 1 downto 0);
   signal rx_rerror_p1          : std_logic_vector(c_swc_num_ports  - 1 downto 0);    
   signal rx_terror_p1          : std_logic_vector(c_swc_num_ports  - 1 downto 0);
   signal rx_rabort_p1          : std_logic_vector(c_swc_num_ports  - 1 downto 0);
   
   signal rtu_rsp_valid        : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal rtu_rsp_ack          : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal rtu_dst_port_mask    : std_logic_vector(c_swc_num_ports * c_swc_num_ports  - 1 downto 0);
   signal rtu_drop             : std_logic_vector(c_swc_num_ports - 1 downto 0);
   signal rtu_prio             : std_logic_vector(c_swc_num_ports * c_swc_prio_width - 1 downto 0);
   
   ---- end tmp      
 
  begin --rtl
   
   
   ---- tmp
   tx_sof_p1(0)                                                            <=  tx_sof_p1_i;
   tx_sof_p1(c_swc_num_ports - 1 downto 1)                                 <=  (others=>'0');
   
   tx_eof_p1(0)                                                            <=  tx_eof_p1_i;
   tx_eof_p1(c_swc_num_ports - 1 downto 1)                                 <=  (others=>'0');
   
   tx_data(c_swc_data_width - 1 downto 0)                                  <=  tx_data_i;
   tx_data(c_swc_num_ports * c_swc_data_width - 1 downto c_swc_data_width) <=  (others=>'0');
   
   tx_ctrl(c_swc_ctrl_width - 1 downto 0)                                  <=  tx_ctrl_i;
   tx_ctrl(c_swc_num_ports * c_swc_ctrl_width - 1 downto c_swc_ctrl_width) <=  (others=>'0');
   
   tx_valid(0)                                                             <=  tx_valid_i;
   tx_valid(c_swc_num_ports - 1 downto 1)                                  <=  (others=>'0');
   
   tx_bytesel(0)                                                           <=  tx_bytesel_i;
   tx_bytesel(c_swc_num_ports - 1 downto 1)                                <=  (others=>'0');
   
   tx_dreq_o                                                               <=  tx_dreq(0);
   
   tx_abort_p1(0)                                                          <=  tx_abort_p1_i;
   tx_abort_p1(c_swc_num_ports - 1 downto 1)                               <=  (others=>'0'); 
   
   tx_rerror_p1(0)                                                         <=  tx_rerror_p1_i;
   tx_rerror_p1(c_swc_num_ports - 1 downto 1)                              <=  (others=>'0');   
   

   
   rx_sof_p1_o   <= rx_sof_p1(0);
   rx_eof_p1_o   <= rx_eof_p1(0);
   rx_ctrl_o     <= rx_ctrl(c_swc_ctrl_width - 1 downto 0);  
   rx_data_o     <= rx_data(c_swc_data_width - 1 downto 0);  
   rx_valid_o    <= rx_valid(0)   ;
   rx_bytesel_o  <= rx_bytesel(0) ;
   rx_idle_o     <= rx_idle(0);    
   rx_rerror_p1_o<= rx_rerror_p1(0);
   
   rx_terror_p1(0)                            <= rx_terror_p1_i;
   rx_terror_p1(c_swc_num_ports - 1 downto 1) <= (others => '0');
   
   rx_rabort_p1(0)                            <= rx_rabort_p1_i;
   rx_rabort_p1(c_swc_num_ports - 1 downto 1) <= (others => '0');
   
   rx_dreq(0)                                 <= rx_dreq_i; 
   rx_dreq(c_swc_num_ports - 1 downto 1)      <= (others => '0');
   
   
   rtu_rsp_valid(0)                                                        <= rtu_rsp_valid_i;    
   rtu_rsp_valid(c_swc_num_ports - 1 downto 1)                             <= (others=> '0');
   
   rtu_rsp_ack_o                                                           <= rtu_rsp_ack(0);
            
   rtu_drop(0)                                                             <= rtu_drop_i;
   rtu_drop(c_swc_num_ports - 1 downto 1)                                  <= (others=> '0');    
   
   rtu_dst_port_mask(c_swc_num_ports - 1 downto 0)                                  <= rtu_dst_port_mask_i;
   rtu_dst_port_mask(c_swc_num_ports * c_swc_num_ports - 1 downto c_swc_num_ports)  <= (others=> '0');             
   
   rtu_prio(c_swc_prio_width  - 1 downto 0)                                <= rtu_prio_i;
   rtu_prio(c_swc_prio_width * c_swc_num_ports - 1 downto c_swc_prio_width)<= (others=> '0');             
   
   
   ---- end timp

   
   
  gen_blocks : for i in 0 to c_swc_num_ports-1 generate
    INPUT_BLOCK : swc_input_block 
      port map (
        clk_i                    => clk_i,
        rst_n_i                  => rst_n_i,
        -------------------------------------------------------------------------------
        -- Fabric I/F  
        ------------------------------------------------------------------------------
        tx_sof_p1_i              => tx_sof_p1(i),
        tx_eof_p1_i              => tx_eof_p1(i),
        tx_data_i                => tx_data((i + 1) * c_swc_data_width -1 downto i * c_swc_data_width),
        tx_ctrl_i                => tx_ctrl((i + 1) * c_swc_ctrl_width -1 downto i * c_swc_ctrl_width),
        tx_valid_i               => tx_valid(i),
        tx_bytesel_i             => tx_bytesel(i),
        tx_dreq_o                => tx_dreq(i),
        tx_abort_p1_i            => tx_abort_p1(i),
        tx_rerror_p1_i           => tx_rerror_p1(i),
        -------------------------------------------------------------------------------
        -- I/F with Page allocator (MMU)
        -------------------------------------------------------------------------------    
        mmu_page_alloc_req_o     => ib_page_alloc_req(i),
        mmu_page_alloc_done_i    => mmu_page_alloc_done(i),
        mmu_pageaddr_i           => mmu_pageaddr_input,
        mmu_pageaddr_o           => ib_pageaddr_output((i + 1) * c_swc_page_addr_width - 1 downto i * c_swc_page_addr_width),
        
        mmu_set_usecnt_o         => ib_set_usecnt(i),
        mmu_set_usecnt_done_i    => mmu_set_usecnt_done(i),
        mmu_usecnt_o             => ib_usecnt((i + 1) * c_swc_usecount_width -1 downto i * c_swc_usecount_width),
        mmu_nomem_i              => mmu_nomem,

        -------------------------------------------------------------------------------
        -- I/F with Pck's Pages Freeing Module (PPFM)
        -------------------------------------------------------------------------------      
        mmu_force_free_o         => ib_force_free(i),
        mmu_force_free_done_i    => ppfm_force_free_done_to_ib(i),
        mmu_force_free_addr_o    => ib_force_free_pgaddr((i + 1) * c_swc_page_addr_width - 1 downto i * c_swc_page_addr_width),

        -------------------------------------------------------------------------------
        -- I/F with Routing Table Unit (RTU)
        -------------------------------------------------------------------------------      
        rtu_rsp_valid_i          => rtu_rsp_valid(i),
        rtu_rsp_ack_o            => rtu_rsp_ack(i),
        rtu_dst_port_mask_i      => rtu_dst_port_mask((i + 1) * c_swc_num_ports -1 downto i * c_swc_num_ports),
        rtu_drop_i               => rtu_drop(i),
        rtu_prio_i               => rtu_prio((i + 1) * c_swc_prio_width -1 downto i * c_swc_prio_width),
        -------------------------------------------------------------------------------
        -- I/F with Multiport Memory (MPU)
        -------------------------------------------------------------------------------    
        mpm_pckstart_o           => ib_pckstart(i),
        mpm_pageaddr_o           => ib_pageaddr_to_mpm((i + 1) * c_swc_page_addr_width - 1 downto i * c_swc_page_addr_width),
        mpm_pagereq_o            => ib_pagereq(i),
        mpm_pageend_i            => mpm_pageend(i),
        mpm_data_o               => ib_data((i + 1) * c_swc_data_width - 1 downto i * c_swc_data_width),
        mpm_ctrl_o               => ib_ctrl((i + 1) * c_swc_ctrl_width - 1 downto i * c_swc_ctrl_width),
        mpm_drdy_o               => ib_drdy(i),
        mpm_full_i               => mpm_full(i),
        mpm_flush_o              => ib_flush(i),
        -------------------------------------------------------------------------------
        -- I/F with Page Transfer Arbiter (PTA)
        -------------------------------------------------------------------------------     
        pta_transfer_pck_o       => ib_transfer_pck(i),
        pta_transfer_ack_i       => pta_transfer_ack(i),
        pta_pageaddr_o           => ib_pageaddr_to_pta((i + 1) * c_swc_page_addr_width    -1 downto i * c_swc_page_addr_width),
        pta_mask_o               => ib_mask           ((i + 1) * c_swc_num_ports          -1 downto i * c_swc_num_ports),
        pta_prio_o               => ib_prio           ((i + 1) * c_swc_prio_width         -1 downto i * c_swc_prio_width),
        pta_pck_size_o           => ib_pck_size       ((i + 1) * c_swc_max_pck_size_width -1 downto i * c_swc_max_pck_size_width)
       
        );
        
        
    OUTPUT_BLOCK: swc_output_block 
      port map (
        clk_i                    => clk_i,
        rst_n_i                  => rst_n_i,
        -------------------------------------------------------------------------------
        -- I/F with Page Transfer Arbiter (PTA)
        -------------------------------------------------------------------------------  
        pta_transfer_data_valid_i=> pta_data_valid(i),
        pta_pageaddr_i           => pta_pageaddr((i + 1) * c_swc_page_addr_width    -1 downto i * c_swc_page_addr_width),
        pta_prio_i               => pta_prio    ((i + 1) * c_swc_prio_width         -1 downto i * c_swc_prio_width),
        pta_pck_size_i           => pta_pck_size((i + 1) * c_swc_max_pck_size_width -1 downto i * c_swc_max_pck_size_width),
        pta_transfer_data_ack_o  => ob_ack(i),
        -------------------------------------------------------------------------------
        -- I/F with Multiport Memory (MPM)
        -------------------------------------------------------------------------------        
        mpm_pgreq_o              => ob_pgreq(i),
        mpm_pgaddr_o             => ob_pgaddr((i + 1) * c_swc_page_addr_width    -1 downto i * c_swc_page_addr_width),
        mpm_pckend_i             => mpm_pckend(i),
        mpm_pgend_i              => mpm_pgend(i),
        mpm_drdy_i               => mpm_drdy(i),
        mpm_dreq_o               => ob_dreq(i),
        mpm_data_i               => mpm_data((i + 1) * c_swc_data_width - 1 downto i * c_swc_data_width),
        mpm_ctrl_i               => mpm_ctrl((i + 1) * c_swc_ctrl_width - 1 downto i * c_swc_ctrl_width),
        -------------------------------------------------------------------------------
        -- I/F with Pck's Pages Freeing Module (PPFM)
        -------------------------------------------------------------------------------  
        ppfm_free_o              => ob_free(i),
        ppfm_free_done_i         => ppfm_free_done_to_ob(i),
        ppfm_free_pgaddr_o       => ob_free_pgaddr((i + 1) * c_swc_page_addr_width    -1 downto i * c_swc_page_addr_width),
        -------------------------------------------------------------------------------
        -- Fabric I/F 
        -------------------------------------------------------------------------------        
        rx_sof_p1_o              => rx_sof_p1(i),
        rx_eof_p1_o              => rx_eof_p1(i),
        rx_dreq_i                => rx_dreq(i),
        rx_ctrl_o                => rx_ctrl((i + 1) * c_swc_ctrl_width    -1 downto i * c_swc_ctrl_width),
        rx_data_o                => rx_data((i + 1) * c_swc_data_width    -1 downto i * c_swc_data_width),
        rx_valid_o               => rx_valid(i),
        rx_bytesel_o             => rx_bytesel(i),
        rx_idle_o                => rx_idle(i),
        rx_rerror_p1_o           => rx_rerror_p1(i),
        rx_terror_p1_i           => rx_terror_p1(i),
        rx_rabort_p1_i           => rx_rabort_p1(i)
      );        
        
  end generate gen_blocks;


  PCK_PAGES_FREEEING_MODULE: swc_multiport_pck_pg_free_module
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
    port map (
      rst_n_i                    => rst_n_i,   
      clk_i                      => clk_i,
      
      alloc_i                    => ib_page_alloc_req,
      alloc_done_o               => mmu_page_alloc_done,
      pgaddr_alloc_o             => mmu_pageaddr_input,
      
      set_usecnt_i               => ib_set_usecnt,
      set_usecnt_done_o          => mmu_set_usecnt_done,
      usecnt_i                   => ib_usecnt,
            
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
      -------------------------------------------------------------------------------
      -- I/F with Output Block
      ------------------------------------------------------------------------------- 
      rd_pagereq_i               => ob_pgreq,
      rd_pageaddr_i              => ob_pgaddr,
      rd_pageend_o               => mpm_pckend,
      rd_pckend_o                => mpm_pgend,
      rd_drdy_o                  => mpm_drdy,
      rd_dreq_i                  => ob_dreq,
      --!!!!!!!!!!
      rd_sync_read_i             => ob_pgreq, -- TODO ???
      --!!!!!!!!!!!!!!!!!!
      rd_data_o                  => mpm_data,
      rd_ctrl_o                  => mpm_ctrl,
      
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
