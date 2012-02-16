-------------------------------------------------------------------------------
-- Title      : Input block (extended interface)
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : xswc_input_block.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-10-28
-- Last update: 2012-02-15
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
-- 2010-11-01  1.0      mlipinsk created
-- 2010-11-29  2.0      mlipinsk added FIFO, major changes
-- 2012-01-20  3.0      mlipinsk wisbhonized
-- 2012-02-02  4.0      mlipinsk generic-azed
-- 2012-02-15  5.0      mlipinsk adapted to the new (async) MPM
-------------------------------------------------------------------------------
-- TODO: 
-- 1) think about enabling reception of new pck when still waiting for the transfer,
--    this requires changing interaction between p_transfer_pck_fsm and p_rcv_pck_fsm
-- 2) make the dsel more generic
-- 3) test with mpm_dreq_i = LOW
-- 4) implement drop_on_SWCORE_stuck
--    
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
    g_page_addr_width                  : integer ;--:= c_swc_page_addr_width;
    g_num_ports                        : integer ;--:= c_swc_num_ports
    g_prio_width                       : integer ;--:= c_swc_prio_width;
    g_max_pck_size_width               : integer ;--:= c_swc_max_pck_size_width  
    g_usecount_width                   : integer ;--:= c_swc_usecount_width
    g_ctrl_width                       : integer ;--:= c_swc_ctrl_width
    g_input_block_cannot_accept_data   : string  ;--:= "drop_pck"; --"stall_o", "rty_o" -- Don't CHANGE !

    -- new
    g_mpm_data_width                   : integer ; -- it needs to be wb_data_width + wb_addr_width
    g_page_size                        : integer ;
    g_partial_select_width             : integer ;

    -- probably useless with new memory
    g_packet_mem_multiply              : integer ;--:= c_swc_packet_mem_multiply
    g_input_block_fifo_size            : integer ;--:= c_swc_input_fifo_size
    g_input_block_fifo_full_in_advance : integer  --:=c_swc_fifo_full_in_advance
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
    mmu_force_free_o      : out std_logic;

    mmu_force_free_done_i : in std_logic;

    mmu_force_free_addr_o : out std_logic_vector(g_page_addr_width - 1 downto 0);

    -- set user count to the already allocated page (on mmu_pageaddr_o)
    mmu_set_usecnt_o     : out std_logic;

    mmu_set_usecnt_done_i : in std_logic;

    -- user count to be set (associated with an allocated page) in two cases:
    -- * mmu_pagereq_o    is HIGH - normal allocation
    -- * mmu_set_usecnt_o is HIGH - force user count to existing page alloc
    mmu_usecnt_o        : out std_logic_vector(g_usecount_width - 1 downto 0);

    -- memory full
    mmu_nomem_i         : in std_logic;
-------------------------------------------------------------------------------
-- I/F with Routing Table Unit (RTU)
-------------------------------------------------------------------------------      

    rtu_rsp_valid_i     : in  std_logic;
    rtu_rsp_ack_o       : out std_logic;
    rtu_dst_port_mask_i : in  std_logic_vector(g_num_ports - 1 downto 0);
    rtu_drop_i          : in  std_logic;
    rtu_prio_i          : in  std_logic_vector(g_prio_width - 1 downto 0);

-------------------------------------------------------------------------------
-- I/F with Async MultiPort Memory (MPM)
-------------------------------------------------------------------------------    
    -- data to be written
    mpm_data_o           : out std_logic_vector(g_mpm_data_width - 1 downto 0);
    -- HIGH if data is valid
    mpm_dvalid_o         : out std_logic;
    -- HIGH if the word data is the last of the pck
    mpm_dlast_o          : out std_logic;
    -- indicates the base address of the page curretly written to
    mpm_pg_addr_o        : out std_logic_vector(g_page_addr_width - 1 downto 0);
    -- if HIGH, new page_addr should be provided in the next cycle
    mpm_pg_req_i         : in std_logic;
    -- if HIGH, the data can be accepted by the MPM
    mpm_dreq_i           : in std_logic;

-------------------------------------------------------------------------------
-- Linked List of page addresses (LL SRAM) interface 
-------------------------------------------------------------------------------

    -- address in LL SRAM which corresponds to the page address
    ll_addr_o : out std_logic_vector(g_page_addr_width -1 downto 0);

    -- data output for LL SRAM - it is the address of the next page or 0xF...F
    -- if this is the last page of the package
    ll_data_o    : out std_logic_vector(g_page_addr_width + 1 downto 0);

    -- request to write to Linked List, should be high until
    -- ll_wr_done_i indicates successfull write
    ll_wr_req_o   : out std_logic;

    ll_wr_done_i  : in std_logic;

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

    pta_pck_size_o : out std_logic_vector(g_max_pck_size_width - 1 downto 0);

    pta_prio_o : out std_logic_vector(g_prio_width - 1 downto 0)

    );
