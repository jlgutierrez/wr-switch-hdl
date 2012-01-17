-------------------------------------------------------------------------------
-- Title      : multiport linked list
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_multiport_linked_list.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-20-26
-- Last update: 2010-20-26
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

-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


library work;
use work.swc_swcore_pkg.all;
use work.genram_pkg.all;

entity swc_multiport_linked_list is
  port (
    rst_n_i               : in std_logic;
    clk_i                 : in std_logic;

    write_i               : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
    free_i                : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
    read_pump_read_i      : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
    free_pck_read_i       : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
     
    write_done_o          : out std_logic_vector(c_swc_num_ports - 1 downto 0);
    free_done_o           : out std_logic_vector(c_swc_num_ports - 1 downto 0);
    read_pump_read_done_o : out std_logic_vector(c_swc_num_ports - 1 downto 0);
    free_pck_read_done_o  : out std_logic_vector(c_swc_num_ports - 1 downto 0);

    read_pump_addr_i      : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
    free_pck_addr_i       : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);

    write_addr_i          : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
    free_addr_i           : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
    write_data_i          : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
    
    data_o                : out  std_logic_vector(c_swc_page_addr_width - 1 downto 0)

    );

end swc_multiport_linked_list;

architecture syn of swc_multiport_linked_list is


   component generic_ssram_dualport_singleclock
     generic (
       g_width     : natural;
       g_addr_bits : natural;
       g_size      : natural);
     port (
       data_i    : in  std_logic_vector (g_width-1 downto 0);
       clk_i     : in  std_logic;
       rd_addr_i : in  std_logic_vector (g_addr_bits-1 downto 0);
       wr_addr_i : in  std_logic_vector (g_addr_bits-1 downto 0);
       wr_en_i   : in  std_logic := '1';
       q_o       : out std_logic_vector (g_width-1 downto 0));
   end component;
  
  
  signal ll_write_enable   : std_logic;
  
  -- not needed for the SSRAM, needed for the valid/done signal 
  signal ll_read_enable    : std_logic;
  
  signal ll_write_addr     : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  signal ll_free_addr      : std_logic_vector(c_swc_page_addr_width - 1 downto 0);

  signal ll_wr_addr        : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  signal ll_rd_addr        : std_logic_vector(c_swc_page_addr_width - 1 downto 0);

  signal ll_read_pump_addr : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  signal ll_free_pck_addr  : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  signal ll_write_data     : std_logic_vector(c_swc_page_addr_width -1 downto 0);
  signal ll_read_data      : std_logic_vector(c_swc_page_addr_width -1 downto 0);

  signal ll_wr_data      : std_logic_vector(c_swc_page_addr_width -1 downto 0);

  signal write_request_vec   : std_logic_vector(c_swc_num_ports*2-1 downto 0);

  signal read_request_vec    : std_logic_vector(c_swc_num_ports*2-1 downto 0);
  
  signal write_request_grant : std_logic_vector(4 downto 0);

  signal read_request_grant  : std_logic_vector(4 downto 0);
  

  -- indicates that the granted request is valid
  signal write_request_grant_valid : std_logic;
  signal read_request_grant_valid  : std_logic;
  

  -- the number of the port to which request has been granted
  signal in_sel_write              : integer range 0 to c_swc_num_ports-1;
  signal in_sel_read               : integer range 0 to c_swc_num_ports-1;

  signal write_done_feedback : std_logic_vector(c_swc_num_ports-1 downto 0);
  signal write_done          : std_logic_vector(c_swc_num_ports-1 downto 0);

  -- indicates that an free has been performed successfully for the 
  -- given port. Used to prevent considering the currently process
  -- port for request to RR arbiter
  signal free_done_feedback  : std_logic_vector(c_swc_num_ports-1 downto 0);
  signal free_done           : std_logic_vector(c_swc_num_ports-1 downto 0);



  signal read_pump_read_done_feedback  : std_logic_vector(c_swc_num_ports-1 downto 0);
  signal read_pump_read_done           : std_logic_vector(c_swc_num_ports-1 downto 0);


  signal free_pck_read_done_feedback  : std_logic_vector(c_swc_num_ports-1 downto 0);
  signal free_pck_read_done           : std_logic_vector(c_swc_num_ports-1 downto 0);

  signal ram_zeros                 : std_logic_vector( c_swc_page_addr_width - 1 downto 0);
  signal ram_ones                  : std_logic_vector((c_swc_page_addr_width+7)/8 - 1 downto 0);
  
begin  -- syn


  ram_zeros <=(others => '0');
  ram_ones  <=(others => '1');

