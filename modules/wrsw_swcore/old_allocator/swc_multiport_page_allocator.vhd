-------------------------------------------------------------------------------
-- Title      : multiport page allocator
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_multiport_page_allocator.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-08
-- Last update: 2012-03-19
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
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
-- 2010-10-11  1.1      twlostow changed allocator
-- 2012-02-02  2.0      mlipinsk generic-azed
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

library work;
use work.swc_swcore_pkg.all;

entity swc_multiport_page_allocator is
  generic ( 
    g_page_addr_width                  : integer ;--:= c_swc_page_addr_width;
    g_num_ports                        : integer ;--:= c_swc_num_ports
    g_page_num                         : integer ;--:= c_swc_packet_mem_num_pages
    g_usecount_width                   : integer --:= c_swc_usecount_width
  );
  port (
    rst_n_i           : in std_logic;
    clk_i             : in std_logic;

    alloc_i           : in  std_logic_vector(g_num_ports - 1 downto 0);
    free_i            : in  std_logic_vector(g_num_ports - 1 downto 0);
    force_free_i      : in  std_logic_vector(g_num_ports - 1 downto 0);
    set_usecnt_i      : in  std_logic_vector(g_num_ports - 1 downto 0);
    
    alloc_done_o      : out std_logic_vector(g_num_ports - 1 downto 0);
    free_done_o       : out std_logic_vector(g_num_ports - 1 downto 0);
    force_free_done_o : out std_logic_vector(g_num_ports - 1 downto 0);
    set_usecnt_done_o : out std_logic_vector(g_num_ports - 1 downto 0);


    pgaddr_free_i       : in  std_logic_vector(g_num_ports * g_page_addr_width - 1 downto 0);
    pgaddr_force_free_i : in  std_logic_vector(g_num_ports * g_page_addr_width - 1 downto 0);
    pgaddr_usecnt_i     : in  std_logic_vector(g_num_ports * g_page_addr_width - 1 downto 0);
    
    usecnt_i          : in  std_logic_vector(g_num_ports * g_usecount_width - 1 downto 0);
    pgaddr_alloc_o    : out std_logic_vector(g_page_addr_width-1 downto 0);

    free_last_usecnt_o    : out std_logic_vector(g_num_ports - 1 downto 0);

    nomem_o           : out std_logic
    );

end swc_multiport_page_allocator;

architecture syn of swc_multiport_page_allocator is

  constant c_arbiter_vec_width        : integer := 4*g_num_ports;
  constant c_arbiter_vec_width_log2   : integer := integer(CEIL(LOG2(real(4*g_num_ports-1))));

  signal pg_alloc      : std_logic;
  signal pg_free       : std_logic;
  signal pg_force_free : std_logic;
  signal pg_set_usecnt : std_logic;
  signal pg_usecnt     : std_logic_vector(g_usecount_width-1 downto 0);
  signal pg_addr_alloc : std_logic_vector(g_page_addr_width -1 downto 0);
  
  signal pg_addr_free        : std_logic_vector(g_page_addr_width -1 downto 0);
  signal pg_addr_force_free  : std_logic_vector(g_page_addr_width -1 downto 0);
  signal pg_addr_usecnt      : std_logic_vector(g_page_addr_width -1 downto 0);
  signal pg_addr  : std_logic_vector(g_page_addr_width -1 downto 0);
  
  signal pg_addr_valid : std_logic; -- used by symulation , don't remove
