-------------------------------------------------------------------------------
-- Title      : Pack packets to memory :)
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_packet_mem.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-08
-- Last update: 2010-10-12
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: Here we enable 'c_swc_num_ports' ports to write and read to/from
-- shared memory. We assume we know the memory page (provided by page 
-- allocator/deallocator, another component).
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- Packets from each port are written/read to/from memory pumps. Each port has 
-- its own write and read pump. The pumps are an intermediate step (buffer) 
-- between port and shared memory (Fucking Big SRAM). Each pump has its own 
-- time slot to access FB SRAM. The time slot is one cycle. The time slot is 
-- granted every 'c_swc_packet_mem_multiply' cycles (regardless it's requested
-- by the pump).
-- 
-- ** writing **
-- 'c_swc_packet_mem_multiply' number of words written to a pump are saved in 
-- FB SRAM (when the access is granted). Writting to a pump can be done 
-- regardless of the time slots granted to the pumps. It can be done as long as
-- the pump's buffer (register of c_swc_packet_mem_multiply words) is not full.
-- Provided data (c_swc_packet_mem_multiply words) is written to  one FB SRAM 
-- word. The address of the word is determined by the provided to the pump 
-- pgaddr (page address, which comes from page allocator) and internal page 
-- address. When the register being filled in currently will be written to the
-- last word of the page, the rd_pageend_o is high indicating that next page
-- needs to be allocated.
--
-- ** reading **
-- similar to writing. there is a register of c_swc_packet_mem_multiply words
-- (ctrl+data) which are read from FB SRAM in the pump's time slot (one cycle).
-- Each word of the register is made available consequtivelly, so first the 
-- LSB word can be read by the port (availability of data is indicated by 
-- rd_drdy_o being set to HIGH. Next word can be requested by setting rd_dreq_i
-- HIGH (while the previous word is read).
-- 
-- If the date which is written to a page by a port does not fill entire 
-- input register (the number is not modulo c_swc_packet_mem_multiply), but
-- the port wants to write next data to new page and save the "not-full-input-reg"
-- in the FB SRAM, e.g. new package is to be saved, then wr_flush_i should be
-- set HIGH, it forces the pump to save "not-entirely-full" input register
-- in FB SRAM during the next time slot for this port
-- 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2010 Tomasz Wlostowski / CERN
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

entity swc_packet_mem is

  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

    ---------------------------------------------------------------------------
    -- Write ports 
    ---------------------------------------------------------------------------
    
    
    ------------------- writing to the shared memory --------------------------
    -- indicates that a port X wants to write page address of the "write" access
    wr_pagereq_i  : in  std_logic_vector(c_swc_num_ports-1 downto 0);
    
    -- indicates the beginning of the package
    wr_pckstart_i : in  std_logic_vector(c_swc_num_ports-1 downto 0);
       
    -- array of pages' addresses to which ports want to write
    wr_pageaddr_i : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
    
    -- indicator that the current page is about to be full (the last FB SRAM word
    -- is being pumped in currently), after ~c_swc_packet_mem_multiply cycles 
    -- from the rising edge of this signal this page will finish
    wr_pageend_o  : out std_logic_vector(c_swc_num_ports -1 downto 0);

    -- array of control data from each port to be written to memoroy
    wr_ctrl_i  : in  std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0);
    
    -- array of data from each port to be written to memory
    wr_data_i  : in  std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
    
    -- data ready - request from each port to write data to port's pump
    wr_drdy_i  : in  std_logic_vector(c_swc_num_ports-1 downto 0);
    
    -- the input register of a pump is full, this means that the pump cannot
    -- be written by the port. As soon as the data which is in the input registet
    -- is written to FB SRAM memory, the signal goes LOW and writing is possible
    wr_full_o  : out std_logic_vector(c_swc_num_ports-1 downto 0);
    
    -- request to write the content of pump's input register to FB SRAM memory, 
    -- thus flash/clean input register of the pump
    wr_flush_i : in  std_logic_vector(c_swc_num_ports-1 downto 0);

    ------------------- reading from the shared memory --------------------------
    -- indicates that a port X wants to write page address of the "read" access
    rd_pagereq_i  : in  std_logic_vector(c_swc_num_ports-1 downto 0);
    
    -- array of pages' addresses from which ports want to read
    rd_pageaddr_i : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
    
    -- indicates that the page being read is about to finish (the last FB SRAM word
    -- is being pumped out currently), after ~c_swc_packet_mem_multiply cycles 
    -- from the rising edge of this signal this page will finish 
    rd_pageend_o  : out std_logic_vector(c_swc_num_ports -1 downto 0);
    
    -- end of the package, new package start-page-address needs to be provided
    -- the best if it is before the last page's word is read 
    rd_pckend_o : out  std_logic_vector(c_swc_num_ports-1 downto 0);

    -- data ready to be read
    rd_drdy_o : out std_logic_vector(c_swc_num_ports -1 downto 0);
    
    -- request next word (ctrl + data) from the pump
    rd_dreq_i      : in  std_logic_vector(c_swc_num_ports -1 downto 0);
    
    rd_sync_read_i : in std_logic_vector(c_swc_num_ports -1 downto 0);
    
    -- data read from the shared memory
    rd_data_o : out std_logic_vector(c_swc_num_ports * c_swc_data_width - 1 downto 0);
    
    -- control data read from the shared memory
    rd_ctrl_o : out std_logic_vector(c_swc_num_ports * c_swc_ctrl_width - 1 downto 0);
    
    