--    PAGE_INDEX_LINKED_LIST : generic_ssram_dualport_singleclock
--      generic map (
--        g_width     => c_swc_page_addr_width,
--        g_addr_bits => c_swc_page_addr_width,
--        g_size      => c_swc_packet_mem_num_pages --c_swc_packet_mem_size / c_swc_packet_mem_multiply
--        )
--      port map (
--        clk_i     => clk_i,
--        rd_addr_i => ll_rd_addr,
--        wr_addr_i => ll_wr_addr,
--        data_i    => ll_wr_data, 
--        wr_en_i   => ll_write_enable ,
--        q_o       => ll_read_data);


   PAGE_INDEX_LINKED_LIST : generic_dpram
     generic map (
       g_data_width  => c_swc_page_addr_width,
       g_size        => c_swc_packet_mem_num_pages
                 )
     port map (
       -- Port A -- writing
       clka_i => clk_i,
       bwea_i => ram_ones,
       wea_i  => ll_write_enable,
       aa_i   => ll_wr_addr,
       da_i   => ll_wr_data,
       qa_o   => open,   
 
       -- Port B  -- reading
       clkb_i => clk_i,
       bweb_i => ram_ones, 
       web_i  => '0',
       ab_i   => ll_rd_addr,
       db_i   => ram_zeros,
       qb_o   => ll_read_data
       );


  gen_write_request_vec : for i in 0 to c_swc_num_ports - 1 generate
    write_request_vec(2 * i + 0) <= write_i(i) and (not (write_done_feedback(i) or write_done(i)));
    write_request_vec(2 * i + 1) <= free_i(i)  and (not (free_done_feedback(i)  or free_done(i)));
  end generate gen_write_request_vec;

  gen_read_request_vec : for i in 0 to c_swc_num_ports - 1 generate
    read_request_vec(2 * i + 0) <= read_pump_read_i(i) and (not (read_pump_read_done_feedback(i) or read_pump_read_done(i)));
    read_request_vec(2 * i + 1) <= free_pck_read_i(i)  and (not (free_pck_read_done_feedback(i)  or free_pck_read_done(i)));
  end generate gen_read_request_vec;

  -- Round Robin arbiter, quite specific for the usage, since it has the "next" 
  -- input. It is used to start processing next request well in advance, to prevent
  -- unnecessary delays
  WRITE_ARB : swc_rr_arbiter
    generic map (
      g_num_ports      => c_swc_num_ports * 2,
      g_num_ports_log2 => 5)
    port map (
      clk_i         => clk_i,
      rst_n_i       => rst_n_i,
      next_i        => '1',
      request_i     => write_request_vec,
      grant_o       => write_request_grant,
      grant_valid_o => write_request_grant_valid);

  READ_ARB : swc_rr_arbiter
    generic map (
      g_num_ports      => c_swc_num_ports * 2,
      g_num_ports_log2 => 5
      )
    port map (
      clk_i         => clk_i,
      rst_n_i       => rst_n_i,
      next_i        => '1',
      request_i     => read_request_vec,
      grant_o       => read_request_grant,
      grant_valid_o => read_request_grant_valid);


  -- port number to which request has been granted.
  in_sel_write <= to_integer(unsigned(write_request_grant(write_request_grant'length-1 downto 1)));
  in_sel_read  <= to_integer(unsigned( read_request_grant( read_request_grant'length-1 downto 1)));
  

  ll_write_enable       <= write_request_grant_valid;
  ll_read_enable       <= read_request_grant_valid;
  data_o                <= ll_read_data;

  -- Getting the address of the page we want to free
  
  -- ======= writing =======
  -- data
  ll_write_data     <= write_data_i(in_sel_write * c_swc_page_addr_width + c_swc_page_addr_width - 1 downto in_sel_write * c_swc_page_addr_width);
  ll_wr_data        <= ll_write_data     when (write_request_grant(0) = '0') else (others=>'1');
    
  -- address
  ll_write_addr     <= write_addr_i(in_sel_write * c_swc_page_addr_width + c_swc_page_addr_width - 1 downto in_sel_write * c_swc_page_addr_width);
  ll_free_addr      <= free_addr_i (in_sel_write * c_swc_page_addr_width + c_swc_page_addr_width - 1 downto in_sel_write * c_swc_page_addr_width);
  ll_wr_addr        <= ll_write_addr     when (write_request_grant(0) = '0') else ll_free_addr;

  -- ======= reading =======    
  -- address
  ll_read_pump_addr <= read_pump_addr_i(in_sel_read * c_swc_page_addr_width + c_swc_page_addr_width - 1 downto in_sel_read * c_swc_page_addr_width);  
  ll_free_pck_addr  <= free_pck_addr_i (in_sel_read * c_swc_page_addr_width + c_swc_page_addr_width - 1 downto in_sel_read * c_swc_page_addr_width);  
  ll_rd_addr        <= ll_read_pump_addr when ( read_request_grant(0) = '0') else ll_free_pck_addr;
  
  process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        write_done_feedback           <= (others => '0');
        free_done_feedback            <= (others => '0');
        read_pump_read_done_feedback  <= (others => '0');
        free_pck_read_done_feedback   <= (others => '0');
      else

        -- recognizing on which port the allocation/deallocation/freeing process
        -- is about to finish. It's solely for request vector composition purpose
        for i in 0 to c_swc_num_ports-1 loop
          if(ll_write_enable = '1' and (in_sel_write = i)) then
          --if(in_sel_write = i) then
          
            write_done_feedback(i)          <= not write_request_grant(0);   
            free_done_feedback(i)           <= write_request_grant(0);   

          else
            
            write_done_feedback(i)          <= '0';
            free_done_feedback(i)           <= '0';
            
          end if;
        end loop;  -- i

        for i in 0 to c_swc_num_ports-1 loop
          if(ll_read_enable = '1' and (in_sel_read = i)) then
          --if(in_sel_read = i) then
          
            read_pump_read_done_feedback(i) <= not read_request_grant(0);   
            free_pck_read_done_feedback(i)  <= read_request_grant(0);   
 
          else

            read_pump_read_done_feedback(i) <= '0';
            free_pck_read_done_feedback(i)  <= '0';
            
          end if;
        end loop;  -- i

        write_done          <= write_done_feedback;
        free_done           <= free_done_feedback;
        read_pump_read_done <= read_pump_read_done_feedback;
        free_pck_read_done  <= free_pck_read_done_feedback;
        
      end if;
    end if;
  end process;

  write_done_o          <= write_done_feedback;
  free_done_o           <= free_done_feedback;
  read_pump_read_done_o <= read_pump_read_done_feedback;
  free_pck_read_done_o  <= free_pck_read_done_feedback;

  
end syn;