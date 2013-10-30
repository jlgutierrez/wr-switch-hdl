-------------------------------------------------------------------------------
-- Title      : Fast page allocator/deallocator
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_page_allocator.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-08
-- Last update: 2013-10-23
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
--   
-- Allocation request (alloc_i = 1) and setting use count (set_usecnt_i = 1) can
-- be done simultaneously whereas Free (free_i = 1) and Force Free (force_free_i = 1)
-- must be done separately then each other and the allocation/usecnat request.
-- In other words, the core can accept:
-- - allocate request or
-- - usecant request or
-- - allocate and usecnt request or
-- - free request or
-- - force free request
-- 
-- The core accepts one request per single cycle. The request input signal must
-- be a sigle-cycle strobe.
-- 
-- Any of the requests is alwyas handled 2 cycles. The output done_{}  at the second
-- cycle from the request, i.e.
-- clk      _|-|_|-|_|-|_|-|_
-- alloc_i  _ _|-|_ _ _ _ _ _
-- done_o   _ _ _ _|-|_ _ _ _
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
-- 2013-10-11  3.1      mlipinsk optimized to work in single cycle + pipelined
-- 2013-10-22  3.2      mlipinsk parallel usecnt/alloc
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
    g_usecount_width : integer := 4;

    --- management
    g_with_RESOURCE_MGR     : boolean := false;
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
    -- read when alloc_i is HIGH
    usecnt_alloc_i : in std_logic_vector(g_usecount_width-1 downto 0);
    
    -- "Use count" value for the page already allocated. If the page is to be
    -- used by multiple output queues, each of them will attempt to free it.
    -- read when set_usecnt_i is HIGH
    usecnt_set_i   : in std_logic_vector(g_usecount_width-1 downto 0);
    
    -- page address to be freed (uscnt descreased or deallocated when uscnt=1)
    pgaddr_free_i : in std_logic_vector(g_page_addr_width -1 downto 0);

    -- page address to set its usecnt
    pgaddr_usecnt_i : in std_logic_vector(g_page_addr_width -1 downto 0);
    
    -- the core is multiplexed between many ports, this is the information about
    -- the currently handled port. The input vector is just delayed by 2 cycls and 
    -- outputd as output vector
    req_vec_i : in  std_logic_vector(g_num_ports-1 downto 0);
    rsp_vec_o : out std_logic_vector(g_num_ports-1 downto 0);

    -- allocated page 
    pgaddr_o : out std_logic_vector(g_page_addr_width -1 downto 0);

    free_last_usecnt_o : out std_logic;
    
    done_o                   : out std_logic;
    done_alloc_o             : out std_logic;     
    done_usecnt_o            : out std_logic;     
    done_free_o              : out std_logic;     
    done_force_free_o        : out std_logic;     

    -- indicate that there is no more pages left. We use some kind of Hysteresis here, or
    -- in other words: the threshold for decideng on nomem going HIGH and LOW is different.
    -- nomem goes HIGH when memory will be empty after accepting the first request on
    --                 the first cycle it is HIGH. Also it goes up at initialization
    -- nomem goes LOW  when there is more then 3*num_port number of free pages,
    --                 this prevents trashing, I need to check but 3 might be also because
    --                 of the number of resources...
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

    dbg_o                         : out std_logic_vector(g_num_dbg_vector_width - 1 downto 0);

    ----------------------------------------------------------------------

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
  signal q_read_d1      : std_logic;

  signal initializing : std_logic;


  signal usecnt_addr_rd_p0                             : std_logic_vector(g_page_addr_width-1 downto 0);
  signal usecnt_rddata_p1                              : std_logic_vector(g_usecount_width-1 downto 0);
  signal rescnt_rddata_p1                              : std_logic_vector(g_resource_num_width-1 downto 0);
  signal ena_wr_p1_ram1, ena_wr_p1_ram2  : std_logic;
  signal rddata_p1_ram1, rddata_p1_ram2  : std_logic_vector(g_usecount_width+1+g_resource_num_width-1 downto 0);
  signal addr_wr_p1_ram1,addr_wr_p1_ram2 : std_logic_vector(g_page_addr_width-1 downto 0);

  signal usecnt_wrdata_p1_ram1, usecnt_wrdata_p1_ram2  : std_logic_vector(g_usecount_width+1-1 downto 0);
  signal rescnt_wrdata_p1_ram1, rescnt_wrdata_p1_ram2  : std_logic_vector(g_resource_num_width-1 downto 0);
  signal wrdata_p1_ram1,        wrdata_p1_ram2         : std_logic_vector(g_usecount_width+1+g_resource_num_width-1 downto 0);

  signal q_output_addr_p1 : std_logic_vector(g_page_addr_width-1 downto 0);
  signal q_input_addr_p1  : std_logic_vector(g_page_addr_width-1 downto 0);
  signal done_p1          : std_logic;
  signal ram_ones         : std_logic_vector(g_page_addr_width + g_usecount_width -1 downto 0);
  signal free_last_usecnt : std_logic; 

  --debuggin sygnals
  signal tmp_dbg_dealloc : std_logic;  -- used for symulation debugging, don't remove
  signal tmp_page        : std_logic_vector(g_page_addr_width -1 downto 0);
  signal free_blocks     : unsigned(g_page_addr_width downto 0);
  signal usecnt_not_zero : std_logic;
  signal real_nomem_d0   : std_logic;
  signal real_nomem_d1   : std_logic;

  -------------------------- resource management
  signal res_mgr_alloc           : std_logic;
  signal res_mgr_free            : std_logic;
  signal res_mgr_res_num         : std_logic_vector(g_resource_num_width-1 downto 0);
  signal res_mgr_rescnt_set      : std_logic;
  signal set_usecnt_allowed_p1   : std_logic;
  signal res_almost_full         : std_logic_vector(g_resource_num      -1 downto 0);
  -----------------------------
  

  type t_alloc_req is record
    alloc                 : std_logic;
    free                  : std_logic;
    f_free                : std_logic;  
    set_usecnt            : std_logic; 
    usecnt_set            : std_logic_vector(g_usecount_width-1 downto 0); -- input when setting usecnt
    usecnt_alloc          : std_logic_vector(g_usecount_width-1 downto 0); -- input when allocating usecnt
    pgaddr_free           : std_logic_vector(g_page_addr_width -1 downto 0); 
    pgaddr_usecnt         : std_logic_vector(g_page_addr_width -1 downto 0);
    grant_vec             : std_logic_vector(g_num_ports-1 downto 0);
    resource              : std_logic_vector(g_resource_num_width-1 downto 0);
    free_res_valid        : std_logic;
    rescnt_page_num       : std_logic_vector(g_page_addr_width   -1 downto 0);
  end record;
  
  constant c_pipeline_depth       : integer := 2; 
  
  type t_alloc_req_pipe is array(integer range <>) of t_alloc_req;
  signal alloc_req_in : t_alloc_req;
  signal alloc_req_d0 : t_alloc_req;
  signal alloc_req_d1 : t_alloc_req;
  
  constant alloc_req_zero  : t_alloc_req := (
    alloc           => '0',
    free            => '0',
    f_free          => '0',
    set_usecnt      => '0',
    usecnt_set      => (others => '0'),
    usecnt_alloc    => (others => '0'),
    pgaddr_free     => (others => '0'),
    pgaddr_usecnt   => (others => '0'),
    grant_vec       => (others => '0'),
    resource        => (others => '0'),
    free_res_valid  => '0',
    rescnt_page_num => (others => '0'));
   

