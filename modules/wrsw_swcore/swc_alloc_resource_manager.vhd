-------------------------------------------------------------------------------
-- Title      : Alloc Resource Manager
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_alloc_resource_manager.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2012-03-30
-- Last update: 2012-03-30
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
-- The available pool of pages can be divided into different resources, e.g:
-- * there will be a reserved number of pages for WR High Priority Traffic
-- * there will be a reserved number of pages for "standard" traffic
-- 
-- This module manages the count of the useage of different resources:
-- 
-- The pool of all pages is devided into [resource_num]:
-- 1) [resource_num = 0] 
--    unknown resource: unknown_res = (port_number*(max_frame_size/(2*page_size)+2*port_number), where:
--                      max_frame_size                is in bytes, i.e.: 1518 + oob
--                      2*page_size                   is in bytes, i.e.: page_size is in 16bits 
--                                                       (word written to FBM), so 2 bytes
--                      (max_frame_size/(2*page_size) is the number of pgaes used by max size frame
--                      2*port_number                 is to be able to allocate in advance first page
--                                                       (pckstart_pageaddr) and intermediate page 
--                                                       (pckinter_pageaddr) for each port 
--     
--    [requested number of separate resources, e.g]
-- 2) [resource_num = 1]
--    High priority traffic (e.g broadcast & 7th prio), e.g.: prio_res = page_num -(unknown_res/2)
-- 3) [resource_num = 2]
--    Standard traffic, e.g.: prio_res = page_num -(unknown_res/2)
-- 
-- If the resource is not known during allocation (which is very likely because we allocte 
-- pages in advance), the default resource number (unknown resource, [resource_num = 0]) 
-- shall be used.
-- 
-- The information about the resource needs to be stored with the first page of the frame, the 
-- inter_pages does not need to store this info
-- 
-- If page is allocated and the resource number is known, it shall be indicated and an appropriate
-- counter will be changes
-- 
-- If we make usecnt, it is used only for the first page of the frame. during usecnt also 
-- resource_cnt is done, which includes:
-- * resource num  - to which resource a provided page should be allocated
-- * resource_cnt  - how many pages from the unknown resource ([resource_num = 0]) shall be 
--                   allocated to the new resource
--                   
-- In the input block the usecnt is set only for the first page, so this is also the "must" for
-- resource number
-- 
-- The deallocating process (when deallocating the last usecnt), will receive the information that :
-- * the usecnt is 0 (last_usecnt)
-- * the resource number, 
-- so, when freeing the rest of the frame, it will indicate the resource number.
-- 
-- When freeing page, two sources of resource number can be used:
-- * the one stored in the memory (when res_num_valid_i = LOW) - this should be used for 
--   the first page of the frame
-- * the one provided by external soruce (when res_num_valid_i = HIGH) - this should be used for
--   the inter-pages of the frame
--   
--   
-- resource page count - tricky (!!!!)
-- * the count is not really for the page being allocated by for the request for allocation
-- * the pages are being requested in advance, so it would be hard to associate the
--   the allocated page with the cnt because we allocate and later we use it or not for
--   a given frame
-- * however, when we receive frame, we do alloc requests (i.e. we had in advance allocated 
--   first page, we use it, and as soon as we can, we allcote again page in advance....)
--   and we actually count how many alloc requets we did for a given frame, even if the pages
--   we allocate now will be used for the next frame... -> it works, it seems 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012, Maciej Lipinski / CERN
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
-- 2010-03-30  1.0      mlipinsk Created
-- 2013-10-30  1.1      mlipinsk adapted to optimized alloc (alloc & usecnt at 
--                               same time must be handled)
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.FLOOR;

use work.swc_swcore_pkg.all;
use work.genram_pkg.all;

