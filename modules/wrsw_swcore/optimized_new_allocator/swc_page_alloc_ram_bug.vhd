-------------------------------------------------------------------------------
-- Title      : Fast page allocator/deallocator
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_page_allocator.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-08
-- Last update: 2013-10-11
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: Module implements a fast (2 cycle) paged memory allocator.
-- The allocator can serve 4 types of requests:
-- - Allocate a page with given use count (alloc_i = 1). The use count tells
--   the allocator how many clients requested that page (and hence, how many free
--   requests are required to return the page to free pages poll)
-- - Free a page (free_i = 1) - check the use count stored for the page. If it's
--   bigger than 1, decrease the use count, if it's 1 mark the page as free.
-- - Force free a page (force_free_i = 1): immediately frees the page regardless
--   of its current use_count.
-- - Set use count (set_usecnt_i = 1): sets the use count value for the given page.
--   Used to define the reference count for pages pre-allocated in advance by
--   the input blocks.
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
-- 2012-03-15  2.2      twlostow fixed really ugly missing pages bug
-- 2012-10-11  3.0      mlipinsk optimized to work in single cycle + pipelined
-- 2012-10-15  3.0      mlipinsk changed to bug-free-ram
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.swc_swcore_pkg.all;
use work.genram_pkg.all;

entity swc_page_allocator_new is
  generic (
    -- number of pages in the allocator pool
    g_num_pages : integer := 2048;

    -- number of bits of the page address
    g_page_addr_width : integer := 11;

    g_num_ports : integer := 10;

    -- number of bits of the user (reference) count value
    g_usecount_width : integer := 4
    );

  port (
    clk_i   : in std_logic;             -- clock & reset
    rst_n_i : in std_logic;

    -- "Allocate" command strobe (active HI), starts allocation process of a page with use
    -- count given on usecnt_i. Address of the allocated page is returned on
    -- pgaddr_o and is valid when done_o is HI.
    alloc_i : in std_logic;

    -- "Free" command strobe (active HI), releases the page at address pgaddr_i if it's current
    -- use count is equal to 1, otherwise decreases the page's use count.
    free_i : in std_logic;

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
    
    req_vec_i : in  std_logic_vector(g_num_ports-1 downto 0);
    rsp_vec_o : out std_logic_vector(g_num_ports-1 downto 0);

    pgaddr_o : out std_logic_vector(g_page_addr_width -1 downto 0);

    free_last_usecnt_o : out std_logic;

    done_o : out std_logic;             -- "early" done output (active HI).
                                        -- Indicates that
                                        -- the alloc/release cycle is going to
                                        -- end 1 cycle in advance, so the
                                        -- multiport scheduler can optimize
                                        -- it's performance

    nomem_o : out std_logic;

    dbg_double_free_o       : out std_logic;
    dbg_double_force_free_o : out std_logic;
    dbg_q_write_o : out std_logic;
    dbg_q_read_o : out std_logic;
    dbg_initializing_o : out std_logic    
    );

end swc_page_allocator_new;

