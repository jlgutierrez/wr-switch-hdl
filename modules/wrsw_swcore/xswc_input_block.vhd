-------------------------------------------------------------------------------
-- Title      : Input block (extended interface)
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : xswc_input_block.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-10-28
-- Last update: 2012-03-16
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: This block controls input to SW Core. It consists of a three 
-- Finite State Machines (FSMs):
-- 1) p_page_alloc_fsm - it allocates in advance pages and sets usecnt (once it's known):
--    - it allocates pckstart_page - the address used for the first page of the pck, 
--      it is important because:
--      -> the address of the first page is used to refer to the entire pck - it is passed to the
--         output ports
--      -> the proper usecnt (number of output ports by which the pck should be read from MPM and
--         sent) is set only on the first page address (pckstart_page), the usecnt of the 
--         intermedaite pages (interpck_page) are set always to 1
--    - it allocatest interpck_page - the address used for the intermediate pages (not first), 
--      the usecnt of this pages is always set to 1
--    - it sets the usecnt of the pckfirst_page once it is know (the RTU decision has been received)
-- 
-- 2) p_transfer_pck_fsm - it receives the RTU decision and transmits it to the output ports 
--    (if the pck is not to be dropped)
-- 
-- 3) p_rcv_pck_fsm - it is a translator between pWB and MPM, it does the following:
--    - receives info from pWB (implements sink) and pipelines (1 stage) the data/valid/sel/addr 
--    - the pipelining is done to detect EOF and assert it for MPM on the last word/error/RTU drop 
--      decision. Since we detect EOF on end_of_cycle, it comes after the valid last word, on 
--      the other hand, we need to indicate to MPM the last valid word. so we need to pipeline to 
--      do so.
--    - it also implements "dummy reception" of a pck that is to be dropped (on the RTU decision or
--      when the SWCORE is stuck, if configured so, TODO)
--    - it takes care to release pages allocated for a pck which was not transfered to outputs 
--      (due to error/drop RTU decision)
--    - it stalls the input if the SWCORE is stuck within pck reception (e.g.: due to full output
--      queue -- transfer not possible, or MPM full -- no new pages)
--   
-- 4) p_ll_write_fsm - it manages writing Linked List
--    - it is a bit too complex, but I could not figure out anything simpler
--    - it enables writing pages from the previous pck to overlaps with the first pg
--      of the next pck, this is important since the last page is likely to be short,
--      so me might need to wait for the previous write to LL, this all can be done 
--      when already receving new pck (to prevent stalling)
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
-- 2010-11-01  1.0      mlipinsk created
-- 2010-11-29  2.0      mlipinsk added FIFO, major changes
-- 2012-01-20  3.0      mlipinsk wisbhonized
-- 2012-02-02  4.0      mlipinsk generic-azed
-- 2012-02-15  5.0      mlipinsk adapted to the new (async) MPM
-- 2013-03-08  5.1      mlipinsk removed dsel
-------------------------------------------------------------------------------
-- TODO: 
-- 1) think about enabling reception of new pck when still waiting for the transfer,
--    this requires changing interaction between p_transfer_pck_fsm and p_rcv_pck_fsm
-- 2) make the dsel more generic
-- 3) test with mpm_dreq_i = LOW
-- 4) implement drop_on_SWCORE_stuck
-- 5) writing to the linked list /  transfer -> we need to include waiting and stuff !!!   
-- 
-- 1.0) throw error when PCK dropped by RTU
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

library work;
use work.swc_swcore_pkg.all;
use work.genram_pkg.all;
use work.wr_fabric_pkg.all;

entity xswc_input_block is
  generic (
    g_page_addr_width                : integer;  --:= c_swc_page_addr_width;
    g_num_ports                      : integer;  --:= c_swc_num_ports
    g_prio_width                     : integer;  --:= c_swc_prio_width;
    g_max_pck_size_width             : integer;  --:= c_swc_max_pck_size_width  
    g_usecount_width                 : integer;  --:= c_swc_usecount_width
    g_input_block_cannot_accept_data : string;  --:= "drop_pck"; --"stall_o", "rty_o" -- Don't CHANGE !

    -- new
    g_mpm_data_width       : integer;  -- it needs to be wb_data_width + wb_addr_width
    g_page_size            : integer;
    g_partial_select_width : integer;
    g_ll_data_width        : integer;
    g_max_oob_size         : integer;   -- on words (16 bits)
    g_port_index           : integer;    -- ID of this port

    --- resource management
    g_resource_num         : integer;
    g_resource_num_width   : integer
    
    );
  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

    -------------------------------------------------------------------------------
    -- pWB  : input (comes from the Endpoint)
    -------------------------------------------------------------------------------

    snk_i : in  t_wrf_sink_in;
    snk_o : out t_wrf_sink_out;

    -------------------------------------------------------------------------------
    -- I/F with Page allocator (MMU)
    -------------------------------------------------------------------------------    

    -- indicates that a port X wants to write page address of the "write" access
    mmu_page_alloc_req_o : out std_logic;


    mmu_page_alloc_done_i : in std_logic;

    -- array of pages' addresses to which ports want to write
    mmu_pageaddr_i : in std_logic_vector(g_page_addr_width - 1 downto 0);

    mmu_pageaddr_o : out std_logic_vector(g_page_addr_width - 1 downto 0);

    -- force freeing package starting with page outputed on mmu_pageaddr_o
    mmu_force_free_o : out std_logic;

    mmu_force_free_done_i : in std_logic;

    mmu_force_free_addr_o : out std_logic_vector(g_page_addr_width - 1 downto 0);

    -- set user count to the already allocated page (on mmu_pageaddr_o)
    mmu_set_usecnt_o : out std_logic;

    mmu_set_usecnt_done_i : in std_logic;

    -- user count to be set (associated with an allocated page) in two cases:
    -- * mmu_pagereq_o    is HIGH - normal allocation
    mmu_usecnt_alloc_o : out std_logic_vector(g_usecount_width - 1 downto 0);
    -- * mmu_set_usecnt_o is HIGH - force user count to existing page alloc
    mmu_usecnt_set_o   : out std_logic_vector(g_usecount_width - 1 downto 0);

    -- memory full
    mmu_nomem_i : in std_logic;

    --------------------------- resource management ----------------------------------
    -- resource number
    --mmu_resource_i             : in  std_logic_vector(g_resource_num_width-1 downto 0);
    
    -- outputed when freeing
    mmu_resource_o             : out std_logic_vector(g_resource_num_width-1 downto 0);

    -- number of pages added to the resurce
    mmu_rescnt_page_num_o      : out std_logic_vector(g_page_addr_width-1 downto 0);
    mmu_set_usecnt_succeeded_i : in  std_logic;
    mmu_res_full_i             : in  std_logic_vector(g_resource_num   -1 downto 0);
    mmu_res_almost_full_i      : in  std_logic_vector(g_resource_num   -1 downto 0); 

-------------------------------------------------------------------------------
-- I/F with Routing Table Unit (RTU)
-------------------------------------------------------------------------------      

    rtu_rsp_valid_i     : in  std_logic;
    rtu_rsp_ack_o       : out std_logic;
    rtu_dst_port_mask_i : in  std_logic_vector(g_num_ports - 1 downto 0);
    rtu_hp_i            : in  std_logic; 
    rtu_drop_i          : in  std_logic;
    rtu_prio_i          : in  std_logic_vector(g_prio_width - 1 downto 0);

-------------------------------------------------------------------------------
-- I/F with Async MultiPort Memory (MPM)
-------------------------------------------------------------------------------    
    -- data to be written
    mpm_data_o    : out std_logic_vector(g_mpm_data_width - 1 downto 0);
    -- HIGH if data is valid
    mpm_dvalid_o  : out std_logic;
    -- HIGH if the word data is the last of the pck
    mpm_dlast_o   : out std_logic;
    -- indicates the base address of the page curretly written to
    mpm_pg_addr_o : out std_logic_vector(g_page_addr_width - 1 downto 0);
    -- if HIGH, new page_addr should be provided in the next cycle
    mpm_pg_req_i  : in  std_logic;
    -- if HIGH, the data can be accepted by the MPM
    mpm_dreq_i    : in  std_logic;

-------------------------------------------------------------------------------
-- Linked List of page addresses (LL SRAM) interface 
-------------------------------------------------------------------------------

    -- address in LL SRAM which corresponds to the page address
    ll_addr_o : out std_logic_vector(g_page_addr_width -1 downto 0);

    -- data output for LL SRAM - it is the address of the next page or 0xF...F
    -- if this is the last page of the package
    ll_data_o : out std_logic_vector(g_ll_data_width - 1 downto 0);

    ll_next_addr_o : out std_logic_vector(g_page_addr_width -1 downto 0);

    ll_next_addr_valid_o : out std_logic;

    -- request to write to Linked List, should be high until
    -- ll_wr_done_i indicates successfull write
    ll_wr_req_o : out std_logic;

    ll_wr_done_i : in std_logic;

-------------------------------------------------------------------------------
-- I/F with Page Transfer Arbiter (PTA)
-------------------------------------------------------------------------------     
    -- indicates the beginning of the package, strobe
    pta_transfer_pck_o : out std_logic;

    pta_transfer_ack_i : in std_logic;

    -- array of pages' addresses to which ports want to write
    pta_pageaddr_o : out std_logic_vector(g_page_addr_width - 1 downto 0);

    -- destination mask - indicates to which ports the packet should be
    -- forwarded
    pta_mask_o : out std_logic_vector(g_num_ports - 1 downto 0);

--     pta_pck_size_o : out std_logic_vector(g_max_pck_size_width - 1 downto 0);

    -- information about resoruce allocation
--     pta_resource_o : out std_logic_vector(g_resource_num_width - 1 downto 0);
    
    -- htraffic
    pta_hp_o : out std_logic;

    pta_prio_o : out std_logic_vector(g_prio_width - 1 downto 0);

    dbg_hwdu_o  : out std_logic_vector(15 downto 0);

    tap_out_o: out std_logic_vector(49 + 62 downto 0)

    );
end xswc_input_block;