end xswc_input_block;

architecture syn of xswc_input_block is

  constant c_input_fifo_size_log2  : integer := integer(CEIL(LOG2(real(g_input_block_fifo_size - 1))));
  constant c_page_size_width       : integer := integer(CEIL(LOG2(real(g_page_size + 1))));

  type t_page_alloc   is(S_IDLE,                  -- waiting for some work :)
                         S_PCKSTART_SET_USECNT,   -- setting usecnt to a page which was allocated 
                                                 -- in advance to be used for the first page of 
                                                 -- the pck
                                                 -- (only in case of the initially allocated usecnt
                                                 -- is different than required)
                         S_PCKSTART_PAGE_REQ,     -- allocating in advnace first page of the pck
                         S_INTERPCK_PAGE_REQ);    -- allocating in advance page to be used by 
                                                 -- all but first page of the pck
  type t_transfer_pck is(S_IDLE,                 -- wait for some work :)
                         S_WAIT_RTU_VALID,       -- Started receiving pck, wait for RTU decision
                         S_WAIT_SOF,             -- received RTU decision but new pck has not been started
                                                 -- still receiving the old one, or non
                         S_SET_USECNT,           -- set usecnt of the first page
                         S_TRANSFER,             -- transfer pck to the outputs
                         S_DROP_PCK,                 -- after receiving RTU decision to drop the pck,
                                                 -- it still needs to be received
                         S_PCK_TRANSFERED        -- transfer has been done, waiting for the end of pck (EOF)
                         ); 

  type t_rcv_pck      is(S_IDLE,                 -- wait for some work :)
                         S_READY,                -- Can accept new pck (i.e. the previous pck has been transfered
                         S_PAUSE,                -- need to pause reception (internal reason, e.g.: next page not allocated) 
                                                 -- still receiving the old one, or non
                         S_RCV_DATA,             -- accepting pck
                         S_DROP,                 -- if 
                         S_WAIT_FORCE_FREE       -- waits for the access to the force freeing process (it
                                                 -- only happens when the previous request has not been handled
                                                 -- (in theory, hardly possible, so it will happen for sure ;=))
                         );

  signal s_page_alloc   : t_page_alloc;
  signal s_transfer_pck : t_transfer_pck;
  signal s_rcv_pck      : t_rcv_pck;

  -- pckstart page allocation in advance
  signal pckstart_page_in_advance  : std_logic;
  signal pckstart_pageaddr         : std_logic_vector(g_page_addr_width - 1 downto 0);
  signal pckstart_page_alloc_req   : std_logic;
  signal pckstart_usecnt_req       : std_logic;
  signal pckstart_usecnt_write     : std_logic_vector(g_usecount_width  - 1 downto 0);
  signal pckstart_usecnt_prev      : std_logic_vector(g_usecount_width  - 1 downto 0);
  signal pckstart_usecnt_pgaddr    : std_logic_vector(g_page_addr_width - 1 downto 0);

  signal need_pckstart_usecnt_set  : std_logic;

  -- interpck page allocation in advance
  signal interpck_page_in_advance  : std_logic;  
  signal interpck_pageaddr         : std_logic_vector(g_page_addr_width - 1 downto 0);
  signal interpck_page_alloc_req   : std_logic;  
  
  signal rtu_dst_port_usecnt : std_logic_vector(g_usecount_width - 1 downto 0);
  signal rtu_rsp_ack          : std_logic;
  signal current_usecnt : std_logic_vector(g_usecount_width - 1 downto 0);
  signal current_drop : std_logic;
  signal current_pckstart_pageaddr : std_logic_vector(g_page_addr_width - 1 downto 0);
  signal usecnt_d0 : std_logic_vector(g_usecount_width - 1 downto 0);
  
  signal pta_transfer_pck: std_logic;
  signal pta_pageaddr    : std_logic_vector(g_page_addr_width - 1 downto 0);
  signal pta_mask        : std_logic_vector(g_num_ports - 1 downto 0);
  signal pta_prio        : std_logic_vector(g_prio_width - 1 downto 0);
  signal pta_pck_size    : std_logic_vector(g_max_pck_size_width - 1 downto 0);  

  signal mpm_data           : std_logic_vector(g_mpm_data_width - 1 downto 0);
  signal mpm_dvalid         : std_logic;
  signal mpm_pg_addr        : std_logic_vector(g_page_addr_width - 1 downto 0);
  signal mpm_dlast          : std_logic;

   -- pWB 
  signal snk_dat_int   : std_logic_vector(15 downto 0);
  signal snk_adr_int   : std_logic_vector(1  downto 0);
  signal snk_sel_int   : std_logic_vector(1  downto 0);
  signal snk_cyc_int   : std_logic;
  signal snk_stb_int   : std_logic;
  signal snk_we_int    : std_logic;
  signal snk_stall_int : std_logic;
  signal snk_err_int   : std_logic;
  signal snk_ack_int   : std_logic;
  signal snk_rty_int   : std_logic;
  
  signal snk_sel_d0    : std_logic_vector(1 downto 0);
  signal snk_cyc_d0    : std_logic;
  signal snk_stall_force_h : std_logic;  
  signal snk_stall_force_l : std_logic;  
  
  -- this si pipelined
  signal in_pck_dvalid   : std_logic;
  signal in_pck_dat      : std_logic_vector(g_mpm_data_width - 1 downto 0);
  signal in_pck_sel      : std_logic_vector(g_partial_select_width - 1 downto 0);
  -- first stage
  signal in_pck_dvalid_d0: std_logic;
  signal in_pck_dat_d0   : std_logic_vector(g_mpm_data_width - 1 downto 0);
  signal in_pck_sel_d0   : std_logic_vector(g_partial_select_width - 1 downto 0);
  -- second stage
  signal in_pck_dvalid_d1: std_logic;
  signal in_pck_dat_d1   : std_logic_vector(g_mpm_data_width - 1 downto 0);
  signal in_pck_sel_d1   : std_logic_vector(g_partial_select_width - 1 downto 0);

  signal in_pck_sof      : std_logic;
  signal in_pck_eof      : std_logic;
  signal in_pck_err      : std_logic;

  signal mmu_force_free_req  : std_logic;
  signal mmu_force_free_addr : std_logic_vector(g_page_addr_width - 1 downto 0);

  signal in_pck_drop_on_sof : std_logic;
  
  signal page_word_cnt    : unsigned(c_page_size_width - 1 downto 0);

  signal no_new_pg_addr_at_eop : std_logic; 
  signal ll_not_written_at_eop : std_logic;
 
  signal ll_addr          : std_logic_vector(g_page_addr_width - 1 downto 0);
  signal ll_data          : std_logic_vector(g_page_addr_width + 1 downto 0);
  signal ll_data_eof      : std_logic_vector(g_page_addr_width - 1 downto 0);
  signal ll_wr_req        : std_logic;

  type t_ll_entry is record
    valid     : std_logic;
    eof       : std_logic;
    next_page : std_logic_vector(g_page_addr_width      - 1 downto 0);
    addr      : std_logic_vector(g_page_addr_width      - 1 downto 0);
    dsel      : std_logic_vector(g_partial_select_width - 1 downto 0);
    size      : std_logic_vector(c_page_size_width      - 1 downto 0);
  end record;

  signal ll_entry           : t_ll_entry;
  -------------------------------------------------------------------------------
  -- Function which calculates number of 1's in a vector
  ------------------------------------------------------------------------------- 
  function cnt (a              : std_logic_vector) return integer is
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
  
  begin  --arch

  --==================================================================================================
  -- pWB (sink) to input FIFO
  --==================================================================================================
  in_pck_sof    <= snk_cyc_int and not snk_cyc_d0;                                       -- detecting the beginning of the pck
  in_pck_dvalid <= snk_stb_int and     snk_we_int and snk_cyc_int and not snk_stall_int; -- valid data which can be stored into FIFO
  in_pck_dat    <= snk_adr_int & snk_dat_int;
  in_pck_eof    <= snk_cyc_d0  and not snk_cyc_int  ;                                    -- detecting the end of the pck
  in_pck_err    <= '1'         when    in_pck_dvalid = '1'   and                         -- we have valid data           *and*
                               (snk_adr_int = c_WRF_STATUS) and                          -- the address indicates status *and*
                               (f_unmarshall_wrf_status(snk_dat_int).error = '1') else   -- the status indicates error       
                   '0';

  -- TODO: we need to indicate somehow that there is error and pck is dumped !!!

  snk_stall_int <= ((not mpm_dreq_i) or snk_stall_force_h) and snk_stall_force_l; --fifo_full or stall_after_err or stall_when_stuck;

  read_helper : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
      --================================================
        snk_ack_int    <= '0';
        snk_cyc_d0     <= '0';
      --================================================
      else
      
        snk_cyc_d0 <= snk_cyc_int;
        
        -- generating ack
        snk_ack_int <= snk_cyc_int and snk_stb_int and snk_we_int and not snk_stall_int;
        
       end if;  -- if(rst_n_i = '0') then
     end if; --rising_edge(clk_i) then
   end process read_helper;

 
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
        s_page_alloc               <= S_IDLE;

        interpck_pageaddr          <= (others => '0');
        interpck_page_alloc_req    <= '0';

        pckstart_pageaddr          <= (others => '0');
        pckstart_page_alloc_req    <= '0';
        
        pckstart_usecnt_req        <= '0';
        pckstart_usecnt_write      <= (others => '0');
        pckstart_usecnt_prev       <= (others => '0');
        pckstart_usecnt_pgaddr     <= (others => '0');
        
      --========================================
      else

        -- main finite state machine
        case s_page_alloc is

          --===========================================================================================
          when S_IDLE =>
            --===========================================================================================   
            interpck_page_alloc_req <= '0';
            pckstart_page_alloc_req <= '0';
            pckstart_usecnt_req     <= '0';
            
            
            if(need_pckstart_usecnt_set = '1') then

              s_page_alloc            <= S_PCKSTART_SET_USECNT;
              pckstart_usecnt_req     <= '1';
              pckstart_usecnt_pgaddr  <= current_pckstart_pageaddr;
              pckstart_usecnt_write   <= current_usecnt;
              pckstart_usecnt_prev    <= current_usecnt;
              
            elsif(pckstart_page_in_advance = '0') then
              
              pckstart_page_alloc_req <= '1';
              s_page_alloc            <= S_PCKSTART_PAGE_REQ;
              pckstart_usecnt_write   <= pckstart_usecnt_prev;
              
            elsif(interpck_page_in_advance = '0') then
              
              interpck_page_alloc_req <= '1';
              s_page_alloc            <= S_INTERPCK_PAGE_REQ;
              pckstart_usecnt_write   <= std_logic_vector(to_unsigned(1, g_usecount_width));

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
                
              elsif(interpck_page_in_advance = '0') then
                
                interpck_page_alloc_req <= '1';
                s_page_alloc            <= S_INTERPCK_PAGE_REQ;
                pckstart_usecnt_write   <= std_logic_vector(to_unsigned(1, g_usecount_width));
                
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
              pckstart_pageaddr          <= mmu_pageaddr_i;

              if(need_pckstart_usecnt_set = '1') then
                
                s_page_alloc            <= S_PCKSTART_SET_USECNT;
                pckstart_usecnt_req     <= '1';
                pckstart_usecnt_write   <= current_usecnt;
                pckstart_usecnt_prev    <= current_usecnt;
                
              elsif(interpck_page_in_advance = '0') then
                
                interpck_page_alloc_req <= '1';
                s_page_alloc            <= S_INTERPCK_PAGE_REQ;
                pckstart_usecnt_write   <= pckstart_usecnt_prev;
                               
              else
                
                s_page_alloc  <= S_IDLE;
                
              end if;
            end if;

          --===========================================================================================
          when S_INTERPCK_PAGE_REQ =>
            --===========================================================================================
            
            if(mmu_page_alloc_done_i = '1') then
              
              interpck_page_alloc_req    <= '0';
              interpck_pageaddr          <= mmu_pageaddr_i;

              if(need_pckstart_usecnt_set = '1') then
                
                s_page_alloc            <= S_PCKSTART_SET_USECNT;
                pckstart_usecnt_req     <= '1';
                pckstart_usecnt_write   <= current_usecnt;
                pckstart_usecnt_prev    <= current_usecnt;
                
              elsif(pckstart_page_in_advance = '0') then
                
                pckstart_page_alloc_req <= '1';
                s_page_alloc            <= S_PCKSTART_PAGE_REQ;
                pckstart_usecnt_write   <= pckstart_usecnt_prev;
                
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

  --==================================================================================================
  -- FSM to receive RTU decision, set usecnt and transfer pck to the output ports
  --==================================================================================================
  -- here we wait for the RTU decision and start of pck (start of frame, SOF). once we have both, we
  -- transmit the pck_info to the outputs and ask for the end of pck (end of frame, EOF)
  -- 

  p_transfer_pck_fsm : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --========================================
        s_transfer_pck <= S_IDLE;

        rtu_rsp_ack    <= '0';
        need_pckstart_usecnt_set <= '0';
        
        pta_transfer_pck<= '0';
        pta_pageaddr    <= (others => '0');
        pta_mask        <= (others => '0');
        pta_prio        <= (others => '0');
        pta_pck_size    <= (others => '0');    
        
        current_drop    <= '0';
        current_usecnt  <= (others => '0');    
      --========================================
      else

        -- default values
        rtu_rsp_ack   <= '0';

        case s_transfer_pck is
          --===========================================================================================
          when S_IDLE =>
          --===========================================================================================  

            if(rtu_rsp_valid_i = '1' and in_pck_sof = '1') then
              if(rtu_drop_i = '1') then
                s_transfer_pck             <= S_DROP_PCK;
              elsif(rtu_dst_port_usecnt = pckstart_usecnt_prev) then
                s_transfer_pck            <= S_TRANSFER;
                pta_transfer_pck          <= '1';
                pta_pageaddr              <= pckstart_pageaddr;  -- we take stright from allocated in 
                                                                 -- advance because we are on SOF         
              else
                s_transfer_pck             <= S_SET_USECNT;
                need_pckstart_usecnt_set   <= '1'; -- let know the p_page_alloc_fsm there is work
              end if;
            elsif(rtu_rsp_valid_i = '1' and in_pck_sof = '0') then
              s_transfer_pck             <= S_WAIT_SOF;
            elsif(rtu_rsp_valid_i = '0' and in_pck_sof = '1') then
              s_transfer_pck             <= S_WAIT_RTU_VALID;
            end if;    
                
            if(rtu_rsp_valid_i = '1') then
              pta_mask       <= rtu_dst_port_mask_i;
              pta_prio       <= rtu_prio_i;
              current_drop   <= rtu_drop_i;
              current_usecnt <= rtu_dst_port_usecnt;

              rtu_rsp_ack    <= '1';
            end if;

          --===========================================================================================
          when S_WAIT_RTU_VALID =>
          --===========================================================================================
            if(rtu_rsp_valid_i = '1') then
              if(rtu_drop_i = '1') then
                s_transfer_pck             <= S_DROP_PCK;
              elsif(rtu_dst_port_usecnt = pckstart_usecnt_prev) then
                s_transfer_pck             <= S_TRANSFER;
                pta_transfer_pck           <= '1';
                pta_pageaddr               <= current_pckstart_pageaddr;              
              else
                s_transfer_pck             <= S_SET_USECNT;
                need_pckstart_usecnt_set   <= '1'; -- let know the p_page_alloc_fsm there is work
              end if;

              pta_mask       <= rtu_dst_port_mask_i;
              pta_prio       <= rtu_prio_i;
              current_drop   <= rtu_drop_i;
              current_usecnt <= rtu_dst_port_usecnt;

              rtu_rsp_ack    <= '1';
            end if;
          --===========================================================================================
          when S_WAIT_SOF =>
          --===========================================================================================
            if(in_pck_sof = '1') then
              if(current_drop = '1') then
                s_transfer_pck             <= S_DROP_PCK;
              elsif(current_usecnt = pckstart_usecnt_prev) then
                s_transfer_pck             <= S_TRANSFER;
                pta_transfer_pck           <= '1';
                pta_pageaddr               <= pckstart_pageaddr; -- take directly from allocation in advance           
              else
                s_transfer_pck             <= S_SET_USECNT;
                need_pckstart_usecnt_set   <= '1'; -- let know the p_page_alloc_fsm there is work
              end if;
            end if;            
          --===========================================================================================
          when S_SET_USECNT =>
          --===========================================================================================
            if(mmu_set_usecnt_done_i = '1') then
              need_pckstart_usecnt_set  <= '0';
              s_transfer_pck            <= S_TRANSFER;
              pta_transfer_pck          <= '1';
              pta_pageaddr              <= current_pckstart_pageaddr;

            end if;
          --===========================================================================================
          when S_TRANSFER =>
          --===========================================================================================
            -- TODO: think about enabling reception of new pck when still waiting for the transfer
            if(pta_transfer_ack_i = '1') then
              pta_transfer_pck          <= '0';
            
              if(s_rcv_pck = S_IDLE) then -- we rcv_pck fsm waits for transfer, so we can restart
                s_transfer_pck          <= S_IDLE;
              else
                s_transfer_pck          <= S_PCK_TRANSFERED;
              end if;

            end if;
          --===========================================================================================
          when S_PCK_TRANSFERED =>
          --===========================================================================================
          
            if(in_pck_eof = '1' or s_rcv_pck = S_IDLE) then -- we rcv_pck fsm waits for transfer, so we can restart
                s_transfer_pck          <= S_IDLE;
            end if;
          --===========================================================================================
          when S_DROP_PCK =>
          --===========================================================================================
            
            if(in_pck_eof = '1' or s_rcv_pck = S_IDLE) then -- we rcv_pck fsm waits for transfer, so we can restart
                s_transfer_pck          <= S_IDLE;
            end if;            

          --===========================================================================================
          when others =>
          --===========================================================================================           
            s_transfer_pck <= S_IDLE;
            
        end case;

      end if;
    end if;
    
  end process p_transfer_pck_fsm;

  --==================================================================================================
  -- FSM to receive pcks, it translates pWB I/F into MPM I/F
  --==================================================================================================
  -- this FSM receives frames from the outside world with pWB and writes the data to 
  -- the MPM (async)
  -- 
  
  -- detecting when the start of pck should not trigger allocation of new pckstart_page because
  -- we are going to dump the pck, not even trying to write to MPM
  in_pck_drop_on_sof <= '1' when ((s_transfer_pck = S_WAIT_SOF and current_drop  = '1' and in_pck_sof = '1') or
                                  (s_transfer_pck = S_IDLE     and rtu_drop_i    = '1' and in_pck_sof = '1' and
                                  rtu_rsp_valid_i = '1' )) else
                        '0';

  -- indicates that the end of the current page is approaching and the new page is not allocated yet
  no_new_pg_addr_at_eop <= '1' when (page_word_cnt = to_unsigned(g_page_size - 3, c_page_size_width) and 
                                     interpck_page_in_advance = '0') else
                           '0';
  -- indicatest that the end of current page is approaching and the previous page has not been written to
  -- the Linked List (in principle, it should not happen)
  ll_not_written_at_eop <= '1' when (page_word_cnt = to_unsigned(g_page_size - 3, c_page_size_width) and 
                                     ll_wr_req = '1') else
                           '0';
  
  p_rcv_pck_fsm : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
      --========================================
      s_rcv_pck           <= S_IDLE;
      snk_stall_force_h   <= '1';
      snk_stall_force_l   <= '1';
      snk_sel_d0          <= (others => '0');
      page_word_cnt       <= (others => '0');
      
      in_pck_dvalid_d0    <= '0';
      in_pck_dat_d0       <= (others => '0');
      in_pck_sel_d0       <= (others => '0');
      in_pck_dvalid_d1    <= '0';
      in_pck_dat_d1       <= (others => '0');
      in_pck_sel_d1       <= (others => '0'); 
      
      mmu_force_free_req  <= '0'; 
      mmu_force_free_addr <= (others => '0'); 

      mpm_dvalid          <= '0';
      mpm_pg_addr         <= (others => '0');
      mpm_data            <= (others => '0');
      mpm_dlast           <= '0';
      current_pckstart_pageaddr <= (others => '0');
      --========================================
      else
        
        -- default values:
        mpm_dlast <= '0';
        mpm_dvalid<= '0';

        case s_rcv_pck is
          --===========================================================================================
          when S_IDLE =>
          --===========================================================================================  
            snk_stall_force_h <= '1';
            snk_stall_force_l <= '1';
            in_pck_dvalid_d0  <= '0';
            in_pck_dat_d0     <= (others=>'0');
            in_pck_sel_d0     <= (others=>'0'); 
            in_pck_sel_d1     <= (others=>'0');              

            if((s_transfer_pck = S_IDLE or s_transfer_pck = S_WAIT_SOF or 
                s_transfer_pck = S_DROP_PCK or s_transfer_pck = S_PCK_TRANSFERED) and -- last pck transfered *and*
                pckstart_page_in_advance = '1' ) then                       -- first page allocated 
                                                                            -- in advance
              snk_stall_force_h <= '0';
              s_rcv_pck         <= S_READY;
            end if;

          --===========================================================================================
          when S_READY =>
          --===========================================================================================
            in_pck_dvalid_d0 <= '0';
            in_pck_dat_d0    <= (others=>'0');
            in_pck_sel_d0    <= (others=>'0');              

            if (in_pck_sof = '1') then               
              if(in_pck_drop_on_sof = '1') then
                s_rcv_pck                 <= S_DROP;
                snk_stall_force_l         <= '0';
              else  
                current_pckstart_pageaddr <= pckstart_pageaddr;
                s_rcv_pck                 <= S_RCV_DATA;
                page_word_cnt             <= (others =>'0');
                if(in_pck_dvalid = '1') then 
                  in_pck_dvalid_d0 <= in_pck_dvalid;
                  in_pck_dat_d0    <= in_pck_dat;
                  in_pck_sel_d0    <= in_pck_sel;         
                end if;
              end if;
            end if;

          --===========================================================================================
          when S_RCV_DATA =>
          --===========================================================================================
              if(in_pck_dvalid = '1') then 
                in_pck_dvalid_d0 <= in_pck_dvalid;
                in_pck_dat_d0    <= in_pck_dat;
                in_pck_sel_d0    <= in_pck_sel;         
              end if;              
              
              if(in_pck_eof = '1' or in_pck_err = '1') then 
                mpm_dlast     <= '1' ;
              end if;

              if((in_pck_dvalid = '1' and in_pck_dvalid_d0 ='1') or in_pck_eof = '1' or in_pck_err = '1') then
                mpm_dvalid    <= '1';
                mpm_data      <= in_pck_dat_d0;
                in_pck_sel_d1 <= in_pck_sel_d0;
              end if;

              if((in_pck_dvalid = '1' and in_pck_dvalid_d0 ='1') or in_pck_eof = '1' or in_pck_err = '1') then
                if(mpm_pg_req_i = '1') then
                  page_word_cnt <= to_unsigned(1, c_page_size_width);
                else
                  page_word_cnt <= page_word_cnt + 1;
                end if;
              elsif(mpm_pg_req_i = '1') then
                page_word_cnt <= (others => '0');
              end if;

              if(in_pck_err = '1') then 

                if(s_transfer_pck /= S_PCK_TRANSFERED) then
                
                  mmu_force_free_addr <= current_pckstart_pageaddr;
                
                  if(mmu_force_free_req = '1') then -- it means that the previous request is still 
                                                    -- waiting to be accepted, which is a very bad sign
                   s_rcv_pck            <= S_WAIT_FORCE_FREE;
                  else
                    mmu_force_free_req <= '1';
                  end if;
                  
                end if;
                
                snk_stall_force_h <= '1';
                snk_stall_force_l <= '1';
                s_rcv_pck         <= S_IDLE;                  
                
              elsif(s_transfer_pck = S_DROP_PCK) then   
              
                  mmu_force_free_addr <= current_pckstart_pageaddr;
                
                  if(mmu_force_free_req = '1') then -- it means that the previous request is still 
                                                    -- waiting to be accepted, which is a very bad sign
                   s_rcv_pck            <= S_WAIT_FORCE_FREE;
                  else
                    mmu_force_free_req <= '1';
                  end if;        
                
                s_rcv_pck         <= S_DROP;
                snk_stall_force_l <= '0';
                
              elsif(in_pck_eof = '1') then 

                if((s_transfer_pck = S_IDLE     or s_transfer_pck = S_WAIT_SOF or 
                    s_transfer_pck = S_DROP_PCK or s_transfer_pck = S_PCK_TRANSFERED) and -- last pck transfered *and*
                    pckstart_page_in_advance = '1' ) then                                 -- first page allocated 
                  snk_stall_force_h <= '0';
                  snk_stall_force_l <= '1';
                  s_rcv_pck         <= S_READY;
                else
                  snk_stall_force_h <= '1';
                  snk_stall_force_l <= '1';
                  s_rcv_pck         <= S_IDLE;              
                end if;                

              elsif(mpm_pg_req_i = '1') then -- MPM asserts pg_req HIGH only if dvalid is HIGH

                if(page_word_cnt /= to_unsigned(g_page_size, c_page_size_width))  then
                  assert false
                    report "something is wrong with word counting, pg_req_i received in the middle of page";
                end if; 

                mpm_pg_addr       <= interpck_pageaddr;
               
              elsif(no_new_pg_addr_at_eop = '1' or ll_not_written_at_eop = '1') then 

                snk_stall_force_h <= '1';
                s_rcv_pck         <= S_PAUSE; 

              end if;              
              
          --===========================================================================================
          when S_DROP =>
          --===========================================================================================
            
            if (in_pck_eof = '1' or in_pck_err = '1') then     
     
              if((s_transfer_pck = S_IDLE     or s_transfer_pck = S_WAIT_SOF or 
                  s_transfer_pck = S_DROP_PCK or s_transfer_pck = S_PCK_TRANSFERED) and -- last pck transfered *and*
                  pckstart_page_in_advance = '1' ) then                                 -- first page allocated 
                snk_stall_force_h <= '0';
                snk_stall_force_l <= '1';
                s_rcv_pck         <= S_READY;
              else
                snk_stall_force_h <= '1';
                snk_stall_force_l <= '1';
                s_rcv_pck         <= S_IDLE;              
              end if;
            
            end if;

          --===========================================================================================
          when S_PAUSE =>
          --===========================================================================================
            if(interpck_page_in_advance = '1' and ll_wr_req = '0') then
              snk_stall_force_h <= '0';
              s_rcv_pck         <= S_RCV_DATA;     
            end if;
          --===========================================================================================
          when S_WAIT_FORCE_FREE =>
          --===========================================================================================

             if(mmu_force_free_req = '0') then 
               mmu_force_free_req    <= '1';

              if((s_transfer_pck = S_IDLE     or s_transfer_pck = S_WAIT_SOF or 
                  s_transfer_pck = S_DROP_PCK or s_transfer_pck = S_PCK_TRANSFERED) and -- last pck transfered *and*
                  pckstart_page_in_advance = '1' ) then                                 -- first page allocated 
                snk_stall_force_h <= '0';
                snk_stall_force_l <= '1';
                s_rcv_pck         <= S_READY;
              else
                snk_stall_force_h <= '1';
                snk_stall_force_l <= '1';
                s_rcv_pck         <= S_IDLE;              
              end if;               

             end if;        
            
          --===========================================================================================
          when others =>
          --===========================================================================================           
            snk_stall_force_h <= '1';
            snk_stall_force_l <= '1';
            s_rcv_pck         <= S_IDLE;    
        end case;
        
        if(mmu_force_free_req = '1' and mmu_force_free_done_i ='1') then 
          mmu_force_free_req    <= '0';
        end if;

      end if;
    end if;
    
  end process p_rcv_pck_fsm;

  --================================================================================================
  -- for page allocation
  --================================================================================================
  page_if : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --===================================================
        pckstart_page_in_advance <= '0';
        interpck_page_in_advance <= '0';
      --===================================================
      else
        
        if(in_pck_sof = '1' and in_pck_drop_on_sof = '0') then
          pckstart_page_in_advance <= '0';
        elsif(mmu_page_alloc_done_i = '1' and pckstart_page_alloc_req = '1') then
          pckstart_page_in_advance <= '1';
        end if;

        if(mpm_pg_req_i = '1') then
          interpck_page_in_advance <= '0';
        elsif(mmu_page_alloc_done_i = '1' and interpck_page_alloc_req = '1') then
          interpck_page_in_advance <= '1';
        end if;


      end if;
    end if;
  end process;

  --================================================================================================
  -- Linked List write
  --================================================================================================
  ll_if : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
      --===================================================
      ll_wr_req         <= '0';
      ll_entry.valid    <= '0';
      ll_entry.eof      <= '0';
      ll_entry.next_page<= (others => '0');
      ll_entry.addr     <= (others => '0');
      ll_entry.dsel     <= (others => '0');
      ll_entry.size     <= (others => '0');      
      --===================================================
      else
        
        if(mpm_dlast = '1') then
          ll_wr_req         <= '1';
          ll_entry.valid    <= '1';
          ll_entry.eof      <= '1';
          ll_entry.addr     <= mpm_pg_addr;
          ---------------- TODO: make it more generic !!!! ---------------------------------
          if(snk_sel_d0 = "00") then
            ll_entry.dsel     <= (others => '1');
          else 
            ll_entry.dsel     <= (others => '0');
          end if;
          -----------------------------------------------------------------------------------
          ll_entry.size     <= std_logic_vector(page_word_cnt);
          ll_entry.next_page<= (others => '0');          
        elsif(mpm_pg_req_i = '1') then
          ll_wr_req         <= '1';
          ll_entry.valid    <= '1';
          ll_entry.eof      <= '0';
          ll_entry.addr     <= mpm_pg_addr;
          ll_entry.dsel     <= (others => '0');
          ll_entry.size     <= (others => '0');
          ll_entry.next_page<= interpck_pageaddr;          
        elsif(ll_wr_req = '1' and ll_wr_done_i = '1') then
          ll_wr_req         <= '0';
          ll_entry.valid    <= '0';
          ll_entry.eof      <= '0';
          ll_entry.next_page<= (others => '0');
          ll_entry.addr     <= (others => '0');
          ll_entry.dsel     <= (others => '0');
          ll_entry.size     <= (others => '0');             