begin  -- syn
  ram_ones                    <= (others => '1');
  alloc_req_in.alloc          <= alloc_i;
  alloc_req_in.free           <= free_i;
  alloc_req_in.f_free         <= force_free_i;
  alloc_req_in.set_usecnt     <= set_usecnt_i;
  alloc_req_in.usecnt_set     <= usecnt_set_i;
  alloc_req_in.usecnt_alloc   <= usecnt_alloc_i;
  alloc_req_in.pgaddr_free    <= pgaddr_free_i; 
  alloc_req_in.pgaddr_usecnt  <= pgaddr_usecnt_i;   
  alloc_req_in.grant_vec      <= req_vec_i;
  alloc_req_in.resource       <= resource_i;
  alloc_req_in.free_res_valid <= free_resource_valid_i;
  alloc_req_in.rescnt_page_num<= rescnt_page_num_i;

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
  q_write_p1 <= '1' when (alloc_req_d1.free   = '1' and unsigned(usecnt_rddata_p1) = 1) or
                         (alloc_req_d1.f_free = '1') else initializing;

  -- increaze pointer to next address -> it stores next freee page, we use the currently read
  -- and increase for next usage
  -- The core accepts requsts which occure at the fist cycle of nomem HIGH -> this is because
  -- we cannot stop once granted access based on the request in the previous cycle:
  -- CLK       : _|-|_|-|_|-|_|-|_|-|_|-|_|-|_|-|_|-|_|-|
  -- alloc_in  : _|----|_____    <= this request needs to be handled because granted access below
  -- grant     : ______|-|___    <= this grant needs to be handled
  -- nomem     : ______|-------
  -- nomem_d0  : _______|-------
  -- alloc_d0  " _______|-|____  <= this need to be handled
  -- nomem_d1  : ________|-------
  q_read_p0  <= '1' when (alloc_req_d0.alloc = '1') and (real_nomem_d1 = '0') else '0'; 
  
  -- address of page stored in the memory (queue)
  q_input_addr_p1 <= std_logic_vector(wr_ptr_p1) when initializing = '1' else alloc_req_d1.pgaddr_free;

  -- memeory in which list of addresses of available pages is stored
  -- rd_ptr points to the address of next available page_addr
  -- wr_ptr points to the address where a freed page can be written
  U_Queue_RAM : swc_rd_wr_ram
    generic map (
      g_data_width => g_page_addr_width,
      g_size       => 2**g_page_addr_width)
    port map (
      clk_i   => clk_i,
      rst_n_i => rst_n_i,
      we_i    => q_write_p1,
      wa_i    => std_logic_vector(wr_ptr_p1),
      wd_i    => q_input_addr_p1,
      ra_i    => std_logic_vector(rd_ptr_p0),
      rd_o    => q_output_addr_p1);
 
  addr_wr_p1_ram1 <= std_logic_vector(rd_ptr_p0) when initializing            = '1' else
                            q_output_addr_p1            when alloc_req_d1.alloc      = '1' else 
                            alloc_req_d1.pgaddr_free;


  addr_wr_p1_ram2 <= std_logic_vector(rd_ptr_p0) when initializing            = '1' else
                            alloc_req_d1.pgaddr_usecnt  when alloc_req_d1.set_usecnt = '1' else 
                            alloc_req_d1.pgaddr_free;


  ena_wr_p1_ram1  <= alloc_req_d1.alloc         or 
                            alloc_req_d1.free          or 
                            alloc_req_d1.f_free        or
                            initializing;

  ena_wr_p1_ram2  <= (alloc_req_d1.set_usecnt and set_usecnt_allowed_p1)   or 
                            alloc_req_d1.free                                     or  -- zero when free (later RAM1 will be used)
                            alloc_req_d1.f_free                                   or
                            initializing;

  ----------------------------------- form write RAM data ------------------------------------
  -----------------------------------   (a bit complex)   ------------------------------------
  usecnt_wrdata_p1_ram1  <= '1' & alloc_req_d1.usecnt_alloc              when alloc_req_d1.alloc      = '1' else
                            '0' & f_gen_dummy_vec('0', g_usecount_width) when alloc_req_d1.f_free     = '1' else
                            '0' & f_gen_dummy_vec('0', g_usecount_width) when initializing            = '1' else
                            '1' & std_logic_vector(unsigned(usecnt_rddata_p1) - 1);

  usecnt_wrdata_p1_ram2  <= '1' & alloc_req_d1.usecnt_set                when alloc_req_d1.set_usecnt = '1' else 
                            '0' & f_gen_dummy_vec('0', g_usecount_width);

  rescnt_wrdata_p1_ram1  <= alloc_req_d1.resource when (alloc_req_d1.alloc = '1' and alloc_req_d1.set_usecnt = '0') else
                            f_gen_dummy_vec('0', g_resource_num_width) ;
  rescnt_wrdata_p1_ram2  <= alloc_req_d1.resource when alloc_req_d1.set_usecnt = '1' else
                            f_gen_dummy_vec('0', g_resource_num_width) ;

  wrdata_p1_ram1         <= rescnt_wrdata_p1_ram1 & usecnt_wrdata_p1_ram1;
  wrdata_p1_ram2         <= rescnt_wrdata_p1_ram2 & usecnt_wrdata_p1_ram2;

  usecnt_addr_rd_p0      <= alloc_req_d0.pgaddr_free;
  
  usecnt_rddata_p1       <= rddata_p1_ram2(g_usecount_width-1 downto 0) when (rddata_p1_ram2(g_usecount_width) = '1') else
                            rddata_p1_ram1(g_usecount_width-1 downto 0);
                            
  rescnt_rddata_p1       <= rddata_p1_ram2(g_resource_num_width+g_usecount_width downto g_usecount_width+1) when (rddata_p1_ram2(g_usecount_width) = '1') else
                            rddata_p1_ram1(g_resource_num_width+g_usecount_width downto g_usecount_width+1);

  -- stores usecnts of pages, the addres is the page_addr (not ptr)
  U_UseCnt_RAM_1 : swc_rd_wr_ram
    generic map (
      g_data_width => g_usecount_width+1+g_resource_num_width,
      g_size       => 2**g_page_addr_width)
    port map (
      clk_i   => clk_i,
      rst_n_i => rst_n_i,
      we_i    => ena_wr_p1_ram1,
      wa_i    => addr_wr_p1_ram1,
      wd_i    => wrdata_p1_ram1,--usecnt_wrdata_p1_ram1,
      ra_i    => usecnt_addr_rd_p0,
      rd_o    => rddata_p1_ram1);

  -- stores usecnts of pages, the addres is the page_addr (not ptr)
  U_UseCnt_RAM_2 : swc_rd_wr_ram
    generic map (
      g_data_width => g_usecount_width+1+g_resource_num_width,
      g_size       => 2**g_page_addr_width)
    port map (
      clk_i   => clk_i,
      rst_n_i => rst_n_i,
      we_i    => ena_wr_p1_ram2,
      wa_i    => addr_wr_p1_ram2,
      wd_i    => wrdata_p1_ram2,--usecnt_wrdata_p1_ram2,
      ra_i    => usecnt_addr_rd_p0,
      rd_o    => rddata_p1_ram2);

  p_pointers : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        initializing     <= '1';
        rd_ptr_p0        <= (others => '0');
        wr_ptr_p1        <= (others => '0');
        real_nomem       <= '0';
        real_nomem_d0    <= '0';
        real_nomem_d1    <= '0';
        free_pages       <= to_unsigned(g_num_pages-1, free_pages'length);
        q_read_d1        <= '0';
      else
        q_read_d1        <= q_read_p0;
        real_nomem_d0    <= real_nomem;
        real_nomem_d1    <= real_nomem_d0;

        if(initializing = '1') then
          if(wr_ptr_p1 = g_num_pages-1) then
            initializing <= '0';
            wr_ptr_p1    <= to_unsigned(g_num_pages-1, wr_ptr_p1'length);
          else
            wr_ptr_p1    <= wr_ptr_p1 + 1;
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
            if(free_pages = 3) then
              real_nomem <= '0';
            end if;
            free_pages <= free_pages + 1;
          elsif (q_write_p1 = '0' and q_read_p0 = '1') then
            if(free_pages = 3) then
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
        if(((alloc_req_d0.alloc      = '1'  and real_nomem_d1     = '0') or 
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
--   out_nomem <= real_nomem;
  free_last_usecnt   <= (not initializing) when (alloc_req_d1.free = '1' and unsigned(usecnt_rddata_p1) = 1) else '0';
  pgaddr_o           <= q_output_addr_p1;
  done_o             <= done_p1; 
  done_alloc_o       <= done_p1 and alloc_req_d1.alloc;
  done_usecnt_o      <= done_p1 and alloc_req_d1.set_usecnt;
  done_free_o        <= done_p1 and alloc_req_d1.free;
  done_force_free_o  <= done_p1 and alloc_req_d1.f_free;
  rsp_vec_o          <= alloc_req_d1.grant_vec;
  nomem_o            <= out_nomem or initializing;
  free_last_usecnt_o <= free_last_usecnt;

  gen_no_RESOURCE_MGR: if (g_with_RESOURCE_MGR = false) generate
    resource_o                                                  <= (others => '0');
    set_usecnt_succeeded_o                                      <= '1';
    res_full_o                                                  <= (others => '0');
    res_almost_full_o                                           <= (others => '0');
    dbg_o (g_page_addr_width+1-1 downto 0)                      <= std_logic_vector(free_pages); 
    dbg_o (g_num_dbg_vector_width-1 downto g_page_addr_width+1) <= (others =>'0'); 
  end generate;

  gen_RESOURCE_MGR: if (g_with_RESOURCE_MGR = true) generate
    --------------------------------------------------------------------------------------------------
    --                               Resource Manager logic and instantiation
    --------------------------------------------------------------------------------------------------
    p_usecnt_set_allow : process(clk_i)
    begin
      if rising_edge(clk_i) then
        if rst_n_i = '0' then
          set_usecnt_allowed_p1 <= '0';
        else
          if(alloc_req_d0.set_usecnt ='1') then
            if(res_almost_full(to_integer(unsigned(alloc_req_d0.resource))) = '1') then
              -- not enough to accommodate max size frame, sorry we cannot serve the request
              set_usecnt_allowed_p1 <= '0';
            else
              set_usecnt_allowed_p1 <= '1';
            end if;
          else 
            set_usecnt_allowed_p1 <= '0';
          end if;
    
        end if;
      end if;
    end process;    

    res_mgr_alloc           <= alloc_req_d1.alloc and done_p1;
    res_mgr_free            <= ((alloc_req_d1.free and free_last_usecnt) or alloc_req_d1.f_free) and done_p1;
    res_mgr_res_num         <= rescnt_rddata_p1  when (alloc_req_d1.free_res_valid='0' and 
                                                      (alloc_req_d1.free='1' or alloc_req_d1.f_free='1')) else
                               alloc_req_d1.resource;
    res_mgr_rescnt_set      <= done_p1 and alloc_req_d1.set_usecnt and set_usecnt_allowed_p1;
   
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
      rescnt_page_num_i        => alloc_req_d1.rescnt_page_num,
      res_full_o               => res_full_o,
      res_almost_full_o        => res_almost_full,
      dbg_o                    => dbg_o
      );
    
    resource_o                 <= rescnt_rddata_p1;
    set_usecnt_succeeded_o     <= res_mgr_rescnt_set;
    res_almost_full_o          <= res_almost_full;
  end generate;
end syn;