architecture syn of xswc_input_block is

  constant c_page_size_width    : integer := integer(CEIL(LOG2(real(g_page_size + 1))));
  constant c_max_oob_size_width : integer := integer(CEIL(LOG2(real(g_max_oob_size + 1))));

  --maximum time we wait for transfer before deciding the core is stuck
  constant c_max_transfer_delay       : integer := g_num_ports+2;
  constant c_max_transfer_delay_width : integer := integer(CEIL(LOG2(real(c_max_transfer_delay + 1))));
  

  type t_page_alloc is(  S_IDLE,          -- waiting for some work :)
                         S_PCKSTART_SET_AND_REQ, -- new state to do setting usecnt and requesting 
                                                 -- new page at the same time 
                         S_PCKSTART_SET_USECNT,  -- setting usecnt to a page which was allocated 
                                  -- in advance to be used for the first page of 
                                  -- the pck
                                  -- (only in case of the initially allocated usecnt
                                  -- is different than required)
                         S_PCKSTART_PAGE_REQ,  -- allocating in advnace first page of the pck
                         S_PCKINTER_PAGE_REQ);  -- allocating in advance page to be used by 
                                  -- all but first page of the pck (inter-packet)
  type t_transfer_pck is(S_IDLE,  -- wait for some work :), it is used only after reset
                         S_READY,  -- being in S_READY state means that we are in sync with rcv_pck
                         S_WAIT_RTU_VALID,  -- Started receiving pck, wait for RTU decision
                         S_WAIT_SOF,  -- received RTU decision but new pck has not been started
                                      -- still receiving the old one, or non
                         S_SET_USECNT,  -- set usecnt of the first page
                         S_WAIT_WITH_TRANSFER,  -- waits for ll_write to clear the first page
                         S_TOO_LONG_TRANSFER,
                         S_TRANSFER,    -- transfer pck to the outputs

                         S_TRANSFERED,  -- transfer has been done, waiting for the end of pck (EOF                         
                         S_DROP  -- after receiving RTU decision to drop the pck,
                                 -- it still needs to be received
                         ); 

  type t_rcv_pck is(S_IDLE,             -- wait for some work :)
                         S_READY,  -- Can accept new pck (i.e. the previous pck has been transfered
                         S_PAUSE,  -- need to pause reception (internal reason, e.g.: next page not allocated) 
                                   -- still receiving the old one, or non
                         S_RCV_DATA,    -- accepting pck
                         S_DROP,        -- if 
                         S_WAIT_FORCE_FREE,  -- waits for the access to the force freeing process (it
                                   -- only happens when the previous request has not been handled
                                   -- (in theory, hardly possible, so it will happen for sure ;=))
                         S_INPUT_STUCK  -- it might happen that the SWcore gets stack, in such case we need 
                                   -- to decide what to do (drop/stall/etc), it is recognzied and done
                                   -- here
                         );

  type t_ll_write is(S_IDLE,            -- wait for some work :)
                          S_READY_FOR_PGR_AND_DLAST,  -- can write both: 
                              --  (1) request of inter-pck page (mpm_pg_req_i)
                              --  (2) request of last page write (dlast)                                                       
                          S_READY_FOR_DLAST_ONLY,  -- can write only last page (dlast) since the
                              -- inter-pck page has not been allocated yet
                          S_WRITE,  -- write Linked List (either double write (with 
                              -- clearing the next page to be used) or just
                              -- one page (if next page not allocated yet)
                          S_EOF_ON_WR,  -- request for writting the last page (dlast) 
                              -- received while writting to Linked List
                          S_SOF_ON_WR  -- reception of new PCK received while writting
                          );  -- this might require some work (if the next
                              -- first page is not cleard) but it also might
                              -- require no work 
  -- state machines
  signal s_page_alloc   : t_page_alloc;  -- page allocation and usecnt setting
  signal s_transfer_pck : t_transfer_pck;  -- reception of RTU decision, its transfer to outputs
  signal s_rcv_pck      : t_rcv_pck;  -- pck reception (pWB sink), writting to MPM 
  signal s_ll_write     : t_ll_write;   -- writting Linked List

  -- pckstart page allocation in advance
  signal pckstart_page_in_advance : std_logic;
  -- page addr allocated in advance
  signal pckstart_pageaddr        : std_logic_vector(g_page_addr_width - 1 downto 0);
  -- the usecnt of the page allocated in advance, usecnt given to allocator
  -- at the moment of allocation. this value is stored in the same moment as pckstart_pageaddr
  -- and later compared with the needed value
  signal pckstart_usecnt          : std_logic_vector(g_usecount_width - 1 downto 0);
  signal pckstart_page_alloc_req  : std_logic;
  signal pckstart_usecnt_req      : std_logic;
  signal pckstart_usecnt_write    : std_logic_vector(g_usecount_width - 1 downto 0);
  -- previously set usecnt (not necessarly the same as pckstart_usecnt !!!)
  signal pckstart_usecnt_prev     : std_logic_vector(g_usecount_width - 1 downto 0);
  signal pckstart_usecnt_next     : std_logic_vector(g_usecount_width - 1 downto 0);
  signal pckstart_usecnt_pgaddr   : std_logic_vector(g_page_addr_width - 1 downto 0);

  -- interpck page allocation in advance
  signal pckinter_page_in_advance : std_logic;
  signal pckinter_pageaddr        : std_logic_vector(g_page_addr_width - 1 downto 0);
  signal pckinter_page_alloc_req  : std_logic;

  -- 
  signal rtu_dst_port_usecnt : std_logic_vector(g_usecount_width - 1 downto 0);
  signal rtu_rsp_ack         : std_logic;

  -- rtu decision stored for the current pck
  signal current_prio      : std_logic_vector(g_prio_width - 1 downto 0);
  signal current_mask      : std_logic_vector(g_num_ports - 1 downto 0);
  signal current_res_info  : std_logic_vector(g_resource_num_width-1 downto 0);
  signal current_hp        : std_logic;
  signal current_usecnt    : std_logic_vector(g_usecount_width - 1 downto 0);
  signal current_drop      : std_logic;

  -- this is stored when first page is taken from the allocated in advanced register
  signal current_pckstart_pageaddr : std_logic_vector(g_page_addr_width - 1 downto 0);
  -- we remember what was it's usecant at the time
  signal current_pckstart_usecnt   : std_logic_vector(g_usecount_width - 1 downto 0);

  -- signals sent to Pck Transfer Unit  
  signal pta_transfer_pck : std_logic;
  signal pta_pageaddr     : std_logic_vector(g_page_addr_width - 1 downto 0);
  signal pta_mask         : std_logic_vector(g_num_ports - 1 downto 0);
  signal pta_resource     : std_logic_vector(g_resource_num_width-1 downto 0);
  signal pta_hp           : std_logic;
  signal pta_prio         : std_logic_vector(g_prio_width - 1 downto 0);
