-------------------------------------------------------------------------------
-- Title      : Memory Read Pump
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_packet_mem_read_pump.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-08
-- Last update: 2010-10-12
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: This piece of code reads a bunch ('c_swc_packet_mem_multiply'
-- of words = ctrl + data) from the FUCKING BIG SRAM and makes it available
-- for read by port. There is one read_pump for each port. Each pump has its
-- time slot to read from FB SRAM. 
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- Detailed description: 
-- the thing works in the following way:
-- 1) it takes the address (FB SRAM addr) of the page
-- 2) it reads it in its time slot which is one cycle every 
--    c_swc_packet_mem_multiply cycles
-- 3) it makes it available on its output (d_o) word by word (in number of
--    c_swc_packet_mem_multiply words, this is how many words is saved in 
--    on FB SRAM word)
-- 4) it announces it with 'drdy_o' HIGH
-- 5) the next word is available after setting dreq_i high
--
-- 
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
-- 2010-10-12  1.1      mlipinsk comments added !!!!!
-------------------------------------------------------------------------------



library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.swc_swcore_pkg.all;

entity swc_packet_mem_read_pump is

  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

    -- Next page address input strobe (active HI) - loads internal
    -- memory address register with the address of new page
    pgreq_i  : in  std_logic;
    
    -- Next page address input (from page allocator)
    pgaddr_i : in  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    
    -- end of package
    pckend_o : out std_logic;
    
    -- HI indicates that current page is done, and that the parent entity must
    -- select another page in following clock cycles (c_swc_packet_mem_multiply
    -- 2) if it wants to write more data into the memory
    
    -- ML: BUG : it's assigned directly to the output, that sucks, it should be
    --           done through register, I presume    
    pgend_o  : out std_logic;

    -- data ready to be read by the host entity
    drdy_o : out std_logic;
    
    -- data request (request next word)
    dreq_i : in  std_logic;
    
    -- used to synchronize first read attempt with synch, 
    -- in other words, it tells the read_pump that this is the
    -- first attempt to read, and the data that is now availabel (some rubbish)
    -- is not interesting for us, so itm (reg_out) does not need to be read to 
    -- the end
    -- to be HIGH during first cycle of dreq_i HIGH (and also most often preq_i)
    sync_read_i : in std_logic;
    
    -- address in LL SRAM which corresponds to the page address
    --current_page_addr_o : out std_logic_vector(c_swc_page_addr_width -1 downto 0);
    ll_read_addr_o : out std_logic_vector(c_swc_page_addr_width -1 downto 0);

    -- data output for LL SRAM - it is the address of the next page or 0xF...F
    -- if this is the last page of the package
    --next_page_addr_i    : in std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    ll_read_data_i    : in std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    
    ll_read_req_o : out std_logic;
    
    ll_read_valid_data_i : in std_logic;
   
    -- the data we want: one word= ctrl+data
    d_o    : out std_logic_vector(c_swc_pump_width - 1 downto 0);

    -- strobe indicating the time slot for this pump
    sync_i : in  std_logic;
    
    -- address in FB SRAM from which the FB SRAM word ( c_swc_packet_mem_multiply 
    -- of words=ctrl+data) is to be read in the pump's time slot
    --------------
    -- IMPORTANT :
    --------------
    -- this address output needs to be multiplexed so that it is 'visible' by
    -- FBSRAM during the pump's time slot (sync_i is HIGH). It means that 
    -- the timeslot for reading addr_o by multiplexer is one cycle before sync_i !!!
    addr_o : out std_logic_vector(c_swc_packet_mem_addr_width - 1 downto 0);
    
    -- data read from FB SRAM 
    q_i    : in  std_logic_vector(c_swc_pump_width * c_swc_packet_mem_multiply -1 downto 0)
    );

end swc_packet_mem_read_pump;



