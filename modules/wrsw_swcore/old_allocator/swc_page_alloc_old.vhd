-------------------------------------------------------------------------------
-- Title      : Fast page allocator/deallocator
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_page_allocator.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-08
-- Last update: 2013-03-15
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: Module implements a fast (3 cycle) paged memory allocator.
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- Detailed description of the magic (by mlipinsk):
-- The address of allocated page is made up of two parts: 
--  * high: bits [x downto 5]
--  * low : bits [4 downto 0]
-- 
-- The low part of the page address (the low bits) is mapped to 
-- a bit of 32 bit word in L0_LUT SRAM. 
-- The high part of the page address is the address of the word in 
-- the L0_LUT_SRAM memory. The address of the word in SRAM is
-- mapped into a bit of l1_bitmap register (high bits of the address).
--
-- Address mapped into bit means that the position of the bit (from LSB)
-- is equal to the address.
-- 
-- '1' means that a give address is free
-- '0' means that a give address is used
-- 
-- Tha page allocator looks for the lowest free (unused) page address. It uses
-- prio_encoder for this purpose. 
-- 
-- prio_encoder's input is a bit vector, the output is the position of the
-- least significant bit set to '1' (see description of prio_encoder).
-- Additionally, prio_encoder returns the position encoded as one_hot and
-- a mask.
-- 
-- In the L0_UCNTMEM SRAM, the number of users assigned to a particular
-- page address is stored. the address in L0_UCNTMEM SRAM corresponds
-- directly to the page address. The default value to fill in the
-- SRAM are all '1s'.
-- 
-- The default value to fill in the l1_bitmap register is all '1s'.
--
-- Page allocation:
-- When page allocation is requested, the number of users (usecnt) needs
-- to be provided. The allocation of the page is not complited until
-- the provided number of users have read the page (attempted to free
-- the page). During allocation, the lowest free page address is sought.
-- As soon as the address is determined, the requested user count is 
-- written to L0_UCNTMEM SRAM and allocation is finished.
-- 
-- Page Deallocation:
-- When free_page is attempted, the address of the page needs to be provided.
-- The address is decoded into high and low parts. First, the count in 
-- L0_UCNTMEM SRAM is checked, if it's greater than 1, it is decreased.
-- If the usecount == 1, it means that this was the last page user, and thus
-- the page is freed. this means that '1' is written to the bit corresponding
-- to the page low part of the address in the word in L0_LUT SRAM. And '1' is
-- written to the l1_bitmap register to the bit corresponding to the high part
-- of the address. 
-- 
-- 
-- 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2010 - 2013 CERN / BE-CO-HT
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
-- 2010-10-11  1.1      mlipinsk comments added !!!!!
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;

use work.swc_swcore_pkg.all;
use work.genram_pkg.all;

--use std.textio.all;
--use work.pck_fio.all;

