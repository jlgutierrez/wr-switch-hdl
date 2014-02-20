-------------------------------------------------------------------------------
-- Title      : multiport page allocator
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_multiport_page_allocator.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-08
-- Last update: 2012-03-15
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: This is a wrapper and arbiter for multi-access to a single
-- page allocation core. Some highlights:
-- * theere are 4 kinds of requrest which are however grouped into two groups:
--   (1) input port requirests
--       alloc_i       -- request to allocate new page 
--       set_usecnt_i  -- request to set usecount of already allocated page
--   (2) output port requests:
--       free_i        -- request to decrease usecnt of page (if uscnt=1, page is deallocated)
--       force_free_i  -- request to deallocated a page regardless of usecnt
-- * output port requests (2) cannot be done by a single port at the same time,
--   this means that a port can either request free_i or force_free_i
-- * input port requets (1) can be done in two fasions
--   -> not simultaneously (like output)
--   -> simultaneously and synchronized - so the data and request input is set/deset
--      at the same time
-- * internally, the arbitration is done between 2*num_port requests  
--   -> num_port for input port requests
--   -> num_port for output port requests
--   this means that the upper bound latency for handling request is:
--   max_time= 2*num_ports + 2 (time needed for handling by core) + 1 (arbitration)
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
-- 2013-10-17  3.0      mlipinsk addapted to new optimized page_allocaotr core
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.ALL;   -- for UNIFORM, TRUNC functions

library work;
use work.swc_swcore_pkg.all;
use work.genram_pkg.all;
use work.gencores_pkg.all;

entity swc_multiport_page_allocator is
  generic (
    g_page_addr_width : integer := 10;    --:= c_swc_page_addr_width;
    g_num_ports       : integer := 7;     --:= c_swc_num_ports
    g_page_num        : integer := 1024;  --:= c_swc_packet_mem_num_pages
    g_usecount_width  : integer := 3;      --:= c_swc_usecount_width
    --- resource manager
    g_max_pck_size                     : integer := 759 ;
    g_page_size                        : integer := 66; 
    g_special_res_num_pages            : integer := 256;
    g_resource_num                     : integer := 3; -- this include 1 for unknown
    g_resource_num_width               : integer := 2;
    g_num_dbg_vector_width             : integer := 10*3;
    g_with_RESOURCE_MGR                : boolean := false
    );
  port (
    rst_n_i             : in std_logic;
    clk_i               : in std_logic;

    alloc_i             : in std_logic_vector(g_num_ports - 1 downto 0);
    free_i              : in std_logic_vector(g_num_ports - 1 downto 0);
    force_free_i        : in std_logic_vector(g_num_ports - 1 downto 0);
    set_usecnt_i        : in std_logic_vector(g_num_ports - 1 downto 0);

    alloc_done_o        : out std_logic_vector(g_num_ports - 1 downto 0);
    free_done_o         : out std_logic_vector(g_num_ports - 1 downto 0);
    force_free_done_o   : out std_logic_vector(g_num_ports - 1 downto 0);
    set_usecnt_done_o   : out std_logic_vector(g_num_ports - 1 downto 0);


    pgaddr_free_i       : in std_logic_vector(g_num_ports * g_page_addr_width - 1 downto 0);
    pgaddr_force_free_i : in std_logic_vector(g_num_ports * g_page_addr_width - 1 downto 0);
    pgaddr_usecnt_i     : in std_logic_vector(g_num_ports * g_page_addr_width - 1 downto 0);

    usecnt_set_i        : in  std_logic_vector(g_num_ports * g_usecount_width - 1 downto 0);
    usecnt_alloc_i      : in  std_logic_vector(g_num_ports * g_usecount_width - 1 downto 0);
    
    pgaddr_alloc_o      : out std_logic_vector(g_page_addr_width-1 downto 0);

    free_last_usecnt_o  : out std_logic_vector(g_num_ports - 1 downto 0);

    nomem_o : out std_logic;

    --------------------------- resource management ----------------------------------
    -- resource number
    resource_i             : in  std_logic_vector(g_num_ports * g_resource_num_width-1 downto 0);
    
    -- outputed when freeing
    resource_o             : out std_logic_vector(g_num_ports * g_resource_num_width-1 downto 0);

    -- used only when freeing page, 
    -- if HIGH then the input resource_i value will be used
    -- if LOW  then the value read from memory will be used (stored along with usecnt)
    free_resource_i             : in  std_logic_vector(g_num_ports * g_resource_num_width - 1 downto 0);
    free_resource_valid_i       : in  std_logic_vector(g_num_ports                        - 1 downto 0);
    force_free_resource_i       : in  std_logic_vector(g_num_ports * g_resource_num_width - 1 downto 0);
    force_free_resource_valid_i : in  std_logic_vector(g_num_ports                        - 1 downto 0);
    
    -- number of pages added to the resurce
    rescnt_page_num_i      : in  std_logic_vector(g_num_ports * g_page_addr_width -1 downto 0);

    -- indicates whether the resources where re-located to the proper resource, if not, then the
    -- whole usecnt operation is abandoned
    set_usecnt_succeeded_o : out std_logic_vector(g_num_ports                     -1 downto 0);
    res_full_o             : out std_logic_vector(g_num_ports * g_resource_num    -1 downto 0);
    res_almost_full_o      : out std_logic_vector(g_num_ports * g_resource_num    -1 downto 0);
    dbg_o                  : out std_logic_vector(g_num_dbg_vector_width - 1 downto 0)  

--     tap_out_o : out std_logic_vector(62 + 49 downto 0)
    );