architecture syn of swc_page_allocator_new is

  -- convention used in the naming:
  -- *_in         - means that the signal is input 
  -- *_p0 or *_d0 - means that the signal is used in the first stage of the pipe
  -- *_p1 or *_d1 - means that the signal is used in the second stage of the pipe
  -- 
  -- *_p0 or *_p1 - is a signal which results from some logic (either registered or not) or
  --                output from RAM 
  -- *_p0 or *_p1 - is a registered signal - a copy with no chagnes                

  signal real_nomem, out_nomem : std_logic;

  signal rd_ptr_p0      : unsigned(g_page_addr_width-1 downto 0);
  signal wr_ptr_p1      : unsigned(g_page_addr_width-1 downto 0);
  signal free_pages     : unsigned(g_page_addr_width downto 0);

  signal q_write_p1     : std_logic;
  signal q_read_p0      : std_logic;

  signal initializing : std_logic;

  signal usecnt_ena_wr_p1                 : std_logic;
  signal usecnt_addr_rd_p0,usecnt_addr_wr_p1: std_logic_vector(g_page_addr_width-1 downto 0);
  signal usecnt_rddata_p1, usecnt_data_wr_p1 : std_logic_vector(g_usecount_width-1 downto 0);

  signal q_output_addr_p1 : std_logic_vector(g_page_addr_width-1 downto 0);
  signal done_p1      : std_logic;
  signal ram_ones      : std_logic_vector(g_page_addr_width + g_usecount_width -1 downto 0);


  --debuggin sygnals
  signal tmp_dbg_dealloc : std_logic;  -- used for symulation debugging, don't remove
  signal tmp_page        : std_logic_vector(g_page_addr_width -1 downto 0);
  signal free_blocks     : unsigned(g_page_addr_width downto 0);
  signal usecnt_not_zero : std_logic;
  signal real_nomem_d0   : std_logic;
  
  type t_alloc_req is record
    alloc              : std_logic;
    free               : std_logic;
    f_free             : std_logic;  
    set_usecnt         : std_logic; 
    usecnt             : std_logic_vector(g_usecount_width-1 downto 0);
    pgaddr             : std_logic_vector(g_page_addr_width -1 downto 0);
    grant_vec          : std_logic_vector(g_num_ports-1 downto 0);
  end record;
  
  constant c_pipeline_depth       : integer := 2; 
  
  type t_alloc_req_pipe is array(integer range <>) of t_alloc_req;
  signal alloc_req_in : t_alloc_req;
  signal alloc_req_d0 : t_alloc_req;
  signal alloc_req_d1 : t_alloc_req;
  
  constant alloc_req_zero  : t_alloc_req := (
    alloc      => '0',
    free       => '0',
    f_free     => '0',
    set_usecnt => '0',
    usecnt     => (others => '0'),
    pgaddr     => (others => '0'),
    grant_vec  => (others => '0'));
   