--         elsif(ll_wr_req = '0' and ll_wr_done_i = '1') then
--           assert false
--             report "Linked List done when not asked for";
        end if;

      end if;
    end if;
  end process ll_if;

  --================================================================================================
  -- Some input signals
  --================================================================================================

  rtu_dst_port_usecnt   <= std_logic_vector(to_signed(cnt(rtu_dst_port_mask_i), g_usecount_width));
  
  snk_o.stall           <= snk_stall_int;
  snk_o.err             <= '0';  
  snk_o.ack             <= snk_ack_int;   
  snk_o.rty             <= snk_rty_int;--'0'; 
  --================================================================================================
  -- Output signals
  --================================================================================================

  rtu_rsp_ack_o         <= rtu_rsp_ack;

  
  mmu_set_usecnt_o      <= pckstart_usecnt_req;
  mmu_usecnt_o          <= pckstart_usecnt_write;  
  mmu_page_alloc_req_o  <= interpck_page_alloc_req or pckstart_page_alloc_req;
  
  mmu_force_free_o      <= mmu_force_free_req;
  mmu_force_free_addr_o <= mmu_force_free_addr;
  ---
  mmu_pageaddr_o        <= pckstart_usecnt_pgaddr;

  mpm_pg_addr_o         <= mpm_pg_addr;
  mpm_dlast_o           <= mpm_dlast;
  mpm_dvalid_o          <= mpm_dvalid;
  mpm_data_o            <= mpm_data;

  pta_transfer_pck_o    <= pta_transfer_pck;
  pta_pageaddr_o        <= pta_pageaddr;
  pta_mask_o            <= pta_mask;
  pta_prio_o            <= pta_prio;
  pta_pck_size_o        <= pta_pck_size;

  -- pWB
  snk_dat_int           <= snk_i.dat; 
  snk_adr_int           <= snk_i.adr;  
  snk_sel_int           <= snk_i.sel;  
  snk_cyc_int           <= snk_i.cyc;  
  snk_stb_int           <= snk_i.stb;  
  snk_we_int            <= snk_i.we;  
  
  
  ll_data_eof(g_page_addr_width-1 downto g_page_addr_width-g_partial_select_width) <= ll_entry.dsel;
  ll_data_eof(c_page_size_width-1 downto 0)                                        <= ll_entry.size;
  ll_data_eof(g_page_addr_width-g_partial_select_width-1 downto c_page_size_width) <= (others =>'0');
  
  ll_addr_o                               <= ll_entry.addr;
  ll_data_o(g_page_addr_width+1)          <= ll_entry.valid;
  ll_data_o(g_page_addr_width)            <= ll_entry.eof; 
  ll_data_o(g_page_addr_width-1 downto 0) <= ll_data_eof when (ll_entry.eof='1') else ll_entry.next_page;
  ll_wr_req_o                             <= ll_wr_req;

  
end syn;  -- arch
