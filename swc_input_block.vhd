-------------------------------------------------------------------------------
-- Title      : Input block
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_input_block.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-10-28
-- Last update: 2010-11-01
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: This block controls input to SW Core. It consists of few 
-- processes:
-- 1) PCK_FSM - the most important, it controls interaction between 
--    Fabric Interface and Multiport Memory
-- 
-- 
-- 
-- 
-- 
-- 
-- 
-- 
-- 
-- 
-- 
-- 
-- 
-- 
-- 
-- 
-- 
-- 
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

-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.swc_swcore_pkg.all;
use work.platform_specific.all;

entity swc_input_block is

  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

-------------------------------------------------------------------------------
-- Fabric I/F  
-------------------------------------------------------------------------------

    tx_sof_p1_i    : in  std_logic;
    tx_eof_p1_i    : in  std_logic;
    tx_data_i      : in  std_logic_vector(c_swc_data_width - 1 downto 0);
    tx_ctrl_i      : in  std_logic_vector(c_swc_ctrl_width - 1 downto 0);
    tx_valid_i     : in  std_logic;
    tx_bytesel_i   : in  std_logic;
    tx_dreq_o      : out std_logic;
    tx_abort_p1_i  : in  std_logic;
    tx_rerror_p1_i : in  std_logic;
-------------------------------------------------------------------------------
-- I/F with Page allocator (MMU)
-------------------------------------------------------------------------------    

    -- indicates that a port X wants to write page address of the "write" access
    mmu_page_alloc_req_o  : out  std_logic;
    
    
    mmu_page_alloc_done_i : in std_logic;

    -- array of pages' addresses to which ports want to write
    mmu_pageaddr_i : in  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    
    mmu_pageaddr_o : out  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    
    -- force freeing package starting with page outputed on mmu_pageaddr_o
    mmu_force_free_o   : out std_logic;
    
    mmu_force_free_done_i : in std_logic;
    
    mmu_force_free_addr_o : out std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    
    -- set user count to the already allocated page (on mmu_pageaddr_o)
    mmu_set_usecnt_o   : out std_logic;
    
    mmu_set_usecnt_done_i  : in  std_logic;
    
    -- user count to be set (associated with an allocated page) in two cases:
    -- * mmu_pagereq_o    is HIGH - normal allocation
    -- * mmu_set_usecnt_o is HIGH - force user count to existing page alloc
    mmu_usecnt_o       : out  std_logic_vector(c_swc_usecount_width - 1 downto 0);
    
    -- memory full
    mmu_nomem_i : in std_logic;     
-------------------------------------------------------------------------------
-- I/F with Routing Table Unit (RTU)
-------------------------------------------------------------------------------      
    
    rtu_rsp_valid_i     : in std_logic;
    rtu_rsp_ack_o       : out std_logic;
    rtu_dst_port_mask_i : in std_logic_vector(c_swc_num_ports  - 1 downto 0);
    rtu_drop_i          : in std_logic;
    rtu_prio_i          : in std_logic_vector(c_swc_prio_width - 1 downto 0);
  
    
-------------------------------------------------------------------------------
-- I/F with Multiport Memory (MPU)
-------------------------------------------------------------------------------    
    
    -- indicates the beginning of the package
    mpm_pckstart_o : out  std_logic;
       
    -- array of pages' addresses to which ports want to write
    mpm_pageaddr_o : out  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    
    
    mpm_pagereq_o : out std_logic;
    -- indicator that the current page is about to be full (the last FB SRAM word
    -- is being pumped in currently), after ~c_swc_packet_mem_multiply cycles 
    -- from the rising edge of this signal this page will finish
    mpm_pageend_i  : in std_logic;

    mpm_data_o  : out  std_logic_vector(c_swc_data_width - 1 downto 0);

    mpm_ctrl_o  : out  std_logic_vector(c_swc_ctrl_width - 1 downto 0);    
    
    -- data ready - request from each port to write data to port's pump
    mpm_drdy_o  : out  std_logic;
    
    -- the input register of a pump is full, this means that the pump cannot
    -- be written by the port. As soon as the data which is in the input registet
    -- is written to FB SRAM memory, the signal goes LOW and writing is possible
    mpm_full_i  : in std_logic;

    -- request to write the content of pump's input register to FB SRAM memory, 
    -- thus flash/clean input register of the pump
    mpm_flush_o : out  std_logic;    
    


-------------------------------------------------------------------------------
-- I/F with Page Transfer Arbiter (PTA)
-------------------------------------------------------------------------------     
    -- indicates the beginning of the package, strobe
    pta_transfer_pck_o : out  std_logic;
    
    pta_transfer_ack_i : in std_logic;
       
    -- array of pages' addresses to which ports want to write
    pta_pageaddr_o : out  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    
    -- destination mask - indicates to which ports the packet should be
    -- forwarded
    pta_mask_o     : out  std_logic_vector(c_swc_num_ports - 1 downto 0);
    
    pta_pck_size_o : out  std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);

    pta_prio_o     : out  std_logic_vector(c_swc_prio_width - 1 downto 0)
    
    );
end swc_input_block;
    
architecture syn of swc_input_block is    

signal fifo_data_in  : std_logic_vector(c_swc_data_width + c_swc_ctrl_width + 2 - 1 downto 0);
signal fifo_wr       : std_logic;
signal fifo_clean    : std_logic;
signal fifo_rd       : std_logic;
signal fifo_rd_and       : std_logic;
signal fifo_data_out : std_logic_vector(c_swc_data_width + c_swc_ctrl_width + 2 - 1 downto 0);
signal fifo_empty    : std_logic;
signal fifo_full     : std_logic;
signal fifo_usedw    : std_logic_vector(5 -1 downto 0);
signal tx_ctrl_trans : std_logic_vector(c_swc_ctrl_width - 1 downto 0);  

signal transfering_pck  : std_logic;
signal pta_pageaddr     : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
signal pta_mask         : std_logic_vector(c_swc_num_ports - 1 downto 0);
signal pta_prio         : std_logic_vector(c_swc_prio_width - 1 downto 0);
signal pta_pck_size     : std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
signal transfering_pck_on_wait   : std_logic;


