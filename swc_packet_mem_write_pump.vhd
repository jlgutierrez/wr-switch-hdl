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
-- 2010-10-18  1.1      mlipinsk clearing register
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.log2;
use ieee.math_real.ceil;

library work;
use work.swc_swcore_pkg.all;

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
  
  -- for the first page of the packet, to indicate the output should be written
  -- signal start_output_page_addr : std_logic;
  
  signal pgreq_reg : std_logic;
  
  --=================================================================================
  
  -- address in LL SRAM which corresponds to the page address
  signal current_page_addr_int : std_logic_vector(c_swc_page_addr_width -1 downto 0);

  signal previous_page_addr_int : std_logic_vector(c_swc_page_addr_width -1 downto 0);

  -- internal
  signal ll_write_addr  : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  
  -- internal
  signal ll_write_data  : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  
  -- indicatest that the next address shall be writtent to
  -- Linked List SRAM
  signal ll_wr_req  : std_logic;
  

  signal ll_wr_done_reg : std_logic;
  
  signal no_next_page_addr: std_logic;
  
  signal writing_last_page : std_logic;
  
  type t_state is (IDLE, WR_NEXT, WR_EOP);
  signal state       : t_state;
    
begin  -- rtl

  -- VHDL sucks...
  allones <= (others => '1');
  zeros   <= (others => '0');

  -- page is full, it means that when the 'in_reg' becomes full, it will be written 
  -- to the last address (word) of the page (indicated by pgaddr_i) in FB SRAM.
  cntr_full <= '1' when cntr = to_unsigned(c_swc_packet_mem_multiply-1, cntr'length) else '0';
  
  -- indicates that there was an attempt (rather successful because we have entire in_reg to use)
  -- to write to 'in_reg' while the 'cntr' indicates that the content of the 'in_reg' being filled in
  -- will be written to the last word of the current page.
--  write_on_sync <= cntr_full and drdy_i;
  write_on_sync <= cntr_full and drdy_i;
  
  
  process(clk_i, rst_n_i)
  begin
    if rising_edge (clk_i) then
      if(rst_n_i = '0') then
        reg_full <= '0';
        cntr     <= (others => '0');
        we_int   <= '0';
        mem_addr <= (others => '0');
        flush_reg <= '0';
        pgend     <= '0';
        pckstart    <= '0';
        no_next_page_addr <='0';
        writing_last_page <= '0';
        -- reset the memory input register
        for i in 0 to c_swc_packet_mem_multiply-1 loop
          in_reg(i) <= (others => '0');
        end loop;  -- i 
        
      else

        -- flush received? mark the input register as full (when it's not
        -- completely empty) and store the flush command. It means that
        -- in the next 'time slot' for this pump, the 'in_reg' (although
        -- not fully filled in) will be written to FB SRAM.
        
--        if(flush_i = '1' and cntr /= to_unsigned(0, cntr'length)) then
        if(flush_i = '1' ) then
          flush_reg <= '1';
          writing_last_page <= '1';
          -- imitating the 'in_reg' full, for simpliciy 
          reg_full  <= '1';
        end if;

        -- TDM write
        -- if in the 'time slot' (indicated by sync_i HIGH) reserved for this pump, 
        -- the 'in_reg' is full, or there is other reason for that, write 'in_reg' 
        -- content to FB SRAM

        
        if(sync_i = '1' and (write_on_sync = '1'  or reg_full = '1' or flush_reg = '1' or no_next_page_addr = '1') and pgend ='0' ) then
          we_int    <= '1'; -- here: write enable
          cntr      <= (others => '0');
  
          -- ml: bugfix        
          --if(flush_i = '0') then
            flush_reg <= '0';
            reg_full <= '0';
            no_next_page_addr <= '0';
          --end if;
        

        elsif(sync_i = '1' and write_on_sync = '1' and pgend = '1') then
          -- if on syn at the end of the page, no new adress is provided,
          -- the page is not written, setting new write address is awaited
          we_int            <= '0';
          no_next_page_addr <= '1';
         
        else
          we_int           <='0';
          
        end if;

        -- page request stuff
        -- here we set the page address in FB SRAM. To this page 'in_reg' content will be written
        -- when the next 'time slot' is assigned to this pump
        if(pgreq_i = '1') then
        
          -- composing the FB SRAM address:
          --  * page address
          mem_addr(c_swc_packet_mem_addr_width-1 downto c_swc_page_offset_width) <= pgaddr_i;
          --  * internal page address
          mem_addr(c_swc_page_offset_width-1 downto 0)                           <= (others => '0');
          

          pgend                                                                  <= '0';
          
        -- after writting to FB SRAM, increase the (internal) address in the given page.
        elsif(we_int = '1') then
          mem_addr(c_swc_page_offset_width-1 downto 0) <= std_logic_vector(unsigned(mem_addr(c_swc_page_offset_width-1 downto 0)) + 1);
          
          -- ml: bugfix        
          if(flush_i = '1') then
            writing_last_page <= '1';
            flush_reg <= '1';
            reg_full  <= '1';
          end if;
          
          -- we are approaching the end of current page. Inform the host entity some
          -- cycles in advance.
          if(mem_addr(c_swc_page_offset_width-1 downto 0) = allones(c_swc_page_offset_width-1 downto 0) ) then
            pgend   <= '1';
          end if;

-- new solution to be investigated !!!
--          if(mem_addr(c_swc_page_offset_width-1 downto 0) = allones(c_swc_page_offset_width-1 downto 0) and writing_last_page = '0') then
--            pgend   <= '1';
--          elsif(mem_addr(c_swc_page_offset_width-1 downto 0) = allones(c_swc_page_offset_width-1 downto 0) and writing_last_page = '1')then
--            writing_last_page <= '0';
--          end if;
          
        end if;

        -- clocking in the data
        -- writting data (ctrl + data) into 'in_reg', once the reg is full,
        -- its content will be written to FB SRAM in the time slot reserved
        -- for this pump
        
        if(drdy_i = '1') then
        
          if( cntr = 0 and pckstart_i = '1') then
            pckstart <= '1';
          end if;
 
          
          -- Added by ML: without this, the old data stayed in register
          -- until it was overwriten, this could cause problems if 'flush' is used,
          -- in such case old dat would be written to memory in the not-overwriten-words
-------------------------------------------------------------------------------------    
-- here problem with synthesization
--          for i in to_integer(cntr) to c_swc_packet_mem_multiply-1 loop
--            in_reg(i) <= (others => '0');
--          end loop;  
-- replaced by this
          for i in 0 to c_swc_packet_mem_multiply-1 loop
            if(i >= to_integer(cntr)) then 
              in_reg(i) <= (others => '0');
            end if;
          end loop;
-------------------------------------------------------------------------------------        
          in_reg(to_integer(cntr)) <= d_i;


                
          -- wrap around the 'in_reg' indicating that the reg is full to the host
          -- entity
          if(cntr = to_unsigned(c_swc_packet_mem_multiply -1,cntr'length)) then
            cntr     <= (others => '0');
            reg_full <= not sync_i;
--          elsif(no_next_page_addr = '1') then 
--            cntr     <= (others => '0');
--            reg_full <= not sync_i;
         else
            cntr <= cntr + 1;
          end if;
        end if;
        
        
        
        if(ll_wr_done_i = '1') then 
          pckstart <= '0';
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





  fsm : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then

        state             <= IDLE;
        ll_write_data     <=(others =>'0');
        ll_write_addr     <=(others =>'0'); 
        ll_wr_req         <='0';
        
      else

        -- main finite state machine
        case state is


          when IDLE =>
            
            -- normal case: load new page within the package (not the
            -- beginning of the package)
            if((pgreq_i = '1') and (pckstart = '0') and (pckstart_i = '0')) then
              state          <= WR_NEXT;
              ll_write_data  <= pgaddr_i;
              ll_write_addr  <= previous_page_addr_int;
              ll_wr_req      <= '1';
            end if;
 
            -- first package, page provided at the same time as pckstart_i strobe
            -- so we remember the address from input
            if((pgreq_i = '1') and (pckstart = '0') and (pckstart_i = '1')) then
              state          <= WR_EOP;
              ll_write_data  <= (others =>'1');
              ll_write_addr  <= pgaddr_i;
              ll_wr_req      <= '1';
            end if;

            -- page provided not in the first cycle of the new package
            if((pgreq_i = '1') and (pckstart = '1') and (pckstart_i = '0')) then
              state          <= WR_EOP;
              ll_write_data  <= (others =>'1');
              ll_write_addr  <= pgaddr_i;
              ll_wr_req      <= '1';
            end if;

          when WR_NEXT =>
            if (ll_wr_done_i = '1') then
              state          <= WR_EOP;
              ll_write_data  <= (others =>'1');
              ll_write_addr  <= current_page_addr_int;
              ll_wr_req      <= '1';
            end if;

            
          when WR_EOP =>
            if (ll_wr_done_i = '1') then
              state          <= IDLE;
              ll_write_data  <= (others =>'0');
              ll_write_addr  <= (others =>'0');
              ll_wr_req      <= '0';
            end if;
  
          when others =>
          
            state             <= IDLE;
            
        end case;
        

      end if;
    end if;
    
  end process;


  we_o   <= we_int;
  full_o <= ((reg_full or cntr_full) and (not sync_i))   -- this one is for the case when writing is not synchronized
                                                         -- in such casem, when we write entire multiply words, we need
                                                         -- to wait for synch to write, so we say that mem is full
                            or                           
                                                         -- here we produce full signal (to enforce pause in writing) 
                                                         -- when new page address is not allocated/known at the end of the page                     
            ((no_next_page_addr or                       -- this signal is high starting with the synch during which 
                                                         -- the page was supposed to be written to FB SRAM but was not because
                                                         -- the address is not know
            (sync_i and write_on_sync and pgend) ) and   -- this is to start the full_o signal one cycle before no_next_page_addr
                                                         -- so that the drdy_i is pulled low and no data is written when no_next_page_addr
                                                         -- is high
            (no_next_page_addr xor sync_i)) ;            -- this is to enforce the full_o signal to go low one cycle before no_next_page_addr
                                                         -- is finished, so that the drdy_i is high soon enough to start writing again
                                                         -- as soon as data is written to FB SRAM
                                                         
                                                         --           clock    _|-|_|-|_|-|_|-|_|-|_|-|_|-|_|-|_|-|_|
                                                         --    write_on_synch ____|---|______________________________
                                                         --           synch_i ____|---|__________________|---|_______
                                                         -- no_next_page_addr ________|----------------------|_______
                                                         --            full_o ____|----------------------|___________
                                                         --            drdy_i --------|______________________|-------
                                                         --              data <=><=><=><=========================><=>
                                                         --             wr_en _______________________________|---|___
                                                                                                                  
            
  addr_o <= mem_addr;
  pgend_o <= pgend;
  
  gen_q1 : for i in 0 to c_swc_packet_mem_multiply-1 generate
    q_o(c_swc_pump_width * (i+1) - 1 downto c_swc_pump_width * i) <= in_reg(i);
  end generate gen_q1;
  
  ll_addr_o     <= ll_write_addr;
  ll_data_o        <= ll_write_data;
  ll_wr_req_o <= ll_wr_req;

end rtl;
