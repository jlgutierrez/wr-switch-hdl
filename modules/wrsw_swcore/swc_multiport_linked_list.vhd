-------------------------------------------------------------------------------
-- Title      : multiport linked list
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_multiport_linked_list.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-10-26
-- Last update: 2012-02-16
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2010 Maciej Lipinski / CERN
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
-- 2010-10-26  1.0      mlipinsk Created
-- 2012-02-02  2.0      mlipinsk generic-azed
-- 2012-02-16  3.0      mlipinsk speeded up & adapted to cut-through & adapted to new MPM
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

library work;
use work.swc_swcore_pkg.all;
use work.genram_pkg.all;
use work.gencores_pkg.all;

entity swc_multiport_linked_list is
  generic ( 
    g_num_ports                        : integer; --:= c_swc_num_ports
    g_addr_width                       : integer; --:= c_swc_page_addr_width;
    g_page_num                         : integer;  --:= c_swc_packet_mem_num_pages
    -- new stuff
    g_size_width                       : integer ;
    g_partial_select_width             : integer ;
    g_data_width                       : integer   --:= c_swc_packet_mem_num_pages    + 2

  ----------------------------------------------------------------------------------------
  -- the following relation is needed for the things to work
  -- g_data_width >= 2 + g_addr_width
  -- g_data_width >= 2 + g_partial_select_width + g_size_width
  -- 
  -- this is because the format of the LL entry (data) is the following:
  -- 
  -- |---------------------------------------------------------------------------------------|
  -- |1[bit]|1[bit]|                      g_data_width - 2 [bits]                            |
  -- |---------------------------------------------------------------------------------------|
  -- |      |      |                   next_page_addr (g_addr_width bits)                    | eof=0
  -- |valid | eof  |                                                                         |
  -- |      |      |dsel(g_partial_select_width [bits]) | words in page (g_size_width [bits])| eof=1
  ---|---------------------------------------------------------------------------------------|
  );
  port (
    rst_n_i               : in std_logic;
    clk_i                 : in std_logic;

    -- write request
    write_i               : in  std_logic_vector(g_num_ports - 1 downto 0);
    -- indicates that the data was written
    write_done_o          : out std_logic_vector(g_num_ports - 1 downto 0);
    -- write address, needs to be valid till write_done_o=HIGH
    write_addr_i          : in  std_logic_vector(g_num_ports * g_addr_width - 1 downto 0);
    -- next page [ctrls,address or (size + sel)]
    write_data_i          : in  std_logic_vector(g_num_ports * g_data_width - 1 downto 0);
    -- if we already know the address (of the next page to be used), we provide it here, it
    -- is invalidated.
    write_next_addr_i     : in  std_logic_vector(g_num_ports * g_addr_width - 1 downto 0);
    -- indicates that the next_addr is provided
    write_next_addr_valid_i: in  std_logic_vector(g_num_ports - 1 downto 0);

    ------------ reading from the Linked List by freeing module ----------
    -- request reading
    free_pck_rd_req_i     : in  std_logic_vector(g_num_ports - 1 downto 0);
    -- requested address,  needs to be valid till write_done_o=HIGH
    free_pck_addr_i       : in  std_logic_vector(g_num_ports * g_addr_width - 1 downto 0);
    -- data available on data_o
    free_pck_read_done_o  : out std_logic_vector(g_num_ports - 1 downto 0);
    -- requested data
    free_pck_data_o       : out std_logic_vector(g_num_ports * g_data_width - 1 downto 0);
    
    -------- reading by Multiport Memory (direct access, different clock domain) -------
    -- clock of the MPM's core
    mpm_rpath_clk_i       : in std_logic;
    -- requested address,  needs to be valid till write_done_o=HIGH
    mpm_rpath_addr_i      : in  std_logic_vector(g_addr_width - 1 downto 0);
    -- requested data
    mpm_rpath_data_o      : out std_logic_vector(g_data_width - 1 downto 0)
    );

end swc_multiport_linked_list;