signal write_ctrl_in : std_logic_vector(1 downto 0);
signal write_ctrl_out: std_logic_vector(1 downto 0);

signal write_ctrl    : std_logic_vector(c_swc_ctrl_width - 1 downto 0);
signal write_data    : std_logic_vector(c_swc_data_width - 1 downto 0);


signal read_mask     : std_logic_vector(c_swc_num_ports - 1 downto 0);
signal read_prio     : std_logic_vector(c_swc_prio_width - 1 downto 0);
signal read_usecnt   : std_logic_vector(c_swc_usecount_width - 1 downto 0);

signal write_mask     : std_logic_vector(c_swc_num_ports - 1 downto 0);
signal write_pck_size : std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
signal write_prio     : std_logic_vector(c_swc_prio_width - 1 downto 0);
signal write_usecnt   : std_logic_vector(c_swc_usecount_width - 1 downto 0);

signal pck_size      : std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
signal current_pckstart_pageaddr : std_logic_vector(c_swc_page_addr_width - 1 downto 0);


signal usecnt_d0                 : std_logic_vector(c_swc_usecount_width - 1 downto 0); 


type t_read_state is (S_IDLE,                   -- we wait for other processes (page fsm and 
                                               -- transfer) to be ready
                     S_READY_FOR_PCK,          -- this is introduced to diminish optimization 
                                               -- (optimized design did not work) in this state, 
                     S_WAIT_FOR_SOF,           -- we've got RTU response, but there is no SOF
                     S_WAIT_FOR_RTU_RSP,       -- we've got SOF (request from previous pck) but
                                               -- there is no RTU valid signal (quite improbable)
                     S_WRITE_FIFO, 
                     S_WRITE_PAUSE_INPUT_COS,
                     S_WRITE_PAUSE_FIFO_COS,
                     S_WRITE_PAUSE_BOTH_COSs,
                     S_WRITE_DUMMY_EOF,
                     S_WAIT_FOR_TRANSFER,
                     S_WAIT_FOR_CLEAN_FIFO,
                     S_DROP_PCK);              -- droping pck

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
                          S_START_FIFO_RD,
                          S_START_MPM_WR,            
                          S_WRITE_MPM,
                          S_WRITE_PAUSE_MPM_COS,
                          S_WRITE_PAUSE_FIFO_COS,
                          S_WRITE_PAUSE_BOTH_COSs,
                          S_LAST_MPM_WR,
                          S_NEW_PCK_IN_FIFO,
                          S_WAIT_WITH_TRANSFER
                          );

 type t_rerror_state is (S_IDLE,                -- waiting for some work :)
                        S_WAIT_TO_FREE_PCK,    -- 
                        S_PERROR); -- droping pck                   
                 
 
 signal rerror_state    : t_rerror_state;                        
 signal read_state      : t_read_state;
 signal write_state     : t_write_state;
 signal page_state      : t_page_state;                         
 
 
 signal mmu_force_free            : std_logic;     
 signal start_transfer  : std_logic;               
 signal zeros : std_logic_vector(63 downto 0);   

 signal tx_dreq  : std_logic;                
 
 signal rtu_rsp_ack   : std_logic;                
 signal pckstart_page_in_advance  : std_logic;
 signal pckstart_pageaddr         : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
 signal pckstart_page_alloc_req   : std_logic;
 signal pckstart_usecnt_req       : std_logic;
 signal pckstart_usecnt_in_advance: std_logic_vector(c_swc_usecount_width - 1 downto 0);  

   
 -- this is a page which used within the pck
 signal interpck_page_in_advance  : std_logic;  
 signal interpck_pageaddr         : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
 signal interpck_page_alloc_req   : std_logic;  
 signal interpck_usecnt_req       : std_logic;  
 signal interpck_usecnt_in_advance: std_logic_vector(c_swc_usecount_width - 1 downto 0);       
 
 signal mmu_force_free_addr : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
 

 
 signal need_pckstart_usecnt_set : std_logic;
 signal need_interpck_usecnt_set : std_logic; 
 
 
 signal tmp_cnt : std_logic_vector(7 downto 0);
 
 signal tx_rerror_reg : std_logic;
 
 signal tx_rerror_or : std_logic; 

 signal mpm_pckstart : std_logic;
 signal mpm_pageaddr : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
 signal mpm_pagereq  : std_logic;
 signal mpm_data     : std_logic_vector(c_swc_data_width - 1 downto 0);
 signal mpm_ctrl     : std_logic_vector(c_swc_ctrl_width - 1 downto 0);    
 signal mpm_drdy     : std_logic;
 signal mpm_flush    : std_logic; 
 
 signal tx_rerror    : std_logic;
 
 signal two_pck_in_fifo: std_logic;
 
 signal fifo_populated_enough : std_logic;
 
 signal first_pck_word  : std_logic;
 
 
 signal clean_pck_cnt  : std_logic;