entity swc_alloc_resource_manager is
  generic (
  
    -- 
    g_num_ports              : integer ;
    
    -- max pck size
    g_max_pck_size           : integer;
    
    -- page size
    g_page_size              : integer;
    
    -- number of pages in the allocator pool - total number of pages in all resource pools
    g_total_num_pages        : integer := 2048;

    g_total_num_pages_width  : integer := 11;

    -- here we define the number of pages in a special resource pool [resource = 1]
    g_special_res_num_pages  : integer :=248;
    
    -- number of separate resources, the number of areas the page pool is divided is always one more
    -- (g_resource_num + 1) since we need to have a number of "unknown source" pages
    g_resource_num           : integer := 3; -- this include 1 for unknown
    
    g_resource_num_width     : integer := 2;
    g_num_dbg_vector_width  : integer
    );

  port (
    clk_i                         : in std_logic;             -- clock & reset
    rst_n_i                       : in std_logic;

    -- indicates the resource to which the page shall be allocated or from which it shall be
    -- deallocated (freed). it is used:
    -- * when alloc_i      HIGH - to indicate to which resource add single page
    -- * when rescnt_set_i HIGH - to indicate to which resource set a number (rescnt_page_num_i) 
    --                            pages from unknown (num=0) resource (regardless whether 
    --                            alloc_i is HIGH or LOW
    -- * when free_i       HIGH - to indicate from which resource to substract a single page
    -- 
    -- When both, alloc_i and rescnt_set_i are HIGH, the resource_i is used by the latter 
    -- to re-allocate rescnt_page_num_i number of pages from the unknown resource (num=0) to 
    -- the resource_i resource. In such case, alloc_i allocates a single page to unknown
    -- resource (num = 0). It might have been done more universal but I found it a waste
    -- of resources, if such solution is sufficient.
    --  
    resource_i                    : in std_logic_vector(g_resource_num_width-1 downto 0);
    
    -- indicate that is allocated
    alloc_i                       : in std_logic;

    -- freeing (completely) page 
    free_i : in std_logic;    
    
    -- setting resource cnt to already allocated pages (strobe)
    rescnt_set_i                  : in std_logic;
    
    -- the of pages number to be added to the resource number indicated by resource_i (and 
    -- substracted from resource number=0 [unknown]). It is used only when rescnt_set_i is HIGH
    -- (whether alloc_i is HIGH or LOW)
    rescnt_page_num_i             : in std_logic_vector(g_total_num_pages_width-1 downto 0);
    
    res_full_o                    : out std_logic_vector(g_resource_num- 1 downto 0);
    res_almost_full_o             : out std_logic_vector(g_resource_num- 1 downto 0);
    dbg_o                         : out std_logic_vector(g_num_dbg_vector_width - 1 downto 0)
    );

end swc_alloc_resource_manager;

architecture syn of swc_alloc_resource_manager is

  -- the number of pages reserved for unknown source (happens because we allocate pages in advance
  -- we don't know RTU decision when we do that, and sometimes we store pages before receiving
  -- RTU decision). It should be enough for all the ports to receive single max_size frame and
  -- all ports to be ready to receive new pcks
  constant c_unknown_res_page_num  : integer := integer(CEIL(real(g_num_ports * (g_max_pck_size/g_page_size)))) +
                                                integer(g_num_ports * 2) ; --98

  constant c_special_res_page_num  : integer := g_special_res_num_pages; -- 256
  
  -- we can have as many resources as we want, the division of the page pool is following:
  -- 0) unknow resources   : number of pages = c_unknown_res_page_num
  -- 1) special resources  : number of pages = c_special_res_page_num
  -- 2) normal resources 1 : number of pages = (total - unknown - special)/(resource_num - 1)
  -- 3) normal resources 2 : number of pages = (total - unknown - special)/(resource_num - 1)
  --  [...]
  constant c_normal_res_page_num   : integer := integer(FLOOR(real((g_total_num_pages - 
                                                                    c_unknown_res_page_num - 
                                                                    c_special_res_page_num)/(g_resource_num-2)))); -- 670

  -- tells how many pages we need to have for a single max ethernet frame to be stored in FBM
  constant c_page_num_for_max_pck  : integer := integer(CEIL(real(g_max_pck_size/g_page_size))); -- 12

  type t_resource is record
    cnt         : unsigned(g_total_num_pages_width-1 downto 0);
    full        : std_logic;
    almost_full : std_logic;
  end record;
  
  type t_resource_array is array(integer range <>) of t_resource;

  signal resources : t_resource_array(g_resource_num-1 downto 0);
  signal cur_res   : integer range 0 to g_resource_num-1;

  -- debugging;
  signal res_page_sum    : unsigned(g_total_num_pages_width-1 downto 0);
  signal res_free_blocks : unsigned(g_total_num_pages_width-1 downto 0);