--  signal pg_idle       : std_logic;
  signal pg_done       : std_logic;
  signal pg_nomem      : std_logic;

  -- vector of requests to the Round Robin arbiter
  -- both alloc and free request
  -- the address of the bit :
  -- * representing alloc request - is even [i*2]
  -- * representing free  request - is odd  [i*2 + 1]
  signal request_vec   : std_logic_vector(c_arbiter_vec_width-1 downto 0);
  
  -- address of the request which has been granted access 
  -- to page alloation core. the LSB bit indicates the kind of
  -- operation:
  -- * '0' - even address, so alloc operation
  -- * '1' - odd  address, so free  operation
  signal request_grant : std_logic_vector(c_arbiter_vec_width_log2-1 downto 0);

  -- used to indicate to the RR arbiter to start
  -- processing next request,
  signal request_next        : std_logic;
  
  -- indicates that the granted request is valid
  signal request_grant_valid : std_logic;

  -- the number of the port to which request has been granted
  signal in_sel              : integer range 0 to g_num_ports-1;
  
  -- >????
  signal in_sel_prev         : integer range 0 to g_num_ports-1;
  
  -- ??
  signal af_prev             : std_logic;


  -- OR of two different free_i signals, they are functionally exclusive
  -- which means that it's not possible for them to be high simultaneously
  signal any_free_i          : std_logic;
  -- indicates that an alloc has been performed successfully for the 
  -- given port. Used to prevent considering the currently process
  -- port for request to RR arbiter
  signal alloc_done_feedback : std_logic_vector(g_num_ports-1 downto 0);
  signal alloc_done          : std_logic_vector(g_num_ports-1 downto 0);

  -- indicates that an free has been performed successfully for the 
  -- given port. Used to prevent considering the currently process
  -- port for request to RR arbiter
  signal free_done_feedback  : std_logic_vector(g_num_ports-1 downto 0);
  signal free_done           : std_logic_vector(g_num_ports-1 downto 0);

  signal free_last_usecnt      : std_logic_vector(g_num_ports-1 downto 0);
  signal free_last_usecnt_feedback      : std_logic_vector(g_num_ports-1 downto 0);

  signal force_free_done_feedback  : std_logic_vector(g_num_ports-1 downto 0);
  signal force_free_done           : std_logic_vector(g_num_ports-1 downto 0);


  signal set_usecnt_done_feedback  : std_logic_vector(g_num_ports-1 downto 0);
--  signal set_usecnt_done           : std_logic_vector(g_num_ports-1 downto 0);

  signal pg_free_last_usecnt            : std_logic;