architecture syn of swc_packet_mem_read_pump is

  -- the register to hold c_swc_packet_mem_multiply words(ctrl+data) read from
  -- one FB SRAM word
  signal out_reg       : t_pump_reg;
  
  -- count the words already read by the host entity
  signal cntr          : unsigned(3 downto 0);
  
  -- some delaying of synch strobe
  signal sync_d0       : std_logic;
  signal sync_d1       : std_logic;
  
  -- out_reg not empty yet,
  signal reg_not_empty : std_logic;
  
  -- all words in the out_reg have been read by the host entity
  signal cntr_full     : std_logic;
  
  -- address to be suplied to FB SRAM, consists of the pgaddr and page-internal address
  signal mem_addr      : std_logic_vector (c_swc_packet_mem_addr_width - 1 downto 0);
  
  -- ... we love VHDL ...
  signal allones       : std_logic_vector(63 downto 0);
  signal zeros         : std_logic_vector(63 downto 0);
  
  -- for the condition needed to increase page-internal address
  signal advance_addr  : std_logic;
  
  -- indicates whether the next FB SRAM word is bo be read and loaded to out_reg
  signal load_out_reg  : std_logic;
  
  -- seems not used ....
 -- signal nothing_read : std_logic;
  
  -- HI indicates that current page is done, and that the parent entity must
  -- select another page in following clock cycles (c_swc_packet_mem_multiply
  -- 2) if it wants to write more data into the memory
  signal pgend        : std_logic;
  
  -- page end
  signal pckend : std_logic;
  
  signal current_page_addr : std_logic_vector(c_swc_page_addr_width - 1 downto 0);

  signal next_page_addr    : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  
  signal ll_read_req       : std_logic;

  signal reading_pck       : std_logic;  
  

  signal read_valid    : std_logic;
  
  signal pgreq_d0      : std_logic;
begin  -- syn

  allones <= (others => '1');
  zeros <= (others => '0');
  
  -- last word from out_reg read
  cntr_full    <= '1' when cntr = to_unsigned(c_swc_packet_mem_multiply-1, cntr'length)                 else '0';
  
  -- reading new FB SRAM word is needed. it happens in the pump's time slot only if :
  -- * out_reg is empty (used in case there is no request to read data from the pump ????)
  -- * the last word from the out_reg has been read and there host entity wants more !!!)