begin 

  cur_res <= to_integer(unsigned(resource_i));

  process(clk_i)
  variable sum : unsigned(g_total_num_pages_width-1 downto 0);
  begin
 
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        
        for i in g_resource_num-1 downto 0 loop
          resources(i).cnt         <= (others => '0');        
          resources(i).full        <= '0';
          resources(i).almost_full <= '0';
        end loop;

      else
        -----------------------------------------------------------------------------------------
        -- "resource count set" is used to move a number of pages from "unknown" resources
        -- to any other resource pool. Therefore, if the cur_res is different then "unknown" (0),
        -- we subtract from unknown pool
        -----------------------------------------------------------------------------------------
        
        if(alloc_i = '1' and rescnt_set_i = '1') then
          -- here we allocate the first page of frame, so it's always to unknown resource num=0
          -- and we also, at the same time, set usecnt (i.e. take pages from unknown to other 
          -- resource), so we need to:
          -- * add to the indicated resource (cur_res) the number of set pages 
          --   (rescnt_page_num_i) - rescnt_set request)
          -- * add to the unknown resources a single page - allocation request
          -- * substract from unknown resource the number of set pages (rescnt_page_num) and
          --   add single page for the allocation
          -- ... SIMPLE...;-p
          if(cur_res = 0) then
            resources(0).cnt       <= resources(0).cnt       + 1;
          else
            resources(0).cnt       <= resources(0).cnt       - unsigned(rescnt_page_num_i) + 1; 
            resources(cur_res).cnt <= resources(cur_res).cnt + unsigned(rescnt_page_num_i);
          end if;          
        elsif(alloc_i = '1') then
          -- we are allocating a page, it can be the first page (so unknow resource) but
          -- it can also be inter-frame page (known resource...)
          resources(cur_res).cnt <= resources(cur_res).cnt + 1;
        elsif(free_i = '1') then
          -- freeing page from some resource
          resources(cur_res).cnt <= resources(cur_res).cnt - 1;
        elsif(rescnt_set_i = '1') then
          -- setting page usecnt and moving a number of pages from unknown resource to 
          -- a known one 
          resources(cur_res).cnt <= resources(cur_res).cnt + unsigned(rescnt_page_num_i);
          if(cur_res /= 0) then
            resources(0).cnt <= resources(0).cnt - unsigned(rescnt_page_num_i);
          end if;
        end if; 
       
        --------------------- generat ---------------------------------
        -- control "unknown" resources
        if(resources(0).cnt > to_unsigned(c_unknown_res_page_num - 1,g_total_num_pages_width)) then
          resources(0).full          <='1';
        else
          resources(0).full          <= '0';
        end if;
        if(resources(0).cnt > to_unsigned(c_unknown_res_page_num - c_page_num_for_max_pck ,g_total_num_pages_width)) then
          resources(0).almost_full   <= '1';
        else 
          resources(0).almost_full   <= '0';
        end if;

        -- control special resources
        if(resources(1).cnt > to_unsigned(c_special_res_page_num - 1,g_total_num_pages_width)) then
          resources(1).full          <='1';
        else
          resources(1).full          <= '0';
        end if;
        if(resources(1).cnt > to_unsigned(c_special_res_page_num - c_page_num_for_max_pck, g_total_num_pages_width)) then
          resources(1).almost_full   <= '1';
        else 
          resources(1).almost_full   <= '0';
        end if;
        
         -- control "normal" resources
        for i in 2 to g_resource_num-1 loop
          if(resources(i).cnt > to_unsigned(c_normal_res_page_num - 1,g_total_num_pages_width)) then
            resources(i).full        <='1';
          else
            resources(i).full        <='0';
          end if;
          if(resources(i).cnt > to_unsigned(c_normal_res_page_num - c_page_num_for_max_pck, g_total_num_pages_width)) then
            resources(i).almost_full <= '1';
          else  
            resources(i).almost_full <= '0';
          end if;          
        end loop;
        
        ------------------------------ debug:  ----------------------------------------
        sum := to_unsigned(0, g_total_num_pages_width);
        for i in 0 to g_resource_num-1 loop
          sum := sum + resources(i).cnt;
        end loop;
        res_page_sum     <= sum;
        res_free_blocks  <= to_unsigned(1024, g_total_num_pages_width) - sum;
        -------------------------------------------------------------------------------
      end if;
    end if;  
  
  end process;

  FULL_OUT: for i in 0 to g_resource_num-1 generate
    res_full_o(i)          <= resources(i).full;
    res_almost_full_o(i)   <= resources(i).almost_full;
  end generate FULL_OUT;
 
  -- debugging stuff
  GEN_DEBUG: if ((g_total_num_pages_width*g_resource_num) <= g_num_dbg_vector_width) generate
    DBG: for i in 0 to g_resource_num-1 generate
      dbg_o((i+1)*g_total_num_pages_width-1 downto i*g_total_num_pages_width) <= std_logic_vector(resources(i).cnt);
    end generate DBG;
  end generate GEN_DEBUG;
  GEN_NO_DEBUG: if ((g_total_num_pages_width*g_resource_num) > g_num_dbg_vector_width) generate
      dbg_o <= (others =>'0');
      assert true report "g_num_dbg_vector_width to small for the defined number debug bits";
  end generate GEN_NO_DEBUG;

 
end syn;
