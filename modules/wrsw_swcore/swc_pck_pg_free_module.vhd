-------------------------------------------------------------------------------
-- Title      : Pck's pages feeing module
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_pck_pg_free_module.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-11-15
-- Last update: 2012-02-02
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
-- 2010-11-16  1.0      mlipinsk Created
-- 2012-02-02  2.0      mlipinsk generic-azed
-------------------------------------------------------------------------------



library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--use work.swc_swcore_pkg.all;
use work.genram_pkg.all;

entity swc_pck_pg_free_module is
  generic( 
    g_page_addr_width       : integer ;--:= c_swc_page_addr_width;
    g_pck_pg_free_fifo_size : integer ;--:= c_swc_freeing_fifo_size
    g_data_width            : integer
    );
  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

    ib_force_free_i         : in  std_logic;
    ib_force_free_done_o    : out std_logic;
    ib_force_free_pgaddr_i  : in  std_logic_vector(g_page_addr_width - 1 downto 0);

    ob_free_i               : in  std_logic;
    ob_free_done_o          : out std_logic;
    ob_free_pgaddr_i        : in  std_logic_vector(g_page_addr_width - 1 downto 0);
    
    ll_read_addr_o          : out std_logic_vector(g_page_addr_width -1 downto 0);
    ll_read_data_i          : in  std_logic_vector(g_data_width     - 1 downto 0);
    ll_read_req_o           : out std_logic;
    ll_read_valid_data_i    : in  std_logic;

    mmu_free_o              : out std_logic;
    mmu_free_done_i         : in  std_logic;
    mmu_free_last_usecnt_i  : in  std_logic;
    mmu_free_pgaddr_o       : out std_logic_vector(g_page_addr_width -1 downto 0);
        
    mmu_force_free_o        : out std_logic;
    mmu_force_free_done_i   : in  std_logic;
    mmu_force_free_pgaddr_o : out std_logic_vector(g_page_addr_width -1 downto 0)

       
    );

end swc_pck_pg_free_module;



architecture syn of swc_pck_pg_free_module is

  type t_state is (S_IDLE, 
                   S_REQ_READ_FIFO,
                   S_READ_FIFO,
                   S_READ_NEXT_PAGE_ADDR,
                   S_FREE_CURRENT_PAGE_ADDR,
                   S_FORCE_FREE_CURRENT_PAGE_ADDR
                   );              
  
  signal state       : t_state;
  
  signal ib_force_free_done : std_logic;
  signal ob_free_done       : std_logic;
  
  signal fifo_wr            : std_logic;
  signal fifo_data_in       : std_logic_vector(g_page_addr_width + 2 - 1 downto 0);
  signal fifo_full          : std_logic;
  signal fifo_empty         : std_logic;
  signal fifo_data_out      : std_logic_vector(g_page_addr_width + 2 - 1 downto 0);
  signal fifo_rd            : std_logic;
  signal fifo_clean         : std_logic;
  
  signal current_page       : std_logic_vector(g_page_addr_width - 1 downto 0);
  signal next_page          : std_logic_vector(g_page_addr_width - 1 downto 0);
  
  
  signal ll_read_req        : std_logic;
    
  signal mmu_force_free     : std_logic;
  signal mmu_free           : std_logic;
  
  signal ones               : std_logic_vector(g_page_addr_width - 1 downto 0);
    
  signal freeing_mode       : std_logic_vector(1 downto 0);
  signal fifo_clear_n : std_logic;
  signal eof : std_logic;