begin  -- syn




  -- one allocator/deallocator for all ports
  --ALLOC_CORE : swc_page_allocator_new -- tom's new allocator, not debugged, looses pages :(
  ALLOC_CORE : swc_page_allocator
    generic map (
      g_num_pages      => g_page_num,
      g_page_addr_width=> g_page_addr_width,
      g_num_ports      => g_num_ports,
      g_usecount_width => g_usecount_width)
    port map (
      clk_i          => clk_i,
      rst_n_i        => rst_n_i,
      alloc_i        => pg_alloc,
      free_i         => pg_free,
      free_last_usecnt_o => pg_free_last_usecnt,
      force_free_i   => pg_force_free,
      set_usecnt_i   => pg_set_usecnt,
      usecnt_i       => pg_usecnt,
      pgaddr_i       => pg_addr,--pg_addr_free,
      pgaddr_o       => pg_addr_alloc,
--      pgaddr_valid_o => pg_addr_valid,
--      idle_o         => open, --pg_idle,
      done_o         => pg_done,
      nomem_o        => pg_nomem);


  -- creating request vector with 'alloc' requests at even addresses
  -- and 'free' requests on odd addresses. The condition prevents
  -- considertion of actually processed port for the request to arbiter
  gen_request_vec : for i in 0 to g_num_ports - 1 generate
    request_vec(4 * i + 0) <= alloc_i(i)      and (not (alloc_done_feedback(i)      or alloc_done(i))) and (not pg_nomem);
    request_vec(4 * i + 1) <= free_i(i)       and (not (free_done_feedback(i)       or free_done(i)));
    request_vec(4 * i + 2) <= set_usecnt_i(i) and (not (set_usecnt_done_feedback(i)));-- or set_usecnt_done(i)));
    request_vec(4 * i + 3) <= force_free_i(i) and (not (force_free_done_feedback(i) or force_free_done(i)));
  end generate gen_request_vec;

  -- Round Robin arbiter, quite specific for the usage, since it has the "next" 
  -- input. It is used to start processing next request well in advance, to prevent
  -- unnecessary delays
  ARB : swc_rr_arbiter
    generic map (
      g_num_ports      => c_arbiter_vec_width,
      g_num_ports_log2 => c_arbiter_vec_width_log2)
    port map (
      clk_i         => clk_i,
      rst_n_i       => rst_n_i,
      next_i        => request_next,
      request_i     => request_vec,
      grant_o       => request_grant,
      grant_valid_o => request_grant_valid);

  -- port number to which request has been granted.
  in_sel <= to_integer(unsigned(request_grant(request_grant'length-1 downto 2)));

  -- if the granted request has even address (LSB = '0'), it means that
  -- the request was of 'alloc' type
  pg_alloc       <= '1' when ((request_grant(1 downto 0) = b"00") and request_grant_valid='1') else '0';
  pg_free        <= '1' when ((request_grant(1 downto 0) = b"01") and request_grant_valid='1') else '0';
  pg_set_usecnt  <= '1' when ((request_grant(1 downto 0) = b"10") and request_grant_valid='1') else '0';
  pg_force_free  <= '1' when ((request_grant(1 downto 0) = b"11") and request_grant_valid='1') else '0';
   
  -- This is special to prevent unnecessary delays.
  -- The allocator indicates that the arbiter may start
  -- processing next request as in 2 cycles, net allocator 
  -- will finish the current job and will be ready for the next one
  request_next   <= pg_done;
  
  -- the address of the allocated page
  pgaddr_alloc_o <= pg_addr_alloc;

  -- Getting the address of the page we want to free
  pg_addr_free       <= pgaddr_free_i      (in_sel * g_page_addr_width + g_page_addr_width - 1 downto in_sel * g_page_addr_width);
  pg_addr_force_free <= pgaddr_force_free_i(in_sel * g_page_addr_width + g_page_addr_width - 1 downto in_sel * g_page_addr_width);
  pg_addr_usecnt     <= pgaddr_usecnt_i    (in_sel * g_page_addr_width + g_page_addr_width - 1 downto in_sel * g_page_addr_width);
  ---
 
  
  
  pg_addr            <= pg_addr_force_free when (pg_force_free = '1') else 
                        pg_addr_free       when (pg_free       = '1') else
                        pg_addr_usecnt     when (pg_set_usecnt = '1') else
                        (others => '0');
  
  -- getting the ouser count which should be assigned to freshly allocated page
  pg_usecnt    <= usecnt_i(in_sel * g_usecount_width + g_usecount_width - 1 downto in_sel * g_usecount_width);

  process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        alloc_done_feedback       <= (others => '0');
        free_done_feedback        <= (others => '0');
        set_usecnt_done_feedback  <= (others => '0');
        force_free_done_feedback  <= (others => '0');
        
        free_last_usecnt              <= (others => '0');
      else

        -- recognizing on which port the allocation/deallocation/freeing process
        -- is about to finish. It's solely for request vector composition purpose
        for i in 0 to g_num_ports-1 loop
          if(pg_done = '1' and (in_sel = i)) then
          
            if(request_grant(1 downto 0) = b"00") then
               alloc_done_feedback(i)      <= '1';
            else
               alloc_done_feedback(i)      <= '0';
            end if;

            if(request_grant(1 downto 0) = b"01") then
               free_done_feedback(i)       <= '1';
               free_last_usecnt_feedback(i)    <= pg_free_last_usecnt;                
            else
               free_done_feedback(i)       <= '0';
               free_last_usecnt_feedback(i)    <= '0';
            end if;

            if(request_grant(1 downto 0) = b"10") then
               set_usecnt_done_feedback(i) <= '1';
            else
               set_usecnt_done_feedback(i) <= '0';
            end if;

            if(request_grant(1 downto 0) = b"11") then
               force_free_done_feedback(i) <= '1';
            else
               force_free_done_feedback(i) <= '0';
            end if;

          else
            alloc_done_feedback(i)       <= '0';
            free_done_feedback(i)        <= '0';
            free_last_usecnt_feedback(i)     <= '0';
            set_usecnt_done_feedback(i)  <= '0';
            force_free_done_feedback(i)  <= '0';
          end if;
        end loop;  -- i

        alloc_done      <= alloc_done_feedback;
        free_done       <= free_done_feedback;
        free_last_usecnt    <= free_last_usecnt_feedback;
       -- set_usecnt_done <= set_usecnt_done_feedback;
        force_free_done <= force_free_done_feedback;
      end if;
    end if;
  end process;

  alloc_done_o      <= alloc_done;
  free_done_o       <= free_done;
  free_last_usecnt_o<= free_last_usecnt;
  set_usecnt_done_o <= set_usecnt_done_feedback;--set_usecnt_done;
  force_free_done_o <= force_free_done;
  nomem_o           <= pg_nomem;
  
end syn;