--    pa_free_o              : out  std_logic_vector(c_swc_num_ports -1 downto 0);
--    pa_free_done_i         : in   std_logic_vector(c_swc_num_ports -1 downto 0);
--    pa_free_pgaddr_o       : out  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
    
    write_o               : out  std_logic_vector(c_swc_num_ports - 1 downto 0);
    write_done_i          : in   std_logic_vector(c_swc_num_ports - 1 downto 0);
    write_addr_o          : out  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
    write_data_o          : out  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
    
    read_pump_read_o      : out  std_logic_vector(c_swc_num_ports - 1 downto 0);
    read_pump_read_done_i : in  std_logic_vector(c_swc_num_ports - 1 downto 0);
    read_pump_addr_o      : out  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);

    data_i                : in   std_logic_vector(c_swc_page_addr_width - 1 downto 0)
    
    );
end swc_packet_mem;

architecture rtl of swc_packet_mem is

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

  --  
  subtype t_pump_data_in        is std_logic_vector(c_swc_pump_width-1                             downto 0);
  subtype t_pump_data_out       is std_logic_vector(c_swc_packet_mem_multiply * c_swc_pump_width-1 downto 0);
  subtype t_pump_addr           is std_logic_vector(c_swc_packet_mem_addr_width - 1                downto 0);
  subtype t_pump_page_addr      is std_logic_vector(c_swc_page_addr_width - 1                      downto 0);

  type t_pump_addr_array           is array (c_swc_packet_mem_multiply - 1 downto 0) of t_pump_addr;
  type t_pump_data_in_array        is array (c_swc_packet_mem_multiply - 1 downto 0) of t_pump_data_in;
  type t_pump_data_out_array       is array (c_swc_packet_mem_multiply - 1 downto 0) of t_pump_data_out;
  type t_pump_page_addr_array      is array (c_swc_packet_mem_multiply - 1 downto 0) of t_pump_page_addr;

  ---------------------------------------------------------------------------
  ------------------ arrays consisting of data from all pumps ---------------
  ---------------------------------------------------------------------------  
  -- array of addresses to which each pump wants to write its data (FB SRAM word)
  -- in FB SRAM word (page addr + internal addr)
  -- *Signal inputed to mux*
  signal wr_pump_addr_out : t_pump_addr_array;
  
  -- data pumped in from the ports: array of words (ctrl + data) from all ports
  -- *Signal inputed to mux*
  signal wr_pump_data_in  : t_pump_data_in_array;
  
  -- data outputed by the pump and inputed to FB SRAM,
  -- it consists of c_swc_packet_mem_multiply words (ctrl + data) which
  -- are written to one FB SRAM word, this is array of such FB SRAM words
  -- from all pumps.
  -- *Signal inputed to mux*
  signal wr_pump_data_out : t_pump_data_out_array;
  
  -- write enable coming from each pump, it needs to be synchronozed with
  -- the time slot given to each pump, synch by the pump.
  -- *Signal inputed to mux*
  signal wr_pump_we       : std_logic_vector(c_swc_num_ports-1 downto 0);

  -- indicates address of the next page in the packet, it is written to
  -- a linked list of addresses
  signal wr_pump_ll_data_out    :t_pump_page_addr_array;

  signal wr_pump_ll_addr_out :t_pump_page_addr_array;
  
  signal wr_pump_ll_wr_req_out : std_logic_vector(c_swc_num_ports-1 downto 0);  
  
  signal wr_pump_ll_wr_req_done_in : std_logic_vector(c_swc_num_ports-1 downto 0);  
  ---------------------------------------------------------------------------
  ---------------------- direct input to FB SRAM (muxed)---------------------
  ---------------------------------------------------------------------------
  -- data currently being written to FB SRAM, depending which pump
  -- is granted a time slot
  signal ram_wr_data_muxed : std_logic_vector(c_swc_pump_width * c_swc_packet_mem_multiply - 1 downto 0);
  
  -- address to which the data from the given pump is written
  signal ram_wr_addr_muxed : std_logic_vector(c_swc_packet_mem_addr_width-1 downto 0);
  
  -- write enable
  signal ram_we_muxed      : std_logic;

  
  ---------------------------------------------------------------------------
  ---------------------- direct input to Linked List (muxed) ----------------
  ---------------------------------------------------------------------------

  signal ll_write_i               : std_logic_vector(c_swc_num_ports - 1 downto 0); 
  signal ll_write_done_o          : std_logic_vector(c_swc_num_ports - 1 downto 0); 
  signal ll_write_addr_i          : std_logic_vector(c_swc_page_addr_width * c_swc_num_ports - 1 downto 0); 
  signal ll_write_data_i          : std_logic_vector(c_swc_page_addr_width * c_swc_num_ports - 1 downto 0); 
      
  signal ll_read_pump_read_i      : std_logic_vector(c_swc_num_ports - 1 downto 0); 
  signal ll_read_pump_read_done_o : std_logic_vector(c_swc_num_ports - 1 downto 0); 
  signal ll_read_pump_addr_i      : std_logic_vector(c_swc_page_addr_width * c_swc_num_ports - 1 downto 0); 
   
  ---------------------------------------------------------------------------
  ------------ input to all pumps which is demuxed from FB SRAM -------------
  ---------------------------------------------------------------------------
  -- address of the FB SRAM word which is read from FB SRAM from a given pump
  signal rd_pump_addr_out : t_pump_addr_array;
  
  -- unused
  signal rd_pump_data_in  : t_pump_data_out_array;
  
  -- array of outputs from the pumps to the ports
  
  signal rd_pump_data_out : t_pump_data_in_array;
  
  
  signal rd_pump_ll_addr_out        : t_pump_page_addr_array;
  signal rd_pump_ll_rd_req_out      : std_logic_vector(c_swc_num_ports-1 downto 0); 
  signal rd_pump_ll_rd_req_done_in  : std_logic_vector(c_swc_num_ports-1 downto 0); 
  
  ---------------------------------------------------------------------------
  ------------------------- direct output from FB SRAM ----------------------
  ---------------------------------------------------------------------------  
  -- data (FB SRAM word) read from the FB SRAM and inputted to the pump
  -- which is requesting it
  signal ram_rd_data : std_logic_vector(c_swc_pump_width * c_swc_packet_mem_multiply - 1 downto 0);
  
  -- read address muxed from the array of addresses from all the pumps
  signal ram_rd_addr_muxed : std_logic_vector(c_swc_packet_mem_addr_width-1 downto 0);

  ---------------------------------------------------------------------------
  ------------------------- direct output from Linked List ------------------
  ---------------------------------------------------------------------------  

  signal llist_rd_data : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  
  signal llist_rd_addr_muxed : std_logic_vector(c_swc_page_addr_width-1 downto 0);

  ---------------------------------------------------------------------------
  ------------------------- synchronization of pumps ------------------------
  ---------------------------------------------------------------------------  
  -- produces a strobe indicating the pump to which current time slot for 
  -- for writing is assigned (time slot == one cycle)
  signal sync_sreg    : std_logic_vector(c_swc_packet_mem_multiply-1 downto 0);

  -- produces a strobe indicating the pump to which current time slot for 
  -- for writing is assigned (time slot == one cycle)
  signal sync_sreg_rd : std_logic_vector(c_swc_packet_mem_multiply-1 downto 0);
  
  -- used for multiplexing of data in arrays (write data)
  -- into *_muxed data inputed into FB SRAM.
  -- not necesserely occures in the same time as sync, since e.g. address
  -- may be needed advance, etc
  signal sync_cntr    : integer range 0 to c_swc_packet_mem_multiply-1;
  
  -- used for multiplexing of data in arrays of rd_addr
  -- and  for demultiplexing of data ouputed by FB SRAM to 
  -- arrays inputed to pumps
  -- not necesserely occures in the same time as sync, since e.g. address
  -- may be needed advance, etc 
  signal sync_cntr_rd : integer range 0 to c_swc_packet_mem_multiply-1;


  