begin  -- syn


  ones <= (others => '1');
  fifo_clean <= not rst_n_i;

  INPUT: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
      
        ib_force_free_done <= '0';
        ob_free_done       <= '0';
        fifo_wr            <= '0';
        fifo_data_in       <= (others => '0');
        
      else

          -- serve Input request, unless it's already served ( ib_force_free_done = '1')         
          if(ib_force_free_i = '1' and fifo_full = '0' and ib_force_free_done = '0') then
          
            fifo_wr                                          <= '1';
            
            fifo_data_in(g_page_addr_width - 1 downto 0) <= ib_force_free_pgaddr_i;
            fifo_data_in(g_page_addr_width)              <= '1';
            fifo_data_in(g_page_addr_width + 1)          <= '0';
            
            ib_force_free_done                               <= '1';
            ob_free_done                                     <= '0';
            
          elsif(ob_free_i  = '1' and fifo_full = '0' and ob_free_done = '0') then
  
            fifo_wr                                          <= '1';           
  
            fifo_data_in(g_page_addr_width - 1 downto 0) <= ob_free_pgaddr_i;
            fifo_data_in(g_page_addr_width)              <= '0';
            fifo_data_in(g_page_addr_width + 1)          <= '1';

            ob_free_done                                     <= '1';
            ib_force_free_done                               <= '0';
            
          else
            
            fifo_wr               <= '0';  
            fifo_data_in          <= (others => '0');         
            ib_force_free_done    <= '0';
            ob_free_done          <= '0';
            
          end if;

      end if;
    end if;
  end process;

  
  fifo_clear_n <= not fifo_clean;

  -- replaced by GenRams component: TW
  U_FIFO: generic_sync_fifo
    generic map (
      g_data_width      => g_page_addr_width + 2,
      g_size      => g_pck_pg_free_fifo_size
      )
    port map (
      rst_n_i        => fifo_clear_n,
      clk_i          => clk_i,
      d_i            => fifo_data_in,
      we_i           => fifo_wr,
      q_o            => fifo_data_out,
      rd_i           => fifo_rd,
      empty_o        => fifo_empty,
      full_o         => fifo_full,
      almost_empty_o => open,
      almost_full_o  => open,
      count_o        => open);
  
 
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
       mmu_free             <= '0';
       freeing_mode         <= (others => '0');
       eof                  <= '0';
       --================================================
     else

       -- main finite state machine
       case state is

         when S_IDLE =>
           
           fifo_rd        <= '0';
           mmu_force_free <= '0';
           mmu_free       <= '0';
           eof            <= '0';
           if(fifo_empty = '0') then
           
             fifo_rd <= '1';
             state   <= S_REQ_READ_FIFO;
             
           end if;
         
         when S_REQ_READ_FIFO =>
           
            fifo_rd <= '0';
            state   <= S_READ_FIFO;
        
         when S_READ_FIFO =>
           
            freeing_mode <= fifo_data_out(g_page_addr_width + 2 - 1 downto g_page_addr_width);
            current_page <= fifo_data_out(g_page_addr_width - 1 downto 0);
            ll_read_req  <= '1';
            state        <= S_READ_NEXT_PAGE_ADDR;
                        
         when S_READ_NEXT_PAGE_ADDR =>

            if(ll_read_valid_data_i = '1') then
            
              ll_read_req    <= '0'; 
              next_page      <= ll_read_data_i(g_page_addr_width-1 downto 0);
              eof            <= ll_read_data_i(g_data_width     -2 );
              -- force free
              if(freeing_mode = b"01") then
                         
                state          <= S_FORCE_FREE_CURRENT_PAGE_ADDR;
                mmu_force_free <= '1';
                
              -- standard free
              elsif(freeing_mode = b"10") then
                
                state          <= S_FREE_CURRENT_PAGE_ADDR;
                mmu_free       <= '1';
                
              else
                
                -- should not get here !!!
                state                <= S_IDLE;
                fifo_rd              <= '0';
                current_page         <= (others => '0');
                next_page            <= (others => '0');
                eof                  <= '0';
                ll_read_req          <= '0';
                mmu_force_free       <= '0';
                freeing_mode         <= (others => '0');
                
              end if;
              
            end if;

         when S_FORCE_FREE_CURRENT_PAGE_ADDR =>
             
            if(mmu_force_free_done_i = '1') then
               
               mmu_force_free <= '0';
               
               --if(next_page = ones ) then
               if(eof = '1') then
                 state  <= S_IDLE;
               else
                 current_page <= next_page;
                 ll_read_req  <= '1';
                 state        <= S_READ_NEXT_PAGE_ADDR;
               end if;
               
             end if;
               
         
         when S_FREE_CURRENT_PAGE_ADDR =>
             
            if(mmu_free_done_i = '1') then
               
               mmu_free <= '0';
                                        
               --if(next_page = ones ) then
               if(eof                    = '1' or     -- end of pck, all pages of this pck freed :)
                  mmu_free_last_usecnt_i = '0') then  -- this means that still more readouts of the
                                                      -- pck is expected, so we just freed the first 
                                                      -- page (therefore decremented the usecnt)
                                                      -- and that's all, we free all the pages of the
                                                      -- pck, only on the last usage
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
           mmu_free             <= '0';
           eof                  <= '0';
       end case;

     end if;
   end if;
   
 end process;

 ll_read_addr_o  <= current_page;     
 ll_read_req_o   <= ll_read_req;     
  
 mmu_force_free_pgaddr_o <= current_page;
 mmu_force_free_o        <= mmu_force_free;
 
 mmu_free_pgaddr_o       <= current_page;
 mmu_free_o              <= mmu_free;
  
 ib_force_free_done_o    <= ib_force_free_done;
 ob_free_done_o          <= ob_free_done;

  
end syn;
