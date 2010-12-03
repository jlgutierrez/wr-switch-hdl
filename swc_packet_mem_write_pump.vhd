-------------------------------------------------------------------------------
-- Title      : Memory Write Pump
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_packet_mem_write_pump.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-08
-- Last update: 2010-10-12
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: Collectes data (words of ctrl+data seq) from one port and 
-- pumps (saves) sequence of such data to one word of SRAM memory with the 
-- page address allocated by mutiport memory allocator. The access to 
-- SSRAM is shared equally between many such pumps, each pump represents 
-- one port.
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- A pump works in the following way:
-- 1) it collects data from a port, data can be written continuously.
--    - data consits of a word of ctrl + data seq
--    - one word can be written at one clock cycle, in such case drdy_i is
--    - constantly HIGH
-- 2) if entire "vector" of data words is collected ('c_swc_packet_mem_multiply'
--    number of data words), such a vector is written to SSRAM to one word:
--    - the dats is written to SRAM memory address = page_addr + offset
--    - each "memory page" (indicated by page_addr) consists of a few
--      SRAM consecutive addresses 
-- 3) when the vector to be written to the last address of the page is being
--    filled in, the 'pend_o' indicates that the end of the page
-- 
-- Each pump has its 'time slot' (one cycle) to read/write from/to 
-- *FUCKING BIG SRAM (FB SRAM)*.  The access is granted to each pump in sequence: 
-- 1,2,3...(c_swc_packet_mem_multiply - 1). The access is multiplexed
-- between the pumps. 
--
-- If we want to write to the FB SRAM vector not fully filled in with data, 
-- we can use 'flush_i'. High stribe on flush input enforces the pump to 
-- behave as if it was full and the write to FB SRAM was needed in the 
-- next available 'time slot'.
-- 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2010 Tomasz Wlostowski / CERN
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
-- -------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2010-04-08  1.0      twlostow Created
-- 2010-10-12  1.1      mlipinsk comments added !!!!!
-- 2010-10-18  1.2      mlipinsk clearing register
-- 2010-11-24  1.3      mlipinsk adding main FSM !
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.log2;
use ieee.math_real.ceil;

use std.textio.all;

library work;
use work.swc_swcore_pkg.all;
use work.pck_fio.all;

entity swc_packet_mem_write_pump is

  
  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

-------------------------------------------------------------------------------
-- paging interface
-------------------------------------------------------------------------------    
    
    -- Next page address input (from page allocator)
    pgaddr_i : in  std_logic_vector(c_swc_page_addr_width-1 downto 0);
    
    -- Next page address input strobe (active HI) - loads internal
    -- memory address register with the address of new page
    pgreq_i  : in  std_logic;

    -- HI indicates that current page is done, and that the parent entity must
    -- select another page in following clock cycles (c_swc_packet_mem_multiply
    -- 2) if it wants to write more data into the memory
    pgend_o  : out std_logic;

    -- it indicates the start of a package, it need to be high when writing the
    -- first data of the new package
    pckstart_i: in std_logic;
-------------------------------------------------------------------------------
-- data channel interface
-------------------------------------------------------------------------------

    -- data input. data consists of 'c_swc_ctrl_width' of control data and 
    -- 'c_swc_data_width' of data
    -- sequence (of 'c_swc_packet_mem_multiply' number) of such data is saved 
    -- in one SRAM memory word at the pgaddr_i
    d_i    : in  std_logic_vector(c_swc_pump_width -1 downto 0);

    -- data input ready strobe (active HI). Clocks in the data. drdy_i cannot 
    -- be asserted when full_o is active.
    drdy_i  : in  std_logic;
    
    -- input register full (active HI). Indicates that the memory input
    -- register is full ('c_swc_packet_mem_multiply' words have been written)
    -- it will go back to 0 as soon as the memory input reg is synced to the
    -- shared memory. 
    full_o  : out std_logic;

    -- Memory input register flush (active HI). Forces a flush of memory input 
    -- register to the shared memory on the next sync pulse even if the number 
    -- of words clocked into the pump is less than c_swc_packet_mem_multiply.
    flush_i : in  std_logic;

