-------------------------------------------------------------------------------
-- Title      : Input block
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_input_block.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-10-28
-- Last update: 2011-03-16
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: This block controls input to SW Core. It consists of a three 
-- Finite State Machines (FSMs):
-- 1) Read FSM - read information from Fabric Interface and stores it in FIFO
-- 
-- 2) Write FSM - reads data from FIFO and writes it into write pump
-- 
-- 3) Page FSM - allocates pages in advance and sets usecnt of pages, i.e
--    * it allocates in advance one page to be used as the first page 
--      of the pck (pckstart)
--    * it allocates in advnace one page to be used within the pck (interpck)
--    * it sets usecnt of pckstart page if it's different then the one set 
--      durring allocation
--    * it sets usecnt of interpck page if it's different then the one set 
--      durring allocation
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
--
-------------------------------------------------------------------------------
-- TODO: 
-- 1) dreq HIGH in idle ?
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.swc_swcore_pkg.all;
use work.genram_pkg.all;
use work.wr_fabric_pkg.all;

entity xswc_input_block is
  generic (
    g_when_cannot_accept_data : string := "drop_pck" --"stall_o", "rty_o" -- Don't CHANGE !
  
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
    mmu_pageaddr_i : in std_logic_vector(c_swc_page_addr_width - 1 downto 0);

    mmu_pageaddr_o : out std_logic_vector(c_swc_page_addr_width - 1 downto 0);

    -- force freeing package starting with page outputed on mmu_pageaddr_o
    mmu_force_free_o : out std_logic;

    mmu_force_free_done_i : in std_logic;

    mmu_force_free_addr_o : out std_logic_vector(c_swc_page_addr_width - 1 downto 0);

    -- set user count to the already allocated page (on mmu_pageaddr_o)
    mmu_set_usecnt_o : out std_logic;

    mmu_set_usecnt_done_i : in std_logic;

    -- user count to be set (associated with an allocated page) in two cases:
    -- * mmu_pagereq_o    is HIGH - normal allocation
    -- * mmu_set_usecnt_o is HIGH - force user count to existing page alloc
    mmu_usecnt_o : out std_logic_vector(c_swc_usecount_width - 1 downto 0);

    -- memory full
    mmu_nomem_i : in std_logic;
-------------------------------------------------------------------------------
-- I/F with Routing Table Unit (RTU)
-------------------------------------------------------------------------------      

    rtu_rsp_valid_i     : in  std_logic;
    rtu_rsp_ack_o       : out std_logic;
    rtu_dst_port_mask_i : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
    rtu_drop_i          : in  std_logic;
    rtu_prio_i          : in  std_logic_vector(c_swc_prio_width - 1 downto 0);


-------------------------------------------------------------------------------
-- I/F with Multiport Memory (MPU)
-------------------------------------------------------------------------------    

    -- indicates the beginning of the package
    mpm_pckstart_o : out std_logic;

    -- array of pages' addresses to which ports want to write
    mpm_pageaddr_o : out std_logic_vector(c_swc_page_addr_width - 1 downto 0);


    mpm_pagereq_o : out std_logic;
    -- indicator that the current page is about to be full (the last FB SRAM word
    -- is being pumped in currently), after ~c_swc_packet_mem_multiply cycles 
    -- from the rising edge of this signal this page will finish
    mpm_pageend_i : in  std_logic;

    mpm_data_o : out std_logic_vector(c_swc_data_width - 1 downto 0);

    mpm_ctrl_o : out std_logic_vector(c_swc_ctrl_width - 1 downto 0);

    -- data ready - request from each port to write data to port's pump
    mpm_drdy_o : out std_logic;

    -- the input register of a pump is full, this means that the pump cannot
    -- be written by the port. As soon as the data which is in the input registet
    -- is written to FB SRAM memory, the signal goes LOW and writing is possible
    mpm_full_i : in std_logic;

    -- request to write the content of pump's input register to FB SRAM memory, 
    -- thus flash/clean input register of the pump
    mpm_flush_o : out std_logic;

    mpm_wr_sync_i : in std_logic;

-------------------------------------------------------------------------------
-- I/F with Page Transfer Arbiter (PTA)
-------------------------------------------------------------------------------     
    -- indicates the beginning of the package, strobe
    pta_transfer_pck_o : out std_logic;

    pta_transfer_ack_i : in std_logic;

    -- array of pages' addresses to which ports want to write
    pta_pageaddr_o : out std_logic_vector(c_swc_page_addr_width - 1 downto 0);

    -- destination mask - indicates to which ports the packet should be
    -- forwarded
    pta_mask_o : out std_logic_vector(c_swc_num_ports - 1 downto 0);

    pta_pck_size_o : out std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);

    pta_prio_o : out std_logic_vector(c_swc_prio_width - 1 downto 0)

    );
end xswc_input_block;