entity swc_page_allocator is
  generic (
    -- number of pages we consider
    g_num_pages : integer := 1024;

    -- number of bits of the page address
    g_page_addr_width: integer := 10; --g_page_addr_bits 

    g_num_ports      : integer := 7;--:= c_swc_num_ports

    -- number of bits of the user count value
    g_usecount_width: integer := 4; --g_use_count_bits ;

    --- management
    g_page_size             : integer := 64;
    g_max_pck_size          : integer := 759; -- in 16 bit words (1518 [octets])/(2 [octets])
    g_special_res_num_pages : integer := 256;
    g_resource_num          : integer := 3;   -- this include: unknown, special and x* normal , so
                                              -- g_resource_num = 2+x
    g_resource_num_width    : integer := 2;
    g_num_dbg_vector_width  : integer 
    );

  port (
    clk_i   : in std_logic;             -- clock & reset
    rst_n_i : in std_logic;

    alloc_i : in std_logic;             -- alloc strobe (active HI), starts
                                        -- allocation process of a page with use
                                        -- count given on usecnt_i. Address of
                                        -- the allocated page is returned on
                                        -- pgaddr_o and is valid when
                                        -- pgaddr_valid_o is HI..

    free_i : in std_logic;  -- free strobe (active HI), releases the page
                            -- at address pgaddr_i if it's current
                            -- use count is equal to 1, otherwise
                            -- decreases the use count



    force_free_i : in std_logic;  -- free strobe (active HI), releases the page
                                  -- at address pgaddr_i regardless of the user 
                                  -- count of the page
                                  -- it is used in case a package is corrupted
                                  -- and what have already been
                                  -- saved, needs to be released


    set_usecnt_i : in std_logic;        -- enables to set user count to already
                                        -- alocated page, used in the case of the
                                        -- address of the first page of a package,
                                        -- we need to allocate this page in advance
                                        -- not knowing the user count, so the user count
                                        -- needs to be set to already allocated page

    -- "Use count" value for the page to be allocated. If the page is to be
    -- used by multiple output queues, each of them will attempt to free it.

    usecnt_i : in std_logic_vector(g_usecount_width-1 downto 0);

    pgaddr_i : in std_logic_vector(g_page_addr_width -1 downto 0);

    pgaddr_o       : out std_logic_vector(g_page_addr_width -1 downto 0);
    pgaddr_valid_o : out std_logic;
    free_last_usecnt_o : out std_logic;

    idle_o : out std_logic;
    done_o : out std_logic;             -- "early" done output (active HI).
                                        -- Indicates that
                                        -- the alloc/release cycle is going to
                                        -- end 1 cycle in advance, so the
                                        -- multiport scheduler can optimize
                                        -- it's performance


    nomem_o : out std_logic;

    --------------------------- resource management ----------------------------------
    -- resource number
    resource_i                    : in  std_logic_vector(g_resource_num_width-1 downto 0);
    
    -- outputed when freeing
    resource_o                    : out std_logic_vector(g_resource_num_width-1 downto 0);

    -- used only when freeing page, 
    -- if HIGH then the input resource_i value will be used
    -- if LOW  then the value read from memory will be used (stored along with usecnt)
    free_resource_valid_i         : in std_logic;
    
    -- number of pages added to the resurce
    rescnt_page_num_i             : in  std_logic_vector(g_page_addr_width   -1 downto 0);

    -- valid when (done_o and usecnt_i) = HIGH
    -- set_usecnt_succeeded_o = LOW ->> indicates that the usecnt was not set and the resources
    --                                were not moved from unknown to resource_o because there is
    --                                not enough resources
    -- set_usecnt_succeeded_o = HIGH->> indicates that usecnt_i requres was handled successfully    
    set_usecnt_succeeded_o        : out std_logic;
    

    res_full_o                    : out std_logic_vector(g_resource_num      -1 downto 0);
    res_almost_full_o             : out std_logic_vector(g_resource_num      -1 downto 0);

    dbg_o                         : out std_logic_vector(g_num_dbg_vector_width - 1 downto 0)
    );

end swc_page_allocator;