-------------------------------------------------------------------------------
-- Linked List of page addresses (LL SRAM) interface 
-------------------------------------------------------------------------------

    -- address in LL SRAM which corresponds to the page address
    ll_addr_o : out std_logic_vector(c_swc_page_addr_width -1 downto 0);

    -- data output for LL SRAM - it is the address of the next page or 0xF...F
    -- if this is the last page of the package
    ll_data_o    : out std_logic_vector(c_swc_page_addr_width - 1 downto 0);

    -- request to write to Linked List, should be high until
    -- ll_wr_done_i indicates successfull write
    ll_wr_req_o   : out std_logic;

    ll_wr_done_i  : in std_logic;
-------------------------------------------------------------------------------
-- shared memory (FB SRAM) interface 
-- The access is multiplexed with other pumps. Each pump has a one-cycle-timeslot
-- to access the FB SRAM every 'c_swc_packet_mem_multiply' cycles.
-------------------------------------------------------------------------------

    -- synchronization pulse. HI indicates a time-slot assigned to this write pump.
    -- One cycle after reception of pulse on sync_i, the pump must provide valid
    -- values of addr_o, q_o and we_o, eventually commiting the contents of memory
    -- input register to the shared mem block.
    sync_i  : in  std_logic;

    -- address output for shared memory block
    addr_o : out std_logic_vector(c_swc_packet_mem_addr_width -1 downto 0);

    -- data output for shared memory block
    q_o    : out std_logic_vector(c_swc_pump_width * c_swc_packet_mem_multiply - 1 downto 0);

    -- write strobe output for shared memory block (FB SRAM), multiplexed with other pumps
    we_o   : out std_logic
    );


end swc_packet_mem_write_pump;

architecture rtl of swc_packet_mem_write_pump is



  -- word counter (word consists of ctrl + data), counts words in the 'in_reg' register
  signal cntr      : unsigned(3 downto 0);

  -- memory input register organized as an array of (c_swc_packet_mem_multiply) input
  -- wordsn (ctrl + data).
  signal in_reg    : t_pump_reg;
  
  -- indicates that in_reg is full, 'c_swc_packet_mem_multiply' words has been written)
  signal reg_full  : std_logic;

  -- memory register, consists of 'pg_addr' and in-page count (the number of inside
  -- page FB SRAM words is: (c_swc_page_size / c_swc_packet_mem_multiply)
  signal mem_addr  : std_logic_vector (c_swc_packet_mem_addr_width - 1 downto 0);
  
  -- FB SRAM write enable (internal). Translate into write request to FB SRAM. 
  -- the access is multiplexed, so the write request has to be issued in this
  -- pump's time slot.
  signal we_int    : std_logic;
  
  -- stores the flush request from 'hihger up'
  signal flush_reg : std_logic;

  -- combinatorial signal: attempt to write when counter is max
  signal write_on_sync : std_logic;

  -- indicates that the 'page' is full, so the internal 
  -- FB SRAM address counter is 1..1
  signal cntr_full : std_logic;
  
  -- we all love VHDL :)
  signal allones : std_logic_vector(63 downto 0);
  signal zeros : std_logic_vector(63 downto 0);  

  -- HI indicates that current page is done, and that the parent entity must
  -- select another page in following clock cycles (c_swc_packet_mem_multiply
  -- 2) if it wants to write more data into the memory
  signal pgend  : std_logic;
  
  -- start of package
  signal pckstart : std_logic;
  
  signal before_sync : std_logic;
  
  --=================================================================================
  
  -- address in LL SRAM which corresponds to the page address
  signal current_page_addr_int : std_logic_vector(c_swc_page_addr_width -1 downto 0);
  
  -- stored during FSM cycle (next->eop), this is needed for the last page of the pck
  -- in such case we need to remember it, otherwise we have problems
  signal current_page_addr_fsm : std_logic_vector(c_swc_page_addr_width -1 downto 0);
   
  signal previous_page_addr_int : std_logic_vector(c_swc_page_addr_width -1 downto 0);

  -- internal
  signal ll_write_addr  : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  
  -- internal
  signal ll_write_data  : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  
  -- indicatest that the next address shall be writtent to
  -- Linked List SRAM
  signal ll_wr_req  : std_logic;
  
  signal ll_idle : std_logic;

  signal ll_wr_done_reg : std_logic;
  
  signal no_next_page_addr: std_logic;
  
  signal writing_last_page : std_logic;
  
  type t_state is (IDLE, WR_NEXT, WR_EOP, WR_LAST_EOP, WR_TRANS_EOP);
  signal state       : t_state;

  type t_state_write is (S_IDLE, S_READ_DATA, S_READ_LAST_DATA_WORD, S_WRITE_DATA, S_FLUSH, S_WAIT_WRITE, S_WAIT_LL_READY,S_NASTY_WAIT);
  signal state_write       : t_state_write;
  
  
  signal cnt_last_word : std_logic;
  signal next_page_loaded : std_logic;
    
  signal pgreq_reg : std_logic;
  signal pckstart_reg : std_logic;  

  signal pgreq_or : std_logic;
  signal pckstart_or : std_logic;  
   
  signal sync_d    : std_logic_vector(c_swc_packet_mem_multiply - 1 downto 0);

  signal nasty_wait_full : std_logic;


    