end swc_multiport_page_allocator;

architecture syn of swc_multiport_page_allocator is


  component swc_page_allocator_new
    generic (
      g_num_pages             : integer;
      g_page_addr_width       : integer;
      g_num_ports             : integer;
      g_usecount_width        : integer;
      --- management
      g_with_RESOURCE_MGR     : boolean := false;
      g_page_size             : integer := 64;
      g_max_pck_size          : integer := 759; -- in 16 bit words (1518 [octets])/(2 [octets])
      g_special_res_num_pages : integer := 256;
      g_resource_num          : integer := 3;   -- this include: unknown, special and x* normal , so
                                                -- g_resource_num = 2+x
      g_resource_num_width    : integer := 2;
      g_num_dbg_vector_width  : integer );
    port (
      clk_i                   : in  std_logic;
      rst_n_i                 : in  std_logic;
      alloc_i                 : in  std_logic;
      free_i                  : in  std_logic;
      force_free_i            : in  std_logic;
      set_usecnt_i            : in  std_logic;
      usecnt_set_i            : in  std_logic_vector(g_usecount_width-1 downto 0);
      usecnt_alloc_i          : in  std_logic_vector(g_usecount_width-1 downto 0);
      pgaddr_free_i           : in  std_logic_vector(g_page_addr_width -1 downto 0);
      pgaddr_usecnt_i         : in  std_logic_vector(g_page_addr_width -1 downto 0);
      req_vec_i               : in  std_logic_vector(g_num_ports-1 downto 0);
      rsp_vec_o               : out std_logic_vector(g_num_ports-1 downto 0);
      pgaddr_o                : out std_logic_vector(g_page_addr_width -1 downto 0);
      free_last_usecnt_o      : out std_logic;
      done_o                  : out std_logic;
      done_alloc_o            : out std_logic;     
      done_usecnt_o           : out std_logic;     
      done_free_o             : out std_logic;     
      done_force_free_o       : out std_logic;     
      nomem_o                 : out std_logic;
      -------- resource management --------
      resource_i              : in  std_logic_vector(g_resource_num_width-1 downto 0);
      resource_o              : out std_logic_vector(g_resource_num_width-1 downto 0);
      free_resource_valid_i   : in  std_logic;
      rescnt_page_num_i       : in  std_logic_vector(g_page_addr_width   -1 downto 0);
      set_usecnt_succeeded_o  : out std_logic;
      res_full_o              : out std_logic_vector(g_resource_num      -1 downto 0);
      res_almost_full_o       : out std_logic_vector(g_resource_num      -1 downto 0);
      dbg_o                   : out std_logic_vector(g_num_dbg_vector_width - 1 downto 0);
      -----------------------
      dbg_double_free_o       : out std_logic;
      dbg_double_force_free_o : out std_logic;
      dbg_q_write_o           : out std_logic;
      dbg_q_read_o            : out std_logic;
      dbg_initializing_o      : out std_logic);
  end component;

  type t_port_state is record
    req_ib               : std_logic;
    req_ob               : std_logic;
    req_alloc            : std_logic;
    req_free             : std_logic;
    req_set_usecnt       : std_logic;
    req_force_free       : std_logic;
    req_addr_usecnt      : std_logic_vector(g_page_addr_width-1 downto 0);
    req_addr_free        : std_logic_vector(g_page_addr_width-1 downto 0);
    req_addr_f_free      : std_logic_vector(g_page_addr_width-1 downto 0);
    req_ucnt_set         : std_logic_vector(g_usecount_width-1 downto 0);
    req_ucnt_alloc       : std_logic_vector(g_usecount_width-1 downto 0);
    req_resource         : std_logic_vector(g_resource_num_width-1 downto 0);
    req_free_resource    : std_logic_vector(g_resource_num_width-1 downto 0);
    req_free_res_valid   : std_logic;
    req_f_free_resource  : std_logic_vector(g_resource_num_width-1 downto 0);
    req_f_free_res_valid : std_logic;
    req_rescnt_pg_num    : std_logic_vector(g_page_addr_width   -1 downto 0);
    
    grant_ib_d : std_logic_vector(2 downto 0);
    grant_ob_d : std_logic_vector(2 downto 0);

    done_alloc      : std_logic;
    done_free       : std_logic;
    done_set_usecnt : std_logic;
    done_force_free : std_logic;
  end record;
  type t_port_state_array is array(0 to g_num_ports-1) of t_port_state;

  signal ports              : t_port_state_array;
  signal arb_req, arb_grant : std_logic_vector(2*g_num_ports-1 downto 0);
  signal arb_req_d0         : std_logic_vector(2*g_num_ports-1 downto 0);


  signal pg_alloc            : std_logic;
  signal pg_free             : std_logic;
  signal pg_force_free       : std_logic;
  signal pg_set_usecnt       : std_logic;
  signal pg_usecnt_set       : std_logic_vector(g_usecount_width-1 downto 0);
  signal pg_usecnt_alloc     : std_logic_vector(g_usecount_width-1 downto 0);
  signal pg_addr_ucnt_set    : std_logic_vector(g_page_addr_width -1 downto 0);
  signal pg_addr_free        : std_logic_vector(g_page_addr_width -1 downto 0);
  signal pg_addr_alloc       : std_logic_vector(g_page_addr_width -1 downto 0);
  signal pg_free_last_usecnt : std_logic;
  signal pg_done             : std_logic;
  signal done_alloc          : std_logic;     
  signal done_usecnt         : std_logic;     
  signal done_free           : std_logic;     
  signal done_force_free     : std_logic;     

  signal pg_nomem            : std_logic;
  signal pg_req_vec          : std_logic_vector(g_num_ports-1 downto 0);
  signal pg_rsp_vec          : std_logic_vector(g_num_ports-1 downto 0);
  signal grant_ob_d0         : std_logic_vector(g_num_ports-1 downto 0);
  signal grant_ib_d0         : std_logic_vector(g_num_ports-1 downto 0);

  signal alloc_done      : std_logic_vector(g_num_ports - 1 downto 0);
  signal free_done       : std_logic_vector(g_num_ports - 1 downto 0);
  signal force_free_done : std_logic_vector(g_num_ports - 1 downto 0);
  signal set_usecnt_done : std_logic_vector(g_num_ports - 1 downto 0);

  signal dbg_double_force_free, dbg_double_free    : std_logic;
  signal dbg_q_read, dbg_q_write, dbg_initializing : std_logic;

  --------------------------- resource management ----------------------------------
    -- resource number
  signal pg_resource_in           : std_logic_vector(g_resource_num_width-1 downto 0);
  signal pg_alloc_usecnt_resource : std_logic_vector(g_resource_num_width-1 downto 0);
  signal pg_free_resource         : std_logic_vector(g_resource_num_width-1 downto 0);
  signal pg_force_free_resource   : std_logic_vector(g_resource_num_width-1 downto 0);
  signal pg_resource_out          : std_logic_vector(g_resource_num_width-1 downto 0);
  signal pg_free_resource_valid   : std_logic;
  signal pg_rescnt_page_num       : std_logic_vector(g_page_addr_width-1 downto 0);
  signal pg_res_full              : std_logic_vector(g_resource_num   -1 downto 0);
  signal pg_res_almost_full       : std_logic_vector(g_resource_num   -1 downto 0);

  type t_port_resource_out is record
    resource    : std_logic_vector(g_resource_num_width-1 downto 0);
    full        : std_logic_vector(g_resource_num-1 downto 0);
    almost_full : std_logic_vector(g_resource_num-1 downto 0);
  end record;
 
  type t_port_resource_out_array is array(integer range <>) of t_port_resource_out;
  
  signal resources_feedback      : t_port_resource_out_array(g_num_ports-1 downto 0);
  signal resources_out           : t_port_resource_out_array(g_num_ports-1 downto 0);
  signal pg_set_usecnt_succeeded : std_logic;
  signal set_usecnt_succeeded    : std_logic_vector(g_num_ports -1 downto 0);

  function f_bool_2_sl (x : boolean) return std_logic is
  begin
    if(x) then
      return '1';
    else
      return '0';
    end if;
  end f_bool_2_sl;

  function f_slv_resize(x : std_logic_vector; len : natural) return std_logic_vector is
    variable tmp : std_logic_vector(len-1 downto 0);
  begin
    tmp                      := (others => '0');
    tmp(x'length-1 downto 0) := x;
    return tmp;
  end f_slv_resize;

  
begin  -- syn

  gen_records : for i in 0 to g_num_ports-1 generate
    ports(i).req_force_free       <= force_free_i(i);
    ports(i).req_free             <= free_i(i);
    ports(i).req_alloc            <= alloc_i(i) and (not pg_nomem);
    ports(i).req_set_usecnt       <= set_usecnt_i(i);
    ports(i).req_free_res_valid   <= free_resource_valid_i(i);
    ports(i).req_f_free_res_valid <= force_free_resource_valid_i(i);
    
    ports(i).req_addr_usecnt      <= pgaddr_usecnt_i      (g_page_addr_width   *(i+1)-1 downto g_page_addr_width   *i);
    ports(i).req_addr_free        <= pgaddr_free_i        (g_page_addr_width   *(i+1)-1 downto g_page_addr_width   *i); 
    ports(i).req_addr_f_free      <= pgaddr_force_free_i  (g_page_addr_width   *(i+1)-1 downto g_page_addr_width   *i);
    ports(i).req_ucnt_set         <= usecnt_set_i         (g_usecount_width    *(i+1)-1 downto g_usecount_width    *i);
    ports(i).req_ucnt_alloc       <= usecnt_alloc_i       (g_usecount_width    *(i+1)-1 downto g_usecount_width    *i);
    ports(i).req_resource         <= resource_i           (g_resource_num_width*(i+1)-1 downto g_resource_num_width*i);
    ports(i).req_free_resource    <= free_resource_i      (g_resource_num_width*(i+1)-1 downto g_resource_num_width*i);
    ports(i).req_f_free_resource  <= force_free_resource_i(g_resource_num_width*(i+1)-1 downto g_resource_num_width*i);
    ports(i).req_rescnt_pg_num    <= rescnt_page_num_i    (g_page_addr_width   *(i+1)-1 downto g_page_addr_width   *i);
  end generate gen_records;

  -- MUXes
  gen_arbiter : for i in 0 to g_num_ports-1 generate
    process(ports, arb_req, arb_grant, pg_done, pg_nomem,arb_req_d0, grant_ob_d0, grant_ib_d0)
    begin
      ports(i).grant_ib_d(0) <= arb_grant(2 * i);
      ports(i).grant_ob_d(0) <= arb_grant(2 * i + 1);
      ports(i).req_ib        <= (ports(i).req_alloc or ports(i).req_set_usecnt);  
      ports(i).req_ob        <= (ports(i).req_free  or ports(i).req_force_free);  
      arb_req(2 * i)         <= ports(i).req_ib and not (ports(i).grant_ib_d(0) or grant_ib_d0(i));
      arb_req(2 * i + 1)     <= ports(i).req_ob and not (ports(i).grant_ob_d(0) or grant_ob_d0(i));
    end process;
  end generate gen_arbiter;

  p_gen_pg_reqs : process(ports)
    variable alloc, free, force_free, set_usecnt : std_logic;
    variable tmp_addr_ucnt  : std_logic_vector(g_page_addr_width-1 downto 0);
    variable tmp_addr_free  : std_logic_vector(g_page_addr_width-1 downto 0);
    variable tmp_ucnt_set   : std_logic_vector(g_usecount_width-1 downto 0);    
    variable tmp_ucnt_alloc : std_logic_vector(g_usecount_width-1 downto 0);    
  begin
    alloc           := '0';
    free            := '0';
    force_free      := '0';
    set_usecnt      := '0';
    tmp_addr_ucnt   := (others => 'X');
    tmp_addr_free   := (others => 'X');
    tmp_ucnt_set    := (others => 'X');
    tmp_ucnt_alloc  := (others => 'X');
    
    for i in 0 to g_num_ports-1 loop
      if(ports(i).grant_ib_d(0) = '1') then
        alloc            := ports(i).req_alloc;
        set_usecnt       := ports(i).req_set_usecnt;
        tmp_addr_ucnt    := ports(i).req_addr_usecnt;
        tmp_addr_free    := (others => 'X');
        if(ports(i).req_alloc = '1' ) then
          tmp_ucnt_alloc := ports(i).req_ucnt_alloc;
        else
          tmp_ucnt_alloc := (others => 'X');
        end if;
        if(ports(i).req_set_usecnt = '1') then
          tmp_ucnt_set   := ports(i).req_ucnt_set;
        else 
          tmp_ucnt_set   := (others => 'X');
        end if;
      elsif(ports(i).grant_ob_d(0) = '1') then
        free             := ports(i).req_free;
        force_free       := ports(i).req_force_free;
        tmp_addr_ucnt    := (others => 'X');
        if(ports(i).req_free = '1') then
          tmp_addr_free  := ports(i).req_addr_free;
          tmp_ucnt_set   := (others => 'X');
          tmp_ucnt_alloc := (others => 'X');
        elsif(ports(i).req_force_free = '1') then
          tmp_addr_free  := ports(i).req_addr_f_free;
          tmp_ucnt_set   := (others => 'X');
          tmp_ucnt_alloc := (others => 'X');
        end if;        
      end if;
      pg_req_vec(i) <= ports(i).grant_ib_d(0) or ports(i).grant_ob_d(0);
    end loop;  -- i

    pg_alloc          <= alloc;
    pg_free           <= free;
    pg_force_free     <= force_free;
    pg_set_usecnt     <= set_usecnt;
    pg_addr_ucnt_set  <= tmp_addr_ucnt;
    pg_addr_free      <= tmp_addr_free;
    pg_usecnt_set     <= tmp_ucnt_set;
    pg_usecnt_alloc   <= tmp_ucnt_alloc;
    
  end process;


  p_arbitrate : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0'then
        arb_grant <= (others => '0');
      else
        f_rr_arbitrate(arb_req, arb_grant, arb_grant);
      end if;
    end if;
  end process;

--  p_arbitrate : process(clk_i)
--     variable seed1, seed2 : positive;   -- Seed values for random generator
--     variable rand         : real;  -- Random real-number value in range 0 to 1.0
--   begin
--     if rising_edge(clk_i) then
--       if rst_n_i = '0'then
--         arb_grant <= (others => '0');
--       else
--         UNIFORM(seed1, seed2, rand);
-- 
--         if(rand < 0.05) then
--           f_rr_arbitrate(arb_req, arb_grant, arb_grant);
--         else
--           arb_grant <= (others => '0');
--         end if;
--         
--       end if;
--     end if;
--   end process;

  p_req_vec_reg : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0'then
        grant_ob_d0 <= (others => '0');       
        grant_ib_d0 <= (others => '0');
      else
        for i in 0 to g_num_ports-1 loop
          
          -- input
          if(ports(i).grant_ib_d(0) = '1' and pg_nomem ='0') then
            grant_ib_d0(i) <= '1';
          elsif(pg_rsp_vec(i)='1' and (alloc_done(i) ='1' or set_usecnt_done(i) ='1')) then
            grant_ib_d0(i) <= '0';
          end if;         
          -- output
          if(ports(i).grant_ob_d(0) = '1') then
            grant_ob_d0(i) <= '1';
          elsif(pg_rsp_vec(i)='1' and (free_done(i) ='1' or force_free_done(i) ='1')) then
            grant_ob_d0(i) <= '0';
          end if;         

        end loop;  -- i
      end if;
    end if;
  end process;

  -- one allocator/deallocator for all ports
  --ALLOC_CORE : swc_page_allocator_new -- tom's new allocator, not debugged, looses pages :(
  ALLOC_CORE : swc_page_allocator_new
    generic map (
      g_num_pages       => g_page_num,
      g_page_addr_width => g_page_addr_width,
      g_num_ports       => g_num_ports,
      g_usecount_width  => g_usecount_width,
      --- management
      g_with_RESOURCE_MGR     => g_with_RESOURCE_MGR,
      g_page_size             => g_page_size,
      g_max_pck_size          => g_max_pck_size,
      g_special_res_num_pages => g_special_res_num_pages,
      g_resource_num          => g_resource_num,
      g_resource_num_width    => g_resource_num_width,
      g_num_dbg_vector_width  => g_num_dbg_vector_width)
    port map (
      clk_i                   => clk_i,
      rst_n_i                 => rst_n_i,
      alloc_i                 => pg_alloc,
      free_i                  => pg_free,
      free_last_usecnt_o      => pg_free_last_usecnt,
      force_free_i            => pg_force_free,
      set_usecnt_i            => pg_set_usecnt,
      usecnt_set_i            => pg_usecnt_set,
      usecnt_alloc_i          => pg_usecnt_alloc,
      pgaddr_free_i           => pg_addr_free,
      pgaddr_usecnt_i         => pg_addr_ucnt_set,
      req_vec_i               => pg_req_vec,
      rsp_vec_o               => pg_rsp_vec,                  
      pgaddr_o                => pg_addr_alloc,
      done_o                  => pg_done,
      done_alloc_o            => done_alloc,
      done_usecnt_o           => done_usecnt,
      done_free_o             => done_free,
      done_force_free_o       => done_force_free,
      nomem_o                 => pg_nomem,
      -------- resource management --------
      set_usecnt_succeeded_o  => pg_set_usecnt_succeeded,
      resource_i              => pg_resource_in,
      resource_o              => pg_resource_out,
      free_resource_valid_i   => pg_free_resource_valid,
      rescnt_page_num_i       => pg_rescnt_page_num,
      res_full_o              => pg_res_full,
      res_almost_full_o       => pg_res_almost_full,
      dbg_o                   => dbg_o,
      -------------------------------      
      dbg_double_force_free_o => dbg_double_force_free,
      dbg_double_free_o       => dbg_double_free,
      dbg_q_read_o            => dbg_q_read,
      dbg_q_write_o           => dbg_q_write,
      dbg_initializing_o      => dbg_initializing);

  nomem_o        <= pg_nomem;
  pgaddr_alloc_o <= pg_addr_alloc;

  gen_done : for i in 0 to g_num_ports-1 generate
-- when nomem it got lost -> the req_alloc is forced LOW by nomam HIGH, so the alloc which happened just before nomem
-- was not answered...
--     alloc_done(i)      <= '1' when (ports(i).req_alloc     ='1' and pg_rsp_vec(i)='1' and done_alloc     ='1') else '0';
--     free_done(i)       <= '1' when (ports(i).req_free      ='1' and pg_rsp_vec(i)='1' and done_free      ='1') else '0';
--     force_free_done(i) <= '1' when (ports(i).req_force_free='1' and pg_rsp_vec(i)='1' and done_force_free='1') else '0';
--     set_usecnt_done(i) <= '1' when (ports(i).req_set_usecnt='1' and pg_rsp_vec(i)='1' and done_usecnt    ='1') else '0';  
    alloc_done(i)      <= '1' when (pg_rsp_vec(i)='1' and done_alloc     ='1') else '0';
    free_done(i)       <= '1' when (pg_rsp_vec(i)='1' and done_free      ='1') else '0';
    force_free_done(i) <= '1' when (pg_rsp_vec(i)='1' and done_force_free='1') else '0';
    set_usecnt_done(i) <= '1' when (pg_rsp_vec(i)='1' and done_usecnt    ='1') else '0';  
  end generate gen_done;

  alloc_done_o       <= alloc_done;
  free_done_o        <= free_done;
  force_free_done_o  <= force_free_done;
  set_usecnt_done_o  <= set_usecnt_done;
  free_last_usecnt_o <= (others => pg_free_last_usecnt);

  p_assertions : process(clk_i)
  begin
    if rising_edge(clk_i) then
      for i in 0 to g_num_ports-1 loop
--         if(ports(i).req_alloc = '1' and ports(i).req_set_usecnt = '1') then
--           report "simultaneous alloc/set_usecnt" severity failure;
--           
--         elsif (ports(i).req_free = '1' and ports(i).req_force_free = '1') then
--           report "simultaneous free/force_free" severity failure;

        if (ports(i).req_free = '1' and ports(i).req_force_free = '1') then
          report "simultaneous free/force_free" severity failure;
        end if;

      end loop;  -- i
    end if;
  end process;

  --------------------------------------------------------------------------------------------------
  --                               Resource Manager logic and instantiation
  --------------------------------------------------------------------------------------------------
  gen_no_RESOURCE_MGR: if (g_with_RESOURCE_MGR = false) generate -- so we don't want resource gnr
    set_usecnt_succeeded_o <= (others => '1');
--     res_full_o             <= (others => pg_res_full);        -- (others => '0');
--     res_almost_full_o      <= (others => pg_res_almost_full); -- (others => '0');
    res_full_o             <= (others => '0');
    res_almost_full_o      <= (others => '0');
    resource_o             <= (others => '0');
    
    pg_resource_in         <= (others => '0');
    pg_free_resource_valid <= '0';
    pg_rescnt_page_num     <= (others => '0');
  end generate gen_no_RESOURCE_MGR;

  gen_RESOURCE_MGR: if (g_with_RESOURCE_MGR = true) generate -- so we do want resource gnr
    
    -- input mux
    p_gen_resource_reqs : process(ports)
      variable     tmp_resource_in      : std_logic_vector(g_resource_num_width-1 downto 0);
      variable     tmp_free_res_valid   : std_logic; 
      variable     tmp_rescnt_pg_num    : std_logic_vector(g_page_addr_width   -1 downto 0);
    begin
      tmp_resource_in          := (others => 'X');
      tmp_free_res_valid       := '0';
      tmp_rescnt_pg_num        := (others => 'X');
    
      for i in 0 to g_num_ports-1 loop
        if(ports(i).grant_ib_d(0) = '1') then
          tmp_resource_in      := ports(i).req_resource;
          tmp_free_res_valid   := '0';
          if(ports(i).req_set_usecnt = '1') then 
            tmp_rescnt_pg_num    := ports(i).req_rescnt_pg_num;
          else
            tmp_rescnt_pg_num    := (others => 'X'); -- to see red in simulation when data not used
          end if;
        elsif(ports(i).grant_ob_d(0) = '1') then
          if(ports(i).req_free = '1' and ports(i).req_free_res_valid = '1') then -- way to enable X if else
            tmp_resource_in    := ports(i).req_free_resource;
            tmp_free_res_valid := '1';
          elsif(ports(i).req_force_free = '1' and ports(i).req_f_free_res_valid ='1') then
            tmp_resource_in    := ports(i).req_f_free_resource;
            tmp_free_res_valid := '1';
          else -- to see problems in red on simulation
            tmp_resource_in    := (others =>'X');
            tmp_free_res_valid := '0';            
          end if; 
          tmp_rescnt_pg_num    := (others =>'X');
        end if;
      end loop;  -- i

      pg_resource_in           <= tmp_resource_in;
      pg_free_resource_valid   <= tmp_free_res_valid;
      pg_rescnt_page_num       <= tmp_rescnt_pg_num;

    end process p_gen_resource_reqs;
    
    -- output de-mux
    gen_res_out : for i in 0 to g_num_ports-1 generate
      resource_o       ((i+1)*g_resource_num_width-1 downto i*g_resource_num_width) <= pg_resource_out when (free_done(i) ='1' or force_free_done(i) ='1') else 
                                                                                       (others => '0');
      res_full_o       ((i+1)*g_resource_num      -1 downto i*g_resource_num)       <= pg_res_full;
      res_almost_full_o((i+1)*g_resource_num      -1 downto i*g_resource_num)       <= pg_res_almost_full;
      
      set_usecnt_succeeded_o(i) <= pg_set_usecnt_succeeded when (set_usecnt_done(i) ='1') else '0';  
    end generate gen_res_out;
  end generate gen_RESOURCE_MGR;  

  --------------------------------------------------------------------------------------------------

--   tap_out_o <= f_slv_resize
--                (
--                  dbg_q_write &
--                  dbg_q_read &
--                  dbg_initializing &
--                  alloc_i &
--                  free_i &
--                  force_free_i &
--                  set_usecnt_i &
-- 
--                  alloc_done&
--                  free_done &
--                  force_free_done&         -- 56
--                  set_usecnt_done &        -- 48
--                  pg_alloc &               -- 47
--                  pg_free &                -- 46
--                  pg_free_last_usecnt &    -- 45
--                  pg_force_free &          -- 44
--                  pg_set_usecnt &          -- 43
--                  pg_usecnt &              -- 40
--                  pg_addr &                -- 30
--                  pg_addr_alloc &          -- 20
--                  pg_done &                -- 19
--                  pg_nomem &               -- 18
--                  dbg_double_free &        -- 17
--                  dbg_double_force_free ,  --  16
--                  50 + 62);

end syn;