begin  -- rtl

  -- managing synchronization of the pumps, so each pump is given one-cycle
  -- time slot in which it can read and write.
  -- the sync_sreg produces a strobe to indicate the timeslot
  -- synch_cntr produces a number indicating pump number to mux/demux data
  sync_gen : process (clk_i, rst_n_i)
  begin  -- process
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        sync_sreg (0)                             <= '1';
        sync_sreg (sync_sreg'length - 1 downto 1) <= (others => '0');
        sync_cntr                                 <= c_swc_packet_mem_multiply-1;
        
        -- ML: BUGFIX ?????????        
        sync_cntr_rd                              <= 1; -- c_swc_packet_mem_multiply-1;
      else
        sync_sreg <= sync_sreg(sync_sreg'length-2 downto 0) & sync_sreg(sync_sreg'length-1);

        if(sync_cntr = c_swc_packet_mem_multiply-1) then
          sync_cntr <= 0;
        else
          sync_cntr <= sync_cntr + 1;
        end if;

        if(sync_cntr_rd = c_swc_packet_mem_multiply-1) then
          sync_cntr_rd <= 0;
        else
          sync_cntr_rd <= sync_cntr_rd + 1;
        end if;

        
      end if;
    end if;
  end process;

  sync_sreg_rd <= sync_sreg;
--  sync_sreg_rd(c_swc_packet_mem_multiply-1 downto 0) <= sync_sreg(1 downto 0) & sync_sreg(c_swc_num_ports-1 downto 2);

  -- producing pump output data
  merge_ctrl_data_wr : for i in 0 to c_swc_num_ports-1 generate
    wr_pump_data_in(i) <= wr_ctrl_i(i * c_swc_ctrl_width + c_swc_ctrl_width - 1 downto i * c_swc_ctrl_width)
                         & wr_data_i(i * c_swc_data_width + c_swc_data_width - 1 downto i * c_swc_data_width);
  end generate merge_ctrl_data_wr;


  ------------------------------------------------------------------------------------------------------------
  -------------------------------------   mutiport memory modul   --------------------------------------------
  ------------------------------------------------------------------------------------------------------------ 

  -- write pump: it saves c_swc_packet_mem_multiply words (ctrl + data) into an input register (regardless 
  -- of the above synch and time slot). As soon as the reg is full (or flush req), it is written to 
  -- FB SRAM (one word). The pump accepts page number of the FB SRAM to which data shall be written.
  -- The pump handles page-internal address. There is one pump for each port.
  gen_write_pumps : for i in 0 to c_swc_num_ports-1 generate
    WRPUMP : swc_packet_mem_write_pump
      port map (
        clk_i               => clk_i,
        rst_n_i             => rst_n_i,
        pgaddr_i            => wr_pageaddr_i(c_swc_page_addr_width * i + c_swc_page_addr_width - 1 downto c_swc_page_addr_width * i),
        pgreq_i             => wr_pagereq_i(i),
        pckstart_i          => wr_pckstart_i(i),
        pgend_o             => wr_pageend_o(i),
        drdy_i              => wr_drdy_i(i),
        full_o              => wr_full_o(i),
        flush_i             => wr_flush_i(i),
        ll_addr_o           => wr_pump_ll_addr_out(i),
        ll_data_o           => wr_pump_ll_data_out(i),
        ll_wr_req_o         => wr_pump_ll_wr_req_out(i),
        ll_wr_done_i        => wr_pump_ll_wr_req_done_in(i),

--        current_page_addr_o => wr_pump_current_page_addr_out(i),
--        next_page_addr_o    => wr_pump_next_page_addr_out(i),
--        next_page_addr_we_o => wr_pump_next_page_addr_we_out(i),
        sync_i              => sync_sreg(i),
        d_i                 => wr_pump_data_in(i),
        q_o                 => wr_pump_data_out(i),
        addr_o              => wr_pump_addr_out(i),
        we_o                => wr_pump_we(i));

  end generate gen_write_pumps;

  -- Muxing of data from each pump (array) into data inputted into FB SRAM.
  -- which data is muxed, depends on the current time slot.
  ram_write_mux : process(sync_cntr, wr_pump_addr_out, wr_pump_data_out, wr_pump_we)
  begin
    if(sync_cntr < c_swc_num_ports) then
      ram_we_muxed      <= wr_pump_we(sync_cntr);
      ram_wr_addr_muxed <= wr_pump_addr_out(sync_cntr);
      ram_wr_data_muxed <= wr_pump_data_out(sync_cntr);
    else
      ram_we_muxed      <= '0';
      ram_wr_data_muxed <= (others => '0');
      ram_wr_addr_muxed <= (others => '0');
    end if;
  end process;

  -- The most important part, the shared memory
  FUCKING_BIG_MEMORY : generic_ssram_dualport_singleclock
    generic map (
      g_width     => c_swc_packet_mem_multiply * c_swc_pump_width,
      g_addr_bits => c_swc_packet_mem_addr_width,
      g_size      => c_swc_packet_mem_size / c_swc_packet_mem_multiply)
    port map (
      clk_i     => clk_i,
      rd_addr_i => ram_rd_addr_muxed,
      wr_addr_i => ram_wr_addr_muxed,
      data_i    => ram_wr_data_muxed,
      wr_en_i   => ram_we_muxed,
      q_o       => ram_rd_data);





  -- read pump: it reads c_swc_packet_mem_multiply words (ctrl + data) from FB SRAM and makes it
  -- available to be read by port (word by wrod, word=ctrl+data). Reading of output register can be 
  -- done regardless of the synch and time slot. As soon as the reg is empty and more reading is 
  -- requested by a port, new FB SRAM word is read 
  -- The pump accepts page number of the FB SRAM from which data shall be read.
  -- The pump handles page-internal address. There is one pump for each port.

  gen_read_pumps : for i in 0 to c_swc_num_ports-1 generate
    RDPUMP : swc_packet_mem_read_pump
      port map (
        clk_i               => clk_i,
        rst_n_i             => rst_n_i,
        pgreq_i             => rd_pagereq_i(i),
        pgaddr_i            => rd_pageaddr_i(c_swc_page_addr_width * i + c_swc_page_addr_width - 1 downto c_swc_page_addr_width * i),
        pckend_o            => rd_pckend_o(i),
        pgend_o             => rd_pageend_o(i),
        drdy_o              => rd_drdy_o(i),
        dreq_i              => rd_dreq_i(i),
        sync_read_i         => rd_sync_read_i(i),
        ll_read_addr_o      => rd_pump_ll_addr_out(i),
        ll_read_data_i      => llist_rd_data,
        ll_read_req_o       => rd_pump_ll_rd_req_out(i),
        ll_read_valid_data_i=> rd_pump_ll_rd_req_done_in(i),
        
--        free_o              => pa_free_o(i),
--        free_done_i         => pa_free_done_i(i),
--        free_pgaddr_o       => pa_free_pgaddr_o((i + 1)*c_swc_page_addr_width -1 downto i * c_swc_page_addr_width), 
        
--        current_page_addr_o => rd_pump_current_page_addr_out(i),
--        next_page_addr_i    => llist_rd_data,
        d_o                 => rd_pump_data_out(i),
        sync_i              => sync_sreg_rd(i),
        addr_o              => rd_pump_addr_out(i),
        q_i                 => ram_rd_data);

  end generate gen_read_pumps;


  -- data from the pump to the ports (demux)
  split_ctrl_data_rd : for i in 0 to c_swc_num_ports-1 generate
    rd_ctrl_o(i * c_swc_ctrl_width + c_swc_ctrl_width - 1 downto i * c_swc_ctrl_width) <= rd_pump_data_out(i)(c_swc_data_width + c_swc_ctrl_width -1 downto c_swc_data_width);
    rd_data_o(i * c_swc_data_width + c_swc_data_width - 1 downto i * c_swc_data_width) <= rd_pump_data_out(i)(c_swc_data_width-1 downto 0);
  end generate split_ctrl_data_rd;

  -- muxing read address
  ram_read_mux : process(sync_cntr_rd, rd_pump_addr_out)
  begin
    if(sync_cntr_rd < c_swc_num_ports) then
      ram_rd_addr_muxed <= rd_pump_addr_out(sync_cntr_rd);
    else
      ram_rd_addr_muxed <= (others => '0');
    end if;
  end process;

  ------------------------------------------------------------------------------------------------------------
  -------------------------------------     linkded list modul    --------------------------------------------
  ------------------------------------------------------------------------------------------------------------ 

--  llist_write_mux : process(sync_cntr,wr_pump_next_page_addr_we_out , wr_pump_current_page_addr_out, wr_pump_next_page_addr_out)
--  begin
--    if(sync_cntr < c_swc_num_ports) then
--      llist_we_muxed      <= wr_pump_next_page_addr_we_out(sync_cntr);
--      llist_wr_addr_muxed <= wr_pump_current_page_addr_out(sync_cntr);
--      llist_wr_data_muxed <= wr_pump_next_page_addr_out(sync_cntr);
--    else
--      llist_we_muxed      <= '0';
--      llist_wr_data_muxed <= (others => '0');
--      llist_wr_addr_muxed <= (others => '0');
--    end if;
--  end process;
--
--  -- muxing read address
--  llist_read_mux : process(sync_cntr_rd, wr_pump_current_page_addr_out)
--  begin
--    if(sync_cntr_rd < c_swc_num_ports) then
--      llist_rd_addr_muxed <= rd_pump_current_page_addr_out(sync_cntr_rd);
--    else
--      llist_rd_addr_muxed <= (others => '0');
--    end if;
--  end process;
--
--  -- The most important part, the shared memory
--  PAGE_INDEX_LINKED_LIST : generic_ssram_dualport_singleclock
--    generic map (
--      g_width     => c_swc_page_addr_width,
--      g_addr_bits => c_swc_page_addr_width,
--      g_size      => c_swc_packet_mem_size / c_swc_packet_mem_multiply)
--    port map (
--      clk_i     => clk_i,
--      rd_addr_i => llist_rd_addr_muxed,
--      wr_addr_i => llist_wr_addr_muxed,
--      data_i    => llist_wr_data_muxed, 
--      wr_en_i   => llist_we_muxed ,
--      q_o       => llist_rd_data);


  linked_list_data : for i in 0 to c_swc_num_ports-1 generate
    ll_write_addr_i    (i* c_swc_page_addr_width + c_swc_page_addr_width - 1 downto i * c_swc_page_addr_width) <= wr_pump_ll_addr_out(i);
    ll_write_data_i    (i* c_swc_page_addr_width + c_swc_page_addr_width - 1 downto i * c_swc_page_addr_width) <= wr_pump_ll_data_out(i);
    ll_read_pump_addr_i(i* c_swc_page_addr_width + c_swc_page_addr_width - 1 downto i * c_swc_page_addr_width) <= rd_pump_ll_addr_out(i);
  end generate linked_list_data;

  ll_read_pump_read_i       <= rd_pump_ll_rd_req_out;
  rd_pump_ll_rd_req_done_in <= ll_read_pump_read_done_o;
  
  ll_write_i                <= wr_pump_ll_wr_req_out;
  wr_pump_ll_wr_req_done_in <= ll_write_done_o;
  
--  LINKED_LIST : swc_multiport_linked_list
--    port map (
--      rst_n_i               => rst_n_i,
--      clk_i                 => clk_i,
--      
--      -- IF with write pump
--      write_i               => ll_write_i,
--      write_done_o          => ll_write_done_o,
--      write_addr_i          => ll_write_addr_i,
--      write_data_i          => ll_write_data_i,
--      
--      -- IF with page allocator      
--      free_i                => (others =>'0'),
--      free_done_o           =>  open,
--      free_addr_i           => (others =>'0'),
--
--      -- IF with read pump      
--      read_pump_read_i      => ll_read_pump_read_i,
--      read_pump_read_done_o => ll_read_pump_read_done_o,
--      read_pump_addr_i      => ll_read_pump_addr_i,
--
--      -- IF with Lost Pck Dealloc (LPD)     
--      free_pck_read_i       => (others =>'0'),
--      free_pck_read_done_o  =>  open,
--      free_pck_addr_i       => (others =>'0'),
--
--      -- output data for all reads
--      data_o                => llist_rd_data
--      );

   -------------------------------------------------
   -- Interface with Linked List
   -- [a bit strange naming due to the fact that
   -- the LL module was initialy inside packet_mem]
   ------------------------------------------------
   write_o               <= ll_write_i;
   write_addr_o          <= ll_write_addr_i;
   write_data_o          <= ll_write_data_i;
   
   read_pump_read_o      <= ll_read_pump_read_i;
   read_pump_addr_o      <= ll_read_pump_addr_i;

   -- output data for all reads
   
   ll_read_pump_read_done_o <= read_pump_read_done_i;
   ll_write_done_o          <= write_done_i;
   llist_rd_data            <= data_i ;


end rtl;