architecture syn of xswc_input_block is

  signal fifo_data_in  : std_logic_vector(c_swc_data_width + c_swc_ctrl_width + 2 - 1 downto 0);
  signal fifo_wr       : std_logic;
  signal fifo_clean    : std_logic;
  signal fifo_clear_n    : std_logic;
  signal fifo_rd       : std_logic;
  signal fifo_data_out : std_logic_vector(c_swc_data_width + c_swc_ctrl_width + 2 - 1 downto 0);
  signal fifo_empty    : std_logic;
  signal fifo_full     : std_logic;
  --signal fifo_usedw    : std_logic_vector(5 -1 downto 0);
  signal fifo_usedw    : std_logic_vector(c_swc_input_fifo_size_log2 -1 downto 0);

  signal tx_ctrl_trans : std_logic_vector(c_swc_ctrl_width - 1 downto 0);

  signal transfering_pck : std_logic;
  signal pta_pageaddr    : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  signal pta_mask        : std_logic_vector(c_swc_num_ports - 1 downto 0);
  signal pta_prio        : std_logic_vector(c_swc_prio_width - 1 downto 0);
  signal pta_pck_size    : std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);



  signal write_ctrl_in  : std_logic_vector(1 downto 0);
  signal write_ctrl_out : std_logic_vector(1 downto 0);

  signal write_ctrl : std_logic_vector(c_swc_ctrl_width - 1 downto 0);
  signal write_data : std_logic_vector(c_swc_data_width - 1 downto 0);


  signal read_mask   : std_logic_vector(c_swc_num_ports - 1 downto 0);
  signal read_prio   : std_logic_vector(c_swc_prio_width - 1 downto 0);
  signal read_drop   : std_logic;
  signal read_usecnt : std_logic_vector(c_swc_usecount_width - 1 downto 0);

  signal write_mask   : std_logic_vector(c_swc_num_ports - 1 downto 0);
  signal write_prio   : std_logic_vector(c_swc_prio_width - 1 downto 0);
  signal write_usecnt : std_logic_vector(c_swc_usecount_width - 1 downto 0);

  signal pck_size                  : std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
  signal current_pckstart_pageaddr : std_logic_vector(c_swc_page_addr_width - 1 downto 0);


  signal usecnt_d0 : std_logic_vector(c_swc_usecount_width - 1 downto 0);

 type t_rcv_rtu_state is (S_IDLE,             
                       S_RTU_DECISION_AVAILABLE); 

 type t_page_state is (S_IDLE,                  -- waiting for some work :)
                       S_PCKSTART_SET_USECNT,   -- setting usecnt to a page which was allocated 
                                                -- in advance to be used for the first page of 
                                                -- the pck
                                                -- (only in case of the initially allocated usecnt
                                                -- is different than required)
                       S_INTERPCK_SET_USECNT,   -- setting usecnt to a page which was allocated 
                                                -- in advance to be used for the page which is 
                                                -- not first
                                                -- in the pck, this is needed, only if the page
                                                -- was allocated during transfer of previous pck 
                                                -- but was not used in the previous pck, 
                                                -- only if usecnt of both pcks are different
                       S_PCKSTART_PAGE_REQ,     -- allocating in advnace first page of the pck
                       S_INTERPCK_PAGE_REQ);    -- allocating in advance page to be used by 
                                                -- all but first page of the pck

type t_write_state is (S_IDLE,  
                       S_DROP_PCK,      
                       S_LAST_DROP, 
                       S_STUCK_WITH_DATA,      
                       S_START_FIFO_RD,         -- start requesting data from FIFO, but still
                                                -- not outputing to write_pump (initial cycle)
                                                -- trick: drdy restricted only to S_WRITE_MPM
                                                -- (see comments in the FSM)
                       S_WRITE_MPM,             -- reading FIFO, writing write_pump
                       S_LAST_MPM_WR,           -- last word of pck already written, finishing
                                                -- pck writting
                       S_NEW_PCK_IN_FIFO,       -- if there is beginning of new pck in the fifo
                                                -- we use this state (not IDLE) to wait for the 
                                                -- possibilty to start new new pck write
                       S_WAIT_WITH_TRANSFER,    -- if we get to the end of the pck, in normal case 
                                                -- we transfer startpck address, pcksize and pck prio
                                                -- to output ports. If the transfer of the previous pck
                                                -- data has not finished yet (only in case the traffic
                                                -- is really heavy), we need to wait for it to be 
                                                -- finished 
                       S_PERROR                 -- handling perror
                       );
                 
                 
 -- we love VHDL
 signal zeros                     : std_logic_vector(63 downto 0);   
 
 -- FSMs                
 signal rcv_rtu_state             : t_rcv_rtu_state;
 signal write_state               : t_write_state;
 signal page_state                : t_page_state;                         
 
 -- pckstart page allocation in advance
 signal pckstart_page_in_advance  : std_logic;
 signal pckstart_pageaddr         : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
 signal pckstart_page_alloc_req   : std_logic;
 signal pckstart_usecnt_req       : std_logic;
 signal pckstart_usecnt_in_advance: std_logic_vector(c_swc_usecount_width - 1 downto 0);  

   
 -- interpck page allocation in advance
 signal interpck_page_in_advance  : std_logic;  
 signal interpck_pageaddr         : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
 signal interpck_page_alloc_req   : std_logic;  
 signal interpck_usecnt_req       : std_logic;  
 signal interpck_usecnt_in_advance: std_logic_vector(c_swc_usecount_width - 1 downto 0);       

 -- pck usecnt setting
 signal need_pckstart_usecnt_set  : std_logic;
 signal need_interpck_usecnt_set  : std_logic; 

 -- errored pck freeing 
 signal mmu_force_free_addr       : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
 signal mmu_force_free            : std_logic;     
 
 -- error signal handling 
 signal tx_rerror_reg             : std_logic;
 signal tx_rerror_or              : std_logic; 
 signal tx_rerror                 : std_logic;
 
 -- data requset
 signal tx_dreq                   : std_logic;   
  
 -- multiport memory I/F
 signal mpm_pckstart              : std_logic;
 signal mpm_pageaddr              : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
 signal mpm_pagereq               : std_logic;
 signal mpm_flush                 : std_logic;
 -- help signal for MPM I/F
 signal flush_sig                 : std_logic; 
 signal flush_reg                 : std_logic; 
 
 -- pck info transfer signal 
 signal start_transfer            : std_logic;                
 
 -- RTU I/F
 signal rtu_rsp_ack               : std_logic;                
 
 
 signal tmp_cnt                   : std_logic_vector(7 downto 0);

 
 signal fifo_populated_enough     : std_logic;
 
 signal first_pck_word            : std_logic;
 
 signal clean_pck_cnt             : std_logic;
 
 -- signals used to check whether there is only
 -- one pck in the FIFO by detecting SOF and EOF
 -- in the FIFO, used for error handling
 signal sof_in_fifo               : std_logic;
 signal eof_in_fifo               : std_logic;
 
 -- indicates that FIFO is going to be full
 -- this is to simplify things: disable dreq
 -- when FIFO full
 signal fifo_full_in_advance      : std_logic;
 
 signal drdy                      : std_logic;
 
 -- to make if-condition simpler
 signal flush_with_valid_data     : std_logic;

 -- pWB 
 signal snk_dat_int   : std_logic_vector(15 downto 0);
 signal snk_adr_int   : std_logic_vector(1 downto 0);
 signal snk_sel_int   : std_logic_vector(1 downto 0);
 signal snk_cyc_int   : std_logic;
 signal snk_stb_int   : std_logic;
 signal snk_we_int    : std_logic;
 signal snk_stall_int : std_logic;
 signal snk_err_int   : std_logic;
 signal snk_ack_int   : std_logic;
 signal snk_rty_int   : std_logic;

 signal snk_cyc_d0    : std_logic;

 signal stall_after_err : std_logic;
 signal stall_when_stuck: std_logic;
 signal in_pck_sof      : std_logic;
 signal in_pck_dvalid   : std_logic;
 signal in_pck_eof      : std_logic;
 signal in_pck_err      : std_logic;

 signal rtu_data_read_by_write_process : std_logic;

 signal mask_eof: std_logic;
 
 signal waiting_for_error_handling : std_logic;

 signal in_fifo_full_on_eof : std_logic;
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

  zeros <= (others => '0');