begin  -- syn
  ram_ones                <= (others => '1');
  alloc_req_in.alloc      <= alloc_i;
  alloc_req_in.free       <= free_i;
  alloc_req_in.f_free     <= force_free_i;
  alloc_req_in.set_usecnt <= set_usecnt_i;
  alloc_req_in.usecnt     <= usecnt_i;
  alloc_req_in.pgaddr     <= pgaddr_i; 
  alloc_req_in.grant_vec  <= req_vec_i;

  p_pipe: process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        alloc_req_d0 <= alloc_req_zero;
        alloc_req_d1 <= alloc_req_zero;
      else
        alloc_req_d0 <= alloc_req_in;
        alloc_req_d1 <= alloc_req_d0;
      end if;
    end if;  
  
  end process;
  
  -- write queue when freeing and not initializing (because when initializing we use other
  -- port of this memory)
  q_write_p1 <= (not initializing) when
                (alloc_req_d1.free   = '1' and unsigned(usecnt_rddata_p1) = 1) or
                (alloc_req_d1.f_free = '1') else '0';

  -- increaze pointer to next address -> it stores next freee page, we use the currently read
  -- and increase for next usage
  q_read_p0 <= '1' when (alloc_req_d0.alloc = '1') else '0';-- and (real_nomem_d0 = '0') else '0'; -- TODO: real_nomem

  U_Queue_RAM : generic_dpram
    generic map (
      g_data_width               => g_page_addr_width,
      g_size                     => 2**g_page_addr_width,
      g_with_byte_enable         => false,
      g_dual_clock               => false)
    port map (
      rst_n_i => rst_n_i,
      clka_i  => clk_i,
      bwea_i  => ram_ones((g_page_addr_width+7)/8 - 1 downto 0),
      wea_i   => q_write_p1,
      aa_i    => std_logic_vector(wr_ptr_p1), -- pointer increase on each q_write_p1=HIGH
      da_i    => alloc_req_d1.pgaddr,

      clkb_i => clk_i,
      bweb_i => ram_ones((g_page_addr_width+7)/8 - 1 downto 0),
      web_i  => initializing,
      ab_i   => std_logic_vector(rd_ptr_p0), -- pointer increase on each q_read_p0=HIGH
      db_i   => std_logic_vector(rd_ptr_p0), -- pointer increase on each q_read_p0=HIGH
      qb_o   => q_output_addr_p1);

  
  usecnt_addr_wr_p1 <= q_output_addr_p1 when alloc_req_d1.alloc = '1' else alloc_req_d1.pgaddr;

  usecnt_ena_wr_p1  <= (alloc_req_d1.alloc         or 
                        alloc_req_d1.set_usecnt    or 
                        alloc_req_d1.free          or 
                        alloc_req_d1.f_free)      and not initializing;

  usecnt_data_wr_p1 <= alloc_req_d1.usecnt                    when alloc_req_d1.set_usecnt = '1' else 
                       alloc_req_d1.usecnt                    when alloc_req_d1.alloc      = '1' else
                       f_gen_dummy_vec('0', g_usecount_width) when alloc_req_d1.f_free     = '1' else
                       std_logic_vector(unsigned(usecnt_rddata_p1) - 1);

  usecnt_addr_rd_p0<= std_logic_vector(rd_ptr_p0) when initializing = '1' else alloc_req_d0.pgaddr;

  U_UseCnt_RAM : generic_dpram
    generic map (
      g_data_width       => g_usecount_width,
      g_size             => 2**g_page_addr_width,
      g_with_byte_enable => false,
      g_dual_clock       => false)
    port map (
      rst_n_i => rst_n_i,
      clka_i  => clk_i,
      wea_i   => usecnt_ena_wr_p1,
      bwea_i  => ram_ones((g_usecount_width+7)/8 - 1 downto 0),
      aa_i    => usecnt_addr_wr_p1,
      da_i    => usecnt_data_wr_p1,

      clkb_i  => clk_i,
      bweb_i  => ram_ones((g_usecount_width+7)/8 - 1 downto 0),
      web_i   => initializing,
      ab_i    => usecnt_addr_rd_p0,--std_logic_vector(rd_ptr_p0),
      db_i    => f_gen_dummy_vec('0', g_usecount_width),
      qb_o    => usecnt_rddata_p1);

  p_pointers : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        initializing <= '1';
        rd_ptr_p0       <= (others => '0');
        real_nomem   <= '0';
      else

        real_nomem_d0 <= real_nomem;

        if(initializing = '1') then
          free_pages <= to_unsigned(g_num_pages-1, free_pages'length);
          wr_ptr_p1     <= to_unsigned(g_num_pages-1, wr_ptr_p1'length);
          rd_ptr_p0     <= rd_ptr_p0 + 1;
          if(rd_ptr_p0 = g_num_pages-2) then
            initializing <= '0';
            rd_ptr_p0       <= (others => '0');
          end if;
        else
          -- just increaing the pointerst to end/beginning of the queue
          if(q_write_p1 = '1') then
            wr_ptr_p1 <= wr_ptr_p1 + 1;
          end if;

          if(q_read_p0 = '1') then
            rd_ptr_p0 <= rd_ptr_p0 + 1;
          end if;
          
          -- counting the usage of pages
          if(q_write_p1 = '1' and q_read_p0 = '0') then
            real_nomem <= '0';
            free_pages <= free_pages + 1;
          elsif (q_write_p1 = '0' and q_read_p0 = '1') then
            if(free_pages = 1) then
              real_nomem <= '1';
            end if;
            free_pages <= free_pages - 1;
          end if;
        end if;
      end if;
    end if;
  end process;  

  p_gen_done : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if (rst_n_i = '0') or (initializing = '1') then
        done_p1 <= '0';
      else
        if(((alloc_req_d0.alloc      = '1'  and real_nomem        = '0') or 
             alloc_req_d0.set_usecnt = '1'  or  alloc_req_d0.free = '1'  or 
             alloc_req_d0.f_free     = '1') and initializing      = '0') then
          done_p1 <= '1';
        else
          done_p1 <= '0';
        end if;
      end if;
    end if;
  end process;

  p_gen_nomem_output : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        out_nomem <= '0';
      else
        if(out_nomem = '0' and (free_pages < to_unsigned(3, free_blocks'length))) then
          out_nomem <= '1';
        elsif(out_nomem = '1' and (free_pages > to_unsigned((3*g_num_ports), free_blocks'length))) then
          out_nomem <= real_nomem;
        end if;
      end if;
    end if;
  end process;

  pgaddr_o           <= q_output_addr_p1;
  done_o             <= done_p1;                 
  rsp_vec_o          <= alloc_req_d1.grant_vec;
  nomem_o            <= out_nomem;
  free_last_usecnt_o <= (not initializing) when (alloc_req_d1.free = '1' and unsigned(usecnt_rddata_p1) = 1) else '0';

end syn;