--   signal pta_pck_size              : std_logic_vector(g_max_pck_size_width - 1 downto 0);  

  -- signals to MPM (registered) 
  signal mpm_data      : std_logic_vector(g_mpm_data_width - 1 downto 0);
  signal mpm_dvalid    : std_logic;
  signal mpm_pg_addr   : std_logic_vector(g_page_addr_width - 1 downto 0);
  signal mpm_dlast     : std_logic;
  -- we need to have single stage history 
  signal mpm_dlast_d0  : std_logic;
  signal mpm_pg_req_d0 : std_logic;

  -- pWB interface (i/o singals)
  -- input
  signal snk_dat_int       : std_logic_vector(15 downto 0);
  signal snk_adr_int       : std_logic_vector(1 downto 0);
  signal snk_sel_int       : std_logic_vector(1 downto 0);
  signal snk_cyc_int       : std_logic;
  signal snk_stb_int       : std_logic;
  signal snk_we_int        : std_logic;
  signal snk_stall_int     : std_logic;
  -- outputs
  signal snk_ack_int       : std_logic;
  signal snk_rty_int       : std_logic;
  signal snk_stall_force_h : std_logic;
  signal snk_stall_force_l : std_logic;

  -- we need to have single stage history
  signal snk_sel_d0   : std_logic_vector(1 downto 0);
  signal snk_cyc_d0   : std_logic;
  signal snk_adr_d0   : std_logic_vector(1 downto 0);
  signal snk_stall_d0 : std_logic;

  -- in_pck_* are the signals which are derived from snk_* signals (most is compinational logic, 
  -- derived on the fly) to get some extra info (e.g.: EOF, SOF, valid...) and make them more 
  -- useable for writting to MPM and Linked List
  signal in_pck_dvalid       : std_logic;
  signal in_pck_dat          : std_logic_vector(g_mpm_data_width - 1 downto 0);
  signal in_pck_sof          : std_logic;  -- start of frame
  signal in_pck_eof          : std_logic;  -- end of frame
  signal in_pck_err          : std_logic;  -- error
  signal in_pck_eod          : std_logic;  -- end of data
  signal in_pck_eof_normal   : std_logic;
  signal in_pck_eof_on_pause : std_logic;
  signal in_pck_sof_allowed  : std_logic;
  signal in_pck_sof_delayed  : std_logic;
  -- first stage register (delayed single cycle)
  signal in_pck_dvalid_d0    : std_logic;
  signal in_pck_dat_d0       : std_logic_vector(g_mpm_data_width - 1 downto 0);

  -- used to produce delayed in_pck_sof -- basically, this is illegal by pWB standard, but 
  -- if it happens, we loose, pck, why not to take care of this?
  signal in_pck_sof_on_stall : std_logic;

  -- indicates that the reception of pck finishes due to :
  -- (1) eof, error    (by in_pck_*)
  -- (2) drop decision (by transfer_pck FSM)
  signal finish_rcv_pck : std_logic;

  -- speaking with MMU
  signal mmu_force_free_req  : std_logic;
  signal mmu_force_free_addr : std_logic_vector(g_page_addr_width - 1 downto 0);

  -- counters to be written in Linked List
  signal page_word_cnt : unsigned(c_page_size_width - 1 downto 0);

  -- tracking transfer time, it transfer takes too long (should be max of 2*port_number)
  -- it means that SWcore is stuck and proper action must be taken 
  signal transfer_delay_cnt : unsigned(c_max_transfer_delay_width -1 downto 0);
  signal max_transfer_delay : std_logic;

  -- used in rcv_pck FSM
  signal new_pck_first_page : std_logic;
  -------------------------------------------------------------------------------
  -- signals used to store information for and interface with Linked List
  -------------------------------------------------------------------------------

  -- to make my life easier :) and code more readible
  type t_ll_entry is record
    valid           : std_logic;
    eof             : std_logic;
    next_page       : std_logic_vector(g_page_addr_width - 1 downto 0);
    next_page_valid : std_logic;
    addr            : std_logic_vector(g_page_addr_width - 1 downto 0);
    size            : std_logic_vector(c_page_size_width - 1 downto 0);
    first_page_clr  : std_logic;
  end record;

  -- entry to store data to be written to Linked List
  signal ll_entry     : t_ll_entry;
  -- if we receive request to write data to LL while we are currently writing data, store it in TEMP
  signal ll_entry_tmp : t_ll_entry;

  -- control Linked List writing process
  signal ll_wr_req : std_logic;

  -- data assembled to be written to the shared part of ll_data_o when EOF is true, otherwise 
  -- ll_entry.next_page is written
  signal ll_data_eof : std_logic_vector(g_page_addr_width - 1 downto 0);

  -- remembers the pckstart page address which has been cleared recently
  signal pckstart_pageaddr_clred : std_logic_vector(g_page_addr_width - 1 downto 0);
  -------------------------------------------------------------------------------
  -- signals used to to sync all the State Machines (this is fun!!!)
  -------------------------------------------------------------------------------

  -- indicates that rcv_pck FSM is ready for sync with ll_write and transfer_pck FSMs
  signal rp_sync : std_logic;

  --it is asserted when error from the source is received
  --it is set in rcv_pck FSM and read by transfer_pck FSM
  signal rp_in_pck_err : std_logic;

  -- Signal set by rcv_pck, indicates that we decided to drop pcks on the input, this implies that:
  -- (1) decisions from RTU which are received (in transfer_pck FSM) need to be received and ignored
  -- (2) SOF needs to be ignored by allocate process (p_page_if)-
  signal rp_drop_on_stuck : std_logic;

  -- rcv_pck FSM indicates that the transfer_pck FSM can start accetping RTU decisions
  -- (HIGH on entering READY state, gets LOW when RTU decision is received)
  signal rp_accept_rtu : std_logic;

  -- set by rcv_pck FSM to indicate to transfer_pck FSM that reception error ocured
  signal rp_in_pck_error : std_logic;

  -- if HIGH, it means that we are receiving/writting the first page of the pck
  signal rp_rcv_first_page : std_logic;

  -- Signals written by rcv_pck FSM and used by ll_write FSM, sync by rtu_rsp_ack
  signal rp_ll_entry_addr     : std_logic_vector(g_page_addr_width - 1 downto 0);
  signal rp_ll_entry_size     : std_logic_vector(c_page_size_width - 1 downto 0);

  -- indicates that tranfser_pck FSM is ready for sync with rcv_pck and ll_write FSMs
  signal tp_sync : std_logic;

  -- Signal set by transfer_pck FSM, which indicates to page_alloc FSM that usecnt needs to be set
  signal tp_need_pckstart_usecnt_set : std_logic;
  signal tp_drop                     : std_logic;
  signal tp_stuck                    : std_logic;
  signal tp_transfer_valid           : std_logic;



  -- used by rcv_pck FSM to sync with ll_write. checked by rcv_pck on entering READY
  signal lw_sync_first_stage : std_logic;

  -- used by rcv_pck FSM to sync with ll_write. checked at the end of each page in order
  -- to make sure that next_page address isready and we can write it instantly to linked List
  signal lw_sync_second_stage : std_logic;

  -- indicates when lw_sync_second_stage shall be verified
  signal lw_sync_2nd_stage_chk : std_logic;

  -- 
  signal lw_pckstart_pg_clred : std_logic;
  signal pckstart_pg_clred    : std_logic;

  signal alloc_FSM : std_logic_vector(2  downto 0);
  signal trans_FSM : std_logic_vector(3  downto 0);
  signal rcv_p_FSM : std_logic_vector(3  downto 0);
  signal linkl_FSM : std_logic_vector(3  downto 0);
  
  signal zeros    : std_logic_vector(g_num_ports - 1 downto 0);
  -------------------------------------------------------------------------------
  -- Function which calculates number of 1's in a vector
  ------------------------------------------------------------------------------- 
  function cnt (a : std_logic_vector) return integer is
    variable nmb    : integer range 0 to a'length;
    variable ai     : std_logic_vector(a'length-1 downto 0);
    constant middle : integer := a'length/2;
  begin
    ai := a;
    if ai'length >= 2 then
      nmb := cnt(ai(ai'length-1 downto middle)) + cnt(ai(middle-1 downto 0));
    else
      if ai(0) = '1' then
        nmb := 1;
      else
        nmb := 0;
      end if;
    end if;
    return nmb;
  end cnt;

  function f_gen_mask(index : integer; length : integer)
    return std_logic_vector is
  variable tmp : std_logic_vector(length-1 downto 0);
  begin
    tmp := (others => '0');
    tmp(index) := '1';
    return tmp;
  end function f_gen_mask;
  
  function f_slv_resize(x: std_logic_vector; len: natural) return std_logic_vector is
    variable tmp : std_logic_vector(len-1 downto 0);
  begin
    tmp := (others => '0');
    tmp(x'length-1 downto 0) := x;
    return tmp;
  end function f_slv_resize;

function f_enum2nat (enum_arg :t_page_alloc) return std_logic_vector is
begin
  for t in t_page_alloc loop
    if(enum_arg = t) then
      return std_logic_vector(to_unsigned(t_page_alloc'pos(t),4));
    end if;
  end loop;  -- i
  return "0000";
end function f_enum2nat;
function f_enum2nat (enum_arg :t_rcv_pck) return std_logic_vector is
begin
  for t in t_rcv_pck loop
    if(enum_arg = t) then
      return std_logic_vector(to_unsigned(t_rcv_pck'pos(t),4));
    end if;
  end loop;  -- i
  return "0000";
end function f_enum2nat;
function f_enum2nat (enum_arg :t_ll_write) return std_logic_vector is
begin
  for t in t_ll_write loop
    if(enum_arg = t) then
      return std_logic_vector(to_unsigned(t_ll_write'pos(t),4));
    end if;
  end loop;  -- i
  return "0000";
end function f_enum2nat;
function f_enum2nat (enum_arg :t_transfer_pck) return std_logic_vector is
begin
  for t in t_transfer_pck loop
    if(enum_arg = t) then
      return std_logic_vector(to_unsigned(t_transfer_pck'pos(t),4));
    end if;
  end loop;  -- i
  return "0000";
end function f_enum2nat;

constant c_force_usecnt             : boolean :=  TRUE;
  constant c_special_res            : std_logic_vector(7 downto 0) := x"01";
  constant c_normal_res             : std_logic_vector(7 downto 0) := x"02"; 
-- resource management
  signal mmu_resource_out           : std_logic_vector(g_resource_num_width-1 downto 0);
  signal mmu_rescnt_page_num        : std_logic_vector(g_page_addr_width-1 downto 0);
  signal mmu_res_full               : std_logic_vector(g_resource_num   -1 downto 0);
  signal mmu_res_almost_full        : std_logic_vector(g_resource_num   -1 downto 0); 

  signal unknown_res_page_cnt       : unsigned(g_page_addr_width-1 downto 0);

  signal res_info_valid             : std_logic;
  signal res_info                   : std_logic_vector(g_resource_num_width-1 downto 0);

  -- the number of pages reserved for a given resource (res_num) is not enough to accommodate
  -- max_size ethernet frame. In most cases we don't know what the received frame's sie will be
  -- (unless we needed to wait for RTU's decision to the end of reception) so we drop the frame
  -- if the resoruce is almost full
  signal res_info_almsot_full       : std_logic;
  
  -- a currently requested resource is full
  signal res_info_full              : std_logic;
  
  signal dbg_dropped_on_res_full    : std_logic;

begin  --archS_PCKSTART_SET_AND_REQ
  
  zeros                      <= (others => '0');
  --================================================================================================
  --------------------------------------------------------------------------------------------------
  -----------------------     Receiving the PCK and writting to MPM  -------------------------------
  --------------------------------------------------------------------------------------------------
  --================================================================================================  

  --==================================================================================================
  -- pWB (sink)
  --==================================================================================================
  -- indicates the beginning of new frame, according to WB standard it might happen only when stall is LOW
  in_pck_sof_allowed <= snk_cyc_int and not snk_cyc_d0 and not snk_stall_int;

  -- some implementations of WB does do start cycle on STALL, so we watch for sof on stall and
  -- regenerate sof on when stall is LOW
  in_pck_sof_delayed <= (not snk_stall_int) and snk_stall_d0 and in_pck_sof_on_stall;

  -- the final sof used throughout the input block:
  in_pck_sof <= in_pck_sof_allowed or in_pck_sof_delayed;

  -- indicates that data is valid
  in_pck_dvalid <= snk_stb_int and snk_we_int and snk_cyc_int and not snk_stall_int;

  -- we store in FBM addr and data 
  in_pck_dat <= snk_adr_int & snk_dat_int;
  
  -- detecting the end of the pck
  -- it is enough always, except special case when we receive eof during PAUSE state, 
  -- in this case,we come back to RCV_DATA and regenerate EOF (this is to make things simpler, 
  -- otherwise loads of COPY+PASE would be required)
  in_pck_eof_normal <= snk_cyc_d0 and not snk_cyc_int;

  -- the final EOF (in_pck_eof_on_pause set in rcv_pck FSM)
  in_pck_eof <= in_pck_eof_normal or in_pck_eof_on_pause;

  -- detecting error 
  in_pck_err <= '1' when in_pck_dvalid = '1' and
                   (snk_adr_int = c_WRF_STATUS) and
                   (f_unmarshall_wrf_status(snk_dat_int).error = '1') else
                   '0';

  -- to simplify stuff:
  finish_rcv_pck <= '1' when (in_pck_eof = '1' or in_pck_err = '1' or tp_drop = '1') else '0';
  --==================================================================================================
  -- FSM to receive pcks, it translates pWB I/F into MPM I/F
  --==================================================================================================

  rcv_pck_helper : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --================================================
        snk_ack_int         <= '0';
        snk_cyc_d0          <= '0';
        snk_adr_d0          <= (others => '0');
        snk_stall_d0        <= '0';
        in_pck_sof_on_stall <= '0';
        --================================================
      else
        
        snk_cyc_d0   <= snk_cyc_int;
        snk_adr_d0   <= snk_adr_int;
        snk_stall_d0 <= snk_stall_int;
        -- generating ack
        snk_ack_int  <= snk_cyc_int and snk_stb_int and snk_we_int and not snk_stall_int;

        -- tracks start of frame on the stall (not allowed, but sometimes happen)
        if(snk_cyc_int = '1' and snk_cyc_d0 = '0' and snk_stall_int = '1') then
          in_pck_sof_on_stall <= '1';
--         elsif(in_pck_delayed_sof = '1' and in_pck_sof_on_stall = '1') then
        elsif(in_pck_sof_delayed = '1' and in_pck_sof_on_stall = '1') then
          in_pck_sof_on_stall <= '0';
        end if;

      end if;  -- if(rst_n_i = '0') then
    end if;  --rising_edge(clk_i) then
  end process rcv_pck_helper;

  --==================================================================================================
  -- FSM to receive pcks, it translates pWB I/F into MPM I/F
  --==================================================================================================
  -- this FSM receives frames from the outside world with pWB and writes the data to 
  -- the MPM (async)
  -- 
  p_rcv_pck_fsm : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --========================================
        s_rcv_pck         <= S_IDLE;
        snk_stall_force_h <= '1';
        snk_stall_force_l <= '1';
        snk_sel_d0        <= (others => '0');
        page_word_cnt     <= (others => '0');

        in_pck_dvalid_d0    <= '0';
        in_pck_dat_d0       <= (others => '0');
        in_pck_eof_on_pause <= '0';



        mmu_force_free_req  <= '0';
        mmu_force_free_addr <= (others => '0');

        mpm_dvalid                <= '0';
        mpm_pg_addr               <= (others => '0');
        mpm_data                  <= (others => '0');
        mpm_dlast                 <= '0';
        current_pckstart_pageaddr <= (others => '0');
        current_pckstart_usecnt   <= (others => '0');

        new_pck_first_page   <= '0';
        -- used in other FSM 
        rp_ll_entry_addr     <= (others => '0');
        rp_ll_entry_size     <= (others => '0');
        rp_drop_on_stuck     <= '0';
        rp_in_pck_err        <= '0';
        rp_accept_rtu        <= '1';

        rp_rcv_first_page <= '0';
        --========================================
      else

        -- default values:
        mpm_dlast           <= '0';
        mpm_dvalid          <= '0';
        in_pck_eof_on_pause <= '0';
        --if(s_ll_write = S_WRITE) then
          new_pck_first_page  <= '0';
        --end if;

        case s_rcv_pck is
          --===========================================================================================
          when S_IDLE =>
            --===========================================================================================  
            snk_stall_force_h <= '1';
            snk_stall_force_l <= '1';
            in_pck_dvalid_d0  <= '0';
            in_pck_dat_d0     <= (others => '0');

            -- Sync with trasnfer_pck FSM and ll_write FSM: 
            if(lw_sync_first_stage = '1' and rp_sync = '1' and tp_sync = '1') then
              rp_in_pck_err     <= '0';
              snk_stall_force_h <= '0';
              s_rcv_pck         <= S_READY;
              rp_accept_rtu     <= '1';

              -- it might happen that the RTU decision is very late, the data is already
              -- received when we get the RTU decision, so we are waiting in IDLE.
              -- in such case, we will get tp_drop before getting tp_sync, but we will
              -- still have tp_drop when finally tp_sync is HIGH, so this is why the order of if's
            elsif(tp_drop            = '1'   and  -- transfer_pck state indicates the drop decision
                  mmu_force_free_req = '0') then  -- the pck is not being freed yet
              
              mmu_force_free_addr <= current_pckstart_pageaddr;

              if(mmu_force_free_req = '1') then  -- it means that the previous request is still 
                                                 -- waiting to be accepted, which is a very bad sign
                s_rcv_pck <= S_WAIT_FORCE_FREE;
              else
                mmu_force_free_req <= '1';
              end if;

              -- transfer seems stcuk
            elsif(tp_stuck = '1') then
              s_rcv_pck <= S_INPUT_STUCK;
              if(g_input_block_cannot_accept_data = "drop_pck") then  -- drop when stuck
                snk_stall_force_l <= '0';
                snk_stall_force_h <= '1';
                rp_drop_on_stuck  <= '1';
                rp_accept_rtu     <= '1';
              else                      -- by default: stall when stuck
                snk_stall_force_h <= '1';
                snk_stall_force_l <= '1';
              end if;
            end if;

            --===========================================================================================
          when S_READY =>
            --===========================================================================================
            in_pck_dvalid_d0 <= '0';
            in_pck_dat_d0    <= (others => '0');

            if (in_pck_sof = '1') then
              
              if(tp_drop = '1') then
                s_rcv_pck         <= S_DROP;
                snk_stall_force_l <= '0';
              else
                current_pckstart_pageaddr <= pckstart_pageaddr;
                current_pckstart_usecnt   <= pckstart_usecnt;
                mpm_pg_addr               <= pckstart_pageaddr;
                s_rcv_pck                 <= S_RCV_DATA;
                new_pck_first_page        <= '1';

                page_word_cnt <= (others => '0');
                if(in_pck_dvalid = '1') then
                  in_pck_dvalid_d0 <= in_pck_dvalid;
                  in_pck_dat_d0    <= in_pck_dat;
                end if;
              end if;
            end if;

            --===========================================================================================
          when S_RCV_DATA =>
            --===========================================================================================
            -- to extend the span of new_pck_first_page into s_ll_write = S_IDLE, when there is S_SOF
            if(s_ll_write = S_SOF_ON_WR and new_pck_first_page = '1') then
              new_pck_first_page <='1';
            end if;
            if(in_pck_dvalid = '1') then
              in_pck_dvalid_d0 <= in_pck_dvalid;
              in_pck_dat_d0    <= in_pck_dat;
            end if;

            --dlast_o needs to go along with dvalid HIGH, for eof we are sure dvalid is always OK
            --for the special cases, we validate any data
            if(finish_rcv_pck = '1') then
              mpm_dlast <= '1';
            end if;

            if(in_pck_err = '1' and tp_drop = '0') then
              -- write the error status to the memory (so it's properly sent -- with error)
              -- and indicate that the error needs to be handled in the next cycle            
              rp_in_pck_err   <= '1';
              mpm_dvalid      <= '1';
              mpm_data        <= in_pck_dat;                
            -- write to MPM data only if you know two consequtive WB writes, this is to detect EOF and
            -- set HIGH dlast at an appropriate time
            elsif((in_pck_dvalid = '1' and in_pck_dvalid_d0 = '1') or finish_rcv_pck = '1') then
              mpm_dvalid <= '1';
              mpm_data   <= in_pck_dat_d0;

            end if;

            -- here we count the size of page and oob
            if((in_pck_dvalid = '1' and in_pck_dvalid_d0 = '1') or finish_rcv_pck = '1') then
              if(mpm_pg_req_i = '1') then
                page_word_cnt <= to_unsigned(1, c_page_size_width);
              else
                page_word_cnt <= page_word_cnt + 1;
              end if;
            elsif(mpm_pg_req_i = '1') then
              page_word_cnt <= (others => '0');
            end if;

            --- below deciding on the next state:
            if(rp_in_pck_err = '1') then

              snk_stall_force_h <= '1';
              snk_stall_force_l <= '1';
              rp_in_pck_err     <= '1';

              -- pck has not been transferred (or is not being transferred), in such case
              -- we need to handle page freeing on our side
              if(tp_transfer_valid = '0') then
                
                mmu_force_free_addr <= current_pckstart_pageaddr;

                -- it means that the previous request is still 
                -- waiting to be accepted, which is a very bad sign
                if(mmu_force_free_req = '1') then
                  s_rcv_pck <= S_WAIT_FORCE_FREE;
                else
                  mmu_force_free_req <= '1';
                  s_rcv_pck          <= S_IDLE;
                end if;
              else
                s_rcv_pck <= S_IDLE;
              end if;

              -- decision from RTU to drop, PCK has not been transfered at all, so we need 
              -- to handle freeing. we also need to receive the rest of the pck
              -- TODO(1.0): throw error????
            elsif(tp_drop = '1') then
              
              mmu_force_free_addr <= current_pckstart_pageaddr;

              if(mmu_force_free_req = '1') then  -- it means that the previous request is still 
                                                 -- waiting to be accepted, which is a very bad sign
                s_rcv_pck <= S_WAIT_FORCE_FREE;
              else
                mmu_force_free_req <= '1';
                s_rcv_pck          <= S_DROP;
              end if;

              snk_stall_force_l <= '0';
              
            elsif(in_pck_eof = '1') then
              
              snk_stall_force_h <= '0';
              snk_stall_force_l <= '1';
              s_rcv_pck         <= S_IDLE;

              -- we always have in this memoment new pckinter_pageaddr allocated because
              -- we check we have it in advance with the next 'elsif' and if we don't have
              -- it in advance, we PAUSE
            elsif(mpm_pg_req_i = '1') then  -- MPM asserts pg_req HIGH only if dvalid is HIGH

              if(page_word_cnt /= to_unsigned(g_page_size, c_page_size_width)) then
                assert false
                  report "something is wrong with word counting, pg_req_i received in the middle of page";
              end if;

              mpm_pg_addr <= pckinter_pageaddr;

              -- sync with (expliclitely) with ll_write and (implicitely) with transfer_pck 
              -- (transfer waits for  first page to be cleared (which is condition of sync_2nd_stage, 
            elsif(lw_sync_2nd_stage_chk = '1' and lw_sync_second_stage = '0') then
              
              snk_stall_force_h <= '1';
              s_rcv_pck         <= S_PAUSE;

            end if;

            --===========================================================================================
          when S_DROP =>
            --===========================================================================================
            
            if (in_pck_eof = '1' or in_pck_err = '1') then
              rp_drop_on_stuck  <= '0';
              snk_stall_force_h <= '1';
              snk_stall_force_l <= '1';
              s_rcv_pck         <= S_IDLE;
            end if;

            --===========================================================================================
          when S_PAUSE =>
            --===========================================================================================
            -- remember the error and enter RCV_DATA state where the error will be handled 
            -- properly (it's done like this to avoid copying the same code
            if(in_pck_err = '1') then
              snk_stall_force_h <= '0';
              rp_in_pck_err     <= '1';
              s_rcv_pck         <= S_RCV_DATA;

              -- the tp_drop is  going to be asserted also in next cycle, so go to RCV_DATA where it will
              -- be handled properly (it's done like this to avoid copying the same code              
            elsif(tp_drop = '1') then
              snk_stall_force_h <= '0';
              s_rcv_pck         <= S_RCV_DATA;

              -- so we finish   
            elsif(in_pck_eof = '1') then
              in_pck_eof_on_pause <= '1';
              snk_stall_force_h   <= '1';
              snk_stall_force_l   <= '1';
              s_rcv_pck           <= S_RCV_DATA;

              -- back to work :)
            elsif(lw_sync_second_stage = '1') then
              snk_stall_force_h <= '0';
              s_rcv_pck         <= S_RCV_DATA;
            end if;

            --===========================================================================================
          when S_WAIT_FORCE_FREE =>
            --===========================================================================================

            if(mmu_force_free_req = '0') then
              mmu_force_free_req  <= '1';
              mmu_force_free_addr <= current_pckstart_pageaddr;
              snk_stall_force_h   <= '1';
              snk_stall_force_l   <= '1';
              s_rcv_pck           <= S_IDLE;
            end if;
            --===========================================================================================
          when S_INPUT_STUCK =>
            --===========================================================================================
            
            if(tp_stuck = '0') then     -- un-stuck the input :)

              s_rcv_pck <= S_IDLE;
              
            else                        -- still stuck

              -- drop when stuck
              if(g_input_block_cannot_accept_data = "drop_pck") then
                snk_stall_force_l <= '0';
                if (in_pck_sof = '1') then
                  s_rcv_pck <= S_DROP;
                end if;

                -- by default: stall when stuck
              else
                snk_stall_force_h <= '1';
              snk_stall_force_l <= '1';
            end if;
        end if;

    --===========================================================================================
    when others =>
    --===========================================================================================           
    snk_stall_force_h <= '1';
    snk_stall_force_l <= '1';
    s_rcv_pck         <= S_IDLE;
  end case;

  if(mmu_force_free_req = '1' and mmu_force_free_done_i = '1') then
    mmu_force_free_req <= '0';
  end if;

  -- we set the *rp_rcv_first_page* one cycle after entering RCV_DATA, this is on purpose !
  -- we need *rp_rcv_first_page* to identify which pckstart_pageaddr clear 
  -- (1) the one stored in pckstart_addr (allocated in advance)
  -- (2) the one stored in  current_pckstart_pageaddr
  -- as soon as RCV_DATA state is entered the first time for a given pck reception,
  -- the pckstart_addr is copied to current_pckstart_pageaddr and new pckstart_addr is 
  -- requestd, but the request takes time (more then 1 cycle). so we delay setting of 
  -- *rp_rcv_first_page* to be able to copie the addr to be clearted (in ll_write FSM) from 
  -- current_pckstart_pageaddr in case *rp_rcv_first_page* is asserted
  if(new_pck_first_page = '1' and rp_rcv_first_page = '0') then
    rp_rcv_first_page <= '1';
  elsif((mpm_pg_req_i = '1' or mpm_dlast = '1') and rp_rcv_first_page = '1') then
    rp_rcv_first_page <= '0';
  end if;

  if(mpm_pg_req_i = '1' or mpm_dlast = '1') then
    rp_ll_entry_size     <= std_logic_vector(page_word_cnt);
    rp_ll_entry_addr     <= mpm_pg_addr;
  end if;

  if(rp_accept_rtu = '1' and rtu_rsp_ack = '1') then
    rp_accept_rtu <= '0';
  end if;
  
end if;
end if;

end process p_rcv_pck_fsm;
--================================================================================================
--------------------------------------------------------------------------------------------------
-------------      Speaking with MMU (page allocating and usecnt setting)  -----------------------
--------------------------------------------------------------------------------------------------
--================================================================================================

--================================================================================================
-- for page allocation
--================================================================================================
p_page_if : process(clk_i, rst_n_i)
begin
  if rising_edge(clk_i) then
    if(rst_n_i = '0') then
      --===================================================
      pckstart_page_in_advance <= '0';
      pckinter_page_in_advance <= '0';
      --===================================================
    else
      
      if(in_pck_sof = '1' and tp_drop = '0' and rp_drop_on_stuck = '0') then
        pckstart_page_in_advance <= '0';
      elsif(mmu_page_alloc_done_i = '1' and pckstart_page_alloc_req = '1') then
        pckstart_page_in_advance <= '1';
      end if;

      if(mpm_pg_req_i = '1' and mpm_dlast = '0') then
        pckinter_page_in_advance <= '0';
      elsif(mmu_page_alloc_done_i = '1' and pckinter_page_alloc_req = '1') then
        pckinter_page_in_advance <= '1';
      end if;

    end if;
  end if;
end process p_page_if;

--==================================================================================================
-- FSM to allocate pages in advance and set USECNT of pages (pckstart) allocated in advance
--==================================================================================================
-- Auxiliary Finite State Machine which talks with
-- Memory Management Unit, it controls:
-- * page allocation
-- * usecnt setting
p_page_alloc_fsm : process(clk_i, rst_n_i)
begin
  if rising_edge(clk_i) then
    if(rst_n_i = '0') then
      --========================================
      s_page_alloc <= S_IDLE;

      pckinter_pageaddr       <= (others => '0');
      pckinter_page_alloc_req <= '0';

      pckstart_pageaddr       <= (others => '0');
      pckstart_usecnt         <= (others => '0');
      pckstart_page_alloc_req <= '0';

      pckstart_usecnt_req    <= '0';
      pckstart_usecnt_write  <= (others => '0');
      pckstart_usecnt_prev   <= (others => '0');
      pckstart_usecnt_pgaddr <= (others => '0');
      
      --- management
      mmu_resource_out       <= (others => '0');
      mmu_rescnt_page_num    <= (others => '0');

      --========================================
    else

      -- main finite state machine 
      -- 
      case s_page_alloc is

        --===========================================================================================
        when S_IDLE =>
          --===========================================================================================   
          pckinter_page_alloc_req <= '0';
          pckstart_page_alloc_req <= '0';
          pckstart_usecnt_req     <= '0';

--------------------------------------------new crap ---------------------------------------------------
--           if(tp_need_pckstart_usecnt_set = '1') then
--           
--             s_page_alloc            <= S_PCKSTART_SET_AND_REQ;
--             pckstart_usecnt_req     <= '1';
--             pckstart_page_alloc_req <= '1';
--             pckstart_usecnt_pgaddr  <= current_pckstart_pageaddr;
--             pckstart_usecnt_write   <= current_usecnt;
--             pckstart_usecnt_prev    <= current_usecnt;
--             ---------- source management  --------------
--             mmu_resource_out        <= current_res_info; --res_info; 
--             mmu_rescnt_page_num     <= std_logic_vector(unknown_res_page_cnt);
--             -------------------------------------------          
----- ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^-------          

------------------------------------------ old crap ---------------------------------------------------
          if(tp_need_pckstart_usecnt_set = '1') then

            s_page_alloc           <= S_PCKSTART_SET_USECNT;
            pckstart_usecnt_req    <= '1';
            pckstart_usecnt_pgaddr <= current_pckstart_pageaddr;
            pckstart_usecnt_write  <= current_usecnt;
            pckstart_usecnt_prev   <= current_usecnt;
            ---------- source management  --------------
            mmu_resource_out       <= current_res_info; --res_info; 
            mmu_rescnt_page_num    <= std_logic_vector(unknown_res_page_cnt);
            -------------------------------------------
            
          elsif(pckstart_page_in_advance = '0' and  
                rtu_rsp_ack              = '0') then -- added to give precedence to usecnt set
            
            pckstart_page_alloc_req <= '1';
            s_page_alloc            <= S_PCKSTART_PAGE_REQ;
            pckstart_usecnt_write   <= pckstart_usecnt_prev;
            ---------- source management  --------------
            mmu_resource_out        <= (others => '0'); -- always zero, even if we know (rare case)
            mmu_rescnt_page_num     <= (others => '0'); -- we don't use it here           
            -------------------------------------------
-------^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^----------------
            
          elsif(pckinter_page_in_advance = '0' and 
                rtu_rsp_ack              = '0') then -- added to give precedence to usecnt set
            
            pckinter_page_alloc_req <= '1';
            s_page_alloc            <= S_PCKINTER_PAGE_REQ;
            pckstart_usecnt_write   <= std_logic_vector(to_unsigned(1, g_usecount_width));
            ---------- source management  --------------
            if(res_info_valid = '1') then
              mmu_resource_out        <= current_res_info;--res_info;
            else
              mmu_resource_out        <= (others => '0');            
            end if;
            mmu_rescnt_page_num     <= (others => '0'); -- we don't use it here        
            -------------------------------------------  

          end if;

          --===========================================================================================
        when S_PCKSTART_SET_AND_REQ =>
          --===========================================================================================    

          if(mmu_set_usecnt_done_i = '1') then
            pckstart_usecnt_req     <= '0';
          end if;

          if(mmu_page_alloc_done_i = '1') then
            pckstart_page_alloc_req <= '0';            
            -- remember the page start addr
            pckstart_pageaddr       <= mmu_pageaddr_i;
            pckstart_usecnt         <= pckstart_usecnt_write;     
          end if;

          -- it might happen that there is no more pages (but should not) and the usecnt_done
          -- comes earlier then alloc_done. This is why we consider two cases for usecnt.
          if((mmu_set_usecnt_done_i = '1' or pckstart_usecnt_req ='0') and mmu_page_alloc_done_i = '1') then
            
            if(pckinter_page_in_advance = '0') then
              
              pckinter_page_alloc_req <= '1';
              s_page_alloc            <= S_PCKINTER_PAGE_REQ;
              pckstart_usecnt_write   <= std_logic_vector(to_unsigned(1, g_usecount_width));
              ---------- source management  --------------
              if(res_info_valid = '1') then
                mmu_resource_out        <= current_res_info; --res_info;
              else
                mmu_resource_out        <= (others => '0');            
              end if;
              mmu_rescnt_page_num     <= (others => '0'); -- we don't use it here        
              ------------------------------------------- 
              
            else
              
              s_page_alloc <= S_IDLE;
              
            end if;
            
          end if;

          --===========================================================================================
        when S_PCKSTART_SET_USECNT =>
          --===========================================================================================        
          if(mmu_set_usecnt_done_i = '1') then
            
            pckstart_usecnt_req <= '0';

            if(pckstart_page_in_advance = '0') then
              
              pckstart_page_alloc_req <= '1';
              s_page_alloc            <= S_PCKSTART_PAGE_REQ;
              pckstart_usecnt_write   <= pckstart_usecnt_prev;
              ---------- source management  --------------
              mmu_resource_out        <= (others => '0'); -- always zero, even if we know (rare case)
              mmu_rescnt_page_num     <= (others => '0'); -- we don't use it here           
              -------------------------------------------
              
            elsif(pckinter_page_in_advance = '0') then
              
              pckinter_page_alloc_req <= '1';
              s_page_alloc            <= S_PCKINTER_PAGE_REQ;
              pckstart_usecnt_write   <= std_logic_vector(to_unsigned(1, g_usecount_width));
              ---------- source management  --------------
              if(res_info_valid = '1') then
                mmu_resource_out        <= current_res_info; --res_info;
              else
                mmu_resource_out        <= (others => '0');            
              end if;
              mmu_rescnt_page_num     <= (others => '0'); -- we don't use it here        
              ------------------------------------------- 
              
            else
              
              s_page_alloc <= S_IDLE;
              
            end if;
            
          end if;

          --===========================================================================================  
        when S_PCKSTART_PAGE_REQ =>
          --===========================================================================================
          if(mmu_page_alloc_done_i = '1') then

            pckstart_page_alloc_req <= '0';

            -- remember the page start addr
            pckstart_pageaddr <= mmu_pageaddr_i;
            pckstart_usecnt   <= pckstart_usecnt_write;

            if(tp_need_pckstart_usecnt_set = '1') then
              
              s_page_alloc           <= S_PCKSTART_SET_USECNT;
              pckstart_usecnt_req    <= '1';
              pckstart_usecnt_pgaddr <= current_pckstart_pageaddr;
              pckstart_usecnt_write  <= current_usecnt;
              pckstart_usecnt_prev   <= current_usecnt;
              ---------- source management  --------------
              mmu_resource_out       <= current_res_info; --res_info; 
              mmu_rescnt_page_num    <= std_logic_vector(unknown_res_page_cnt);
              -------------------------------------------
              
            elsif(pckinter_page_in_advance = '0') then
              
              pckinter_page_alloc_req <= '1';
              s_page_alloc            <= S_PCKINTER_PAGE_REQ;
              pckstart_usecnt_write   <= std_logic_vector(to_unsigned(1, g_usecount_width));
              ---------- source management  --------------
              if(res_info_valid = '1') then
                mmu_resource_out        <= current_res_info; --res_info;
              else
                mmu_resource_out        <= (others => '0');            
              end if;
              mmu_rescnt_page_num     <= (others => '0'); -- we don't use it here        
              ------------------------------------------- 
              
            else
              
              s_page_alloc <= S_IDLE;
              
            end if;
          end if;

          --===========================================================================================
        when S_PCKINTER_PAGE_REQ =>
          --===========================================================================================
          
          if(mmu_page_alloc_done_i = '1') then
            
            pckinter_page_alloc_req <= '0';
            pckinter_pageaddr       <= mmu_pageaddr_i;

            if(tp_need_pckstart_usecnt_set = '1') then
              
              s_page_alloc           <= S_PCKSTART_SET_USECNT;
              pckstart_usecnt_req    <= '1';
              pckstart_usecnt_pgaddr <= current_pckstart_pageaddr;
              pckstart_usecnt_write  <= current_usecnt;
              pckstart_usecnt_prev   <= current_usecnt;
              ---------- source management  --------------
              mmu_resource_out       <= current_res_info;--res_info; 
              mmu_rescnt_page_num    <= std_logic_vector(unknown_res_page_cnt);
              -------------------------------------------
              
            elsif(pckstart_page_in_advance = '0') then
              
              pckstart_page_alloc_req <= '1';
              s_page_alloc            <= S_PCKSTART_PAGE_REQ;
              pckstart_usecnt_write   <= pckstart_usecnt_prev;
              ---------- source management  --------------
              mmu_resource_out        <= (others => '0'); -- always zero, even if we know (rare case)
              mmu_rescnt_page_num     <= (others => '0'); -- we don't use it here           
              -------------------------------------------
              
            else
              
              s_page_alloc <= S_IDLE;
              
            end if;
          end if;

          --===========================================================================================
        when others =>
          --===========================================================================================           
          s_page_alloc <= S_IDLE;
          
      end case;
    end if;
  end if;
end process p_page_alloc_fsm;

--================================================================================================
--------------------------------------------------------------------------------------------------
-------------------      Receiving and transfering Forwarding Decision  --------------------------
--------------------------------------------------------------------------------------------------
--================================================================================================

p_register_rtu_rsp : process(clk_i)
begin
  if rising_edge(clk_i) then
    if(rst_n_i = '0') then
      --========================================
      current_mask      <= (others => '0');
      current_res_info  <= (others => '0');
      current_hp        <= '0';
      current_drop      <= '0';
      current_usecnt    <= (others => '0');
      current_prio      <= (others => '0');
      current_usecnt    <= (others => '0');
      rtu_rsp_ack       <= '0';
      --========================================
    else
      -- remember input rtu decision
      if(rtu_rsp_valid_i = '1' and rtu_rsp_ack = '0' and rp_accept_rtu = '1') then
        -- make sure we're not forwarding packets to ourselves. 
        current_mask      <= rtu_dst_port_mask_i; -- and (not f_gen_mask(g_port_index, current_mask'length));
        current_res_info  <= res_info;
        current_hp        <= rtu_hp_i         ;
        current_prio      <= rtu_prio_i;
        current_drop      <= rtu_drop_i;-- or res_info_almsot_full;
        current_usecnt    <= rtu_dst_port_usecnt;

        rtu_rsp_ack <= '1';
      else
        rtu_rsp_ack <= '0';
      end if;
    end if;
  end if;
end process p_register_rtu_rsp;

p_cnts : process(clk_i)
begin
  if rising_edge(clk_i) then
    if(rst_n_i = '0') then
      --================================================
      transfer_delay_cnt <= (others => '0');
      max_transfer_delay <= '0';
      --================================================
    else
      
      if(pta_transfer_pck = '1' and max_transfer_delay = '0') then
        transfer_delay_cnt <= transfer_delay_cnt + 1;
      elsif(pta_transfer_pck = '0') then
        transfer_delay_cnt <= (others => '0');
      end if;

      if(transfer_delay_cnt < to_unsigned(c_max_transfer_delay, transfer_delay_cnt'length)) then
        max_transfer_delay <= '0';
      else
        max_transfer_delay <= '1';
      end if;
      
    end if;  -- if(rst_n_i = '0') then
  end if;  --rising_edge(clk_i) then
end process p_cnts;

p_2nd_stage_syc : process(clk_i)
begin
  if rising_edge(clk_i) then
    if(rst_n_i = '0') then
      --================================================
      pckstart_pg_clred       <= '0';
      lw_pckstart_pg_clred    <= '0';
      pckstart_pageaddr_clred <= (others => '1');  --make it different then the first allocated addr
      --================================================
    else

      if(lw_sync_first_stage = '1' and rp_sync = '1' and tp_sync = '1') then
        lw_pckstart_pg_clred <= '0';
      elsif(pckstart_pg_clred = '1' and rp_rcv_first_page = '1' and pckstart_pageaddr_clred = current_pckstart_pageaddr) then
        lw_pckstart_pg_clred <= '1';
      end if;

      if(ll_wr_req = '1' and ll_wr_done_i = '1' and ll_entry.first_page_clr = '1') then
        if(ll_entry.next_page_valid = '1') then
          pckstart_pageaddr_clred <= ll_entry.next_page;
        else
          pckstart_pageaddr_clred <= ll_entry.addr;
        end if;
      end if;


      -- clear before starting receive pck
--        if(lw_sync_first_stage = '1' and rp_sync = '1' and  tp_sync ='1') then 
--          lw_pckstart_pg_clred <= '0';

      -- as soon as the pckstart_addr is known to be cleared (could be the first cycle of RCV_DATA)
      -- remember it for the rest of pck reception. as soon as in_pck_sof is received, RCV_DATA
      -- is entered and next page is requested)
--        elsif( (s_rcv_pck = S_RCV_DATA or s_rcv_pck = S_PAUSE) and
--               (pckstart_pg_clred = '1' and pckstart_pageaddr_clred = current_pckstart_pageaddr) ) then
--          lw_pckstart_pg_clred <= '1';
--        end if;

      -- if the written page is the one which we started clearing, it means that  we've used it
      -- we check it at the beginning of the request, so that when we finish the WRITE state,
      -- we can verify *pckstart_pg_clred* and based on its value decide whether clearing
      -- new first page is needed
      if(ll_wr_req = '1' and pckstart_pg_clred = '1' and  -- @ beginning of req
         ll_entry.addr = pckstart_pageaddr_clred and ll_entry.valid = '1') then 
        pckstart_pg_clred <= '0';
      end if;

      -- if we just cleanred a page, remember the page and that we have something clred
      if(ll_wr_req = '1' and ll_wr_done_i = '1' and ll_entry.first_page_clr = '1') then
        
        pckstart_pg_clred <= '1';

        -- remember the page which you just cleared
        -- it is used to sync ll_write FSM with rcv_pck FSM and also transfer_pck            
        if(ll_entry.next_page_valid = '1') then
          pckstart_pageaddr_clred <= ll_entry.next_page;
        else
          pckstart_pageaddr_clred <= ll_entry.addr;
        end if;
      end if;
      
    end if;
  end if;
end process p_2nd_stage_syc;
--==================================================================================================
-- FSM to receive RTU decision, set usecnt and transfer pck to the output ports
--==================================================================================================
-- here we wait for the RTU decision and start of pck (start of frame, SOF). once we have both, we
-- transmit the pck_info to the outputs and ask for the end of pck (end of frame, EOF)
-- 
p_transfer_pck_fsm : process(clk_i)
begin
  if rising_edge(clk_i) then
    if(rst_n_i = '0') then
      --========================================
      s_transfer_pck <= S_IDLE;

      tp_need_pckstart_usecnt_set <= '0';

      pta_transfer_pck <= '0';
      pta_pageaddr     <= (others => '0');
      pta_mask         <= (others => '0');
      pta_resource     <= (others => '0');
      pta_hp           <= '0';
      pta_prio         <= (others => '0');
      --========================================
    else

      case s_transfer_pck is
        --===========================================================================================
        when S_IDLE =>                  -- used only during start
          --===========================================================================================  
          if(lw_sync_first_stage = '1' and rp_sync = '1' and tp_sync = '1') then
            s_transfer_pck <= S_READY;
          end if;
          --===========================================================================================
        when S_READY =>
          --===========================================================================================  
          -- being in S_READY state means that we are in sync with rcv_pck 

          -- won lotery: you have RTU data and SOF at the same time, the data has been ack-ed
          -- the SOF should not happen if rcv_pck FSM is not ready !!!!
          -- this is the sync between these two FSMs
          if(rtu_rsp_ack = '1' and tp_drop = '1') then  -- impossible to have rp_in_pck_error here
            
            s_transfer_pck <= S_DROP;
            
          elsif(rtu_rsp_ack = '1' and in_pck_sof = '1') then

            -- don't need to set usecnt
            if(current_usecnt = current_pckstart_usecnt and c_force_usecnt=FALSE) then
              -- if(current_usecnt = pckstart_usecnt_prev) then

              -- first page is cleared in the Linked List
              if(lw_pckstart_pg_clred = '1') then
                
                s_transfer_pck   <= S_TRANSFER;
                pta_transfer_pck <= '1';
                pta_mask         <= current_mask;
                pta_resource     <= current_res_info;
                pta_hp           <= current_hp;
                pta_prio         <= current_prio;
                -- we take stright from allocated in 
                -- advance because we are on SOF
                pta_pageaddr     <= pckstart_pageaddr;

                -- wait for the first page to be cleard, sync-ing transfer_pck and rcv_pck and ll_wrie
              else
                s_transfer_pck <= S_WAIT_WITH_TRANSFER;
              end if;

              -- need to set usecnt
            else
              s_transfer_pck              <= S_SET_USECNT;
              tp_need_pckstart_usecnt_set <= '1';  -- let know the p_page_alloc_fsm there is work
            end if;

            -- got RTU decision but not SOF yet
          elsif(rtu_rsp_ack = '1' and in_pck_sof = '0') then
            s_transfer_pck <= S_WAIT_SOF;

            -- got SOF, need RTU decision
          elsif(rtu_rsp_ack = '0' and in_pck_sof = '1') then
            s_transfer_pck <= S_WAIT_RTU_VALID;
          end if;

          --===========================================================================================
        when S_WAIT_RTU_VALID =>
          --===========================================================================================

          -- error coming from rcv_pck FSM, ignore transfer
          if (rp_in_pck_error = '1') then
              s_transfer_pck <= S_DROP;

          -- RTU decision received
          elsif(rtu_rsp_ack = '1') then

            -- error coming from rcv_pck FSM or RTU decisio no drop, both cases, ignore transfer
            if (rp_in_pck_error = '1' or tp_drop = '1') then
              s_transfer_pck <= S_DROP;

              -- don't need to set usecnt
            elsif(current_usecnt = current_pckstart_usecnt and c_force_usecnt=FALSE) then
              -- elsif(current_usecnt = pckstart_usecnt_prev) then

              -- first page is cleared in the Linked List
              if(lw_pckstart_pg_clred = '1') then
                s_transfer_pck   <= S_TRANSFER;
                pta_transfer_pck <= '1';
                pta_pageaddr     <= current_pckstart_pageaddr;
                pta_mask         <= current_mask;
                pta_resource     <= current_res_info;
                pta_hp           <= current_hp;                
                pta_prio         <= current_prio;
                -- wait for the first page to be cleard, sync-ing transfer_pck and rcv_pck and ll_wrie
              else
                s_transfer_pck <= S_WAIT_WITH_TRANSFER;
              end if;

              -- need to set usecnt
            else
              s_transfer_pck              <= S_SET_USECNT;
              tp_need_pckstart_usecnt_set <= '1';
            end if;
          end if;
          --===========================================================================================
        when S_WAIT_SOF =>
          --===========================================================================================
          
          if(in_pck_sof = '1') then

            -- don't need to set usecnt
            if(current_usecnt = current_pckstart_usecnt and c_force_usecnt=FALSE) then
              -- if(current_usecnt = pckstart_usecnt_prev) then

              -- first page is cleared in the Linked List
              if(lw_pckstart_pg_clred = '1') then
                s_transfer_pck   <= S_TRANSFER;
                pta_transfer_pck <= '1';
                pta_mask         <= current_mask;
                pta_resource     <= current_res_info;
                pta_hp           <= current_hp;                
                pta_prio         <= current_prio;
                -- take directly from allocation in advanc !!!
                pta_pageaddr     <= pckstart_pageaddr;

                -- wait for the first page to be cleard, sync-ing transfer_pck and rcv_pck and ll_wrie
              else
                s_transfer_pck <= S_WAIT_WITH_TRANSFER;
              end if;

              -- need to set usecnt
            else
              s_transfer_pck              <= S_SET_USECNT;
              tp_need_pckstart_usecnt_set <= '1';
            end if;
          end if;
          --===========================================================================================
        when S_SET_USECNT =>
          --===========================================================================================
          if(mmu_set_usecnt_done_i = '1' and tp_need_pckstart_usecnt_set = '1') then
            tp_need_pckstart_usecnt_set <= '0';

            -- error coming from rcv_pck FSM, ignore transfer
            if (rp_in_pck_error = '1') then
              s_transfer_pck <= S_DROP;
              
            -- there is no resources available so the set_usecnt operation was not successfull
            -- we need to drop the pck
            elsif(mmu_set_usecnt_succeeded_i = '0') then
              s_transfer_pck <= S_DROP;
            else
              -- first page is cleared in the Linked List      
              if(lw_pckstart_pg_clred = '1') then
                s_transfer_pck   <= S_TRANSFER;
                pta_transfer_pck <= '1';
                pta_mask         <= current_mask;
                pta_resource     <= current_res_info;
                pta_hp           <= current_hp;
                pta_prio         <= current_prio;
                pta_pageaddr     <= current_pckstart_pageaddr;
              else
                s_transfer_pck <= S_WAIT_WITH_TRANSFER;
              end if;
            end if;
          end if;
          --===========================================================================================
        when S_TRANSFER =>
          --===========================================================================================
          -- TODO: think about enabling reception of new pck when still waiting for the transfer
          if(pta_transfer_ack_i = '1') then
            pta_transfer_pck <= '0';
            s_transfer_pck   <= S_TRANSFERED;

            -- it seems that the SWcore is stuck (transfer should be done in limited time if 
            -- everything is ok), we change the state to let know the other FSMs something is wrong
          elsif(max_transfer_delay = '1') then
            s_transfer_pck <= S_TOO_LONG_TRANSFER;
          end if;
          --===========================================================================================
        when S_WAIT_WITH_TRANSFER =>  -- waits for ll_write to clear the first page
          --===========================================================================================            
          if(lw_pckstart_pg_clred = '1') then
            s_transfer_pck   <= S_TRANSFER;
            pta_transfer_pck <= '1';
            pta_mask         <= current_mask;
            pta_resource     <= current_res_info;
            pta_hp           <= current_hp;
            pta_prio         <= current_prio;
            pta_pageaddr     <= current_pckstart_pageaddr;
          end if;
          --===========================================================================================
        when S_TOO_LONG_TRANSFER =>  -- SWcore seems stuck, let know rcv_pck so it drop incoming pcks
          --===========================================================================================
          if(pta_transfer_ack_i = '1') then
            pta_transfer_pck <= '0';
            s_transfer_pck   <= S_TRANSFERED;
          end if;
          --===========================================================================================
        when S_TRANSFERED =>
          --===========================================================================================

          -- sync-ing with rcv_pck FSM
          if(lw_sync_first_stage = '1' and rp_sync = '1' and tp_sync = '1') then
            s_transfer_pck <= S_READY;
          end if;
          --===========================================================================================
        when S_DROP =>
          --===========================================================================================

          -- sync-ing with rcv_pck FSM
          if(lw_sync_first_stage = '1' and rp_sync = '1' and tp_sync = '1') then
            s_transfer_pck <= S_READY;

          -- this is to prevent trashing of the drop process (it happened that force_free was
          -- re-done many times by rcv_pck FSM when transfer_pck FSM stayed in DROP state waiting
          -- for global sync
          elsif(mmu_force_free_req = '1' and mmu_force_free_done_i = '1') then
            s_transfer_pck <= S_IDLE;  
          end if;

          --===========================================================================================
        when others =>
          --===========================================================================================           
          s_transfer_pck <= S_IDLE;
          
      end case;
    end if;
  end if;
  
end process p_transfer_pck_fsm;

--================================================================================================
--------------------------------------------------------------------------------------------------
--------------------------------      Linked List handling        --------------------------------
--------------------------------------------------------------------------------------------------
--================================================================================================


--==================================================================================================
-- FSM to receive pcks, it translates pWB I/F into MPM I/F
--==================================================================================================
-- this FSM receives frames from the outside world with pWB and writes the data to 
-- the MPM (async)
-- 

p_ll_write_fsm : process(clk_i, rst_n_i)
begin
  if rising_edge(clk_i) then
    if(rst_n_i = '0') then
      --========================================
      ll_wr_req                <= '0';
      ll_entry.valid           <= '0';
      ll_entry.eof             <= '0';
      ll_entry.addr            <= (others => '0');
      ll_entry.size            <= (others => '0');
      ll_entry.next_page       <= (others => '0');
      ll_entry.next_page_valid <= '0';
      ll_entry.first_page_clr  <= '0';

      ll_entry_tmp.valid           <= '0';
      ll_entry_tmp.eof             <= '0';
      ll_entry_tmp.addr            <= (others => '0');
      ll_entry_tmp.size            <= (others => '0');
      ll_entry_tmp.next_page       <= (others => '0');
      ll_entry_tmp.next_page_valid <= '0';
      ll_entry_tmp.first_page_clr  <= '0';

      mpm_dlast_d0  <= '0';
      mpm_pg_req_d0 <= '0';
      --pckstart_pageaddr_clred      <= (others => '1');--make it different then the first allocated addr
      --========================================
    else
      
      mpm_dlast_d0  <= mpm_dlast;
      mpm_pg_req_d0 <= mpm_pg_req_i;

      case s_ll_write is
        --===========================================================================================
        when S_IDLE =>
          --===========================================================================================  

          -- clear the first page of the pck:
          -- (1) as soon as the first page is allocated, or
          -- (2) in case the WRITE state is quite long and it spans from the previous pck
          --     to the new one and into RCV_PCK state of rcv_pck FSM, we use the first page
          --     indication
          if(pckstart_page_in_advance = '1' or new_pck_first_page = '1') then
            ll_wr_req      <= '1';
            ll_entry.valid <= '0';
            ll_entry.eof   <= '0';

            -- if we've already started sending new pck, then new page already can be allocated
            -- (this is because we trigger allocation of new pckstart_pageaddr as soon as
            -- we use it at the beginning of RCV_DATA)
            -- but we need to clear previously allocated pckstart_pageaddr (this was stored
            -- in current_pckstart_pageaddr).
            -- such situation can happen only within the first page, if pckstart_pageaddr
            -- is not allocated by the end of first page,  we PAUSE..
            if(rp_rcv_first_page = '1') then
              ll_entry.addr <= current_pckstart_pageaddr;
            else
              ll_entry.addr <= pckstart_pageaddr;
            end if;
            ll_entry.size            <= (others => '0');
            ll_entry.next_page       <= (others => '0');
            ll_entry.next_page_valid <= '0';
            ll_entry.first_page_clr  <= '1';
            s_ll_write               <= S_WRITE;
          end if;

          --===========================================================================================
        when S_READY_FOR_PGR_AND_DLAST =>
          --===========================================================================================
          if(mpm_dlast_d0 = '1') then
            ll_wr_req                <= '1';
            ll_entry.valid           <= '1';
            ll_entry.eof             <= '1';
            ll_entry.addr            <= rp_ll_entry_addr;
            ll_entry.size            <= rp_ll_entry_size;
            -- next_page is not use because we use  addr,dsel,size
            ll_entry.next_page       <= (others => '0');
            ll_entry.next_page_valid <= '0';
            ll_entry.first_page_clr  <= '0';
            s_ll_write               <= S_WRITE;
          elsif(mpm_pg_req_d0 = '1') then
            ll_wr_req                <= '1';
            ll_entry.valid           <= '1';
            ll_entry.eof             <= '0';
            ll_entry.addr            <= rp_ll_entry_addr;
            ll_entry.size            <= (others => '0');
            -- in this state we need to have pckinter allocated   
            ll_entry.next_page       <= pckinter_pageaddr;
            ll_entry.next_page_valid <= '1';
            ll_entry.first_page_clr  <= '0';
            s_ll_write               <= S_WRITE;
          end if;
          --===========================================================================================
        when S_READY_FOR_DLAST_ONLY =>
          --===========================================================================================
          if(mpm_dlast_d0 = '1') then
            ll_wr_req      <= '1';
            ll_entry.valid <= '1';
            ll_entry.eof   <= '1';
            ll_entry.addr  <= rp_ll_entry_addr;
            ll_entry.size  <= rp_ll_entry_size;

            -- we write size and stuff, next_page unused
            ll_entry.next_page       <= (others => '0');
            ll_entry.next_page_valid <= '0';
            ll_entry.first_page_clr  <= '0';

            s_ll_write        <= S_WRITE;
          elsif(mpm_pg_req_d0 = '1') then
            assert false
              report "ll_write FSM: received mpm_pg_req on S_READY_FOR_DLAST_ONLY, it should not";
          elsif(pckinter_page_in_advance = '1' and pckstart_page_in_advance = '1') then
            s_ll_write <= S_READY_FOR_PGR_AND_DLAST;
          end if;
          --===========================================================================================
        when S_WRITE =>
          --===========================================================================================
          if(ll_wr_req = '1' and ll_wr_done_i = '1') then  -- written
            ll_wr_req <= '0';

            if(mpm_dlast_d0 = '1') then
              ll_wr_req                <= '1';
              ll_entry.valid           <= '1';
              ll_entry.eof             <= '1';
              ll_entry.addr            <= rp_ll_entry_addr;
              ll_entry.size            <= rp_ll_entry_size;
              -- we use the space of next_page for dsel/size ..        
              ll_entry.next_page       <= (others => '0');
              ll_entry.next_page_valid <= '0';
              ll_entry.first_page_clr  <= '0';

              s_ll_write <= S_WRITE;
            elsif(mpm_pg_req_d0 = '1') then
              assert false
                report "ll_write FSM: received mpm_pg_req on S_WRITE, it should not";
            else                        -- most commont case
              ll_entry.valid           <= '0';
              ll_entry.eof             <= '0';
              ll_entry.addr            <= (others => '0');
              ll_entry.size            <= (others => '0');
              ll_entry.next_page       <= (others => '0');
              ll_entry.next_page_valid <= '0';
              ll_entry.first_page_clr  <= '0';

              -- what happens here:
              -- (1) we exit write process of the End of frame (ll_entry.eof = '1' and ll_entry.valid = '1' )              -- (2) it should not clear the first page but we still check(ll_entry.first_page_clr = '0' )
              -- (3) and the current first page allocated in advance has not been cleared yet 
              --     (pckstart_pg_clred = '0')
              -- so we go into S_IDLE state, in this state (by default) we wait for the first
              -- page to be allocated in advance, once it's done, we clear it
              if(ll_entry.first_page_clr = '0' and ll_entry.eof = '1' and ll_entry.valid = '1' and
                 pckstart_pg_clred = '0') then 
                -- finished writing end-of-frame page addr without cleaning pckstart_addr
                ll_wr_req  <= '0';
                s_ll_write <= S_IDLE;  -- here it will be waiting for pckstart_page

              elsif(pckinter_page_in_advance = '1' and pckstart_page_in_advance = '1') then
                s_ll_write <= S_READY_FOR_PGR_AND_DLAST;
              else
                s_ll_write <= S_READY_FOR_DLAST_ONLY;
              end if;
            end if;
          else  -- if(ll_wr_req = '1' and ll_wr_done_i = '1)

            if(mpm_dlast_d0 = '1') then
              s_ll_write <= S_EOF_ON_WR;
            elsif(in_pck_sof = '1') then
              s_ll_write <= S_SOF_ON_WR;
            end if;

            if(mpm_pg_req_d0 = '1' or mpm_dlast_d0 = '1') then
              ll_entry_tmp.valid    <= '1';
              ll_entry_tmp.eof      <= mpm_dlast_d0;
              ll_entry_tmp.addr     <= rp_ll_entry_addr;
              ll_entry_tmp.size     <= rp_ll_entry_size;
            end if;
          end if;  -- if(ll_wr_req = '1' and ll_wr_done_i = '1)


          --===========================================================================================
        when S_EOF_ON_WR =>
          --===========================================================================================
          -- if (EOF or error or drop decision) happens on writing
          if(ll_wr_req = '1' and ll_wr_done_i = '1') then  -- written
            ll_wr_req                <= '1';
            ll_entry                 <= ll_entry_tmp;
            --- not used because we write size and stuff
            ll_entry.next_page       <= (others => '0');
            ll_entry.next_page_valid <= '0';
            ll_entry.first_page_clr  <= '0';
            s_ll_write               <= S_WRITE;
          end if;
          --===========================================================================================
        when S_SOF_ON_WR =>
          --===========================================================================================
          if(ll_wr_req = '1' and ll_wr_done_i = '1') then  -- written
            ll_wr_req                <= '0';
            ll_entry.valid           <= '0';
            ll_entry.eof             <= '0';
            ll_entry.addr            <= (others => '0');
            ll_entry.size            <= (others => '0');
            ll_entry.next_page       <= (others => '0');
            ll_entry.next_page_valid <= '0';
            ll_entry.first_page_clr  <= '0';

            if(ll_entry.first_page_clr = '1') then
              if(pckinter_page_in_advance = '1' and pckstart_page_in_advance = '1') then
                s_ll_write <= S_READY_FOR_PGR_AND_DLAST;
              else
                s_ll_write <= S_READY_FOR_DLAST_ONLY;
              end if;
            else
              s_ll_write <= S_IDLE;
            end if;
          end if;

          --===========================================================================================
        when others =>
          --===========================================================================================    
          s_ll_write <= S_IDLE;
          ll_wr_req  <= '1';
      end case;

      -- remember the page which you just cleared
      -- it is used to sync ll_write FSM with rcv_pck FSM and also transfer_pck
--            if(ll_wr_req = '1' and ll_wr_done_i = '1' and ll_entry.first_page_clr = '1') then
--              if(ll_entry.next_page_valid = '1') then
--                pckstart_pageaddr_clred <= ll_entry.next_page;
--              else
--                pckstart_pageaddr_clred <= ll_entry.addr;
--              end if;
--            end if;
      
    end if;
  end if;
  
end process p_ll_write_fsm;

--================================================================================================
--------------------------------------------------------------------------------------------------
-------------------------------- synchronization with other FSMs: --------------------------------
--------------------------------------------------------------------------------------------------
--================================================================================================

-- ll_write FSM sync (lw): first stage, needs to be true for rcv_pck to enter READY state
-- for the first stage, we need have already allocated first page throughout process of receiving
-- previous pck (it is to prevent very small pcks of less then single page to mess up)
lw_sync_first_stage <= '1' when (s_ll_write /= S_IDLE and pckstart_page_in_advance = '1') else '0';

-- ll_write FSM sync (lw): second stage, needs to be true for rcv_pck to finish writing page
-- rcv_pck goes to pause at the end of receiving first page if second state sync not fulfilled
lw_sync_second_stage <= '1' when (s_ll_write = S_READY_FOR_PGR_AND_DLAST and lw_pckstart_pg_clred = '1') else '0';

-- indicate that the sync should be checked
lw_sync_2nd_stage_chk <= '1' when (page_word_cnt = to_unsigned(g_page_size - 3, c_page_size_width)) else '0';

-- transfer_pck FSM sync (tp): needs to be true for rcv_pck to enter READY state
tp_sync <= '1' when (s_transfer_pck = S_IDLE or               -- 
                                 -- s_transfer_pck = S_DROP or  -- 
                                  s_transfer_pck = S_TRANSFERED) else '0';

-- rcv_pck FSM is sync-ed                                  
rp_sync <= '1' when (s_rcv_pck = S_IDLE) else '0';

-- transfer_pck FSM indicates that SWcore is stuck                                    
tp_stuck <= '1' when (s_transfer_pck = S_TOO_LONG_TRANSFER) else '0';

-- transfer_pck FSM indicates that the frame should be dropped
tp_drop <= '1' when ((s_transfer_pck = S_DROP) or
                                  ((current_drop = '1' or current_mask = zeros) and rtu_rsp_ack = '1')) else '0';

-- transfer_pck FSM indicates that transfer already started or is finished, 
tp_transfer_valid <= '1' when (s_transfer_pck = S_TRANSFERED or
                                  s_transfer_pck = S_TRANSFER or
                                  s_transfer_pck = S_TOO_LONG_TRANSFER) else '0';

-- rcv_pck FSM indicates that there is or was error on the received pck
rp_in_pck_error <= '1' when (rp_in_pck_err = '1' or in_pck_err = '1') else '0';


--================================================================================================
--------------------------------------------------------------------------------------------------
--------------------------------        resource management       --------------------------------
--------------------------------------------------------------------------------------------------
--================================================================================================

  -- generate signal indicating that the inforamtion about resource number for a given
  -- pck is valid (based on RTU decision), it is used during allocation of a new
  -- inter-pck page to indicate that the previous page was allocated to a give resource
  res_info_valid <= '1' when ((s_transfer_pck = S_WAIT_SOF           or
                               s_transfer_pck = S_SET_USECNT         or
                               s_transfer_pck = S_WAIT_WITH_TRANSFER or
                               s_transfer_pck = S_TOO_LONG_TRANSFER  or
                               s_transfer_pck = S_TRANSFER           or
                               s_transfer_pck = S_TRANSFERED       ) and
                              (s_rcv_pck      = S_RCV_DATA           or 
                               s_rcv_pck      = S_PAUSE            ))else 
                    '0';

  ---------------------------------------------
  -- mapping of RTU decision into resources
--   res_info             <= f_map_rtu_rsp_to_mmu_res(rtu_prio_i, rtu_hp_i , g_resource_num_width);
  
  res_info             <= c_special_res(g_resource_num_width-1 downto 0) when rtu_hp_i = '1' else
                          c_normal_res (g_resource_num_width-1 downto 0);

  res_info_almsot_full <= mmu_res_almost_full_i(to_integer(unsigned(res_info)));
  res_info_full        <= mmu_res_full_i(to_integer(unsigned(res_info)));
  ---------------------------------------------
  
  p_cnt_unused_pages: process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --================================================
        unknown_res_page_cnt <= to_unsigned(0,unknown_res_page_cnt'length);
        --================================================
      else
      
        -- reset the count of pages allocated to unknown resource when sync-ing FSMs
        if(lw_sync_first_stage = '1' and rp_sync = '1' and tp_sync = '1') then 
          unknown_res_page_cnt <= to_unsigned(1,unknown_res_page_cnt'length);
        elsif(mpm_pg_req_i = '1' and mpm_dlast = '0' and s_transfer_pck = S_WAIT_RTU_VALID) then
          unknown_res_page_cnt <= unknown_res_page_cnt + 1;
        end if;

      end if;  -- if(rst_n_i = '0') then
    end if;  --rising_edge(clk_i) then

  end process;


 mmu_resource_o        <= mmu_resource_out;
 mmu_rescnt_page_num_o <= mmu_rescnt_page_num;



--================================================================================================
--------------------------------------------------------------------------------------------------
--------------------------------         inputs/outputs           --------------------------------
--------------------------------------------------------------------------------------------------
--================================================================================================

--================================================================================================
-- Input signals
--================================================================================================
rtu_dst_port_usecnt <= std_logic_vector(to_unsigned(cnt(rtu_dst_port_mask_i), g_usecount_width));

-- generating output STALL: fifo_full or stall_after_err or stall_when_stuck;
-- snk_stall_int <= ((not mpm_dreq_i) or snk_stall_force_h or in_pck_eof) and snk_stall_force_l;
snk_stall_int <= ((not mpm_dreq_i) or snk_stall_force_h) and snk_stall_force_l;

snk_o.stall <= snk_stall_int;
snk_o.err   <= '0';
snk_o.ack   <= snk_ack_int;
snk_o.rty   <= '0';--snk_rty_int;             --'0'; 
--================================================================================================
-- Output signals
--================================================================================================

rtu_rsp_ack_o <= rtu_rsp_ack;

mmu_set_usecnt_o     <= pckstart_usecnt_req;
mmu_usecnt_set_o     <= pckstart_usecnt_write;
mmu_usecnt_alloc_o   <= pckstart_usecnt_write;--std_logic_vector(to_unsigned(1,g_usecount_width));
mmu_page_alloc_req_o <= pckinter_page_alloc_req or pckstart_page_alloc_req;

mmu_force_free_o      <= mmu_force_free_req;
mmu_force_free_addr_o <= mmu_force_free_addr;
---
mmu_pageaddr_o        <= pckstart_usecnt_pgaddr;

mpm_pg_addr_o <= mpm_pg_addr;
mpm_dlast_o   <= mpm_dlast;
mpm_dvalid_o  <= mpm_dvalid;
mpm_data_o    <= mpm_data;

pta_transfer_pck_o <= pta_transfer_pck;
pta_pageaddr_o     <= pta_pageaddr;
pta_mask_o         <= pta_mask;         --current_mask;
-- pta_resource_o     <= pta_resource;
pta_hp_o           <= pta_hp;
pta_prio_o         <= pta_prio;         --current_prio;
-- pta_pck_size_o     <= (others => '0');  -- unused

-- pWB
-- snk_dat_int <= snk_i.dat;
-- snk_adr_int <= snk_i.adr;
snk_sel_int <= snk_i.sel;
snk_cyc_int <= snk_i.cyc;
snk_stb_int <= snk_i.stb;
snk_we_int  <= snk_i.we;

--dsel--
p_encode_byte_selects : process(snk_i)
begin
  if(unsigned(not snk_i.sel) /= 0) then
    snk_adr_int               <= c_WRF_USER;
    snk_dat_int(15 downto 8) <= snk_i.dat(15 downto 8);
    snk_dat_int(7 downto 6) <= snk_i.adr;
    snk_dat_int(5 downto 4) <= snk_i.sel;
    snk_dat_int(3 downto 0) <= (others => 'X');
  else
    snk_adr_int <= snk_i.adr;
    snk_dat_int <= snk_i.dat;
  end if;
end process;

ll_data_eof(c_page_size_width-1 downto 0)                                        <= ll_entry.size;
ll_data_eof(g_page_addr_width-g_partial_select_width-1 downto c_page_size_width) <= (others => '0');

ll_addr_o                                                                                                                  <= ll_entry.addr;
ll_data_o(g_ll_data_width-0 -1)                                                                                            <= ll_entry.valid;
ll_data_o(g_ll_data_width-1 -1)                                                                                            <= ll_entry.eof;

ll_data_o(g_page_addr_width-1 downto 0) <= ll_data_eof when (ll_entry.eof = '1') else ll_entry.next_page;
ll_next_addr_o                          <= ll_entry.next_page;
ll_next_addr_valid_o                    <= ll_entry.next_page_valid;
ll_wr_req_o                             <= ll_wr_req;

alloc_FSM <= "000" when (s_page_alloc = S_IDLE) else
             "001" when (s_page_alloc = S_PCKSTART_SET_USECNT) else
             "010" when (s_page_alloc = S_PCKSTART_PAGE_REQ) else
             "011" when (s_page_alloc = S_PCKINTER_PAGE_REQ) else
             "100";
trans_FSM <= x"0" when (s_transfer_pck = S_IDLE) else
             x"1" when (s_transfer_pck = S_READY) else
             x"2" when (s_transfer_pck = S_WAIT_RTU_VALID) else
             x"3" when (s_transfer_pck = S_WAIT_SOF) else
             x"4" when (s_transfer_pck = S_SET_USECNT) else
             x"5" when (s_transfer_pck = S_WAIT_WITH_TRANSFER) else
             x"6" when (s_transfer_pck = S_TOO_LONG_TRANSFER) else
             x"7" when (s_transfer_pck = S_TRANSFER) else
             x"8" when (s_transfer_pck = S_TRANSFERED) else
             x"9" when (s_transfer_pck = S_DROP) else
             x"A";

rcv_p_FSM <= x"0" when (s_rcv_pck = S_IDLE) else
             x"1" when (s_rcv_pck = S_READY) else
             x"2" when (s_rcv_pck = S_PAUSE) else
             x"3" when (s_rcv_pck = S_RCV_DATA) else
             x"4" when (s_rcv_pck = S_DROP) else
             x"5" when (s_rcv_pck = S_WAIT_FORCE_FREE) else
             x"6" when (s_rcv_pck = S_INPUT_STUCK) else
             x"7";

linkl_FSM <= x"0" when (s_ll_write = S_IDLE) else
             x"1" when (s_ll_write = S_READY_FOR_PGR_AND_DLAST) else
             x"2" when (s_ll_write = S_READY_FOR_DLAST_ONLY) else
             x"3" when (s_ll_write = S_WRITE) else
             x"4" when (s_ll_write = S_EOF_ON_WR) else
             x"5" when (s_ll_write = S_SOF_ON_WR) else
             x"6";

dbg_hwdu_o <= rtu_rsp_valid_i & alloc_FSM & trans_FSM & rcv_p_FSM & linkl_FSM;

dbg_dropped_on_res_full <= pckstart_usecnt_req and mmu_set_usecnt_done_i and (not mmu_set_usecnt_succeeded_i);

-- tap_out_o <= f_slv_resize(              -- 
--  -- f_enum2nat(s_rcv_pck) &               --
--   (mmu_nomem_i) &
--   (mmu_page_alloc_done_i) &
--   (pckinter_page_alloc_req or pckstart_page_alloc_req) &
--   snk_stall_int &
--   in_pck_sof_allowed &
--   in_pck_sof_on_stall &
--   snk_stall_d0 &
--   snk_cyc_int &                         -- 94
--   in_pck_sof_delayed &                  -- 93
--   f_enum2nat(s_transfer_pck) &          -- 89
--   lw_sync_second_stage &                -- 88
--   in_pck_err &                          -- 87
--   in_pck_eof &                          -- 86
--   in_pck_sof &                          -- 85
--   f_enum2nat(s_ll_write) &              -- 81
--   f_enum2nat(s_page_alloc) &            -- 77
--   pckinter_pageaddr &                   -- 67
--   pckinter_page_in_advance &            -- 66
--   '1' &                                 -- 65
-- 
--   ll_wr_req &                           -- 64
--   ll_wr_done_i &                        -- 63
--   ll_entry.addr &                       -- 54
--   ll_entry.valid &                      -- 53
--   ll_entry.eof &                        -- 52
--   ll_entry.dsel &                       -- 51
--   ll_entry.oob_size &                   -- 49
--   ll_entry.next_page &                  -- 39
--   ll_entry.next_page_valid &            -- 38
--   "0000000000" & --pta_pageaddr &                        -- 28
--   pta_transfer_pck &                    -- 27
--   "0000000000" & --mpm_pg_addr &                         -- 17
--   mpm_pg_req_i,                         -- 16
--   50 + 62);

end syn;  -- arch