architecture syn of swc_multiport_linked_list is
  
  ---------------------- writing process --------------------------------
  -- arbitrating writing process
  signal write_request_vec        : std_logic_vector(g_num_ports-1 downto 0);
  signal write_grant_vec          : std_logic_vector(g_num_ports-1 downto 0);
  signal write_grant_vec_d0       : std_logic_vector(g_num_ports-1 downto 0);
  signal write_grant_vec_d1       : std_logic_vector(g_num_ports-1 downto 0);
  signal write_grant_index        : integer range 0 to g_num_ports-1;
  signal write_grant_index_d0     : integer range 0 to g_num_ports-1;
  signal write_request_noempty    : std_logic;

  signal write_done               : std_logic_vector(g_num_ports-1 downto 0);

  signal in_sel_write             : integer range 0 to g_num_ports-1;
  -- signals used by writing process  
  signal ll_write_ena             : std_logic;
  signal ll_write_next_ena        : std_logic;
  signal ll_write_addr            : std_logic_vector(g_addr_width - 1 downto 0);
  signal ll_write_next_addr       : std_logic_vector(g_addr_width - 1 downto 0);
  signal ll_write_data            : std_logic_vector(g_data_width - 1 downto 0);
  signal ll_write_data_valid      : std_logic;
  signal ll_write_end_of_list     : std_logic;

  signal tmp_write_end_of_list    : std_logic_vector(g_num_ports-1 downto 0);
  -- signal connected directly to DPRAM (driven/multiplexd by the above
  signal ll_wr_addr               : std_logic_vector(g_addr_width - 1 downto 0);
  signal ll_wr_data               : std_logic_vector(g_data_width - 1 downto 0);
  signal ll_wr_ena                : std_logic;

  ---------------------- reading process (free pck module) --------------------------------
  -- arbitrating access
  signal free_pck_request_vec     : std_logic_vector(g_num_ports-1 downto 0);
  signal free_pck_request_noempty : std_logic;
  signal free_pck_grant_vec       : std_logic_vector(g_num_ports-1 downto 0); 
  signal free_pck_grant_vec_d0    : std_logic_vector(g_num_ports-1 downto 0);
  signal free_pck_grant_vec_d1    : std_logic_vector(g_num_ports-1 downto 0);
  signal free_pck_grant_index     : integer range 0 to g_num_ports-1;
  signal free_pck_grant_index_d0  : integer range 0 to g_num_ports-1;
  signal free_pck_grant_valid     : std_logic;
  signal free_pck_grant_valid_d0  : std_logic;

  signal free_pck_read                : std_logic_vector(g_num_ports -1 downto 0);
  signal free_pck_read_done           : std_logic_vector(g_num_ports -1 downto 0);

  -- interface to DPRAM
  signal ll_free_pck_ena         : std_logic;
  signal ll_free_pck_addr        : std_logic_vector(g_addr_width - 1 downto 0);
  signal ll_free_pck_data        : std_logic_vector(g_data_width - 1 downto 0);
  
  -- output
  type t_ll_data_array is array (g_num_ports-1 downto 0) of std_logic_vector(g_data_width - 1 downto 0);
  signal free_pck_data          : t_ll_data_array;
  signal free_pck_data_out      : t_ll_data_array;
  -- helper
  signal zeros       : std_logic_vector(g_num_ports-1 downto 0); 
  ----------------- translate one hot to binary --------------------------
  function f_one_hot_to_binary (
      One_Hot : std_logic_vector 
     ) return integer  is
  variable Bin_Vec_Var : integer range 0 to One_Hot'length -1;
  begin
    Bin_Vec_Var := 0;

     for I in 0 to (One_Hot'length - 1) loop
       if One_Hot(I) = '1' then
         Bin_Vec_Var := I;
       end if;
     end loop;
    return Bin_Vec_Var;
  end function;
  -----------------------------------------------------------------------

begin  -- syn

  zeros     <= (others => '0');

   -- this memory is read by the output of the MPM (called read pump)
   PAGE_INDEX_LINKED_LIST_MPM : generic_dpram
     generic map (
       g_data_width  => g_data_width,-- one bit for validating the data
       g_size        => g_page_num
                 )
     port map (
       -- Port A -- writing
       clka_i => clk_i,
       bwea_i => (others => '1'),
       wea_i  => ll_wr_ena,
       aa_i   => ll_wr_addr,
       da_i   => ll_wr_data,
       qa_o   => open,   
 
       -- Port B  -- reading
       clkb_i => mpm_rpath_clk_i,
       bweb_i => (others => '1'), 
       web_i  => '0',
       ab_i   => mpm_rpath_addr_i,
       db_i   => (others => '0'),
       qb_o   => mpm_rpath_data_o
       );

   -- this memory is read by the process that force-frees pck on error
   PAGE_INDEX_LINKED_LIST_FREE_PCK : generic_dpram
     generic map (
       g_data_width  => g_data_width,-- one bit for validating the data
       g_size        => g_page_num
                 )
     port map (
       -- Port A -- writing
       clka_i => clk_i,
       bwea_i => (others => '1'),
       wea_i  => ll_wr_ena,
       aa_i   => ll_wr_addr,
       da_i   => ll_wr_data,
       qa_o   => open,   
 
       -- Port B  -- reading
       clkb_i => clk_i,
       bweb_i => (others => '1'),
       web_i  => '0',
       ab_i   => ll_free_pck_addr,
       db_i   => (others => '0'),
       qb_o   => ll_free_pck_data
       );

  gen_write_request_vec : for i in 0 to g_num_ports - 1 generate
    tmp_write_end_of_list(i) <= write_data_i((i + 1) * g_data_width - 2);
    --write_request_vec(i)     <= write_i(i)  and (not ((tmp_write_end_of_list(i) and write_grant_vec_d0(i)) or write_grant_vec_d1(i)));
    write_request_vec(i)     <= write_i(i)  and (not ((not write_next_addr_valid_i(i) and write_grant_vec_d0(i)) or write_grant_vec_d1(i)));
  end generate;

  gen_free_pck_request_vec : for i in 0 to g_num_ports - 1 generate
    free_pck_request_vec(i) <= free_pck_read(i) and (not (free_pck_grant_vec_d0(i) or free_pck_grant_vec_d1(i)));
  end generate;

  -- writing
  f_rr_arbitrate(req      => write_request_vec,
                 pre_grant=> write_grant_vec_d0,
                 grant    => write_grant_vec);

  write_grant_index     <= f_one_hot_to_binary(write_grant_vec_d0) ;
  write_request_noempty <= '1' when (write_request_vec /= zeros) else '0';

  -- reading
  f_rr_arbitrate(req      => free_pck_request_vec,
                 pre_grant=> free_pck_grant_vec_d0,
                 grant    => free_pck_grant_vec);

  free_pck_grant_index     <= f_one_hot_to_binary(free_pck_grant_vec_d0) ;
  free_pck_request_noempty <= '1' when (free_pck_request_vec /= zeros) else '0';

  
  -- ======= writing =======
  -- mux input data for the port to which access is granted
  ll_write_data       <= write_data_i((write_grant_index + 1) * g_data_width - 1 downto write_grant_index * g_data_width);
  ll_write_addr       <= write_addr_i((write_grant_index + 1) * g_addr_width - 1 downto write_grant_index * g_addr_width);
  ll_write_data_valid <= write_data_i((write_grant_index + 1) * g_data_width - 1); -- MSB    bit
  ll_write_end_of_list<= write_data_i((write_grant_index + 1) * g_data_width - 2); -- MSB -1 bit
  --ll_write_next_addr  <= ll_write_data(g_addr_width - 1 downto 0);
  ll_write_next_addr  <= write_next_addr_i((write_grant_index + 1) * g_addr_width - 1 downto write_grant_index * g_addr_width);
    -- create data and address to be written to memory (both DPRAMs)
  ll_wr_data          <= (others => '0')    when (ll_write_next_ena = '1' ) else ll_write_data;   
  ll_wr_addr          <= ll_write_next_addr when (ll_write_next_ena = '1' ) else ll_write_addr;
--   ll_write_ena        <= (write_grant_vec   (write_grant_index) and write_grant_vec_d0(write_grant_index) and not ll_write_end_of_list) or 
--                          (write_grant_vec_d0(write_grant_index)                                           and     ll_write_end_of_list);
  ll_write_ena        <= (write_grant_vec   (write_grant_index) and write_grant_vec_d0(write_grant_index) and        write_next_addr_valid_i(write_grant_index)) or 
                         (write_grant_vec_d0(write_grant_index)                                           and not    write_next_addr_valid_i(write_grant_index));
  ll_write_next_ena   <=  write_grant_vec_d0(write_grant_index) and write_grant_vec_d1(write_grant_index);
  -- ======= reading (read pump) =======    
  -- address
  ll_free_pck_addr <= free_pck_addr_i((free_pck_grant_index + 1) * g_addr_width - 1 downto free_pck_grant_index * g_addr_width);  
    
  process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then

        free_pck_grant_vec_d0        <= (others => '0' );
        free_pck_grant_vec_d1        <= (others => '0' );
        free_pck_grant_valid         <= '0';
        free_pck_grant_valid_d0      <= '0';
        free_pck_grant_index_d0      <=  0;
        
        write_grant_vec_d0           <= (others => '0' );
        write_grant_vec_d1           <= (others => '0' );
        write_grant_index_d0         <=  0;

      else

        free_pck_grant_vec_d0        <= free_pck_grant_vec;
        free_pck_grant_vec_d1        <= free_pck_grant_vec_d0;   
        free_pck_grant_index_d0      <= free_pck_grant_index;
        free_pck_grant_valid         <= free_pck_request_noempty; -- we always get grant in 1-cycle
        free_pck_grant_valid_d0      <= free_pck_grant_valid;

        write_grant_vec_d0           <= write_grant_vec;
        write_grant_vec_d1           <= write_grant_vec_d0;   
        write_grant_index_d0         <= write_grant_index;


      end if;
    end if;
  end process;

  read_valid: for i in 0 to g_num_ports -1 generate

    free_pck_data(i) <= ll_free_pck_data  when  (free_pck_grant_index_d0 = i) else (others => '0' );

    read_data_valid: swc_ll_read_data_validation
    generic map(
      g_addr_width => g_addr_width,
      g_data_width => g_data_width
    )
    port map(
      clk_i                => clk_i, 
      rst_n_i              => rst_n_i,  

      read_req_i           => free_pck_rd_req_i(i),
      read_req_o           => free_pck_read(i),
      
      read_addr_i          => free_pck_addr_i((i+1)*g_addr_width - 1 downto i*g_addr_width ), 
      read_data_i          => free_pck_data(i),--(g_data_width - 2 downto 0),  
      read_data_valid_i    => free_pck_data(i)(g_data_width - 1), 
      read_data_ready_i    => free_pck_grant_vec_d1(i),  
      
      write_addr_i         => ll_wr_addr, 
      write_data_i         => ll_wr_data,--(g_data_width - 2 downto 0), 
      write_data_valid_i   => ll_wr_data(g_data_width - 1),
      write_data_ready_i   => ll_write_ena, 

      read_data_o          => free_pck_data_o((i+1)*g_data_width - 1 downto i*g_data_width), --free_pck_data_out(i),--(g_data_width - 2 downto 0),
      read_data_valid_o    => free_pck_read_done_o(i)                                        --free_pck_read_done(i)
    );

--    free_pck_data_o     ((i+1)*g_data_width - 1 downto i*g_data_width) <= free_pck_data_out(i)(g_data_width - 1 downto 0);
--    free_pck_data_o     ((i+1)*g_data_width - 1)                       <= free_pck_read_done(i);
--    free_pck_read_done_o(i)                                            <= free_pck_read_done(i);
   end generate;


  ll_free_pck_ena       <= free_pck_grant_valid_d0;

  ll_wr_ena             <= ll_write_ena or ll_write_next_ena;

--   wr_done: for i in 0 to g_num_ports -1 generate
--     write_done_o(i)     <= '1' when ((write_grant_vec_d0(i) = '1'                                 and tmp_write_end_of_list(i) = '1')  or  -- end-of-list, one one write, so write_done faster
--                                      (write_grant_vec_d0(i) = '1' and write_grant_vec_d1(i) = '1' and tmp_write_end_of_list(i) = '0')) else -- normal write, we write two words, it takes longer
--                            '0';   
--   end generate;
  wr_done: for i in 0 to g_num_ports -1 generate
    write_done_o(i)     <= '1' when ((write_grant_vec_d0(i) = '1'                                 and write_next_addr_valid_i(i) = '0')  or  -- end-of-list, one one write, so write_done faster
                                     (write_grant_vec_d0(i) = '1' and write_grant_vec_d1(i) = '1' and write_next_addr_valid_i(i) = '1')) else -- normal write, we write two words, it takes longer
                           '0';   
  end generate;
 
  
end syn;