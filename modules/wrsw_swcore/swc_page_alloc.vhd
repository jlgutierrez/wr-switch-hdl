-------------------------------------------------------------------------------
-- Title      : Fast page allocator/deallocator
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_page_allocator.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-08
-- Last update: 2012-03-05
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: Module implements a fast (3 cycle) paged memory allocator.
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- Detailed description of the magic (by mlipinsk): needed
-- 
-- THIS IS STILL BUGGY, IT LOOSES PAGES !!!
-- 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2010 Tomasz Wlostowski, Maciej Lipinski / CERN
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
-- 2012-01-24  2.0      twlostow completely changed (uses FIFO)
-- 2012-03-05  2.1      mlipinsk added debugging stuff + made interchangeable with old (still buggy)
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.swc_swcore_pkg.all;
use work.genram_pkg.all;

--use std.textio.all;
--use work.pck_fio.all;

entity swc_page_allocator_new is
  generic (
    -- number of pages we consider
    g_num_pages : integer := 2048;

    -- number of bits of the page address
    g_page_addr_width: integer := 11; --g_page_addr_bits 

    -- not needed here, but added for inter-changeability withh the old version
    g_num_ports      : integer ;--:= c_swc_num_ports

    -- number of bits of the user count value
    g_usecount_width: integer := 4 --g_usecount_width 
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

    idle_o : out std_logic;

    free_last_usecnt_o : out std_logic;

    done_o : out std_logic;             -- "early" done output (active HI).
                                        -- Indicates that
                                        -- the alloc/release cycle is going to
                                        -- end 1 cycle in advance, so the
                                        -- multiport scheduler can optimize
                                        -- it's performance

    nomem_o : out std_logic
    );

end swc_page_allocator_new;

architecture syn of swc_page_allocator_new is

  signal nomem : std_logic;

  signal rd_ptr, wr_ptr : unsigned(g_page_addr_width-1 downto 0);
  signal free_pages     : unsigned(g_page_addr_width downto 0);

  signal q_write , q_read : std_logic;
  signal pending_free     : std_logic;
  signal read_usecnt      : std_logic_vector(g_usecount_width-1 downto 0);
  signal q_init_data      : unsigned(g_page_addr_width -1 downto 0);

  signal initializing : std_logic;

  signal usecnt_write                 : std_logic;
  signal usecnt_addr                  : std_logic_vector(g_page_addr_width-1 downto 0);
  signal usecnt_rddata, usecnt_wrdata : std_logic_vector(g_usecount_width-1 downto 0);
  
  signal q_output_addr                : std_logic_vector(g_page_addr_width-1 downto 0);
  signal alloc_d0                     : std_logic;
  signal free_d0                      : std_logic;
  signal done_int                     : std_logic;
   signal ram_ones     : std_logic_vector(g_page_addr_width + g_usecount_width -1 downto 0);
   

  --debuggin sygnals
  signal tmp_dbg_dealloc : std_logic;  -- used for symulation debugging, don't remove
  signal tmp_page : std_logic_vector(g_page_addr_width -1 downto 0);
  signal free_blocks : unsigned(g_page_addr_width downto 0);

