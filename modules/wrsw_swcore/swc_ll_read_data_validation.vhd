-------------------------------------------------------------------------------
-- Title      : Linked List read-data validation
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_ll_read_data_validation.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2012-01-30
-- Last update: 2012-01-30
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: This module scans (on the fly) the data that is read from the
-- Linked List, if the valid bit is not HIGH (meaning that the process of 
-- writing the page, on the input, has not been finished yet), it will supperss
-- the output until the valid input is received. This module will hook on the 
-- input to the DPRAM and wait for appripriate write. The required info (data) 
-- will be read directly from the DPRAM write request -- it means that no read
-- from DPRAM is required. In this way, any reading requiest to the LinkedList
-- requires always only single read access to the DPRAM, even if the read data
-- is not valid yet.
-- This is necessary for cut-through implementation in which the reading process
-- can overtake the writting process.
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 CERN / BE-CO-HT
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
-- 2012-01-30  1.0      mlipinsk Created
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


library work;
use work.swc_swcore_pkg.all;
use work.genram_pkg.all;

entity swc_ll_read_data_validation is
  generic(
     g_addr_width : integer ;--:= c_swc_page_addr_width;
     g_data_width : integer --:= c_swc_page_addr_width
  );
  port(
     clk_i                 : in std_logic;
     rst_n_i               : in std_logic;

     -- read request to the LinkedList
     read_req_i            : in std_logic;
     -- read request to the RR Arbiter (it is suppressed by this module after
     -- any read (valid or not) was done. While the request to the Linked List
     -- shall be HIGH until valid data was outputed and read_done HIGH
     read_req_o            : out std_logic;

     -- data read from the Linked List DPRAM
     read_addr_i           : in std_logic_vector(g_addr_width - 1 downto 0);
     read_data_i           : in std_logic_vector(g_data_width - 1 downto 0);
     read_data_valid_i     : in std_logic;
     read_data_ready_i     : in std_logic;
     
     -- data being written to DPRAM
     write_addr_i          : in std_logic_vector(g_addr_width - 1 downto 0);
     write_data_i          : in std_logic_vector(g_data_width - 1 downto 0);
     write_data_valid_i    : in std_logic;
     write_data_ready_i    : in std_logic;

     -- data read from multiport_linked_list module
     read_data_o          : out std_logic_vector(g_data_width - 1 downto 0);
     read_data_valid_o    : out std_logic
     
  );
  end swc_ll_read_data_validation;

architecture syn of swc_ll_read_data_validation is

  signal valid_data_read       : std_logic; -- data read from the DPRAM is valid (page address written)
  signal nonvalid_data_read    : std_logic; -- data in DPRAM is not valid (the page is being written to)
  signal valid_data_write      : std_logic; -- valid data is being written to the address we are hooked to
  signal valid_data_write_d0   : std_logic; 
  signal wait_valid_data_write : std_logic; -- HIGH after a non-valid data was read,
  signal mask_read_req         : std_logic; -- masks the request to the RR Rabiter which governs
                                            -- the access to DPRAM 
  signal  write_data_d0        : std_logic_vector(g_data_width - 1 downto 0);
begin 

  -- the data being read from the Linked List DPRAM is valid,so we just need to pass it
  valid_data_read     <= '1' when (read_data_ready_i = '1' and read_data_valid_i = '1') else '0';
  
  -- the data being read from the Linked List DPRAM is not valid (it means that data is still 
  -- being written under the  indicated address), this is the case for this module
  nonvalid_data_read  <= '1' when (read_data_ready_i = '1' and read_data_valid_i = '0') else '0';
  
  -- the data being written to the Linked List DPRAM is what we are wating for and it's valid.
  valid_data_write    <= '1' when (read_addr_i = write_addr_i and write_data_valid_i = '1' and write_data_ready_i = '1') else '0';

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        
        wait_valid_data_write <= '0';
        mask_read_req         <= '1';
        valid_data_write_d0   <= '0';
        write_data_d0         <= (others =>'0' );

      else
        
        write_data_d0       <= write_data_i;
        valid_data_write_d0 <= valid_data_write;
        
        if(nonvalid_data_read  = '1' and 
           valid_data_write    = '0' and valid_data_write_d0 = '0') then -- suppress the request, so we don't waste 
          mask_read_req  <= '0';                                      -- access time to the DPRAM 
        elsif(valid_data_write = '1' or  
              valid_data_write = '1' or valid_data_write_d0 = '1') then -- at this point, the request (read_req_i) to 
          mask_read_req  <= '1';                                        -- the LL should finish, and we get read for new request
        end if;

        if(nonvalid_data_read = '1' and                                 -- non-valid data was read *and*
           valid_data_write   = '0' and valid_data_write_d0 = '0') then -- the same time (or 1-cyc- before -- this is a write gap)
          wait_valid_data_write  <= '1';                                -- there was no write to the address which is of interest
        elsif(valid_data_write = '1') then                              -- so we need to wait for the proper write
          wait_valid_data_write  <= '0';
        end if;
        
      end if;
    end if;
    
  end process;
 
  read_data_o <= read_data_i   when (valid_data_read  = '1' )                                   else -- normal case, the data being read is valid
                 write_data_i  when (valid_data_write = '1'                                     and  -- the data being written is valid *and* 
                                     (wait_valid_data_write ='1' or nonvalid_data_read = '1' )) else -- we are waiting for valid dta at that address *or*
                                                                                                    -- we are just reading non-valid data
                 write_data_d0 when (valid_data_write_d0 = '1'                                  and  -- there is a 1-cycle gap between writing/reading data *and* 
                                     (wait_valid_data_write ='1' or nonvalid_data_read = '1' )) else -- we are waiting for valid dta at that address *or*
                                                                                                    -- we are just reading non-valid data

                 read_data_i;

  read_data_valid_o <= (valid_data_read                                                        or       -- normal case
                       (valid_data_write    and (wait_valid_data_write or nonvalid_data_read)) or       
                       (valid_data_write_d0 and (wait_valid_data_write or nonvalid_data_read))    ) and -- reading data from LL input
                        read_req_i;                                                                  -- no request, no answer :)
  read_req_o        <=  mask_read_req  and read_req_i;

end syn;