architecture syn of swc_page_allocator is

  signal nomem : std_logic;

  function f_onehot_decode(x : std_logic_vector) return std_logic_vector is
    variable tmp : std_logic_vector(2**x'length-1 downto 0);
  begin
    tmp                          := (others => '0');
    tmp(to_integer(unsigned(x))) := '1';

    return tmp;
  end function f_onehot_decode;

  constant c_l1_bitmap_size     : integer := g_num_pages/32;
  constant c_l1_bitmap_addrbits : integer := g_page_addr_width - 5;

  type t_state is (IDLE, ALLOC_LOOKUP_L1, ALLOC_LOOKUP_L0_UPDATE,
                   FREE_CHECK_USECNT, FREE_RELEASE_PAGE, FREE_DECREASE_UCNT,
                   SET_UCNT,NOT_SET_UCNT, NASTY_WAIT, DUMMY  --, FORCE_FREE_RELEASE_PAGE
                   );

  -- this represents high part of the page address (bit mapping)
  signal l1_bitmap     : std_logic_vector(c_l1_bitmap_size-1 downto 0);
  signal l1_first_free : std_logic_vector (c_l1_bitmap_addrbits-1 downto 0);

  -- mask is used whe 
  signal l1_mask : std_logic_vector (c_l1_bitmap_size -1 downto 0);

  -- this mask (which is in reallity hot-one) is used when allocating the page
  -- it cancels '1' at the address
  signal l0_mask : std_logic_vector(31 downto 0);

  -- low part of the page address (decoded from the L0_LUT SRAM
  signal l0_first_free : std_logic_vector(4 downto 0);


  signal state       : t_state;
  signal free_blocks : unsigned(g_page_addr_width downto 0);

  -- address decoded from l1_bitmap, we read data from this address 
  -- to decode the low part of  the page address
  signal l0_wr_data, l0_rd_data : std_logic_vector(31 downto 0);
  signal l0_wr_addr, l0_rd_addr : std_logic_vector(c_l1_bitmap_addrbits-1 downto 0);
  signal l0_wr                  : std_logic;

  -- this is used for storing user count
  signal usecnt_mem_wraddr : std_logic_vector(g_page_addr_width-1 downto 0);
  signal usecnt_mem_rdaddr : std_logic_vector(g_page_addr_width-1 downto 0);
  signal usecnt_mem_wr     : std_logic;

  signal usecnt_mem_rddata : std_logic_vector(g_usecount_width-1 downto 0);
  signal usecnt_mem_wrdata : std_logic_vector(g_usecount_width-1 downto 0);

  signal rescnt_mem_rddata : std_logic_vector(g_resource_num_width-1 downto 0);
  signal rescnt_mem_wrdata : std_logic_vector(g_resource_num_width-1 downto 0);

  signal mem_rddata : std_logic_vector(g_resource_num_width+g_usecount_width-1 downto 0);
  signal mem_wrdata : std_logic_vector(g_resource_num_width+g_usecount_width-1 downto 0);
  

  signal pgaddr_to_free : std_logic_vector(g_page_addr_width -1 downto 0);

  signal page_freeing_in_last_operation : std_logic;
  signal previously_freed_page          : std_logic_vector(g_page_addr_width -1 downto 0);

  signal tmp_page : std_logic_vector(g_page_addr_width -1 downto 0);

--  signal tmp_pgs   : std_logic_vector(1023 downto 0);

  signal tmp_dbg_dealloc : std_logic;  -- used for symulation debugging, don't remove

  signal was_reset  : std_logic;
  signal first_addr : std_logic;
  signal ones       : std_logic_vector(c_l1_bitmap_addrbits-1 downto 0);

  signal done       : std_logic;
  
  signal free_last_usecnt  : std_logic;

-------------------------- resource management

  signal res_mgr_alloc           : std_logic;
  signal res_mgr_free            : std_logic;
  signal res_mgr_res_num         : std_logic_vector(g_resource_num_width-1 downto 0);
  signal res_mgr_rescnt_set      : std_logic;
  signal set_usecnt_succeeded    : std_logic;
  signal res_almost_full         : std_logic_vector(g_resource_num      -1 downto 0);
-----------------------------

begin  -- syn

  ones <= (others => '1');

  tmp_dbg_dealloc <= '1' when (state = FREE_RELEASE_PAGE) else '0';

  -- this guy is responsible for decoding 
  -- the bits of l1_bitmap register into the
  -- high part of the page address
  L1_ENCODE : swc_prio_encoder
    generic map (
      g_num_inputs  => c_l1_bitmap_size,
      g_output_bits => c_l1_bitmap_addrbits)
    port map (
      in_i     => l1_bitmap,
      out_o    => l1_first_free,
      onehot_o => l1_mask);

  -- this guy is responsible for the low part of 
  -- the page address. 
  L0_ENCODE : swc_prio_encoder
    generic map (
      g_num_inputs  => 32,
      g_output_bits => 5)
    port map (
      in_i     => l0_rd_data,
      onehot_o => l0_mask,
      out_o    => l0_first_free);

  L0_LUT: swc_rd_wr_ram
    generic map (
      g_data_width => 32,
      g_size       => c_l1_bitmap_size,
      g_use_native => true)
    port map (
      clk_i => clk_i,
      rst_n_i => rst_n_i,
      we_i  => l0_wr,
      wa_i  => l0_wr_addr,
      wd_i  => l0_wr_data,
      ra_i  => l0_rd_addr,
      rd_o  => l0_rd_data);

  L0_UCNTMEM: swc_rd_wr_ram
    generic map (
      g_data_width => g_resource_num_width+g_usecount_width,
      g_size       => g_num_pages)
    port map (
      clk_i => clk_i,
      rst_n_i => rst_n_i,
      we_i  => usecnt_mem_wr,
      wa_i  => usecnt_mem_wraddr,
      wd_i  => mem_wrdata,
      ra_i  => usecnt_mem_rdaddr,
      rd_o  => mem_rddata);


  usecnt_mem_rddata <= mem_rddata(g_usecount_width-1 downto 0);
  rescnt_mem_rddata <= mem_rddata(g_resource_num_width+g_usecount_width-1 downto g_usecount_width);
  
  mem_wrdata        <= rescnt_mem_wrdata & usecnt_mem_wrdata ;

  fsm : process(clk_i, rst_n_i)
    
    variable cnt                 : integer := -1;
    variable usecnt_mem_rdaddr_v : integer := 0;
    
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        l1_bitmap                      <= (others => '1');
        idle_o                         <= '1';
        state                          <= IDLE;
        usecnt_mem_wr                  <= '0';
        --usecnt_mem_rdaddr <= (others => '0');
        usecnt_mem_wraddr              <= (others => '0');
        free_blocks                    <= to_unsigned(g_num_pages, free_blocks'length);
        done                           <= '0';
        l0_wr_addr                     <= (others => '0');
        l0_rd_addr                     <= (others => '0');
        l0_wr_data                     <= (others => '0');
        pgaddr_valid_o                 <= '0';
        nomem                          <= '0';
        usecnt_mem_wrdata              <= (others => '0');
        rescnt_mem_wrdata              <= (others => '0');
        pgaddr_o                       <= (others => '0');
        tmp_page                       <= (others => '0');  -- used for symulation debugging, don't remove
        --tmp_pgs           <= (others => '0');
        -- bugfix by ML (two consecutive page free of the same page addr)
        page_freeing_in_last_operation <= '0';
        previously_freed_page          <= (others => '0');
        pgaddr_to_free                 <= (others => '0');
        was_reset                      <= '1';
        first_addr                     <= '1';
        
        set_usecnt_succeeded           <= '0';
        
      elsif(was_reset = '1') then
        
        if(first_addr = '1') then
          l0_wr_data <= (others => '1');
          --l0_wr_data <= x"fffffffe"; -- tom
          l0_wr      <= '1';
          first_addr <= '0';
        elsif(l0_wr_addr = ones) then
          was_reset <= '0';
          l0_wr     <= '0';
        else
          l0_wr_data <= (others => '1'); -- tom
          l0_wr_addr <= std_logic_vector(unsigned(l0_wr_addr) + 1);
        end if;

      else
        -- main finite state machine
        case state is

          -- idle state: wait for alloc/release requests
          when IDLE =>

            done           <= '0';
            idle_o         <= '1';
            l0_wr          <= '0';
            pgaddr_valid_o <= '0';
            usecnt_mem_wr  <= '0';
            page_freeing_in_last_operation <= '0';
            --usecnt_mem_rdaddr <= pgaddr_i;
            usecnt_mem_wraddr              <= pgaddr_i;
            set_usecnt_succeeded           <= '0';
            -- check if we have any free blocks and drive the nomem_o line.
            -- last address (all '1') reserved for end-of-page marker in
            -- linked list

            -- ========= hystheresis ===========================
            if(nomem = '0' and ( free_blocks < to_unsigned(3,free_blocks'length ) ) ) then
              nomem <= '1';
            elsif(nomem = '1' and (free_blocks > to_unsigned((3*g_num_ports),free_blocks'length ) ) ) then
              nomem <= '0';
            end if;
            -- ========= =========== ===========================

            -- got page allocation request
            if(alloc_i = '1' and free_blocks > 0) then
              -- initiate read from L0 bitmap at address of first free entry in
              -- L1. The address of L0_LUT maps into the position of the first 
              -- LSB '1' in the l1_bitmap register (high part of the page address)
              -- The word at the l1_first_free address represents the low part 
              -- of the page address (mapping of the first '1' LSB bit, again)
              l0_rd_addr <= l1_first_free;
              idle_o     <= '0';
              state      <= ALLOC_LOOKUP_L1;
              done       <= '1';
            end if;

            -- got page release request
            if(free_i = '1') then
              
              idle_o <= '0';

              if(page_freeing_in_last_operation = '1' and previously_freed_page = pgaddr_i) then
                
                state <= NASTY_WAIT;
                
              else
                
                idle_o <= '0';

                pgaddr_to_free <= pgaddr_i;

                state             <= FREE_CHECK_USECNT;
                -- decoding of provided code into low and high part
                l0_wr_addr        <= pgaddr_i(g_page_addr_width-1 downto 5);
                l0_rd_addr        <= pgaddr_i(g_page_addr_width-1 downto 5);
                --usecnt_mem_rdaddr <= pgaddr_i;
                usecnt_mem_wraddr <= pgaddr_i;
                done              <= '1';  -- assert the done signal early enough
                                        -- so the multiport allocator will also
                                        -- take 3 cycles per request

                page_freeing_in_last_operation <= '1';

                previously_freed_page <= pgaddr_i;
                
              end if;
              
            end if;

            if(force_free_i = '1') then
              
              idle_o <= '0';

              pgaddr_to_free <= pgaddr_i;

              state             <= DUMMY;  -- FREE_RELEASE_PAGE;
              -- decoding of provided code into low and high part
              l0_wr_addr        <= pgaddr_i(g_page_addr_width-1 downto 5);
              l0_rd_addr        <= pgaddr_i(g_page_addr_width-1 downto 5);
              --usecnt_mem_rdaddr <= pgaddr_i;
              usecnt_mem_wraddr <= pgaddr_i;
              done              <= '1';  -- assert the done signal early enough
                                        -- so the multiport allocator will also
                                        -- take 3 cycles per request
            end if;

            if(set_usecnt_i = '1') then
              
              idle_o            <= '0';
               
              -- check if we have enough resources !!!!
              if(res_almost_full(to_integer(unsigned(resource_i))) = '1') then
                -- not enough to accommodate max size frame, sorry we cannot serve the request
                state                <= NOT_SET_UCNT;       
                set_usecnt_succeeded <= '0';
              else
                -- enough resources
                state                <= SET_UCNT;              
                usecnt_mem_wrdata    <= usecnt_i;
                rescnt_mem_wrdata    <= resource_i;
                usecnt_mem_wraddr    <= pgaddr_i;
                set_usecnt_succeeded <= '1';

              end if;
              done              <= '1';  -- assert the done signal early enough
                                         -- so the multiport allocator will also
                                         -- take 3 cycles per request
            end if;

          when DUMMY =>
            
            state  <= FREE_RELEASE_PAGE;
            done   <= '0';
            
          when NASTY_WAIT =>
            
            idle_o <= '0';

            pgaddr_to_free <= pgaddr_i;

            state             <= FREE_CHECK_USECNT;
            -- decoding of provided code into low and high part
            l0_wr_addr        <= pgaddr_i(g_page_addr_width-1 downto 5);
            l0_rd_addr        <= pgaddr_i(g_page_addr_width-1 downto 5);
            --usecnt_mem_rdaddr <= pgaddr_i;
            usecnt_mem_wraddr <= pgaddr_i;
            done              <= '1';   -- assert the done signal early enough
            -- so the multiport allocator will also
            -- take 3 cycles per request

            page_freeing_in_last_operation <= '1';

            previously_freed_page <= pgaddr_i;
            
          when ALLOC_LOOKUP_L1 =>

            -- wait until read from L0 bitmap memory is complete
            state <= ALLOC_LOOKUP_L0_UPDATE;

            -- drive "done" output early, so the arbiter will now that it can initiate
            -- another operation in the next cycle.
            done   <= '0';
            
            
          when ALLOC_LOOKUP_L0_UPDATE =>
            
            l0_wr_addr <= l0_rd_addr;

            -- change the '1' at the position of the chosen address to '0'..
            -- in other words, the LSB '1' is zerod
            l0_wr_data <= l0_rd_data xor l0_mask;
            l0_wr      <= '1';


            if(unsigned(l0_rd_data xor l0_mask) = 0) then  -- full L0 entry?
              -- if the word in L0_LUT at particular address is 0, all pages
              -- at this range have been used. So after allocating the current page address
              -- there will be no more space in thsi range. So set the corresponding bit to '0'
              
              l1_bitmap <= l1_bitmap xor l1_mask;
            end if;

            pgaddr_o          <= l1_first_free & l0_first_free;
            usecnt_mem_wraddr <= l1_first_free & l0_first_free;
            usecnt_mem_wrdata <= usecnt_i;
            rescnt_mem_wrdata <= resource_i;
            usecnt_mem_wr     <= '1';
            pgaddr_valid_o    <= '1';
            free_blocks       <= free_blocks-1;
            state             <= IDLE;

            --if(l1_first_free & l0_first_free = x"0E5")
            --    fprint(fout, l, "==> Allocate page %d  ,  usecnt %d, free blocks: %d \n", fo(l1_first_free & l0_first_free),fo(usecnt_i), fo(free_blocks-1));
            -- tmp_pgs(to_integer(unsigned(l1_first_free & l0_first_free))) <= '1';
            --    done   <= '0';

          when FREE_CHECK_USECNT =>
            -- use count = 1 - release the page

            done   <= '0';

            -- last user, free page
            if(usecnt_mem_rddata = std_logic_vector(to_unsigned(1, usecnt_mem_rddata'length))) then
              state <= FREE_RELEASE_PAGE;

            -- attempte to free empty page
            elsif(usecnt_mem_rddata = std_logic_vector(to_unsigned(0, usecnt_mem_rddata'length))) then
              state <= IDLE;

            -- there are still users, 
            else
              state <= FREE_DECREASE_UCNT;
            end if;

          when FREE_RELEASE_PAGE =>
--            l0_wr_data        <= l0_rd_data or f_onehot_decode(pgaddr_i(4 downto 0));
            l0_wr_data <= l0_rd_data or f_onehot_decode(pgaddr_to_free(4 downto 0));
            l0_wr      <= '1';

            l1_bitmap         <= l1_bitmap or f_onehot_decode(pgaddr_to_free(g_page_addr_width-1 downto 5));
--            l1_bitmap         <= l1_bitmap or f_onehot_decode(pgaddr_i(g_page_addr_width-1 downto 5));
            free_blocks       <= free_blocks+ 1;
            usecnt_mem_wrdata <= (others => '0');
            rescnt_mem_wrdata <= (others => '0');
            usecnt_mem_wr     <= '1';
            state             <= IDLE;
            done              <= '0';

          --       fprint(fout, l, "<== Release page: %d, free blocks: %d  \n",fo(tmp_page),fo(free_blocks+ 1));
          --tmp_pgs(to_integer(unsigned(tmp_page))) <= '0';
          when FREE_DECREASE_UCNT =>

            usecnt_mem_wrdata <= std_logic_vector(unsigned(usecnt_mem_rddata) - 1);
            rescnt_mem_wrdata <= rescnt_mem_rddata;
            usecnt_mem_wr     <= '1';
            state             <= IDLE;

            --   fprint(fout, l, "     Free page: %d (usecnt = %d)\n",fo(tmp_page),fo(std_logic_vector(unsigned(usecnt_mem_rddata) - 1)));

          when SET_UCNT =>
            
            usecnt_mem_wrdata    <= usecnt_i;
            rescnt_mem_wrdata    <= resource_i;
            usecnt_mem_wr        <= '1';
            state                <= IDLE;
            done                 <= '0';
            set_usecnt_succeeded <= '0';

            --    fprint(fout, l, "     Usecnt set: %d (usecnt = %d)\n",fo(tmp_page),fo(usecnt_i));

          when NOT_SET_UCNT =>

            state                <= IDLE;
            done                 <= '0';          
            set_usecnt_succeeded <= '0';
                        
          when others =>
            state  <= IDLE;
            done   <= '0';
            
        end case;
        --usecnt_mem_rdaddr <= pgaddr_i;
        tmp_page <= pgaddr_i;

      end if;
    end if;
    
  end process;

  -- IMPORTANT :
  -- we need to set the usercnt read address as early as possible
  -- so that the data is available at the end of the first stata after IDLE
  usecnt_mem_rdaddr <= pgaddr_i;

  free_last_usecnt<= '1' when (state             = FREE_CHECK_USECNT and 
                              usecnt_mem_rddata = std_logic_vector(to_unsigned(1, usecnt_mem_rddata'length ))) else
                     '0';

  nomem_o                 <= nomem;
  done_o                  <= done;
  free_last_usecnt_o      <= free_last_usecnt;
  resource_o              <= rescnt_mem_rddata;
  set_usecnt_succeeded_o  <= set_usecnt_succeeded;
  res_almost_full_o       <= res_almost_full;
  --------------------------------------------------------------------------------------------------
  --                               Resource Manager logic and instantiation
  --------------------------------------------------------------------------------------------------

  res_mgr_alloc           <= alloc_i and done;
  res_mgr_free            <= ((free_i and free_last_usecnt) or force_free_i) and done;
  res_mgr_res_num         <= rescnt_mem_rddata  when (free_resource_valid_i='0' and (free_i='1' or force_free_i='1')) else 
                             resource_i;
  res_mgr_rescnt_set      <= set_usecnt_i and done and set_usecnt_succeeded;
  
  ------ resource management 
  RESOURCE_MANAGEMENT: swc_alloc_resource_manager
  generic map(
    g_num_ports              => g_num_ports,
    g_max_pck_size           => g_max_pck_size,
    g_page_size              => g_page_size,
    g_total_num_pages        => g_num_pages,
    g_total_num_pages_width  => g_page_addr_width,
    g_special_res_num_pages  => g_special_res_num_pages,
    g_resource_num           => g_resource_num,
    g_resource_num_width     => g_resource_num_width,
    g_num_dbg_vector_width   => g_num_dbg_vector_width
    )
  port map (
    clk_i                    => clk_i,
    rst_n_i                  => rst_n_i,
    resource_i               => res_mgr_res_num,
    alloc_i                  => res_mgr_alloc,
    free_i                   => res_mgr_free,
    rescnt_set_i             => res_mgr_rescnt_set,
    rescnt_page_num_i        => rescnt_page_num_i,
    res_full_o               => res_full_o,
    res_almost_full_o        => res_almost_full,
    dbg_o                    => dbg_o
    );
  
end syn;
