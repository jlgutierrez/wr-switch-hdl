-------------------------------------------------------------------------------
-- Title      : Lost Pck Deallocator
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_lost_pck_dealloc.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-11-15
-- Last update: 2011-03-15
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- 
--
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
-- 2010-11-15  1.0      mlipinsk Created
-------------------------------------------------------------------------------



library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.swc_swcore_pkg.all;
use work.genram_pkg.all;


entity swc_lost_pck_dealloc is

  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

    ib_force_free_i      : in  std_logic;
    ib_force_free_done_o : out std_logic;
    ib_force_free_pgaddr_i     : in  std_logic_vector(c_swc_page_addr_width - 1 downto 0);

    ob_force_free_i      : in  std_logic;
    ob_force_free_done_o : out std_logic;
    ob_force_free_pgaddr_i     : in  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    
    ll_read_addr_o       : out std_logic_vector(c_swc_page_addr_width -1 downto 0);
    ll_read_data_i       : in std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    ll_read_req_o        : out std_logic;
    ll_read_valid_data_i : in std_logic;
    
    mmu_force_free_o        : out std_logic;
    mmu_force_free_done_i   : in std_logic;
    mmu_force_free_pgaddr_o : out std_logic_vector(c_swc_page_addr_width -1 downto 0)

       
    );

end swc_lost_pck_dealloc;



architecture syn of swc_lost_pck_dealloc is

  type t_state is (S_IDLE, 
                   S_REQ_READ_FIFO,
                   S_READ_FIFO,
                   S_READ_NEXT_PAGE_ADDR,
                   S_FREE_CURRENT_PAGE_ADDR
                       );              
  
  signal state       : t_state;
  
  signal ib_force_free_done : std_logic;
  signal ob_force_free_done : std_logic;
  
  signal fifo_wr            : std_logic;
  signal fifo_data_in       : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  signal fifo_full          : std_logic;
  signal fifo_empty         : std_logic;
  signal fifo_data_out      : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  signal fifo_rd            : std_logic;
  signal fifo_clean         : std_logic;
  
  signal current_page       : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  signal next_page          : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  
  
  signal ll_read_req        : std_logic;    
  signal mmu_force_free     : std_logic;  
  signal ones               : std_logic_vector(c_swc_page_addr_width - 1 downto 0);

  
  
begin  -- syn


  ones <= (others => '1');

  INPUT: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
      
        ib_force_free_done <= '0';
        ob_force_free_done <= '0';
        fifo_wr            <= '0';
        fifo_data_in       <= (others => '0');
        
      else

          -- serve Input request, unless it's already served ( ib_force_free_done = '1')         
          if(ib_force_free_i = '1' and fifo_full = '0' and ib_force_free_done = '0') then
          
            fifo_wr               <= '1';
            fifo_data_in          <= ib_force_free_pgaddr_i;
            ib_force_free_done    <= '1';
            ob_force_free_done    <= '0';
            
          elsif(ob_force_free_done  = '1' and fifo_full = '0') then
  
            fifo_wr               <= '1';           
            fifo_data_in          <= ob_force_free_pgaddr_i;
            ob_force_free_done    <= '1';
            ib_force_free_done    <= '0';
            
          else
            
            fifo_wr               <= '0';  
            fifo_data_in          <= (others => '0');         
            ib_force_free_done    <= '0';
            ob_force_free_done    <= '0';
            
          end if;

      end if;
    end if;
  end process;


U_FIFO: generic_sync_fifo
  generic map(
    g_data_width      => c_swc_page_addr_width,
    g_size      => 16
    )
  port map   (
      clk_i   => clk_i,
      rst_n_i => rst_n_i,

      we_i => fifo_wr,
      d_i      => fifo_data_in,

      rd_i => fifo_rd,
      q_o      => fifo_data_out,

      empty_o  => fifo_empty,
      full_o   => fifo_full,
      count_o  => open
      );


fsm_force_free : process(clk_i, rst_n_i)
 begin
   if rising_edge(clk_i) then
     if(rst_n_i = '0') then
       --================================================
       state                <= S_IDLE;
       fifo_rd              <= '0';
       current_page         <= (others => '0');
       next_page            <= (others => '0');
       
       ll_read_req          <= '0';
       
       mmu_force_free       <= '0';
       --================================================
     else

       -- main finite state machine
       case state is

         when S_IDLE =>
           
           fifo_rd        <= '0';
           mmu_force_free <= '0';
           
           if(fifo_empty = '0') then
           
             fifo_rd <= '1';
             state   <= S_REQ_READ_FIFO;
             
           end if;
         
         when S_REQ_READ_FIFO =>
           
            fifo_rd <= '0';
            state   <= S_READ_FIFO;
        
         when S_READ_FIFO =>
           
            current_page <= fifo_data_out;
            ll_read_req  <= '1';
            state        <= S_READ_NEXT_PAGE_ADDR;
                        
         when S_READ_NEXT_PAGE_ADDR =>

            if(ll_read_valid_data_i = '1') then
            
              ll_read_req    <= '0'; 
              state          <= S_FREE_CURRENT_PAGE_ADDR;
              next_page      <= ll_read_data_i;
              mmu_force_free <= '1';
              
            end if;
         
         when S_FREE_CURRENT_PAGE_ADDR =>
             
            if(mmu_force_free_done_i = '1') then
               
               mmu_force_free <= '0';
               
               if(next_page = ones ) then
                 state  <= S_IDLE;
               else
                 current_page <= next_page;
                 ll_read_req  <= '1';
                 state        <= S_READ_NEXT_PAGE_ADDR;
               end if;
               
             end if;
               
            
         when others =>
           
           state                <= S_IDLE;
           fifo_rd              <= '0';
           current_page         <= (others => '0');
           next_page            <= (others => '0');
           ll_read_req          <= '0';
           mmu_force_free       <= '0';
           
       end case;

     end if;
   end if;
   
 end process;

 ll_read_addr_o  <= current_page;     
 ll_read_req_o   <= ll_read_req;     
  
 mmu_force_free_pgaddr_o <= current_page;
 mmu_force_free_o        <= mmu_force_free;
  
 ib_force_free_done_o    <= ib_force_free_done;
 ob_force_free_done_o    <= ob_force_free_done;

  
end syn;