-------------------------------------------------------------------------------
-- Function which calculates number of 1's in a vector
------------------------------------------------------------------------------- 
  function cnt (a:std_logic_vector) return integer is
    variable nmb : integer range 0 to a'LENGTH;
    variable ai : std_logic_vector(a'LENGTH-1 downto 0);
    constant middle : integer := a'LENGTH/2;
  begin
    ai := a;
    if ai'length>=2 then
      nmb := cnt(ai(ai'length-1 downto middle)) + cnt(ai(middle-1 downto 0));
    else
      if ai(0)='1' then 
        nmb:=1; 
      else 
        nmb:=0; 
      end if;
    end if;
    return nmb;
  end cnt;

  
  
begin --arch

 zeros <= (others =>'0');

 fifo_data_in(c_swc_data_width                    - 1 downto 0)                                   <= tx_data_i;
 fifo_data_in(c_swc_data_width + c_swc_ctrl_width - 1 downto c_swc_data_width)                    <= tx_ctrl_trans;
 fifo_data_in(c_swc_data_width + c_swc_ctrl_width + 1 downto c_swc_data_width + c_swc_ctrl_width) <= write_ctrl_in;

 tx_ctrl_trans <= b"1111" when (tx_ctrl_i      = x"7" and tx_bytesel_i = '1')  else tx_ctrl_i;
 
 fifo_wr       <=  '1'                                when (read_state = S_WRITE_DUMMY_EOF )     else 
                    ((not fifo_full) and tx_valid_i)  when (read_state = S_WRITE_FIFO )          else
                    (not fifo_full)                   when (read_state = S_WRITE_PAUSE_FIFO_COS) else
                    (tx_valid_i)                      when (read_state = S_WRITE_PAUSE_INPUT_COS)else
                    ((not fifo_full) and tx_valid_i)  when (read_state = S_WRITE_PAUSE_BOTH_COSs)else
                    '0';

 
 write_ctrl_in <=  b"01"  when (first_pck_word = '1'                   )       else
                   b"10"  when (tx_valid_i     = '1' and tx_eof_p1_i = '1')    else
                   b"11"  when (read_state     = S_WRITE_DUMMY_EOF)            else
                   b"00" ;
 
 write_ctrl_out <= fifo_data_out(c_swc_data_width + c_swc_ctrl_width + 1 downto c_swc_data_width + c_swc_ctrl_width); 
 write_data     <= fifo_data_out(c_swc_data_width                    - 1 downto 0);
 write_ctrl     <= fifo_data_out(c_swc_data_width + c_swc_ctrl_width - 1 downto c_swc_data_width) ;
 
 fifo_rd_and    <=  (not fifo_empty) and (not mpm_full_i)                             when (write_state = S_WRITE_PAUSE_BOTH_COSs) else
                    (not fifo_empty)                                                  when (write_state = S_WRITE_PAUSE_FIFO_COS ) else
                   ((not fifo_empty) and (not mpm_full_i) 
                   and fifo_populated_enough and pckstart_page_in_advance)            when (write_state = S_NEW_PCK_IN_FIFO   )    else fifo_rd ;
     
     
 fifo_populated_enough <= '1'  when ((fifo_usedw  > b"01111") or fifo_full = '1') else '0';    
 
 clean_pck_cnt         <= '1'  when ((write_state = S_START_MPM_WR) or (write_state = S_NEW_PCK_IN_FIFO)) else '0';
 
 FIFO: generic_sync_fifo
  generic map(
    g_width      => c_swc_data_width + c_swc_ctrl_width + 2,
    g_depth      => 32,
    g_depth_log2 => 5
    )
  port map   (
      clk_i    => clk_i,
      clear_i  => fifo_clean,

      wr_req_i => fifo_wr,
      d_i      => fifo_data_in,

      rd_req_i => fifo_rd_and,
      q_o      => fifo_data_out,

      empty_o  => fifo_empty,
      full_o   => fifo_full,
      usedw_o  => fifo_usedw
      );

 -- here we calculate pck size: we increment when
 -- the valid_i is HIGH
 pck_size_cnt : process(clk_i, rst_n_i)
 begin
   if rising_edge(clk_i) then
     if(rst_n_i = '0') then
       
       pck_size <= (others =>'0');
       
     else
       
       if(clean_pck_cnt = '1') then
       
         pck_size <= (others =>'0');
         
       elsif(mpm_drdy = '1' and mpm_flush = '0') then
       
         pck_size <= std_logic_vector(unsigned(pck_size) + 1);
         
       end if;
       
     end if;
   end if;
   
 end process;
   
 transition_check : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --================================================
        two_pck_in_fifo          <= '0';
        --================================================
      else

        if(fifo_empty ='0' and tx_sof_p1_i = '1') then
          
          two_pck_in_fifo          <= '1';
      
        elsif(write_ctrl_out = b"01") then
    
          two_pck_in_fifo          <= '0';
          
        end if;  

        
      end if;
    end if;   
  end process;
  
  

  
 read_fsm : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --================================================
        read_state               <= S_IDLE;
        
        tx_dreq                  <= '0';

        rtu_rsp_ack              <= '0';
    
        read_mask                <= (others => '0');
        read_prio                <= (others => '0');
        read_usecnt              <= (others => '0');
        tx_rerror                <= '0';
        first_pck_word           <= '0';
        --================================================
      else


        if(tx_sof_p1_i = '1') then
          first_pck_word <= '1';
        elsif(first_pck_word = '1' and tx_valid_i = '1') then
          first_pck_word <= '0';
        end if;
        
        
        -- main finite state machine
        case read_state is


          --============================================================================
          when S_IDLE =>
          --============================================================================
                   
            tx_dreq      <= '0';
            fifo_clean   <= '0';
            tx_rerror    <= '0';
            
            
            if(fifo_full = '0' and tx_rerror_reg = '0'   ) then 
         
               -- prepared to be accepting new package
               read_state <= S_READY_FOR_PCK;
              
            end if;
            
            
          --============================================================================           
          when S_READY_FOR_PCK =>
          --============================================================================
                    
              fifo_clean               <= '0';
              tx_dreq                  <= '0';
              
            if(rtu_rsp_valid_i = '1'  and rtu_drop_i = '1') then
            
               -- if we've got RTU decision to drop, we don't give a damn about 
               -- anything else, just pretend to be receiving the msg
               tx_dreq                  <= '1';
               rtu_rsp_ack              <= '1';
               read_state               <= S_DROP_PCK;
            
            elsif(fifo_full = '0') then
            
               if(rtu_rsp_valid_i = '1' and tx_sof_p1_i = '1') then

                 -- beutifull, everything that is needed, is there:
                 --  * RTU decision
                 --  * SOF
                 read_state               <=  S_WRITE_FIFO;
                 tx_dreq                  <= '1';
                 rtu_rsp_ack              <= '1';
         
         
                 -- remember
                 read_mask                <= rtu_dst_port_mask_i;
                 read_prio                <= rtu_prio_i;
                 read_usecnt              <= std_logic_vector(to_signed(cnt(rtu_dst_port_mask_i),read_usecnt'length));
                                

               elsif(rtu_rsp_valid_i = '1' and tx_sof_p1_i = '0') then
             
                 -- so we've got RTU decision, but no SOF, let's wait for SOF
                 -- but remember RTU RSP and ack it, so RTU is free 
                 rtu_rsp_ack              <= '1';
                 read_state                <= S_WAIT_FOR_SOF;
                 tx_dreq                  <= '1';
                 --- remember
                 read_mask                <= rtu_dst_port_mask_i;
                 read_prio                <= rtu_prio_i;
                 read_usecnt              <= std_logic_vector(to_signed(cnt(rtu_dst_port_mask_i),read_usecnt'length));
             
               elsif(rtu_rsp_valid_i = '0' and tx_sof_p1_i = '1') then
               
                 -- we've got SOF because it was requested at the end of the last PCK
                 -- but the RTU is still processing
                 rtu_rsp_ack              <= '0';
                 read_state                <= S_WAIT_FOR_RTU_RSP;
                 tx_dreq                  <= '0';

               end if;
             end if;
          --============================================================================   
          when S_WAIT_FOR_SOF =>
          --============================================================================
                       
              rtu_rsp_ack             <= '0';
              
              if(tx_sof_p1_i = '1') then
              
                -- very nicely, everything is in place, we can go ahead
                tx_dreq               <= '1';
                read_state            <=  S_WRITE_FIFO;   
                
              end if;

          --============================================================================         
          when S_WAIT_FOR_RTU_RSP => 
          --============================================================================          
            
            if(tx_rerror_p1_i = '1' ) then
            
              read_state               <= S_IDLE;
              tx_dreq                  <= '0';
              
            elsif(rtu_rsp_valid_i = '1') then

              tx_dreq                  <= '1';
              rtu_rsp_ack              <= '1'; 
              read_state               <=  S_WRITE_FIFO;
             --remember
              read_mask                <= rtu_dst_port_mask_i;
              read_prio                <= rtu_prio_i;
              read_usecnt              <= std_logic_vector(to_signed(cnt(rtu_dst_port_mask_i),read_usecnt'length));
         
            end if;

          --============================================================================     
          when S_WRITE_FIFO =>
          --============================================================================           
            if(tx_rerror_p1_i = '1')then
             
              if(two_pck_in_fifo = '1') then
        
                read_state               <= S_WAIT_FOR_CLEAN_FIFO;
                tx_dreq                  <= '0';
        
              else
        
                -- error, screw everything else
                read_state               <= S_IDLE;
                tx_dreq                  <= '0';
                fifo_clean               <= '1';
                tx_rerror                <= '1';
        
              end if;
              
            elsif( tx_valid_i = '1' and tx_eof_p1_i = '1') then
              
              read_state               <= S_IDLE;
              tx_dreq                  <= '0';
              
            elsif( tx_valid_i = '0' and tx_eof_p1_i = '1') then
            
              read_state               <= S_WRITE_DUMMY_EOF;
              tx_dreq                  <= '0';   
              
            elsif(fifo_full = '1' and tx_valid_i = '0') then
            
              read_state              <= S_WRITE_PAUSE_INPUT_COS;
              
            elsif(fifo_full = '1' and tx_valid_i = '1') then  
              
              read_state              <= S_WRITE_PAUSE_FIFO_COS;
              
            elsif(fifo_full = '0' and tx_valid_i = '0') then  
            
              read_state              <= S_WRITE_PAUSE_INPUT_COS;

                   
              
            end if;    
          
          --============================================================================ 
          when S_WRITE_PAUSE_FIFO_COS  =>
          --============================================================================
           
            if(tx_rerror_p1_i = '1')then
             
              if(two_pck_in_fifo = '1') then
        
                read_state               <= S_WAIT_FOR_CLEAN_FIFO;
                tx_dreq                  <= '0';
        
              else
        
                -- error, screw everything else
                read_state               <= S_IDLE;
                tx_dreq                  <= '0';
                fifo_clean               <= '1';
                tx_rerror                <= '1';
        
              end if;
              
            elsif(fifo_full = '0') then
              
              if( tx_valid_i = '1' and tx_eof_p1_i = '1') then
              
                read_state               <= S_IDLE;
                tx_dreq                  <= '0';
              
              elsif( tx_valid_i = '0' and tx_eof_p1_i = '1') then
            
                read_state               <= S_WRITE_DUMMY_EOF;
                tx_dreq                  <= '0';                    
                
              else
                
                read_state              <= S_WRITE_FIFO;
                
              end if;    
            end if;
          --============================================================================   
          when S_WRITE_PAUSE_INPUT_COS =>                      
          --============================================================================

            if(tx_rerror_p1_i = '1')then
             
              if(two_pck_in_fifo = '1') then
        
                read_state               <= S_WAIT_FOR_CLEAN_FIFO;
                tx_dreq                  <= '0';
        
              else
        
                -- error, screw everything else
                read_state               <= S_IDLE;
                tx_dreq                  <= '0';
                fifo_clean               <= '1';
                tx_rerror                <= '1';
        
              end if;
              
            elsif( tx_valid_i = '1' and tx_eof_p1_i = '1') then
              
              read_state               <= S_IDLE;
              tx_dreq                  <= '0';
              
            elsif( tx_valid_i = '0' and tx_eof_p1_i = '1') then
            
              read_state               <= S_WRITE_DUMMY_EOF;
              tx_dreq                  <= '0';                    
                
            elsif( tx_valid_i = '1' and tx_eof_p1_i = '0') then
                
              read_state              <= S_WRITE_FIFO;
                
            end if;
            
          --============================================================================ 
          when S_WAIT_FOR_CLEAN_FIFO =>			
          --============================================================================
                
            if(two_pck_in_fifo = '0') then
       
              read_state               <= S_IDLE;
              tx_dreq                  <= '0';
              fifo_clean               <= '1';
              tx_rerror                <= '1';
        
            end if;

          --============================================================================
          when S_WRITE_DUMMY_EOF =>
          --============================================================================
                        
              read_state               <= S_IDLE;  

          --============================================================================          
          when S_DROP_PCK => 
          --============================================================================             
            rtu_rsp_ack               <= '0';
             
            if(tx_eof_p1_i = '1' or tx_rerror_p1_i = '1' ) then 
              
              read_state              <= S_IDLE;
              tx_dreq                 <= '0';
              
            end if;

          --============================================================================
          when others =>
          --============================================================================
                      
              read_state              <= S_IDLE;
              tx_dreq                 <= '0';
          
          --============================================================================
          --============================================================================                    
            
        end case;
        
      end if;
    end if;
    
  end process;
  

 write_fsm : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --================================================
        write_state               <= S_IDLE;
        fifo_rd                  <= '0';
        start_transfer           <= '0';
        mpm_pckstart             <= '0';
        mpm_pagereq              <= '0';
        
        current_pckstart_pageaddr<= (others => '1');
        mpm_drdy                 <= '0';
        
        write_mask               <= (others => '0');
        write_pck_size           <= (others => '0');
        write_prio               <= (others => '0');
        write_usecnt             <= (others => '0');
    
        mpm_pckstart             <= '0';
        mpm_pageaddr             <= (others => '1');
        mpm_pagereq              <= '0';
        mpm_data                 <= (others => '0');
        mpm_ctrl                 <= (others => '0');
        mpm_drdy                 <= '0';
        mpm_flush                <= '0';
        --================================================
      else

        -- main finite state machine
        case write_state is

          --============================================================================
          when S_IDLE =>
          --============================================================================
                     
            start_transfer       <= '0';
            mpm_flush            <= '0';
            mpm_drdy             <= '0';
            start_transfer       <= '0';  
            if(((fifo_usedw  > b"01111") or (fifo_full = '1'))  and (pckstart_page_in_advance = '1') and mpm_full_i = '0') then   
                
              if(write_ctrl_out = b"01" ) then
              
                fifo_rd                    <= '1';
                write_state                <= S_START_MPM_WR;
                
              else
            
                write_state                <= S_START_FIFO_RD;
                fifo_rd                    <= '1';
                
              end if;
               
            end if;
       
          --============================================================================       
          when S_START_FIFO_RD =>
          --============================================================================
                     
            write_state                <= S_START_MPM_WR;
           
          --============================================================================        
          when S_START_MPM_WR =>
          --============================================================================            
            
            if(write_ctrl_out = b"01" ) then
              
              -- first word of the pck
              current_pckstart_pageaddr  <= pckstart_pageaddr;
              write_mask                 <= read_mask;
              write_prio                 <= read_prio;
              write_usecnt               <= read_usecnt;			
              
              
              mpm_pckstart               <= '1';
              mpm_pagereq                <= '1';
              mpm_pageaddr               <= pckstart_pageaddr;
              mpm_data                   <= write_data;
              mpm_ctrl                   <= write_ctrl;
              mpm_drdy                   <= '1';
            
              write_state                <= S_WRITE_MPM;
        
            end if;
          
          --============================================================================     
          when S_WRITE_MPM =>
          --============================================================================
          
          mpm_pckstart               <= '0';
          mpm_pagereq                <= '0';
          
          if(tx_rerror = '1') then 
          
            mpm_flush              <= '1';
            mpm_drdy               <= '0';
            fifo_rd                <= '0';
            write_state            <= S_IDLE;
            
          else
            
            if(mpm_pagereq = '0' and mpm_pageend_i = '1' and interpck_page_in_advance = '1') then
        
              mpm_pageaddr               <= interpck_pageaddr;
              mpm_pagereq                <= '1';
        
            else

              mpm_pageaddr               <= (others => '1');
              mpm_pagereq                <= '0';
        
            end if;
            
            if(fifo_empty = '1' and mpm_full_i = '1' ) then
        
              write_state              <= S_WRITE_PAUSE_BOTH_COSs;
              mpm_data                 <= write_data;
              mpm_ctrl                 <= write_ctrl;
              mpm_drdy                 <= '0';
              fifo_rd                  <= '0';

            elsif(fifo_empty = '1' and write_ctrl_out = b"00") then
        
              write_state              <= S_WRITE_PAUSE_FIFO_COS;
              mpm_data                 <= write_data;
              mpm_ctrl                 <= write_ctrl;
              mpm_drdy                 <= '0';
              fifo_rd                  <= '0';
            
            elsif(mpm_full_i = '1' ) then
               
               write_state              <= S_WRITE_PAUSE_MPM_COS;
               mpm_data                 <= write_data;
               mpm_ctrl                 <= write_ctrl;
               mpm_drdy                 <= '0';
               fifo_rd                  <= '0';
                            
                
            else
          
              if( write_ctrl_out = b"11") then
          
                -- last empty word of the pck
                mpm_flush              <= '1';
                mpm_drdy               <= '0';
                fifo_rd                <= '0';
               -- start_transfer         <= '1';
                write_state            <= S_LAST_MPM_WR;
          
              elsif( write_ctrl_out = b"10") then				  
        
                -- last non-empty word of the pck
                mpm_flush            <= '1';
                fifo_rd              <= '0';
                mpm_data             <= write_data;
                mpm_ctrl             <= write_ctrl;
                mpm_drdy             <= '1';
                write_state          <= S_LAST_MPM_WR;
                --start_transfer       <= '1';
        
              else
        
                mpm_flush            <= '0';
                fifo_rd              <= '1';				
                mpm_data             <= write_data;
                mpm_ctrl             <= write_ctrl;
                mpm_drdy             <= '1';
                write_state          <= S_WRITE_MPM;
          
              end if;
            end if;
          end if;

       --============================================================================
       when S_WAIT_WITH_TRANSFER =>
       --============================================================================

         if(interpck_page_in_advance = '1') then

            start_transfer       <= '1';
                
            if(write_ctrl_out = b"01") then 
              write_state               <= S_NEW_PCK_IN_FIFO;
            else
              write_state               <= S_IDLE;
            end if;
         end if;
         

       --============================================================================
       when S_WRITE_PAUSE_MPM_COS =>
       --============================================================================
                
         if(tx_rerror = '1') then 
           mpm_flush              <= '1';
           mpm_drdy               <= '0';
           fifo_rd                <= '0';
           write_state            <= S_IDLE;
            
         else
         
           if(mpm_pagereq = '0' and mpm_pageend_i = '1' and interpck_page_in_advance = '1') then
          
             mpm_pageaddr               <= interpck_pageaddr;
             mpm_pagereq                <= '1';
          
           else
  
             mpm_pageaddr               <= (others => '1');
             mpm_pagereq                <= '0';
          
           end if;
  
           if(mpm_full_i = '0' and fifo_empty = '0') then
                    
             if( write_ctrl_out = b"11") then
             
               -- last empty word of the pck
               mpm_flush              <= '1';
               mpm_drdy               <= '0';
               fifo_rd                <= '0';
               write_state           <= S_LAST_MPM_WR;
           
             elsif( write_ctrl_out = b"10") then				  
          
                -- last non-empty word of the pck
               mpm_flush            <= '1';
               fifo_rd              <= '0';
               --mpm_data             <= write_data;
               --mpm_ctrl             <= write_ctrl;
               mpm_drdy             <= '1';
               write_state          <= S_LAST_MPM_WR;
        
             else
        
               mpm_flush            <= '0';
               fifo_rd              <= '1';				
              -- mpm_data             <= write_data;
               --mpm_ctrl             <= write_ctrl;
               mpm_drdy             <= '1';
               write_state          <= S_WRITE_MPM;
          
             end if;
           end if;
         end if;         
         
         --============================================================================         
         when S_WRITE_PAUSE_BOTH_COSs =>
         --============================================================================
               
           if(tx_rerror = '1') then 
             mpm_flush              <= '1';
             mpm_drdy               <= '0';
             fifo_rd                <= '0';
             write_state            <= S_IDLE;
              
           else
           
             if(mpm_pagereq = '0' and mpm_pageend_i = '1' and interpck_page_in_advance = '1') then
            
               mpm_pageaddr               <= interpck_pageaddr;
               mpm_pagereq                <= '1';
            
             else
    
               mpm_pageaddr               <= (others => '1');
               mpm_pagereq                <= '0';
            
             end if;
    
             if(fifo_empty = '0' and mpm_full_i = '0') then
                      
               if( write_ctrl_out = b"11") then
               
                 -- last empty word of the pck
                 mpm_flush              <= '1';
                 mpm_drdy               <= '0';
                 fifo_rd                <= '0';
                 write_state           <= S_LAST_MPM_WR;
             
               elsif( write_ctrl_out = b"10") then				  
            
                  -- last non-empty word of the pck
                 mpm_flush            <= '1';
                 fifo_rd              <= '0';
                 --mpm_data             <= write_data;
                 --mpm_ctrl             <= write_ctrl;
                 mpm_drdy             <= '1';
                 write_state          <= S_LAST_MPM_WR;
          
               else
          
                 mpm_flush            <= '0';
                 fifo_rd              <= '1';				
                -- mpm_data             <= write_data;
                 --mpm_ctrl             <= write_ctrl;
                 mpm_drdy             <= '1';
                 write_state          <= S_WRITE_MPM;
            
               end if;
             end if;
           end if;      
  
           
         
       --============================================================================         
       when S_WRITE_PAUSE_FIFO_COS =>
       --============================================================================
             
         if(tx_rerror = '1') then 
           mpm_flush              <= '1';
           mpm_drdy               <= '0';
           fifo_rd                <= '0';
           write_state            <= S_IDLE;
            
         else
         
           if(mpm_pagereq = '0' and mpm_pageend_i = '1' and interpck_page_in_advance = '1') then
          
             mpm_pageaddr               <= interpck_pageaddr;
             mpm_pagereq                <= '1';
          
           else
  
             mpm_pageaddr               <= (others => '1');
             mpm_pagereq                <= '0';
          
           end if;
  
           if(fifo_empty = '0' and mpm_full_i = '0') then
                    
             if( write_ctrl_out = b"11") then
             
               -- last empty word of the pck
               mpm_flush              <= '1';
               mpm_drdy               <= '0';
               fifo_rd                <= '0';
               write_state           <= S_LAST_MPM_WR;
           
             elsif( write_ctrl_out = b"10") then				  
          
                -- last non-empty word of the pck
               mpm_flush            <= '1';
               fifo_rd              <= '0';
               --mpm_data             <= write_data;
               --mpm_ctrl             <= write_ctrl;
               mpm_drdy             <= '1';
               write_state          <= S_LAST_MPM_WR;
        
             else
        
               mpm_flush            <= '0';
               fifo_rd              <= '1';				
              -- mpm_data             <= write_data;
               --mpm_ctrl             <= write_ctrl;
               mpm_drdy             <= '1';
               write_state          <= S_WRITE_MPM;
          
             end if;
           end if;
         end if;      

       --============================================================================      
       when S_LAST_MPM_WR =>
       --============================================================================
        
         start_transfer            <= '0';
         mpm_flush                 <= '0';
         mpm_drdy                  <= '0';
         fifo_rd                   <= '0';
         
         if(mpm_pagereq = '0' and mpm_pageend_i = '1' and interpck_page_in_advance = '1') then
        
           mpm_pageaddr               <= interpck_pageaddr;
           mpm_pagereq                <= '1';
        
         else

           mpm_pageaddr               <= (others => '1');
           mpm_pagereq                <= '0';
        
         end if;         

                
         -- if another page needs to be allocated for the last chunck 
         -- of date, transfer only if we have spare page for that.
         -- otherwise, we can end up reading pck without last piece of data !!!!
         if(interpck_page_in_advance = '0' and mpm_pageend_i ='1') then
             write_state          <= S_WAIT_WITH_TRANSFER;
         else
         
            start_transfer       <= '1';
                  
            if(write_ctrl_out = b"01") then 
              write_state               <= S_NEW_PCK_IN_FIFO;
            else
              write_state               <= S_IDLE;
            end if;
         end if;

       --============================================================================         
       when S_NEW_PCK_IN_FIFO => 
       --============================================================================         
         start_transfer       <= '0';
         if(mpm_pagereq = '0' and mpm_pageend_i = '1' and interpck_page_in_advance = '1') then
        
           mpm_pageaddr               <= interpck_pageaddr;
           mpm_pagereq                <= '1';
        
         else

           mpm_pageaddr               <= (others => '1');
           mpm_pagereq                <= '0';
        
         end if; 
         
         
         if(((fifo_usedw  > b"01111") or (fifo_full = '1')) and (pckstart_page_in_advance = '1') and mpm_full_i = '0') then 
         
           -- first word of the pck
           current_pckstart_pageaddr  <= pckstart_pageaddr;
           write_mask                 <= read_mask;
           write_prio                 <= read_prio;
           write_usecnt               <= read_usecnt;			
   
           mpm_pckstart               <= '1';
           mpm_pagereq                <= '1';
           mpm_pageaddr               <= pckstart_pageaddr;
           mpm_data                   <= write_data;
           mpm_ctrl                   <= write_ctrl;
           mpm_drdy                   <= '1';
         
           fifo_rd                    <= '1';
           write_state                <= S_WRITE_MPM;
           
         end if;
      --============================================================================         
      when others =>
      --============================================================================
            
         write_state               <= S_IDLE;
         fifo_rd                   <= '0';
         mpm_drdy                  <= '0';
           
           
      --============================================================================
      --============================================================================                      
      end case;
        
   end if;
 end if;
    
end process;
  

 -- Auxiliary Finite State Machine which talks with
 -- Memory Management Unit, it controls:
 -- * page allocation
 -- * usecnt setting
 fsm_page : process(clk_i, rst_n_i)
 begin
   if rising_edge(clk_i) then
     if(rst_n_i = '0') then
       --========================================
       page_state                 <= S_IDLE;
       
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

        when S_IDLE =>
           
           interpck_page_alloc_req   <= '0';
           interpck_usecnt_req       <= '0';
           pckstart_page_alloc_req   <= '0';
           pckstart_usecnt_req       <= '0';
           
           
           if((need_pckstart_usecnt_set = '1' and need_interpck_usecnt_set = '1') or
              (need_pckstart_usecnt_set = '1' and need_interpck_usecnt_set = '0') ) then
             
             page_state               <= S_PCKSTART_SET_USECNT;
             pckstart_usecnt_req      <= '1';
            
           elsif(pckstart_page_in_advance = '0') then
           
             pckstart_page_alloc_req  <= '1';
             page_state               <= S_PCKSTART_PAGE_REQ;
             
             
           elsif(interpck_page_in_advance = '0') then 
             
             interpck_page_alloc_req  <= '1';
             page_state               <= S_INTERPCK_PAGE_REQ;

           elsif(need_interpck_usecnt_set = '1') then 
             
             page_state               <= S_INTERPCK_SET_USECNT;
             interpck_usecnt_req      <= '1';
           
           end if;
                      

        when S_PCKSTART_SET_USECNT =>
        
           if(mmu_set_usecnt_done_i = '1') then
          
             pckstart_usecnt_req        <= '0';   
             pckstart_usecnt_in_advance<= usecnt_d0;
             
             if(need_interpck_usecnt_set = '1') then 
               
               page_state               <= S_INTERPCK_SET_USECNT;
               interpck_usecnt_req      <= '1';
             
             elsif(interpck_page_in_advance = '0') then 
               
               interpck_page_alloc_req  <= '1';
               page_state               <= S_INTERPCK_PAGE_REQ;
  
               
             elsif(pckstart_page_in_advance = '0') then
             
               pckstart_page_alloc_req  <= '1';
               page_state               <= S_PCKSTART_PAGE_REQ;
             
             else
             
               page_state               <=  S_IDLE;  
               
             end if;
           
           end if;

        
        when S_INTERPCK_SET_USECNT =>

           if(mmu_set_usecnt_done_i = '1') then
          
             interpck_usecnt_req        <= '0';   
             interpck_usecnt_in_advance <= usecnt_d0;
             
             if(interpck_page_in_advance = '0') then 
             
               interpck_page_alloc_req  <= '1';
               page_state               <= S_INTERPCK_PAGE_REQ;

             elsif(need_pckstart_usecnt_set = '1') then
             
               page_state               <= S_PCKSTART_SET_USECNT;
               pckstart_usecnt_req      <= '1';
           
             elsif(pckstart_page_in_advance = '0') then
           
               pckstart_page_alloc_req  <= '1';
               page_state               <= S_PCKSTART_PAGE_REQ;
               
             else
               
               page_state               <=  S_IDLE;
             
             end if;
           
           end if;          
          
          
        when S_PCKSTART_PAGE_REQ =>          
    
          if( mmu_page_alloc_done_i = '1') then

             pckstart_page_alloc_req  <= '0';
             -- remember the page start addr
             pckstart_pageaddr         <= mmu_pageaddr_i;
             pckstart_usecnt_in_advance<= usecnt_d0;
      
             if(need_interpck_usecnt_set = '1') then 
             
               page_state               <= S_INTERPCK_SET_USECNT;
               interpck_usecnt_req      <= '1';
           
             elsif(interpck_page_in_advance = '0') then 
             
               interpck_page_alloc_req  <= '1';
               page_state               <= S_INTERPCK_PAGE_REQ;

             
             elsif(need_pckstart_usecnt_set = '1') then
             
               page_state               <= S_PCKSTART_SET_USECNT;
               pckstart_usecnt_req      <= '1';
           
             else
               
               page_state               <= S_IDLE;
               
             end if;
           end if;

        when S_INTERPCK_PAGE_REQ =>          
    
          if( mmu_page_alloc_done_i = '1') then
    
             interpck_page_alloc_req   <= '0';
             interpck_pageaddr         <= mmu_pageaddr_i;
             --remember the usecnt which was at the time of
             -- page allocation, this is in case that the page
             -- is used to store another pck then the current one.
             -- therefore we compare this stored value with the
             -- current usecnt
             interpck_usecnt_in_advance <= usecnt_d0;
             interpck_page_alloc_req    <= '0';
      
             if(need_interpck_usecnt_set = '1') then 
             
               page_state               <= S_INTERPCK_SET_USECNT;
               interpck_usecnt_req      <= '1';
           
             elsif(need_pckstart_usecnt_set = '1') then
               
               page_state               <= S_PCKSTART_SET_USECNT;
               pckstart_usecnt_req      <= '1';
           
             elsif(pckstart_page_in_advance = '0') then
             
               pckstart_page_alloc_req  <= '1';
               page_state               <= S_PCKSTART_PAGE_REQ;
               
             else
               
               page_state                 <= S_IDLE;
               
             end if;
      
           end if;

         when others =>
           
             page_state                   <= S_IDLE;
           
       end case;
       
       usecnt_d0 <= read_usecnt;

     end if;
   end if;
   
 end process;
  
  -- used to remember that there was error, when 
  -- error received when hadline another error
  tx_rerror_or <= tx_rerror_reg or tx_rerror_p1_i;
 
 -- Auxiliary Finite State Machine which controls
 -- error handling
 fsm_perror : process(clk_i, rst_n_i)
 variable cnt : integer := 0;
 begin
   if rising_edge(clk_i) then
     if(rst_n_i = '0') then
       --========================================
       mmu_force_free_addr <= (others => '0');
       mmu_force_free      <= '0';
       cnt                 := 0;
       tx_rerror_reg       <= '0';
       --========================================
     else

       
       -- here is some magic which foresees a case in which
       -- an rerror occures when a previous rerror case is being
       -- handled, in such case, we remmeber another signal
       -- which will be handled next time
       -- simultaneously, the pck_fsm will wait with
       -- the transfer of another pck since we cannot stand
       -- more pck tropped
       
       if(tx_rerror_p1_i = '1' and rerror_state /=S_IDLE) then
       
         -- when previous error is being handled, remember
         -- the error signal
         tx_rerror_reg <= '1';
         
       elsif(tx_rerror_reg = '1' and rerror_state = S_IDLE) then
       
         -- remembered signal is now detected so we can
         -- stop remembering
         tx_rerror_reg <= '0';
         
       end if;
       
       
       case rerror_state is

        when S_IDLE =>
          
          mmu_force_free      <= '0';
          
          if(tx_rerror_or = '1' and read_state /= S_DROP_PCK and two_pck_in_fifo = '0' ) then 
          
            rerror_state          <= S_PERROR;
            mmu_force_free_addr   <= current_pckstart_pageaddr;
            mmu_force_free        <= '1';
            
          end if;

        -- why this state ?
        -- most probably, the pck that is tropped, will be immediately
        -- followed by another pck, we don't want to perform pck forced
        -- deallocation at the beginning of transmitting new pck, since
        -- these two operations interface the same block (MMU), thus
        -- both of them will work two times slower, so we wait
        -- until the pck transfer is in "less busy state" 
        -- (i.e. S_WAIT_FOR_PAGE_END) or there is no pcks being
        -- transfered for some arbitrar time (10 cycles)
        -- it may be not the best solutions
        

        when S_PERROR => 
          
          if(mmu_force_free_done_i = '1' ) then
            
            mmu_force_free      <= '0';
            rerror_state        <= S_IDLE;
            
          end if;

         when others =>
           
             rerror_state        <= S_IDLE;
             mmu_force_free      <= '0';
       end case;
       
       --

     end if;
   end if;
   
 end process;

  -- this proces controls Package Transfer Arbiter
  pta_if: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
      --===================================================
      transfering_pck           <= '0';
      pta_pageaddr              <=(others => '0');
      pta_mask                  <=(others => '0');
      pta_prio                  <=(others => '0');
      pta_pck_size              <=(others => '0');
      transfering_pck_on_wait   <= '0';
      --===================================================
      else

        
        if(start_transfer = '1' ) then 
           
          -- normal case, transfer arbiter free                      
          transfering_pck <= '1';
        
          pta_pageaddr    <= current_pckstart_pageaddr;
          pta_mask        <= write_mask;
          pta_prio        <= write_prio;
          pta_pck_size    <= pck_size;
--          pta_pck_size    <= std_logic_vector(unsigned(pck_size) + 1);        
                    
        elsif(pta_transfer_ack_i = '1' and transfering_pck = '1') then
        
          --transfer finished
          transfering_pck   <= '0';
          pta_pageaddr      <=(others => '0');
          pta_mask          <=(others => '0');
          pta_prio          <=(others => '0');
          pta_pck_size      <=(others => '0');
          

        end if;
      end if;
    end if;
  end process;

  -- for page allocation
  page_if: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
      --===================================================
      pckstart_page_in_advance  <= '0';
      interpck_page_in_advance  <= '0';
      need_pckstart_usecnt_set  <= '0';
      need_interpck_usecnt_set  <= '0'; 
      --===================================================
      else        
      
        if(mpm_pckstart = '1') then
        
          if(read_usecnt = pckstart_usecnt_in_advance) then
            need_pckstart_usecnt_set  <= '0';
            pckstart_page_in_advance  <= '0';            
          else
            need_pckstart_usecnt_set  <= '1';

          end if;
        
          if(read_usecnt = interpck_usecnt_in_advance) then 
            need_interpck_usecnt_set  <= '0';
          else
            need_interpck_usecnt_set  <= '1';
          end if;
          
        elsif(page_state = S_INTERPCK_SET_USECNT and mmu_set_usecnt_done_i = '1') then
          need_interpck_usecnt_set  <= '0';
        elsif(page_state = S_PCKSTART_SET_USECNT and mmu_set_usecnt_done_i = '1')then
          need_pckstart_usecnt_set  <= '0';
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

  tx_dreq_o              <= '0'    when (read_state = S_IDLE)     else
                            '1'    when (read_state = S_DROP_PCK) else   
                            tx_dreq and not fifo_full    ;
                            
  rtu_rsp_ack_o          <= rtu_rsp_ack;

  mmu_force_free_addr_o  <= mmu_force_free_addr;
  mmu_set_usecnt_o       <= pckstart_usecnt_req or interpck_usecnt_req;
  mmu_usecnt_o           <= read_usecnt;
  mmu_page_alloc_req_o   <= interpck_page_alloc_req or pckstart_page_alloc_req;
  mmu_force_free_o       <= mmu_force_free;                            
  mmu_pageaddr_o         <= interpck_pageaddr when (page_state = S_INTERPCK_SET_USECNT)  else
                            pckstart_pageaddr when (page_state = S_PCKSTART_SET_USECNT)  else (others => '0') ;
  
  mpm_pckstart_o         <= mpm_pckstart;                            
  mpm_pageaddr_o         <= mpm_pageaddr;
  mpm_pagereq_o          <= mpm_pagereq;
  mpm_data_o             <= mpm_data;
  mpm_ctrl_o             <= mpm_ctrl;
  mpm_drdy_o             <= mpm_drdy;
  mpm_flush_o            <= mpm_flush;        
                                                            
  pta_transfer_pck_o     <= transfering_pck;
  pta_pageaddr_o         <= pta_pageaddr;
  pta_mask_o             <= pta_mask;
  pta_prio_o             <= pta_prio;
  pta_pck_size_o         <= pta_pck_size;
  
  
end syn; -- arch