--==================================================================================================
-- FIFO 
--==================================================================================================


  write_ctrl_out <= fifo_data_out(c_swc_data_width + c_swc_ctrl_width + 1 downto c_swc_data_width +
                                  c_swc_ctrl_width); 
  write_data     <= fifo_data_out(c_swc_data_width - 1 downto 0);
  write_ctrl     <= fifo_data_out(c_swc_data_width + c_swc_ctrl_width - 1 downto c_swc_data_width);

  fifo_rd        <= ((not fifo_empty) and (not mpm_full_i)) when (write_state = S_WRITE_MPM or
                                                                  write_state = S_START_FIFO_RD)    else
                     '1'                                    when (write_state = S_DROP_PCK)             else 
                     '0';


  fifo_populated_enough <= '1' when
                           ((fifo_usedw > std_logic_vector(to_unsigned(c_swc_packet_mem_multiply, c_swc_input_fifo_size_log2)))
                            or fifo_full = '1') else '0';    

  fifo_full_in_advance <= '1'
                      when ((fifo_usedw > std_logic_vector(to_unsigned(c_swc_fifo_full_in_advance, c_swc_input_fifo_size_log2)))
                                 or fifo_full = '1') else '0';


  fifo_clear_n <= (not fifo_clean) and rst_n_i;
  U_FIFO : generic_sync_fifo
    generic map(
      g_data_width      => c_swc_data_width + c_swc_ctrl_width + 2,
      g_size      => c_swc_input_fifo_size,
      g_with_count => true
      )
    port map (
      clk_i   => clk_i,
      rst_n_i => fifo_clear_n,

      we_i => fifo_wr,
      d_i      => fifo_data_in,

      rd_i => fifo_rd,
      q_o      => fifo_data_out,

      empty_o => fifo_empty,
      full_o  => fifo_full,
      count_o => fifo_usedw
      );

  --==================================================================================================
  -- PCK size cnt
  --==================================================================================================
  -- here we calculate pck size: we increment when
  -- the valid_i is HIGH

  -- cleaning counter
  clean_pck_cnt <= '1' when ((write_state = S_START_FIFO_RD) or
                                 (write_state = S_NEW_PCK_IN_FIFO)) else '0';

  pck_size_cnt : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        
        pck_size <= (others => '0');
        
      else
        
        if(clean_pck_cnt = '1') then
          
          pck_size <= (others => '0');
          
        elsif(drdy = '1') then
          
          pck_size <= std_logic_vector(unsigned(pck_size) + 1);
          
        end if;
        
      end if;
    end if;
    
  end process;

  --==================================================================================================
  -- PCK transition (after pck has been received) 
  --==================================================================================================   
  -- we need to know whether there is Start of Pck or End of Pck in the FIFO in order to handle 
  -- errors correctly

  transition_check : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --================================================
        sof_in_fifo <= '0';
        eof_in_fifo <= '0';
      --================================================
      else

        if(in_pck_sof = '1') then
          
          sof_in_fifo <= '1';
          
        elsif(write_ctrl_out = b"01" ) then -- ??? or tx_rerror = '1') then
          
          sof_in_fifo <= '0';
          
        end if;

        --if(tx_eof_p1_i = '1' or tx_rerror_p1_i = '0' ) then
        if(in_pck_eof = '1') then
          
          eof_in_fifo <= '1';
          
        elsif(flush_sig = '1') then
          
          eof_in_fifo <= '0';
          
        end if;
        
      end if;
    end if;
  end process;

  --==================================================================================================
  -- pWB (sink) to input FIFO
  --==================================================================================================
  in_pck_sof    <= snk_cyc_int and not snk_cyc_d0;                                       -- detecting the beginning of the pck
  in_pck_dvalid <= snk_stb_int and     snk_we_int and snk_cyc_int and not snk_stall_int; -- valid data which can be stored into FIFO
  in_pck_eof    <= snk_cyc_d0  and not snk_cyc_int  ;                     -- detecting the end of the pck
  in_pck_err    <= '1'         when   in_pck_dvalid = '1'   and                          -- we have valid data           *and*
                               (snk_adr_int = c_WRF_STATUS) and                          -- the address indicates status *and*
                               (f_unmarshall_wrf_status(snk_dat_int).error = '1') else   -- the status indicates error       
                   '0';

  -- we need to indicate somehow that there is error and pck is dumped !!!

  snk_stall_int <= fifo_full or stall_after_err or stall_when_stuck;

  -- this is internal to the input_block (i.e. the input FIFO)
  -- IMPORTANT: bit 1 [write_ctrl_in(1)] determines (negation) whether data written to MPM is valid
  -- (see the bottom of the page)
  write_ctrl_in <=  b"01" when (first_pck_word = '1' or in_pck_sof = '1')    else -- first word of the pck
                    b"10" when (in_pck_err = '1')                            else -- error on input
                    b"11" when (in_pck_eof = '1' or in_fifo_full_on_eof = '1')     else -- last word or dummy after last word
                    b"00";
  

  fifo_wr       <=  ((in_pck_dvalid                  or   -- valid data from pWB
                    (in_pck_eof and (not mask_eof))) and  -- we want to write dummy EOF, but not when there is an error
                    (not fifo_full))                 or   -- we usually don't attempt to write to a full fifo
                     in_fifo_full_on_eof;                 -- this is the case when the dummy EOF is to be written to 
                                                          -- FIFO but the FIFO is full, so we try writing as long as we we succeed 
                                                          -- (in_fifo_full_on_eof is HIGH when (fifo_full & in_pck_eof), gets LOW 
                                                          -- 1 cycle after fifo_full gets LOW

  fifo_data_in(c_swc_data_width - 1    downto 0)                     <= snk_dat_int;
  fifo_data_in(c_swc_data_width + 2 -1 downto c_swc_data_width)      <= snk_adr_int;
  fifo_data_in(c_swc_data_width + 4 -1 downto c_swc_data_width + 2)  <= snk_sel_int;
  fifo_data_in(c_swc_data_width + 6 -1 downto c_swc_data_width + 4)  <= write_ctrl_in;


  read_helper : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
      --================================================
        snk_ack_int    <= '0';
        first_pck_word <= '0';
        tx_rerror      <= '0';
        stall_after_err<= '0';
	fifo_clean     <= '0';
	snk_cyc_d0     <= '0';
	mask_eof       <= '0';
	waiting_for_error_handling <= '0';
	in_fifo_full_on_eof <='0';
      --================================================
      else
      
        snk_cyc_d0 <= snk_cyc_int;

        -- remember the info that we are writing first word to the FIFO in the case
        -- when the first word is stalled.
        if(in_pck_sof = '1' and (snk_stall_int = '1' or snk_stb_int='0') ) then
          first_pck_word <= '1';
        elsif(first_pck_word = '1' and snk_stall_int = '0' and snk_stb_int='1') then
          first_pck_word <= '0';
        end if;
        
        if(in_pck_eof = '1' and fifo_full = '1') then 
          in_fifo_full_on_eof <='1';
        elsif(in_fifo_full_on_eof = '1' and fifo_full = '0') then
          in_fifo_full_on_eof <='0';
        end if;
        
        -- generating ack
        snk_ack_int <= snk_cyc_int and snk_stb_int and snk_we_int and not snk_stall_int;

        
        if(in_pck_err = '1') then 
          mask_eof       <= '1';
        elsif( in_pck_eof = '1') then
          mask_eof       <= '0';
        end if;

	if(in_pck_err = '1') then
	   waiting_for_error_handling <='1';
	elsif(tx_rerror = '1') then
	  waiting_for_error_handling <='0';
	end if;

        -- if there is error and the input is stopped, 
        fifo_clean     <= '0';
        tx_rerror      <= '0';

        if(in_pck_err = '1' or snk_rty_int = '1') then 
          if(eof_in_fifo = '1' and sof_in_fifo = '1') then
            -- there is the end of a valid pck in the fifo, wait fo this pck to be read
            -- by the write_fsm, stall input while waiting
            stall_after_err  <= '1';
          else
            -- there is only invalid pck in the fifo, clean the fifo
            fifo_clean     <= '1';
            tx_rerror      <= '1';            
          end if;
        elsif(stall_after_err ='1' and eof_in_fifo = '0') then
          -- the valid pck has been read by write_fsm from the FIFO, now the fifo can be cleaned,
          -- the error handled on the other side of the FIFO, and pWB input enabled (stall LOW on 
          -- sink)
          fifo_clean     <= '1';
          tx_rerror      <= '1';
          stall_after_err<= '0';
        end if;

       end if;  -- if(rst_n_i = '0') then
     end if; --rising_edge(clk_i) then
   end process read_helper;

  --==================================================================================================
  -- FSM to write pck to Multiport memory write pump (FIFO -> MPM)
  --==================================================================================================
  -- 

  write_fsm : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --================================================
        write_state    <= S_IDLE;
        start_transfer <= '0';
        mpm_pckstart   <= '0';
        mpm_pagereq    <= '0';

        current_pckstart_pageaddr <= (others => '1');

        write_mask   <= (others => '0');
        write_prio   <= (others => '0');
        write_usecnt <= (others => '0');

        mpm_pckstart <= '0';
        mpm_pageaddr <= (others => '1');
        mpm_pagereq  <= '0';
        flush_reg    <= '0';
        snk_rty_int      <= '0';

        mmu_force_free_addr <= (others => '0');
        mmu_force_free      <= '0';
        
	stall_when_stuck <='0';

        rtu_data_read_by_write_process <= '0';
      --================================================
      else

        -- main finite state machine
        case write_state is

          --========================================================================================
          when S_IDLE =>
            --========================================================================================
            
            start_transfer <= '0';
            flush_reg      <= '0';
            start_transfer <= '0';
            mpm_pagereq    <= '0';
            rtu_data_read_by_write_process <= '0';
            stall_when_stuck <= '0';
	    snk_rty_int      <= '0';
            
            if((fifo_populated_enough = '1'             ) and   -- at least on "c_swc_packet_mem_multiply"
               (pckstart_page_in_advance = '1'          ) and   -- needed to write first page
               (rcv_rtu_state = S_RTU_DECISION_AVAILABLE) and   -- there is RTU decision avaible (TODO: *)
               (mpm_full_i = '0'                        )) then -- obvious, no write to full MPM

               if(read_drop = '1' or read_mask = zeros(c_swc_num_ports - 1 downto 0)) then
                 
                 --droping pcks
                 --
                  write_state <= S_DROP_PCK;
                  rtu_data_read_by_write_process <= '1';

               else
                  write_state <= S_START_FIFO_RD;
               end if;
              
            end if;
          --========================================================================================       
          when S_DROP_PCK =>
            --========================================================================================

            rtu_data_read_by_write_process <= '0';
            ------------------------------------------------------------------------------------------          
            if(tx_rerror      = '1'     or   -- handling error, this signal is generated by read_fsm
               write_ctrl_out = b"10") then  -- should not use this (this should be indicated previously
                                             -- by tx_rerror
              ------------------------------------------------------------------------------------------          
              write_state                  <= S_IDLE;
              
            ------------------------------------------------------------------------------------------ 
            else                        -- in normal case, we end up here
              ------------------------------------------------------------------------------------------ 

              if(write_ctrl_out = b"11") then  -- EOF without valid data -

                write_state <= S_LAST_DROP;
                
              end if;
            ------------------------------------------------------------------------------------------  
            end if;
          --===========================================================================================      
          when S_LAST_DROP =>
            --===========================================================================================

              if(transfering_pck = '1') then -- this means that we are fucked, the SWCORE is stuck with too
                                              -- much data
                 --write_state                    <= S_STUCK_WITH_DATA;
                  write_state <= S_DROP_PCK;
                  rtu_data_read_by_write_process <= '1';

              elsif(write_ctrl_out = b"01") then
                write_state <= S_NEW_PCK_IN_FIFO;
              else
                write_state <= S_IDLE;
              end if;

          -- TODO* enable to write to MPM even without RTU decision (will be quite some work)
          -- for the time being wait for RTU here
          --========================================================================================       
          when S_START_FIFO_RD =>
            --========================================================================================

            -- here is a small trick, we already request data from FIFO with fifo_rd HIHG
            -- but the drdy (which is the same signal as fifo_rd)  is not HIGH here because
            -- drdy is restricted only to S_WRITE_MPM !!! thanx to this trick we can have things
            -- simple
            
            write_state                    <= S_WRITE_MPM;
            -- address of the first word of the pck, need to be remembered (for i.e. transfer, force free)
            current_pckstart_pageaddr      <= pckstart_pageaddr;
            write_mask                     <= read_mask;
            write_prio                     <= read_prio;
            write_usecnt                   <= read_usecnt;
            
            -- info to the *fsm_rcv_rtu*
            rtu_data_read_by_write_process <= '1'; 

            -- indicate this is the first pck, set page
            mpm_pckstart                   <= '1';
            mpm_pagereq                    <= '1';
            mpm_pageaddr                   <= pckstart_pageaddr;

          --========================================================================================     
          when S_STUCK_WITH_DATA =>
            --========================================================================================

                if(g_when_cannot_accept_data = "drop_pck") then 

                   if(mmu_force_free_done_i = '1') then
               
                       mmu_force_free <= '0';
                       write_state <= S_DROP_PCK;
                       rtu_data_read_by_write_process <= '1';

                    end if;
                end if;

          --========================================================================================     
          when S_WRITE_MPM =>
            --========================================================================================
            
            rtu_data_read_by_write_process <= '0';
            mpm_pckstart                   <= '0';
            mpm_pagereq                    <= '0';
            ------------------------------------------------------------------------------------------          
            if(tx_rerror      = '1'     or   -- handling error, this signal is generated by read_fsm
               write_ctrl_out = b"10") then  -- should not use this (this should be indicated previously
                                             -- by tx_rerror
              ------------------------------------------------------------------------------------------          
              
              flush_reg                    <= '1';
              write_state                  <= S_PERROR;
              mmu_force_free_addr          <= current_pckstart_pageaddr;
              mmu_force_free               <= '1';
            ------------------------------------------------------------------------------------------  
            elsif(write_ctrl_out /= b"01" and  -- the data coming from FIFO indicates its not the first 
                                               -- word of PCK *and*
                  mpm_pckstart = '1') then     -- we are saying to MPM it's first word of PCK
              ------------------------------------------------------------------------------------------  

              -- this is pathologic situation, bad, not sure what to do
              assert false
                report "write_fsm: S_WRITE_MPM, should not go here";
              
              write_state <= S_START_FIFO_RD;

            ------------------------------------------------------------------------------------------ 
            else                        -- in normal case, we end up here
              ------------------------------------------------------------------------------------------ 
              
              if(mpm_pagereq              = '0'  and  -- not setting yet new page
                 mpm_pageend_i            = '1'  and  -- detecting info from MPM: new page needed
                 interpck_page_in_advance = '1') then -- we have a spare page allocated

                mpm_pageaddr <= interpck_pageaddr;
                mpm_pagereq  <= '1';
                
              else

                mpm_pageaddr <= (others => '1');
                mpm_pagereq  <= '0';
                
              end if;
              

              if(write_ctrl_out = b"11") then  -- EOF without valid data -

                write_state <= S_LAST_MPM_WR;
                
              end if;
            ------------------------------------------------------------------------------------------  
            end if;

          --===========================================================================================      
          when S_LAST_MPM_WR =>
            --===========================================================================================

            start_transfer <= '0';
            flush_reg      <= '0';
            mpm_pageaddr   <= (others => '1');
            mpm_pagereq    <= '0';
            -- if another page needs to be allocated for the last chunck 
            -- of date, transfer only if we have spare page for that.
            -- otherwise, we can end up reading pck without last piece of data !!!!

--         if(interpck_page_in_advance = '0' and    -- no spare page
            if(mpm_pageend_i = '1') then  -- new page needed to write last chucnk of data
              
              write_state <= S_WAIT_WITH_TRANSFER;
              
            elsif(transfering_pck = '1') then -- this means that we are fucked, the SWCORE is stuck with too
                                              -- much data
              write_state                    <= S_STUCK_WITH_DATA;
              mmu_force_free_addr            <= current_pckstart_pageaddr;
              mmu_force_free                 <= '1';

              
            else
              
              start_transfer <= '1';

              if(write_ctrl_out = b"01" and waiting_for_error_handling = '0') then
                write_state <= S_NEW_PCK_IN_FIFO;
              else
                write_state <= S_IDLE;
              end if;
            end if;

          --===========================================================================================
          when S_WAIT_WITH_TRANSFER =>
            --===========================================================================================
            -- we need to be sure that the last chunk of data is written to MPM before it's read 
            -- on the other side, if the MPM is full, allocating new page may take looooong time
            -- so we transfer only if there is page prepared 
            -- Of course, this is the case only if the pck finished while pgend request HIGH
            
            if(interpck_page_in_advance = '1') then
            
              if(transfering_pck = '1') then
                  write_state                    <= S_STUCK_WITH_DATA;
                  mmu_force_free_addr            <= current_pckstart_pageaddr;
                  mmu_force_free                 <= '1';
                  
              else

                 start_transfer <= '1';
                 mpm_pageaddr   <= interpck_pageaddr;
                 mpm_pagereq    <= '1';

                 if(write_ctrl_out = b"01") then
                   write_state <= S_NEW_PCK_IN_FIFO;
                 else
                   write_state <= S_IDLE;
                 end if;
              end if;
            end if;

          --===========================================================================================         
          when S_NEW_PCK_IN_FIFO =>
            --===========================================================================================         
            start_transfer <= '0';
            mpm_pagereq    <= '0';
            -- i'm not usre here
--         if(mpm_pagereq              = '0'  and   -- not setting yet new page
--            mpm_pageend_i            = '1'  and   -- detecting info from MPM: new page needed
--            interpck_page_in_advance = '1') then  -- we have a spare page allocated
--        
--           mpm_pageaddr               <= interpck_pageaddr;
--           mpm_pagereq                <= '1';
--        
--         else
--
--           mpm_pageaddr               <= (others => '1');
--           mpm_pagereq                <= '0';
--        
--         end if; 
            if(tx_rerror      = '1' ) then -- in case that the pack which we are about to read
                                           -- from the FIFO gets errored
               
               write_state <= S_IDLE;
               rtu_data_read_by_write_process <= '1';
               
            elsif((fifo_populated_enough = '1'             ) and   -- at least on "c_swc_packet_mem_multiply"
               (pckstart_page_in_advance = '1'          ) and   -- needed to write first page
               (rcv_rtu_state = S_RTU_DECISION_AVAILABLE) and   -- there is RTU decision avaible (TODO: !!!)
               (mpm_full_i = '0'                        )) then -- obvious, no write to full MPM

               if(read_drop = '1' or read_mask = zeros(c_swc_num_ports - 1 downto 0)) then

                  --droping pcks
                  write_state <= S_DROP_PCK;
                  rtu_data_read_by_write_process <= '1';

               else

                  -- first word of the pck
                  current_pckstart_pageaddr <= pckstart_pageaddr;
                  write_mask                <= read_mask;
                  write_prio                <= read_prio;
                  write_usecnt              <= read_usecnt;
                  rtu_data_read_by_write_process <= '1';

                  mpm_pckstart <= '1';
                  mpm_pagereq  <= '1';
                  mpm_pageaddr <= pckstart_pageaddr;
    
                  write_state <= S_WRITE_MPM;
               end if;
              
            end if;


          --===========================================================================================
          when S_PERROR =>
            --===========================================================================================         
            flush_reg <= '0';

            if(mmu_force_free_done_i = '1') then
              
              mmu_force_free <= '0';
              write_state    <= S_IDLE;
              
            end if;

          --===========================================================================================         
          when others =>
            --===========================================================================================
            
            write_state    <= S_IDLE;
            start_transfer <= '0';
            mpm_pckstart   <= '0';
            mpm_pagereq    <= '0';

        --===========================================================================================                     
        end case;
        --===========================================================================================
        
      end if;
    end if;
    
  end process;

  --==================================================================================================
  -- FSM to allocate pages in advance and set USECNT of pages allocated in advance
  --==================================================================================================
  -- Auxiliary Finite State Machine which talks with
  -- Memory Management Unit, it controls:
  -- * page allocation
  -- * usecnt setting
  fsm_page : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --========================================
        page_state <= S_IDLE;

        interpck_pageaddr          <= (others => '0');
        interpck_page_alloc_req    <= '0';
        interpck_usecnt_in_advance <= (others => '0');
        interpck_usecnt_req        <= '0';

        pckstart_pageaddr          <= (others => '0');
        pckstart_page_alloc_req    <= '0';
        pckstart_usecnt_req        <= '0';
        pckstart_usecnt_in_advance <= (others => '0');
      --========================================
      else

        -- main finite state machine
        case page_state is

          --===========================================================================================
          when S_IDLE =>
            --===========================================================================================   
            interpck_page_alloc_req <= '0';
            interpck_usecnt_req     <= '0';
            pckstart_page_alloc_req <= '0';
            pckstart_usecnt_req     <= '0';
            
            
            if((need_pckstart_usecnt_set = '1' and need_interpck_usecnt_set = '1') or
               (need_pckstart_usecnt_set = '1' and need_interpck_usecnt_set = '0')) then

              page_state          <= S_PCKSTART_SET_USECNT;
              pckstart_usecnt_req <= '1';
              
            elsif(pckstart_page_in_advance = '0') then
              
              pckstart_page_alloc_req <= '1';
              page_state              <= S_PCKSTART_PAGE_REQ;
              
            elsif(interpck_page_in_advance = '0') then
              
              interpck_page_alloc_req <= '1';
              page_state              <= S_INTERPCK_PAGE_REQ;

            elsif(need_interpck_usecnt_set = '1') then
              
              page_state          <= S_INTERPCK_SET_USECNT;
              interpck_usecnt_req <= '1';
              
            end if;

          --===========================================================================================
          when S_PCKSTART_SET_USECNT =>
            --===========================================================================================        
            if(mmu_set_usecnt_done_i = '1') then
              
              pckstart_usecnt_req <= '0';

              -- remember the count of allocated page
              -- this is becuase, we will use it for different 
              -- pck with probably different uscnt 
              pckstart_usecnt_in_advance <= usecnt_d0;

              if(pckstart_page_in_advance = '0') then
                
                pckstart_page_alloc_req <= '1';
                page_state              <= S_PCKSTART_PAGE_REQ;
                
              elsif(interpck_page_in_advance = '0') then
                
                interpck_page_alloc_req <= '1';
                page_state              <= S_INTERPCK_PAGE_REQ;
                
              elsif(need_interpck_usecnt_set = '1') then
                
                page_state          <= S_INTERPCK_SET_USECNT;
                interpck_usecnt_req <= '1';
                
              else
                
                page_state <= S_IDLE;
                
              end if;
              
            end if;

          --===========================================================================================        
          when S_INTERPCK_SET_USECNT =>
            --===========================================================================================

            if(mmu_set_usecnt_done_i = '1') then
              
              interpck_usecnt_req <= '0';

              -- remember the count of allocated page
              -- this is becuase, we will use it for different 
              -- pck with probably different uscnt 
              -- we do it here as well, because it's possible
              -- that this page is not used by the pck
              -- which set the USECNT
              interpck_usecnt_in_advance <= usecnt_d0;

              if(pckstart_page_in_advance = '0') then
                
                pckstart_page_alloc_req <= '1';
                page_state              <= S_PCKSTART_PAGE_REQ;
                
              elsif(need_pckstart_usecnt_set = '0') then
                
                page_state          <= S_PCKSTART_SET_USECNT;
                pckstart_usecnt_req <= '1';
                
              elsif(need_interpck_usecnt_set = '1') then
                
                page_state          <= S_INTERPCK_SET_USECNT;
                interpck_usecnt_req <= '1';
                
              else
                
                page_state <= S_IDLE;
                
              end if;
              
            end if;

          --===========================================================================================  
          when S_PCKSTART_PAGE_REQ =>
            --===========================================================================================
            if(mmu_page_alloc_done_i = '1') then

              pckstart_page_alloc_req <= '0';


              -- remember the page start addr
              pckstart_pageaddr          <= mmu_pageaddr_i;
              pckstart_usecnt_in_advance <= usecnt_d0;


              if(need_pckstart_usecnt_set = '1') then
                
                page_state          <= S_PCKSTART_SET_USECNT;
                pckstart_usecnt_req <= '1';

                
              elsif(interpck_page_in_advance = '0') then
                
                interpck_page_alloc_req <= '1';
                page_state              <= S_INTERPCK_PAGE_REQ;

                
              elsif(need_interpck_usecnt_set = '1') then
                
                page_state          <= S_INTERPCK_SET_USECNT;
                interpck_usecnt_req <= '1';
                
              else
                
                page_state <= S_IDLE;
                
              end if;
            end if;

          --===========================================================================================
          when S_INTERPCK_PAGE_REQ =>
            --===========================================================================================
            
            if(mmu_page_alloc_done_i = '1') then
              
              interpck_page_alloc_req    <= '0';
              interpck_pageaddr          <= mmu_pageaddr_i;
              --remember the usecnt which was at the time of
              -- page allocation, this is in case that the page
              -- is used to store another pck then the current one.
              -- therefore we compare this stored value with the
              -- current usecnt
              interpck_usecnt_in_advance <= usecnt_d0;
              interpck_page_alloc_req    <= '0';

              if(need_pckstart_usecnt_set = '1') then
                
                page_state          <= S_PCKSTART_SET_USECNT;
                pckstart_usecnt_req <= '1';

                
              elsif(pckstart_page_in_advance = '0') then
                
                pckstart_page_alloc_req <= '1';
                page_state              <= S_PCKSTART_PAGE_REQ;
                
              elsif(need_interpck_usecnt_set = '1') then
                
                page_state          <= S_INTERPCK_SET_USECNT;
                interpck_usecnt_req <= '1';
                
              else
                
                page_state <= S_IDLE;
                
              end if;
            end if;

          --===========================================================================================
          when others =>
            --===========================================================================================           
            page_state <= S_IDLE;
            
        end case;

        usecnt_d0 <= write_usecnt;

      end if;
    end if;
    
  end process;


  fsm_rcv_rtu : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --========================================
        rcv_rtu_state  <= S_IDLE;
        read_mask      <= (others => '0');
        read_prio      <= (others => '0');
        read_usecnt    <= (others => '0');
        read_drop      <= '0';
        rtu_rsp_ack    <= '0';
      --========================================
      else

        
        case rcv_rtu_state is

          --===========================================================================================
          when S_IDLE =>
          --===========================================================================================  

            if(rtu_rsp_valid_i = '1') then

                read_mask     <= rtu_dst_port_mask_i;
                read_prio     <= rtu_prio_i;
		read_drop     <= rtu_drop_i;
                read_usecnt   <= std_logic_vector(to_signed(cnt(rtu_dst_port_mask_i), read_usecnt'length));
                rcv_rtu_state <= S_RTU_DECISION_AVAILABLE;
                rtu_rsp_ack   <= '1';

             end if;
          --===========================================================================================
          when S_RTU_DECISION_AVAILABLE =>
          --===========================================================================================

             rtu_rsp_ack   <= '0';
             
             -- TODO: potential problem if we can confuse RTU decisions if 
             -- the error occures at the end of the pck, and the new decision is there
             if(rtu_data_read_by_write_process = '1' or tx_rerror = '1') then
               rcv_rtu_state <= S_IDLE;
             end if;

          --===========================================================================================
          when others =>
            --===========================================================================================           
            rcv_rtu_state <= S_IDLE;
            
        end case;

      end if;
    end if;
    
  end process;


  --================================================================================================
  -- this proces controls Package Transfer Arbiter
  --================================================================================================
  pta_if : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --===================================================
        transfering_pck <= '0';
        pta_pageaddr    <= (others => '0');
        pta_mask        <= (others => '0');
        pta_prio        <= (others => '0');
        pta_pck_size    <= (others => '0');
      --===================================================
      else

        
        if(start_transfer = '1' ) then -- after being stuck, transfer the pck received while being stuck

          -- normal case, transfer arbiter free                      
          transfering_pck <= '1';

          pta_pageaddr <= current_pckstart_pageaddr;
          pta_mask     <= write_mask;
          pta_prio     <= write_prio;
          pta_pck_size <= pck_size;
          --pta_pck_size <= std_logic_vector(unsigned(pck_size) - 1);
          
        elsif(pta_transfer_ack_i = '1' and transfering_pck = '1') then

          --transfer finished
          transfering_pck <= '0';
          pta_pageaddr    <= (others => '0');
          pta_mask        <= (others => '0');
          pta_prio        <= (others => '0');
          pta_pck_size    <= (others => '0');
          

        end if;
      end if;
    end if;
  end process;

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
        need_pckstart_usecnt_set <= '0';
        need_interpck_usecnt_set <= '0';
      --===================================================
      else
        
        if(mpm_pckstart = '1') then
          
          if(read_usecnt = pckstart_usecnt_in_advance) then
            need_pckstart_usecnt_set <= '0';
            pckstart_page_in_advance <= '0';
          else
            need_pckstart_usecnt_set <= '1';

          end if;

          if(read_usecnt = interpck_usecnt_in_advance) then
            need_interpck_usecnt_set <= '0';
          else
            need_interpck_usecnt_set <= '1';
          end if;
          
        elsif(page_state = S_INTERPCK_SET_USECNT and mmu_set_usecnt_done_i = '1') then
          need_interpck_usecnt_set <= '0';
        elsif(page_state = S_PCKSTART_SET_USECNT and mmu_set_usecnt_done_i = '1')then
          need_pckstart_usecnt_set <= '0';
        end if;

        --if(write_state = S_SET_NEXT_PAGE or write_state = S_SET_LAST_NEXT_PAGE) then 
        if(mpm_pagereq = '1' and mpm_pckstart = '0') then
          interpck_page_in_advance <= '0';
        elsif(mmu_page_alloc_done_i = '1' and interpck_page_alloc_req = '1') then
          interpck_page_in_advance <= '1';
        end if;


        if(mmu_set_usecnt_done_i = '1' and page_state = S_PCKSTART_SET_USECNT) then
          pckstart_page_in_advance <= '0';
        elsif(mmu_page_alloc_done_i = '1' and pckstart_page_alloc_req = '1') then
          pckstart_page_in_advance <= '1';
        end if;

      end if;
    end if;
  end process;


  --================================================================================================
  -- Output signals
  --================================================================================================
  
  --flush_with_valid_data <= '1' when (write_ctrl_out = b"10") else '0';
  flush_with_valid_data <= '0';

  drdy <= ((not (fifo_empty and (not flush_with_valid_data))) and (not mpm_full_i) and not write_ctrl_out(1))
                            when (write_state = S_WRITE_MPM) else '0';
  
  flush_sig <= (write_ctrl_out(1)) when (write_state = S_WRITE_MPM) else '0';
  mpm_flush <= flush_reg or flush_sig;


  rtu_rsp_ack_o <= rtu_rsp_ack;

  mmu_force_free_addr_o <= mmu_force_free_addr;
  mmu_set_usecnt_o      <= pckstart_usecnt_req or interpck_usecnt_req;
  mmu_usecnt_o          <= write_usecnt;  --read_usecnt;
  mmu_page_alloc_req_o  <= interpck_page_alloc_req or pckstart_page_alloc_req;
  mmu_force_free_o      <= mmu_force_free;
  mmu_pageaddr_o        <= interpck_pageaddr when (page_state = S_INTERPCK_SET_USECNT) else
                            pckstart_pageaddr when (page_state = S_PCKSTART_SET_USECNT) else (others => '0');
  
  mpm_pckstart_o <= mpm_pckstart;
  mpm_pageaddr_o <= mpm_pageaddr;
  mpm_pagereq_o  <= mpm_pagereq;
  mpm_data_o     <= write_data;
  mpm_ctrl_o     <= write_ctrl;
  mpm_drdy_o     <= drdy;
  mpm_flush_o    <= mpm_flush;

  pta_transfer_pck_o <= transfering_pck;
  pta_pageaddr_o     <= pta_pageaddr;
  pta_mask_o         <= pta_mask;
  pta_prio_o         <= pta_prio;
  pta_pck_size_o     <= pta_pck_size;

  -- pWB
  snk_dat_int        <= snk_i.dat; 
  snk_adr_int        <= snk_i.adr;  
  snk_sel_int        <= snk_i.sel;  
  snk_cyc_int        <= snk_i.cyc;  
  snk_stb_int        <= snk_i.stb;  
  snk_we_int         <= snk_i.we;  
  snk_o.stall        <= snk_stall_int;
  snk_o.err          <= '0';  
  snk_o.ack          <= snk_ack_int;   
  snk_o.rty          <= snk_rty_int;--'0';   
  
  
end syn;  -- arch