begin  -- syn
ram_ones  <=(others => '1');

  U_Queue_RAM : generic_dpram
    generic map (
      g_data_width       => g_page_addr_width,
      g_size             => 2**g_page_addr_width,
      g_with_byte_enable => false,
      g_dual_clock       => false)
    port map (
      rst_n_i => rst_n_i,
      clka_i  => clk_i,
      bwea_i => ram_ones((g_page_addr_width+7)/8 - 1 downto 0),
      wea_i   => q_write,
      aa_i    => std_logic_vector(wr_ptr),
      da_i    => pgaddr_i,

      clkb_i => clk_i,
      bweb_i => ram_ones((g_page_addr_width+7)/8 - 1 downto 0),
      web_i  => initializing,
      ab_i   => std_logic_vector(rd_ptr),
      db_i   => std_logic_vector(rd_ptr),
      qb_o   => q_output_addr);

  

  usecnt_addr  <= q_output_addr when alloc_d0 = '1' else pgaddr_i;
  usecnt_write <= (alloc_d0 or set_usecnt_i or free_d0 or force_free_i) and not initializing;

  usecnt_wrdata <= usecnt_i when (set_usecnt_i = '1' or alloc_d0 = '1') else
                   f_gen_dummy_vec('0', g_usecount_width) when force_free_i = '1' else
                   std_logic_vector(unsigned(usecnt_rddata) - 1);
  
  
  U_UseCnt_RAM : generic_dpram
    generic map (
      g_data_width       => g_usecount_width,
      g_size             => 2**g_page_addr_width,
      g_with_byte_enable => false,
      g_dual_clock       => false)
    port map (
      rst_n_i => rst_n_i,
      clka_i  => clk_i,
      wea_i   => usecnt_write,
       bwea_i => ram_ones((g_usecount_width+7)/8 - 1 downto 0),
      aa_i    => usecnt_addr,
      da_i    => usecnt_wrdata,
      qa_o    => usecnt_rddata,

      clkb_i => clk_i,
       bweb_i => ram_ones((g_usecount_width+7)/8 - 1 downto 0),
      web_i  => initializing,
      ab_i   => std_logic_vector(rd_ptr),
      db_i   => f_gen_dummy_vec('0', g_usecount_width));

  p_pointers : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        initializing <= '1';
        rd_ptr       <= (others => '0');
        nomem        <= '0';
      else
        if(initializing = '1') then
          free_pages <= to_unsigned(g_num_pages-1, free_pages'length);
          wr_ptr     <= to_unsigned(g_num_pages-1, wr_ptr'length);
          rd_ptr     <= rd_ptr + 1;
          if(rd_ptr = g_num_pages-2) then
            initializing <= '0';
            rd_ptr       <= (others => '0');
          end if;
        else
          if(q_write = '1') then
            wr_ptr <= wr_ptr + 1;
          end if;

          if(q_read = '1') then
            rd_ptr <= rd_ptr + 1;
          end if;

          if(q_write = '1' and q_read = '0') then
            nomem      <= '0';
            free_pages <= free_pages + 1;
          elsif (q_write = '0' and q_read = '1') then
            if(free_pages = 1) then
              nomem <= '1';
            end if;
            free_pages <= free_pages - 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  p_delay_alloc : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' or initializing = '1' then
        alloc_d0 <= '0';
        free_d0  <= '0';
      else
        alloc_d0 <= alloc_i and not alloc_d0;
        free_d0  <= free_i and not free_d0;
      end if;
    end if;
  end process;

  pgaddr_o       <= q_output_addr;
  pgaddr_valid_o <= alloc_d0;

  p_gen_done : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if (rst_n_i = '0') or (initializing = '1') then
        done_int <= '0';
      else
        if(done_int = '1')then
          done_int <= '0';
        elsif((alloc_i = '1' or set_usecnt_i = '1' or free_i = '1' or force_free_i = '1') and initializing = '0') then
          done_int <= '1';
        end if;
      end if;
    end if;
  end process;

  done_o  <= done_int;-- and not(free_d0 or alloc_d0);
  q_write <= (not initializing) when (free_d0 = '1' and unsigned(usecnt_rddata) = 1) or (force_free_i = '1') else '0';
  q_read  <= '1'                when (alloc_d0 = '1') and (nomem = '0')                                      else '0';

  nomem_o <= nomem;

  idle_o <= not (initializing or free_d0 or alloc_d0);
  
  free_last_usecnt_o <= (not initializing) when (free_d0 = '1' and unsigned(usecnt_rddata) = 1) else '0';
  
  -- generating debugging signals
  

  p_dbg : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        tmp_page                       <= (others => '0');
      else
        tmp_page        <= pgaddr_i;      
        tmp_dbg_dealloc <= done_int and (free_i or force_free_i); -- not sure whether force as well
      end if;
    end if;
  end process;
  free_blocks <= free_pages;


end syn;
