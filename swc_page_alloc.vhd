-------------------------------------------------------------------------------
-- Title      : Fast page allocator/deallocator
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_page_allocator.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-08
-- Last update: 2010-04-08
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
-- Copyright (c) 2010 Tomasz Wlostowski
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2010-04-08  1.0      twlostow Created
-- 2010-10-11  1.1      mlipinsk comments added !!!!!
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.platform_specific.all;
use work.swc_swcore_pkg.all;


entity swc_page_allocator is
  generic (
    -- number of pages we consider
    g_num_pages      : integer := 2048;

    -- number of bits of the page address
    g_page_addr_bits : integer := 11;
    
    -- number of bits of the user count value
    g_use_count_bits : integer := 4
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

    free_i : in std_logic;              -- free strobe (active HI), releases the page
                                        -- at address pgaddr_i if it's current
                                        -- use count is equal to 1, otherwise
                                        -- decreases the use count

    
  
    force_free_i : in std_logic;          -- free strobe (active HI), releases the page
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

    usecnt_i : in std_logic_vector(g_use_count_bits-1 downto 0);

    pgaddr_i : in std_logic_vector(g_page_addr_bits -1 downto 0);

    pgaddr_o       : out std_logic_vector(g_page_addr_bits -1 downto 0);
    pgaddr_valid_o : out std_logic;

    idle_o  : out std_logic;
    done_o  : out std_logic;            -- "early" done output (active HI).
                                        -- Indicates that
                                        -- the alloc/release cycle is going to
                                        -- end 1 cycle in advance, so the
                                        -- multiport scheduler can optimize
                                        -- it's performance
    nomem_o : out std_logic
    );

end swc_page_allocator;