begin  -- rtl

  -- VHDL sucks...
  allones <= (others => '1');
  zeros   <= (others => '0');
  
  write_on_sync <= '1' when (cntr = to_unsigned(0,cntr'length)) else '0';
  
  synch_delay : process(clk_i, rst_n_i)
  begin
     if rising_edge(clk_i) then
       if(rst_n_i = '0') then
 
          sync_d <= (others =>'0');
          
       else
         
         sync_d(0) <= sync_i;
         for i in 1 to c_swc_packet_mem_multiply-1 loop
           sync_d(i) <= sync_d(i - 1);
         end loop; 
         
       end if;
     end if;
     
  end process;
  
  before_sync <= sync_d(c_swc_packet_mem_multiply - 2);
  
  write_fsm : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then

        we_int <= '0';
        reg_full <= '0';
        cnt_last_word <='0';
      else

        -- main finite state machine
        case state_write is


          when S_IDLE =>
             
             if(drdy_i = '1') then
             
               state_write <= S_READ_DATA;                
             end if;



          when S_READ_DATA =>
               
             if(flush_i = '1') then
                
               state_write   <= S_FLUSH;
               reg_full      <= '1';
                
             elsif(cntr = to_unsigned(c_swc_packet_mem_multiply - 2,cntr'length) and drdy_i ='1') then

               state_write   <= S_READ_LAST_DATA_WORD;       
               cnt_last_word <= '1';
               
             end if;

          when S_READ_LAST_DATA_WORD =>           
             
             
           
             if( sync_i = '1') then
             
               if(pgend = '1' and drdy_i = '1') then -- see screenshot: swcore-writepump-p1
               
                 reg_full      <= '1';
                 state_write   <= S_WAIT_WRITE;
                 cnt_last_word <= '0';
               

               -- during the last address of the page, the Linked list is being written, so we need 
               -- to wait for it to finish
               elsif(mem_addr(c_swc_page_offset_width-1 downto 0) = allones(c_swc_page_offset_width-1 downto 0) and ll_idle = '0' ) then
                 
                 state_write   <= S_WAIT_LL_READY;
                 reg_full      <= '1';
                 
               elsif(drdy_i ='1') then
               
                 state_write   <= S_WRITE_DATA;
                 we_int        <= '1';
                 reg_full      <= '0';
                 cnt_last_word <= '0';
               
               else  
                 
                 state_write   <= S_NASTY_WAIT;        
                 we_int        <= '0';
                 reg_full      <= '0';
                 cnt_last_word <= '0';
                                 
               end if;
            
--            elsif(drdy_i = '1' and flush_i ='1') then
--              
--              state_write   <= S_WRITE_DATA;
--              we_int        <= '1';
--              reg_full      <= '0';
--              cnt_last_word <= '0';
--                 
            else -- synch_i = '0'
               
--               if(cntr = to_unsigned(c_swc_packet_mem_multiply -1,cntr'length) and drdy_i = '1') then 
--               
                 --==== needs test - start ===
                 if( drdy_i = '1') then
                 --==== needs test - end   ===
                   reg_full      <= '1';
                   state_write   <= S_WAIT_WRITE;
                   cnt_last_word <= '0';
                 --==== needs test - start ===
                 end if;
                 --==== needs test - end   ===                 
--                 
--               else
--                 
---                 reg_full      <= '0';
--                 state_write   <= S_NASTY_WAIT;
--               cnt_last_word <= '0';
                 
--               end if;
             end if;
             
          when S_NASTY_WAIT =>
             
            if(drdy_i = '1' and sync_i = '1' and cntr = to_unsigned(c_swc_packet_mem_multiply -1,cntr'length)) then
    
              state_write   <= S_WRITE_DATA;
              we_int        <= '1';
              reg_full      <= '0';
              cnt_last_word <= '0';
    
            elsif(drdy_i = '1' and sync_i = '0' ) then
            
              reg_full      <= '1';
              state_write   <= S_WAIT_WRITE;
              cnt_last_word <= '0';
            
            end if;   

          when S_WRITE_DATA =>
             
             we_int      <= '0';
             reg_full    <= '0';
             
             -- flushed precisely when writing data
             -- when there is new data available
             -- in such case, there will be one word
             -- to write in new page
             if(drdy_i = '1' and flush_i ='1') then
               
               state_write   <= S_FLUSH;
               reg_full      <= '1';
               
            -- NORMAL CASE: writing when new data available
             elsif(drdy_i = '1' and flush_i ='0') then
             
               state_write <= S_READ_DATA;
               
             elsif(drdy_i = '1' and ll_idle = '0') then
             
               state_write   <= S_WAIT_LL_READY;
               reg_full      <= '1';
               
             -- flush when there is no new data, it means that
             -- the data that is being written is the last
             elsif(drdy_i = '0' and flush_i ='1') then
               
               state_write <= S_IDLE;
               

               
             else

--               state_write <= S_IDLE;
               state_write <= S_READ_DATA;
               
             end if;
             
          when S_FLUSH =>
             
             if(sync_i = '1' and pgend = '0') then
               
               state_write <= S_WRITE_DATA;
               reg_full    <= '0';
               we_int      <= '1';
              
             end if;
            
          when S_WAIT_WRITE =>
  
             if(sync_i = '1' and pgend = '0') then
               
               if(mem_addr(c_swc_page_offset_width-1 downto 0) = allones(c_swc_page_offset_width-1 downto 0) and ll_idle = '0') then
                 
                 state_write   <= S_WAIT_LL_READY;
                 reg_full      <= '1';
                 
               elsif(drdy_i = '1' or write_on_sync = '1' or flush_reg = '1') then
--               else
               
                 state_write <= S_WRITE_DATA;
                 we_int      <= '1';
                 reg_full    <= '0';
                 
               end if;
               
             end if;  
  
          when S_WAIT_LL_READY => 
            
            if(drdy_i = '0' and ll_idle = '1') then
               state_write   <= S_WRITE_DATA;
               we_int        <= '1';
               reg_full      <= '0';
               cnt_last_word <= '0';
            end if;
            
          when others =>
            
            state_write <= S_IDLE;
            
        end case;
        

      end if;
    end if;
    
  end process;
  
  
  
  
  
  
  
  
--  cntr_full <= '1' when cntr = to_unsigned(c_swc_packet_mem_multiply-1, cntr'length) else '0';
  

  
  
  process(clk_i, rst_n_i)
  begin
    if rising_edge (clk_i) then
      if(rst_n_i = '0') then
       
        cntr     <= (others => '0');
        mem_addr <= (others => '0');
        pgend    <= '0';
        next_page_loaded <= '0';
        --pckstart <= '0';
        for i in 0 to c_swc_packet_mem_multiply-1 loop
          in_reg(i) <= (others => '0');
        end loop;  -- i 
        
        pckstart_reg <= '0';
        pgreq_reg    <= '0';
        

        flush_reg   <='0';
      else
      
        if(flush_i = '1') then 
          flush_reg <= '1';
        elsif(sync_i = '1' and flush_reg ='1') then
          flush_reg <= '0';
        end if;
        
        if(pgreq_i = '1') then
        
          pgend                <= '0';
          
        elsif(mem_addr(c_swc_page_offset_width-1 downto 0) = allones(c_swc_page_offset_width-1 downto 0) ) then          
          
          
          if(cntr = to_unsigned(c_swc_packet_mem_multiply -1,cntr'length) and sync_i = '1' and drdy_i = '1') then
        
            pgend              <= '1';
            
          elsif(write_on_sync = '1' and sync_i = '1') then
          
            pgend              <= '1';

          end if;
        
        end if;
         
        if(pgreq_i = '1') then
        
          mem_addr(c_swc_packet_mem_addr_width-1 downto c_swc_page_offset_width) <= pgaddr_i;
          mem_addr(c_swc_page_offset_width-1 downto 0)                           <= (others => '0');
--          pgend                                                                  <= '0';
          next_page_loaded                                                       <= '1';
          
        elsif(state_write = S_WRITE_DATA) then
          
          if(mem_addr(c_swc_page_offset_width-1 downto 0) = allones(c_swc_page_offset_width-1 downto 0) ) then
--            pgend            <= '1';
            next_page_loaded <= '0';
          else
            
            mem_addr(c_swc_page_offset_width-1 downto 0) <= std_logic_vector(unsigned(mem_addr(c_swc_page_offset_width-1 downto 0)) + 1);
                        
          end if;

          
        end if;
        
        
        if(drdy_i = '1') then
        
--          if( cntr = 0 and pckstart_i = '1') then
--            pckstart <= '1';
--          end if;
          
          -- if new address is set when the previous is 
          -- being written to Linked List, we need to remember
          -- this to be able to come to it later
          if(pgreq_i ='1' and state /= IDLE ) then
            pgreq_reg <='1';
          end if;
          
          if(pckstart_i = '1' and state /=IDLE ) then 
            pckstart_reg <= '1';
          end if;
          
          
          for i in 0 to c_swc_packet_mem_multiply-1 loop
            if(i >= to_integer(cntr)) then 
              in_reg(i) <= (others => '0');
            end if;
          end loop;

          in_reg(to_integer(cntr)) <= d_i;
                
          -- wrap around the 'in_reg' indicating that the reg is full to the host
          -- entity
--          if(state_write = S_IDLE) then
--            cntr <= (others =>'1');
--          elsif(cntr = to_unsigned(c_swc_packet_mem_multiply -1,cntr'length)) then
          if(cntr = to_unsigned(c_swc_packet_mem_multiply -1,cntr'length)) then
            cntr     <= (others => '0');
          elsif((state_write = S_READ_LAST_DATA_WORD) and sync_i = '1') then
            cntr      <= (others => '0');
--          elsif(reg_full = '1') then
--            cntr      <= (others => '0');
          else
            cntr <= cntr + 1;
          end if;
        else
          if((state_write = S_FLUSH or state_write = S_WAIT_LL_READY ) and sync_i = '1') then
            cntr      <= (others => '0');
          end if;
        end if;
        
        
        if(ll_wr_done_i = '1') then 
          pckstart_reg <= '0';
          pgreq_reg    <='0';
        end if;
        
      end if;
    end if;
  end process;



  pg : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then

         current_page_addr_int    <= (others => '0');
         previous_page_addr_int   <= (others => '0');
         
      else
        
        if(pgreq_i = '1') then
          current_page_addr_int   <= pgaddr_i;
        end if;
        
        if(ll_wr_done_i = '1') then
          previous_page_addr_int  <= current_page_addr_int;
        end if;
        
      end if;
    end if;
  end process;

 -- IMPORTANT, see below WR_EOP
 pgreq_or    <= pgreq_i    or pgreq_reg;
 pckstart_or <= pckstart_i or pckstart_reg;


  fsm : process(clk_i, rst_n_i)
  variable l:line;
  file fout:text open write_mode is "stdout" ;
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then

        state                 <= IDLE;
        ll_write_data         <=(others =>'0');
        ll_write_addr         <=(others =>'0'); 
        ll_wr_req             <='0';
        current_page_addr_fsm <=(others =>'0'); 
        
      else

        -- main finite state machine
        case state is


          when IDLE =>
            --fprint(fout, l, "Jou, ziom!\n");

            
            --if((pgreq_i = '1') and (pckstart = '0') and (pckstart_i = '0')) then
            
            if((pgreq_or = '1') and (pckstart_or = '0') ) then

              -- normal case: load new page within the package (not the
              -- beginning of the package)
              
              -- this will not happen during the staart of the frame
              -- within the frame, pgaddr_i will have the appripriate value
              state                  <= WR_NEXT;
              ll_write_data          <= pgaddr_i;
              ll_write_addr          <= previous_page_addr_int;
              
              -- we remember the current (new address)
              -- just in case, the pck finishes during NEXT OR EOP state
              -- and new page is set, or just new page is set
              current_page_addr_fsm  <= pgaddr_i;
              ll_wr_req              <= '1';
 
            elsif((pgreq_or = '1') and (pckstart_or = '1')) then

              -- first package, page provided at the same time as pckstart_i strobe
              -- so we remember the address from input
              --if((pgreq_i = '1') and (pckstart = '0') and (pckstart_i = '1')) then

              state          <= WR_EOP;
              ll_write_data  <= (others =>'1');
              ll_write_addr  <= pgaddr_i;
              ll_wr_req      <= '1';
            end if;

            -- page provided not in the first cycle of the new package
            --if((pgreq_i = '1') and (pckstart = '1') and (pckstart_i = '0')) then
            --  state          <= WR_EOP;
            --  ll_write_data  <= (others =>'1');
            --  ll_write_addr  <= pgaddr_i;
            --  ll_wr_req      <= '1';
            --end if;

          when WR_NEXT =>

            if (ll_wr_done_i = '1') then
              
              if((pgreq_or = '1') and (pckstart_or = '1') ) then

                -- this means that the pck finished during NEXT state
                -- 
                state          <= WR_LAST_EOP;
                ll_write_data  <= (others =>'1');
                --ll_write_addr  <= current_page_addr_int;
                ll_write_addr  <= current_page_addr_fsm;
                ll_wr_req      <= '1';
             
             elsif((pgreq_or = '1') and (pckstart_or = '0') ) then

                -- this means that new page was set during NEXT state
                -- 
                state          <= WR_TRANS_EOP;
                ll_write_data  <= (others =>'1');
                --ll_write_addr  <= current_page_addr_int;
                ll_write_addr  <= current_page_addr_fsm;
                ll_wr_req      <= '1';
              
              else
          
                state          <= WR_EOP;
                ll_write_data  <= (others =>'1');
                --ll_write_addr  <= current_page_addr_int;
                ll_write_addr  <= current_page_addr_fsm;
                ll_wr_req      <= '1';
          
              end if;
            end if;

            
          when WR_EOP =>
            
            if (ll_wr_done_i = '1') then
              
              
              
              if((pgreq_or = '1') and (pckstart_or = '0') ) then
              -- this foresees the situation when new page was set
              -- while the linked list was being written, so 
              -- we don't go to idle, but write LL again.
              -- in theory, should not get here, because the 
              -- writing FSM, waits for ll_FSM to be IDLE
                          
                state          <= WR_NEXT;
                ll_write_data  <= pgaddr_i;
                ll_write_addr  <= previous_page_addr_int;
                ll_wr_req      <= '1';

              elsif((pgreq_or = '1') and (pckstart_or = '1')) then
              -- this foresees quite often situation when the
              -- address of previous pck is written to LL while
              -- new pck's first page is already being set,
              -- so we remember the request and set the page as soon
              -- as previous' pck's operations to LL are finished
 
                state          <= WR_EOP;
                ll_write_data  <= (others =>'1');
                ll_write_addr  <= pgaddr_i;
                ll_wr_req      <= '1';

              else
              -- normal functioning
              
                state          <= IDLE;
                ll_write_data  <= (others =>'0');
                ll_write_addr  <= (others =>'0');
                ll_wr_req      <= '0';
                
              end if;
            end if;
            
          when WR_LAST_EOP => 
            
           if (ll_wr_done_i = '1') then

              state          <= WR_EOP;
              ll_write_data  <= (others =>'1');
              ll_write_addr  <= current_page_addr_int;
              ll_wr_req      <= '1';

            end if;

          when WR_TRANS_EOP =>
            
            if (ll_wr_done_i = '1') then
              state                  <= WR_NEXT;
              ll_write_data          <= current_page_addr_int;
              ll_write_addr          <= previous_page_addr_int;
            end if;
            
          when others =>
          
            state             <= IDLE;
            
        end case;
        

      end if;
    end if;
    
  end process;

  nasty_wait_full <= '1' when (state_write = S_NASTY_WAIT) else '0';
  
  ll_idle <= '1' when (state = IDLE) else '0';
  
  we_o   <= we_int;
  full_o <= reg_full;
--  
--            (((reg_full           -- obvous
--                or 
--            (cnt_last_word and drdy_i) 
--                or
--            (nasty_wait_full and drdy_i))                
--               and 
--            (not sync_i)) or(pgend and sync_i));-- or (sync_i and (not drdy_i)));-- and not before_sync;
            
         
  --addr_o <= pgaddr_i & zeros (c_swc_page_offset_width-1 downto 0) when (we_int = '1' and pgreq_i = '1') else mem_addr;
  addr_o <= mem_addr;
  pgend_o <= pgend;
  
  gen_q1 : for i in 0 to c_swc_packet_mem_multiply-1 generate
    q_o(c_swc_pump_width * (i+1) - 1 downto c_swc_pump_width * i) <= in_reg(i);
  end generate gen_q1;
  
  ll_addr_o   <= ll_write_addr;
  ll_data_o   <= ll_write_data;
  ll_wr_req_o <= ll_wr_req;

end rtl;