--  load_out_reg <= '1' when sync_i = '1' and (reg_not_empty = '0' or (cntr_full = '1' and dreq_i = '1')) else '0';
  load_out_reg <= '1' when (sync_i = '1' and (reg_not_empty = '0' or (cntr_full = '1' and dreq_i = '1')) and pgreq_d0 = '0' and pgreq_i = '0') else '0';



  process (clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        sync_d1 <= '0';
        sync_d0 <= '0';
        pgreq_d0<= '0';
      else
        sync_d1 <= sync_d0;
        sync_d0 <= sync_i;
        
        pgreq_d0<= pgreq_i;
      end if;
    end if;
  end process;

  process(clk_i, rst_n_i)
  begin

    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        cntr              <= (others => '0');
        reg_not_empty     <= '0';
        mem_addr          <= (others => '0');
        advance_addr      <= '0';
     --   nothing_read      <= '0';
        pgend             <= '0';
        pckend            <= '0';
        current_page_addr <= (others => '0');
        next_page_addr    <= (others => '0');
        ll_read_req       <= '0';
        reading_pck       <= '0';
        read_valid        <= '0';
      else

        if(pgreq_i = '1') then
          -- writing FB SRAM web address which consists of page address and page-internal address
          mem_addr(c_swc_packet_mem_addr_width-1 downto c_swc_page_offset_width) <= pgaddr_i;
          mem_addr(c_swc_page_offset_width-1 downto 0)                           <= (others => '0');
          pgend                                                                  <= '0';
          current_page_addr <= pgaddr_i;
          pckend            <='0';
          reading_pck       <='1';
          
          -----------------------------
          reg_not_empty     <= '0'; -- added by ML
          cntr <= (others=>'0');
          -----------------------------
          
          --ll_read_req       <= '1';
        elsif(sync_d1 = '1' and advance_addr = '1') then
          -- incrementing address inside the same page 
          mem_addr(c_swc_page_offset_width-1 downto 0) <= std_logic_vector(unsigned(mem_addr(c_swc_page_offset_width-1 downto 0)) + 1);

          -- we are approaching the end of current page. Inform the host entity some
          -- cycles in advance.
          advance_addr <= '0';
          if(mem_addr(c_swc_page_offset_width-1 downto 0) = allones(c_swc_page_offset_width-1 downto 0)) then
            
            if(next_page_addr = allones(c_swc_page_addr_width - 1 downto 0)) then
              pckend <= '1';
              reading_pck <= '0';
            else
              mem_addr(c_swc_packet_mem_addr_width-1 downto c_swc_page_offset_width) <= next_page_addr;
              mem_addr(c_swc_page_offset_width-1 downto 0)                           <= (others => '0');
            end if;
            pgend <= '1';
          end if;
          
          if(mem_addr(c_swc_page_offset_width-1 downto 0) = zeros(c_swc_page_offset_width-1 downto 0)) then
            current_page_addr <= mem_addr(c_swc_packet_mem_addr_width-1 downto c_swc_page_offset_width);
            pgend <= '0';
            
            -- start requesting next address
            if(reading_pck = '1') then
              ll_read_req  <= '1';
            end if;
            
          end if;
        end if;

        -- we want to read next FB SRAM word and laod it into out_reg (this s our
        -- time slot
        if(load_out_reg = '1' and pckend = '0') then
          reg_not_empty <= '1';
          advance_addr  <= '1';
          

--          next_page_addr <= next_page_addr_i;


          for i in 0 to c_swc_packet_mem_multiply-1 loop
            -- reading the word and putting it into out_reg array
            out_reg (i) <= q_i(c_swc_pump_width * (i+1) - 1 downto c_swc_pump_width * i);
          end loop;

        -- we read all the words from out_reg, we want more but it's not
        -- our time slot yet, so we indicate with reg_not_empty that
        -- in the next time slot read from FB SRAM should be done
        elsif(sync_i = '0' and cntr_full = '1' and dreq_i = '1') then
          reg_not_empty <= '0';
        end if;

        -- request for the next word from out_reg, increment the counter
        if(dreq_i = '1' and reg_not_empty = '1') then
        
          if(sync_read_i = '1') then
            reg_not_empty <= '0';
            cntr <= (others=>'0');
          else
            cntr <= cntr + 1;  
          end if;
        
          
         
          -- we don't load new stuff from the FB SRAM, so 
          -- this is normal situation, this means that
          -- the currently available word has been read and
          -- we want to provide new word to the outside word
          -- so we shift  right the words in the array
          if(load_out_reg = '0') then
            for i in 1 to c_swc_packet_mem_multiply-1 loop
              out_reg (i-1) <= out_reg(i);
            end loop;
            out_reg(c_swc_packet_mem_multiply-1) <= (others => 'X');
          end if;
        end if;
        
        if(ll_read_valid_data_i = '1' ) then
          next_page_addr <= ll_read_data_i;
          ll_read_req  <= '0';
        end if;
        

        if(dreq_i = '1' and reg_not_empty = '1' and load_out_reg = '0') then  
          read_valid <= '1';
        elsif(load_out_reg = '1' and pckend = '0') then 
          read_valid <= '1';
        else
          read_valid <= '0';
        end if;
 
        
      end if;
    end if;

  end process;


  drdy_o              <= reg_not_empty and read_valid;
  addr_o              <= mem_addr;
  d_o                 <= out_reg (0);
  pgend_o             <= pgend;
  pckend_o            <= pckend;
  ll_read_addr_o      <= current_page_addr; -- current_page_addr_o <= current_page_addr;
  ll_read_req_o       <= ll_read_req;

  
end syn;