architecture syn of swc_page_allocator is



  function f_onehot_decode(x : std_logic_vector) return std_logic_vector is
    variable tmp : std_logic_vector(2**x'length-1 downto 0);
  begin
    tmp                          := (others => '0');
    tmp(to_integer(unsigned(x))) := '1';

    return tmp;
  end function;
  




  constant c_l1_bitmap_size     : integer := g_num_pages/32;
  constant c_l1_bitmap_addrbits : integer := g_page_addr_bits - 5;

  type t_state is (IDLE, ALLOC_LOOKUP_L1, ALLOC_LOOKUP_L0_UPDATE, 
                   FREE_CHECK_USECNT, FREE_RELEASE_PAGE, FREE_DECREASE_UCNT, 
                   SET_UCNT--, FORCE_FREE_RELEASE_PAGE
                   );

  -- this represents high part of the page address (bit mapping)
  signal l1_bitmap     : std_logic_vector(c_l1_bitmap_size-1 downto 0);
  signal l1_first_free : std_logic_vector (c_l1_bitmap_addrbits-1 downto 0);
  
  -- mask is used whe 
  signal l1_mask       : std_logic_vector (c_l1_bitmap_size -1 downto 0);

  -- this mask (which is in reallity hot-one) is used when allocating the page
  -- it cancels '1' at the address
  signal l0_mask       : std_logic_vector(31 downto 0);
  
  -- low part of the page address (decoded from the L0_LUT SRAM
  signal l0_first_free : std_logic_vector(4 downto 0);


  signal state       : t_state;
  signal free_blocks : unsigned(g_page_addr_bits downto 0);

  -- address decoded from l1_bitmap, we read data from this address 
  -- to decode the low part of  the page address
  signal l0_wr_data, l0_rd_data : std_logic_vector(31 downto 0);
  signal l0_wr_addr, l0_rd_addr : std_logic_vector(c_l1_bitmap_addrbits-1 downto 0);
  signal l0_wr                  : std_logic;

  -- this is used for storing user count
  signal usecnt_mem_wraddr : std_logic_vector(g_page_addr_bits-1 downto 0);
  signal usecnt_mem_rdaddr : std_logic_vector(g_page_addr_bits-1 downto 0);
  signal usecnt_mem_wr     : std_logic;

  signal usecnt_mem_rddata : std_logic_vector(g_use_count_bits-1 downto 0);
  signal usecnt_mem_wrdata : std_logic_vector(g_use_count_bits-1 downto 0);

  
begin  -- syn


  -- this guy is responsible for decoding 
  -- the bits of l1_bitmap register into the
  -- high part of the page address
  L1_ENCODE : swc_prio_encoder
    generic map (
      g_num_inputs  => c_l1_bitmap_size,
      g_output_bits => c_l1_bitmap_addrbits)
    port map (
      in_i   => l1_bitmap,
      out_o  => l1_first_free,
      onehot_o => l1_mask);

  -- this guy is responsible for the low part of 
  -- the page address. 
  L0_ENCODE : swc_prio_encoder
    generic map (
      g_num_inputs  => 32,
      g_output_bits => 5)
    port map (
      in_i   => l0_rd_data,
      onehot_o => l0_mask,
      out_o  => l0_first_free);


  L0_LUT : generic_ssram_dualport_singleclock
    generic map (
      g_width     => 32,
      g_addr_bits => c_l1_bitmap_addrbits,
      g_size      => c_l1_bitmap_size,
      g_init_file => "l0_init.mif")
    port map (
      clk_i     => clk_i,
      rd_addr_i => l0_rd_addr,
      wr_addr_i => l0_wr_addr,
      data_i    => l0_wr_data,
      q_o       => l0_rd_data,
      wr_en_i   => l0_wr);


  L0_UCNTMEM : generic_ssram_dualport_singleclock
    generic map (
      g_width     => g_use_count_bits,
      g_addr_bits => g_page_addr_bits,
      g_size      => g_num_pages)
    port map (
      data_i    => usecnt_mem_wrdata,
      clk_i     => clk_i,
      rd_addr_i => usecnt_mem_rdaddr,
      wr_addr_i => usecnt_mem_wraddr,
      wr_en_i   => usecnt_mem_wr,
      q_o       => usecnt_mem_rddata);




  fsm : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        l1_bitmap         <= (others => '1');
        idle_o            <= '1';
        state             <= IDLE;
        usecnt_mem_wr     <= '0';
        --usecnt_mem_rdaddr <= (others => '0');
        usecnt_mem_wraddr <= (others => '0');
        free_blocks       <= to_unsigned(g_num_pages, free_blocks'length);
        done_o            <= '0';
        l0_wr_addr        <= (others => '0');
        l0_rd_addr        <= (others => '0');
        l0_wr_data        <= (others => '0');
        
      else

        -- main finite state machine
        case state is

          -- idle state: wait for alloc/release requests
          when IDLE =>

            done_o         <= '0';
            idle_o         <= '1';
            l0_wr          <= '0';
            pgaddr_valid_o <= '0';
            usecnt_mem_wr  <= '0';
            
            
            --usecnt_mem_rdaddr <= pgaddr_i;
            usecnt_mem_wraddr <= pgaddr_i;

            -- check if we have any free blocks and drive the nomem_o line.
            if(free_blocks = 0) then
              nomem_o <= '1';
            else
              nomem_o <= '0';
            end if;

            -- got page allocation request
            if(alloc_i = '1') then
              -- initiate read from L0 bitmap at address of first free entry in
              -- L1. The address of L0_LUT maps into the position of the first 
              -- LSB '1' in the l1_bitmap register (high part of the page address)
              -- The word at the l1_first_free address represents the low part 
              -- of the page address (mapping of the first '1' LSB bit, again)
              l0_rd_addr <= l1_first_free;
              idle_o     <= '0';
              state      <= ALLOC_LOOKUP_L1;
              done_o <= '1';
            end if;

            -- got page release request
            if(free_i = '1') then
              idle_o            <= '0';
              state             <= FREE_CHECK_USECNT;
              -- decoding of provided code into low and high part
              l0_wr_addr        <= pgaddr_i(g_page_addr_bits-1 downto 5);
              l0_rd_addr        <= pgaddr_i(g_page_addr_bits-1 downto 5);
              --usecnt_mem_rdaddr <= pgaddr_i;
              usecnt_mem_wraddr <= pgaddr_i;
              done_o <= '1';            -- assert the done signal early enough
                                        -- so the multiport allocator will also
                                        -- take 3 cycles per request
            end if;
             
             if(force_free_i = '1') then
             
               idle_o            <= '0';
               state             <= FREE_RELEASE_PAGE;
               -- decoding of provided code into low and high part
               l0_wr_addr        <= pgaddr_i(g_page_addr_bits-1 downto 5);
               l0_rd_addr        <= pgaddr_i(g_page_addr_bits-1 downto 5);
               --usecnt_mem_rdaddr <= pgaddr_i;
               usecnt_mem_wraddr <= pgaddr_i;
               done_o <= '1';            -- assert the done signal early enough
                                         -- so the multiport allocator will also
                                         -- take 3 cycles per request
             end if;

             if(set_usecnt_i = '1') then
             
               idle_o            <= '0';
               state             <= SET_UCNT;
               usecnt_mem_wrdata <= usecnt_i;
               usecnt_mem_wraddr <= pgaddr_i;
               done_o <= '1';            -- assert the done signal early enough
                                         -- so the multiport allocator will also
                                         -- take 3 cycles per request
             end if;
             
             
             
             
          when ALLOC_LOOKUP_L1 =>
            
            -- wait until read from L0 bitmap memory is complete
            state  <= ALLOC_LOOKUP_L0_UPDATE;
            
            -- drive "done" output early, so the arbiter will now that it can initiate
            -- another operation in the next cycle.
            done_o <= '0';
            
            
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
            usecnt_mem_wr     <= '1';
            pgaddr_valid_o    <= '1';
            free_blocks       <= free_blocks-1;
            state             <= IDLE;
             --    done_o <= '0';

          when FREE_CHECK_USECNT =>
            -- use count = 1 - release the page

            done_o <= '0';

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
            l0_wr_data        <= l0_rd_data or f_onehot_decode(pgaddr_i(4 downto 0));
            l0_wr             <= '1';
            l1_bitmap         <= l1_bitmap or f_onehot_decode(pgaddr_i(g_page_addr_bits-1 downto 5));
            free_blocks       <= free_blocks+ 1;
            usecnt_mem_wrdata <= (others =>'0');
            usecnt_mem_wr     <= '1';
            state             <= IDLE;
            done_o            <= '0';
            
          when FREE_DECREASE_UCNT =>

            usecnt_mem_wrdata <= std_logic_vector(unsigned(usecnt_mem_rddata) - 1);
            usecnt_mem_wr     <= '1';
            state             <= IDLE;

            
          when SET_UCNT =>  
            
            usecnt_mem_wrdata <= usecnt_i;
            usecnt_mem_wr     <= '1';
            state             <= IDLE;
            done_o            <= '0';
  
          
          when others =>
            state             <= IDLE;
            done_o            <= '0';
            
        end case;
        

      end if;
    end if;
    
  end process;

  -- IMPORTANT :
  -- we need to set the usercnt read address as early as possible
  -- so that the data is available at the end of the first stata after IDLE
  usecnt_mem_rdaddr <= pgaddr_i;

end syn;
