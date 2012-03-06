-------------------------------------------------------------------------------
-- Title      : Routing Table Unit (RTU)
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_rtu.vhd
-- Authors    : Tomasz Wlostowski, Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-27
-- Last update: 2012-01-26
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description: Module takes packet source & destination MAC addresses, VLAN ID
-- and priority priority and decides where and with what final priority (after
-- evalating the per MAC-assigned priorities, per-VLAN priorities, per-port and
-- per-packet), the packet shall be routed. The exact lookup algorithm is described in
-- rtu_sim.c file.
--
-- RTU has c_rtu_num_ports independent request ports which take RTU requests
-- from the endpoints, and c_rtu_num_ports response ports which deliver the routing
-- decisions for requests coming to associated input ports.
--
-- You can assume that RTU requests won't come more often than every 40 refclk2
-- cycles for each port. 
--
-- Since the RTU engine is shared by all ports, the requests are:
-- - scheduled by a round-robin arbiter, so each port gets the same priority
-- - inserted into a common request FIFO
-- - processed by the lookup engine
-- - responses are outputted to response FIFO and delivered into appropriate
--   destination ports.
--
-- RTU has 2 memory blocks:
-- external ZBT memory to store the main MAC table
-- small BRAM block (HCAM) for storage of entries which cause hash collisions in main
--
-- The main MAC table is organized as a
-- bucketed hashtable (see rtu_sim.c for details). Each bucket contains 4 entries:
--
-- addr 0: bucket 0 [entry 1] [entry 2] [entry 3] [entry 4]
-- addr 1: bucket 1 [entry 1] [entry 2] [entry 3] [entry 4]
--
-- If there are more than 4 MAC addresses with the same hash, the last entry in
-- the bucket contains a pointer to CAM memory which stores the remaining MAC
-- entries.
--
-- Both memories (ZBT and HCAM) are split into 2 banks. While one bank is
-- being used by the lookup engine, the other can be accessed from the Wishbone.
-- Bank switching is done by setting appropriate bit in WB control register.
-- RTU has a separate FIFO for writing the memories by the CPU (MFIFO). Each MFIFO
-- entry has 2 fields:
-- - address/data field select bit (determines if A/D field is a new address or
--   data value)
-- - address/data value
-- MFIFO has a separate timeslot for accessing the memory, which is scheduled
-- in the same manner as the input ports.
--
-- For all unrecognized requests RTU should (depending on configuration bit,
-- independently for each port) either drop or broadcast the packet. The
-- request itself is put into a separate FIFO (along with requesting port
-- number) and an interrupt is triggered. CPU parses the request using more sophisticated
-- algorithm and eventually updates the MAC table.
--
-- Aging: There is a separate RAM block ARAM (8192 + some bits for CAM entries), accessible both
-- from the CPU and the Wishbone. Every time matching entry is found, it's
-- corresponding bit is set to 1. CPU reads this table every few seconds and
-- updates the aging counters (aging is not implemented in hardware to make it
-- simpler)
--
-- Additional port configuration bits (needed for RSTP/STP implementation)
-- - LEARN_EN: enable learning on certain port (unrecognized requests go to
--   FIFO) (port is in ENABLED or LEARNING mode)
-- - DROP: drop all the packets regardless of the RTU decision (port is BLOCKING)
-- - PASS_BPDU: enable passing of BPDU packets (port is BLOCKING). BPDUs go to
--   the designated NIC port (ID/mask set in separate register)
--
-- Maciek: if you decide to use CRC-based hash, make the initial hash value & polynomial
-- programmable from Wishbone.
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
-- Date        Version  Author          Description
-- 2010-04-27  1.0      twlostow        Created
-- 2010-05-09  1.1      lipinskimm      added Architecture
-- 2010-05-31  1.2      lipinskimm      first working (known bugs, needs 
--                                      and thorough testing
-------------------------------------------------------------------------------
-- TODO:
-- 1) enable ressing CRC polly from CPU (add reg to wb_rtu)
-- 2) test for different number of ports
-- 3) enable_learning set for each port !!!
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.genram_pkg.all;
use work.wrsw_rtu_private_pkg.all;
use work.wishbone_pkg.all;


entity wrsw_rtu is

  port(
-- clock (62.5 MHz refclk/2)
    clk_sys_i   : in std_logic;
    clk_match_i : in std_logic;
-- reset (synchronous, active low)
    rst_n_i     : in std_logic;

-------------------------------------------------------------------------------
-- N-port RTU input interface (from the endpoint)
-------------------------------------------------------------------------------

-- 1 indicates that coresponding RTU port is idle and ready to accept requests
    rtu_idle_o : out std_logic_vector(c_rtu_num_ports-1 downto 0);

-- request strobe, single HI pulse begins evaluation of the request. All
-- request input lines have to be valid when rq_strobe_p_i is asserted.
    rq_strobe_p_i : in std_logic_vector(c_rtu_num_ports-1 downto 0);

-- source and destination MAC addresses extracted from the packet header
    rq_smac_i : in std_logic_vector(c_wrsw_mac_addr_width * c_rtu_num_ports - 1 downto 0);
    rq_dmac_i : in std_logic_vector(c_wrsw_mac_addr_width * c_rtu_num_ports -1 downto 0);

-- VLAN id (extracted from the header for TRUNK ports and assigned by the port
-- for ACCESS ports)
    rq_vid_i : in std_logic_vector(c_wrsw_vid_width * c_rtu_num_ports - 1 downto 0);

-- HI means that packet has valid assigned a valid VID (low - packet is untagged)
    rq_has_vid_i : in std_logic_vector(c_rtu_num_ports -1 downto 0);

-- packet priority (either extracted from the header or assigned per port).
    rq_prio_i     : in std_logic_vector(c_wrsw_prio_width * c_rtu_num_ports -1 downto 0);
-- HI indicates that packet has assigned priority.
    rq_has_prio_i : in std_logic_vector(c_rtu_num_ports -1 downto 0);

-------------------------------------------------------------------------------
-- N-port RTU output interface (to the packet buffer
-------------------------------------------------------------------------------

-- response strobe. Single HI pulse indicates that a valid response for port N
-- request is available on rsp_dst_port_mask_o, rsp_drop_o and rsp_prio_o.
    rsp_valid_o : out std_logic_vector (c_rtu_num_ports-1 downto 0);

-- destination port mask. HI bits indicate that packet should be routed to
-- the corresponding port(s).
    rsp_dst_port_mask_o : out std_logic_vector(c_wrsw_num_ports * c_rtu_num_ports - 1 downto 0);

-- HI -> packet must be dropped
    rsp_drop_o : out std_logic_vector(c_rtu_num_ports -1 downto 0);

-- Final packet priority (evaluated from port priority, tag priority, VLAN
-- priority or source/destination priority).
    rsp_prio_o         : out std_logic_vector (c_rtu_num_ports * c_wrsw_prio_width-1 downto 0);
-- Acknowledge from endpoin that the data has been read    
    rsp_ack_i          : in  std_logic_vector(c_rtu_num_ports -1 downto 0);
-- indication for the endpoint - says how busy is a port    
    port_almost_full_o : out std_logic_vector(c_rtu_num_ports -1 downto 0);
    port_full_o        : out std_logic_vector(c_rtu_num_ports -1 downto 0);


-------------------------------------------------------------------------------
-- Wishbone (synchronous to refclk2_i). See the wbgen2 file for register details
-------------------------------------------------------------------------------
    wb_addr_i : in  std_logic_vector(13 downto 0);
    wb_data_i : in  std_logic_vector(31 downto 0);
    wb_data_o : out std_logic_vector(31 downto 0);
    wb_sel_i  : in  std_logic_vector(3 downto 0);
    wb_cyc_i  : in  std_logic;
    wb_stb_i  : in  std_logic;
    wb_ack_o  : out std_logic;
    wb_irq_o  : out std_logic;
    wb_we_i   : in  std_logic



    );

end wrsw_rtu;

architecture behavioral of wrsw_rtu is
-------------------------------------------------------------------------------------------------------------------------
--| signals
-------------------------------------------------------------------------------------------------------------------------
  --| REQUEST FIFO
  -- input to request FIFO
  signal s_req_fifo_input    : std_logic_vector(c_rtu_num_ports + c_wrsw_mac_addr_width + c_wrsw_mac_addr_width + c_wrsw_vid_width + c_wrsw_prio_width + 2 - 1 downto 0);
  -- writes request FIFO
  signal s_rq_fifo_write_all : std_logic_vector(c_rtu_num_ports - 1 downto 0);
  signal s_rq_fifo_write_sng : std_logic;
  -- request FIFO is full
  signal s_rq_fifo_full      : std_logic;
  -- data input to request FIFO

  type   t_rq_fifo_data_a is array (c_rtu_num_ports - 1 downto 0) of std_logic_vector(c_wrsw_mac_addr_width + c_wrsw_mac_addr_width + c_wrsw_vid_width + c_wrsw_prio_width + 2 - 1 downto 0);
  signal s_rq_fifo_data_a : t_rq_fifo_data_a;
  signal s_rq_fifo_data   : std_logic_vector(c_wrsw_mac_addr_width + c_wrsw_mac_addr_width + c_wrsw_vid_width + c_wrsw_prio_width + 2 - 1 downto 0);

  -- read request FIFO
  signal s_rq_fifo_read  : std_logic;
  -- request fifo empty
  signal s_rq_fifo_empty : std_logic;

  --| RESPONSE FIFO
  signal s_rsp_fifo_full : std_logic;


  --| RTU ENGINE
  -- request data read by RTU engine from rq_fifo
  signal s_rq_rtu_match_data  : std_logic_vector(c_rtu_num_ports + c_wrsw_mac_addr_width + c_wrsw_mac_addr_width + c_wrsw_vid_width + c_wrsw_prio_width + 2 - 1 downto 0);
  -- response data outputed from RTU to rsp_fifo
  signal s_rsp_rtu_match_data : std_logic_vector(c_rtu_num_ports + c_wrsw_num_ports + c_wrsw_prio_width + 1 - 1 downto 0);



  --| HASH TABLE lookup engine 

  signal s_htab_rr_sel_w : std_logic;
  signal s_htab_rr_sel_r : std_logic;
  signal s_htab_rr_req   : std_logic_vector(1 downto 0);
  signal s_htab_rr_gnt   : std_logic_vector(1 downto 0);

--HTAB interface

  signal s_htab_start : std_logic;
  signal s_htab_ack   : std_logic;
  signal s_htab_hash  : std_logic_vector(c_wrsw_hash_width-1 downto 0);
  signal s_htab_mac   : std_logic_vector(47 downto 0);
  signal s_htab_fid   : std_logic_vector(7 downto 0);
  signal s_htab_found : std_logic;
  signal s_htab_drdy  : std_logic;
  signal s_htab_valid : std_logic;
  signal s_htab_entry : t_rtu_htab_entry;

  signal mfifo_trigger : std_logic;

  --|VLAN TAB
  signal s_vlan_tab_addr : std_logic_vector(11 downto 0);
  signal s_vlan_tab_data : std_logic_vector(31 downto 0);
  signal s_vlan_tab_rd   : std_logic;

  --| MFIFO
  signal s_rtu_mfifo_rd_usedw : std_logic_vector(5 downto 0);
  signal s_rtu_mfifo_rd_empty : std_logic;
  signal s_rtu_mfifo_rd_req   : std_logic;
  signal s_rtu_mfifo_ad_sel   : std_logic;
  signal s_rtu_mfifo_ad_val   : std_logic_vector(31 downto 0);

  -- | UFIFO for learning
  signal s_ufifo_wr_req   : std_logic;
  signal s_ufifo_wr_full  : std_logic;
  signal s_ufifo_wr_empty : std_logic;
  signal s_ufifo_dmac_lo  : std_logic_vector(31 downto 0);
  signal s_ufifo_dmac_hi  : std_logic_vector(15 downto 0);
  signal s_ufifo_smac_lo  : std_logic_vector(31 downto 0);
  signal s_ufifo_smac_hi  : std_logic_vector(15 downto 0);
  signal s_ufifo_vid      : std_logic_vector(11 downto 0);
  signal s_ufifo_prio     : std_logic_vector(2 downto 0);
  signal s_ufifo_pid      : std_logic_vector(3 downto 0);
  signal s_ufifo_has_vid  : std_logic;
  signal s_ufifo_has_prio : std_logic;

  --|IRQ
  signal s_irq_nempty : std_logic;

  --|HCAM - Hash collision memory
  signal s_aram_main_addr   : std_logic_vector(7 downto 0);
  signal s_aram_main_data_i : std_logic_vector(31 downto 0);
  signal s_aram_main_data_o : std_logic_vector(31 downto 0);
  signal s_aram_main_rd     : std_logic;
  signal s_aram_main_wr     : std_logic;

  --| ARG_HCAM - Aging register for HCAM
  signal s_agr_hcam_o    : std_logic_vector(31 downto 0);
  signal s_agr_hcam_i    : std_logic_vector(31 downto 0);
  signal s_agr_hcam_load : std_logic;

  --| CONTROL REGISTERS

  signal gcr_mfifotrig_out  : std_logic;
  signal gcr_mfifotrig_in   : std_logic;
  signal gcr_mfifotrig_load : std_logic;

  signal s_pcr_learn_en  : std_logic_vector(c_wrsw_num_ports_max - 1 downto 0);
  signal s_pcr_pass_all  : std_logic_vector(c_wrsw_num_ports_max - 1 downto 0);
  signal s_pcr_pass_bpdu : std_logic_vector(c_wrsw_num_ports_max - 1 downto 0);
  signal s_pcr_fix_prio  : std_logic_vector(c_wrsw_num_ports_max - 1 downto 0);
  signal s_pcr_prio_val  : std_logic_vector(c_wrsw_num_ports_max  * c_rtu_num_ports - 1 downto 0);
  signal s_pcr_b_unrec   : std_logic_vector(c_wrsw_num_ports_max - 1 downto 0);


  --| RESPONSE FIFO
  -- response FIFO empty
  signal s_rsp_fifo_empty          : std_logic;
  -- response FIFO read data
  type   t_rsp_fifo_data_a is array(c_rtu_num_ports - 1 downto 0) of std_logic_vector(c_wrsw_num_ports + c_wrsw_prio_width + 1 - 1 downto 0);
  signal s_rsp_fifo_data_a         : t_rsp_fifo_data_a;
  signal s_rsp_fifo_data           : std_logic_vector(c_wrsw_num_ports + c_wrsw_prio_width + 1 - 1 downto 0);
  -- output from the response fifo (this is split into s_rsp_fifo_data and s_rsp_fifo_sel)
  signal s_rsp_fifo_output         : std_logic_vector(c_rtu_num_ports + c_wrsw_num_ports + c_wrsw_prio_width + 1 - 1 downto 0);
  -- says which port should read the datase
  signal s_rsp_fifo_sel            : std_logic_vector(c_rtu_num_ports - 1 downto 0);
  -- read response FIFO
  signal s_rsp_fifo_read_all       : std_logic_vector(c_rtu_num_ports - 1 downto 0);
  -- just for zero comparison
  signal s_rsp_fifo_read_all_zeros : std_logic_vector(c_rtu_num_ports - 1 downto 0);
  --signal s_rsp_fifo_read_sng : std_logic;
  signal s_rsp_fifo_read_port      : std_logic;
  signal s_rsp_fifo_read_fifo      : std_logic;
  -- driven by rtu_match
  signal s_rsp_fifo_write          : std_logic;

  signal s_rq_rsp_cnt_dec : std_logic_vector(c_rtu_num_ports - 1 downto 0);

  --| ARBITER TO REQUEST FIFO  
  -- request signals from ports to REQ_FIFO_ARBITER
  signal s_req_fifo_access : std_logic_vector(c_rtu_num_ports - 1 downto 0);
  -- access granted by REQ_FIFO_ARBITER to single port (if '1' access is granted
  signal s_gnt_fifo_access : std_logic_vector(c_rtu_num_ports - 1 downto 0);

  --| GLOBAL CONTROL REG

  -- HT_BSEL : Main table bank select
  -- Selects active bank of RTU hashtable (ZBT).
  -- 0: bank 0 is used by lookup engine and bank 1 can be accessed using MFIFO
  -- 1: bank 1 is used by lookup engine and bank 0 can be accessed using MFIFO 
  signal s_htab_bsel : std_logic;

  -- HCAM_BSEL : Hash collision table (HCAM) bank select
  -- Selects active bank of RTU extra memory for colliding hashes.
  -- 0: bank 0 is used by lookup engine
  -- 1: bank 1 is used by lookup engine 
  signal s_cam_bsel : std_logic;

  -- global enable
  signal s_global_ena : std_logic;

  -- hash polynomial
  signal s_rtu_gcr_poly_input : std_logic_vector(15 downto 0);
  signal s_rtu_gcr_poly_used  : std_logic_vector(15 downto 0);
signal s_rq_fifo_qvalid : std_logic;
  
-------------------------------------------------------------------------------------------------------------------------
begin

  s_irq_nempty <= s_ufifo_wr_empty;

  ---------------------------------------------------------------------------------------------------------------------
  --| REQUEST ROUND ROBIN ARBITER - governs access to REQUEST FIFO
  ---------------------------------------------------------------------------------------------------------------------
  req_fifo_arbiter : wrsw_rr_arbiter
    generic map (
      g_width => c_rtu_num_ports)
    port map(
      clk_i   => clk_sys_i,
      rst_n_i => rst_n_i,
      req_i   => s_req_fifo_access,
      gnt_o   => s_gnt_fifo_access
      );

  ---------------------------------------------------------------------------------------------------------------------
  --| PORTS - c_rtu_num_ports number of I/O ports, a port:
  --| - inputs request to REQUEST FIFO
  --| - waits for the response,
  --| - reads response from RESPONSE FIFO
  ---------------------------------------------------------------------------------------------------------------------
  ports : for i in 0 to (c_rtu_num_ports - 1) generate
    wrsw_port : wrsw_rtu_port
      generic map (
        g_port_index => i)
      port map(
        clk_i               => clk_sys_i,
        rst_n_i             => rst_n_i,
        rtu_gcr_g_ena_i     => s_global_ena,
        rtu_idle_o          => rtu_idle_o(i),
        rq_strobe_p_i       => rq_strobe_p_i(i),
        rq_smac_i           => rq_smac_i((i+1)*c_wrsw_mac_addr_width - 1 downto i*c_wrsw_mac_addr_width),
        rq_dmac_i           => rq_dmac_i((i+1)*c_wrsw_mac_addr_width - 1 downto i*c_wrsw_mac_addr_width),
        rq_vid_i            => rq_vid_i ((i+1)*c_wrsw_vid_width -1 downto i*c_wrsw_vid_width),
        rq_has_vid_i        => rq_has_vid_i(i),
        rq_prio_i           => rq_prio_i ((i+1)*c_wrsw_prio_width - 1 downto i*c_wrsw_prio_width),
        rq_has_prio_i       => rq_has_prio_i(i),
        rsp_valid_o         => rsp_valid_o(i),
        rsp_dst_port_mask_o => rsp_dst_port_mask_o((i+1)*c_wrsw_num_ports - 1 downto i*c_wrsw_num_ports),
        rsp_drop_o          => rsp_drop_o(i),
        rsp_prio_o          => rsp_prio_o((i+1)*c_wrsw_prio_width - 1 downto i*c_wrsw_prio_width),

        -- this goes to the arbiter
        rq_fifo_write_o => s_rq_fifo_write_all(i),

        rq_fifo_full_i => s_rq_fifo_full,
        rq_fifo_data_o => s_rq_fifo_data_a(i),

        rsp_write_i      => s_rsp_fifo_write,
        rsp_match_data_i => s_rsp_rtu_match_data,

        rsp_ack_i              => rsp_ack_i(i),
        rr_request_wr_access_o => s_req_fifo_access(i),
        rr_access_ena_i        => s_gnt_fifo_access(i),
        port_almost_full_o     => port_almost_full_o(i),
        port_full_o            => port_full_o(i),
        rq_rsp_cnt_dec_i       => s_rq_rsp_cnt_dec(i),  -- s_rq_rtu_match_data(i) -- and s_rq_fifo_read
        rtu_pcr_pass_bpdu_i    => s_pcr_pass_bpdu(i),
        rtu_pcr_pass_all_i     => s_pcr_pass_all(i),
        rtu_pcr_fix_prio_i     => s_pcr_fix_prio(i),
        rtu_pcr_prio_val_i     => s_pcr_prio_val((i+1)*c_wrsw_prio_width - 1 downto i*c_wrsw_prio_width)
        );
  end generate;  -- end ports

  ---------------------------------------------------------------------------------------------------------------------
  --| REQUEST FIFO BUS
  --| data from all ports into one match module
  --| 
  ---------------------------------------------------------------------------------------------------------------------

  --req_fifo_input_bus : for i in 0 to (c_rtu_num_ports - 1) generate
  --  s_rq_fifo_data      <= s_rq_fifo_data_a(i)    when(s_gnt_fifo_access(i) = '1') else (others => 'Z');
  --  -- write request from a port which has been granted access to the (match
  --  s_rq_fifo_write_sng <= s_rq_fifo_write_all(i) when(s_gnt_fifo_access(i) = '1') else 'Z';
  --end generate;
  ---- when there is no access granted, write request goes to '0'
  ---- TODO HERE

  --s_rq_fifo_write_sng <= '0' when(s_gnt_fifo_access = s_rsp_fifo_read_all_zeros) else '1';


  p_mux_fifo_req : process(s_rq_fifo_data_a, s_gnt_fifo_access, s_rq_fifo_write_all)
    variable do_wr   : std_logic;
    variable do_data : std_logic_vector(s_rq_fifo_data'left downto 0);
  begin

    do_data := (others => 'X');
    do_wr   := '0';

    if(s_gnt_fifo_access = s_rsp_fifo_read_all_zeros) then
      do_wr := '0';
    else
      for i in 0 to c_rtu_num_ports-1 loop
        if(s_gnt_fifo_access(i) = '1') then
          do_wr := s_rq_fifo_write_all(i);
        end if;
      end loop;  -- i
    end if;

    s_rq_fifo_write_sng <= do_wr;

    for i in 0 to c_rtu_num_ports-1 loop
      if(s_gnt_fifo_access(i) = '1') then
        do_data := s_rq_fifo_data_a(i);
      end if;
    end loop;  -- i

    s_rq_fifo_data <= do_data;
    
  end process;



------------------------
  --| REQUEST FIFO: takes requests from ports and makes it available for RTU MATCH
  ---------------------------------------------------------------------------------------------------------------------
  s_req_fifo_input(c_rtu_num_ports - 1 downto 0)                                                                                                          <= s_gnt_fifo_access;  --s_rsp_fifo_sel; -- we treat it as PORT ID
  s_req_fifo_input(c_rtu_num_ports + c_wrsw_mac_addr_width + c_wrsw_mac_addr_width + c_wrsw_vid_width + c_wrsw_prio_width + 2 - 1 downto c_rtu_num_ports) <= s_rq_fifo_data;

  req_fifo : generic_shiftreg_fifo
    generic map (  -- |request port ID |    destination MAC    |     source MAC        |     VLAN ID      |      PRIORITY     | has_prio | has vid |
      g_data_width             => c_rtu_num_ports + c_wrsw_mac_addr_width + c_wrsw_mac_addr_width + c_wrsw_vid_width + c_wrsw_prio_width + 1 + 1,
      g_size                   => 32
--      g_almost_full_threshold  => 27,
--      g_almost_empty_threshold => 0,
--      g_show_ahead             => true
      )
    port map
    (
      rst_n_i => rst_n_i,
      d_i     => s_req_fifo_input,
      clk_i   => clk_sys_i,
      rd_i    => s_rq_fifo_read,        --rtu_match
      we_i    => s_rq_fifo_write_sng,
      q_o     => s_rq_rtu_match_data,
      q_valid_o => s_rq_fifo_qvalid,
      full_o  => s_rq_fifo_full
      );

  s_rq_fifo_empty <= not s_rq_fifo_qvalid;

  

  ---------------------------------------------------------------------------------------------------------------------
  --| RTU MATCH: Routing Table Unit Engine
  ---------------------------------------------------------------------------------------------------------------------
  -- to be added
  U_Match : wrsw_rtu_match
    port map(

      clk_i             => clk_sys_i,
      rst_n_i           => rst_n_i,
      rq_fifo_read_o    => s_rq_fifo_read,
      rq_fifo_empty_i   => s_rq_fifo_empty,
      rq_fifo_input_i   => s_rq_rtu_match_data,
      rsp_fifo_write_o  => s_rsp_fifo_write,
      rsp_fifo_full_i   => s_rsp_fifo_full,
      rsp_fifo_output_o => s_rsp_rtu_match_data,

      htab_start_o => s_htab_start,
      htab_ack_o   => s_htab_ack,
      htab_found_i => s_htab_found,
      htab_hash_o  => s_htab_hash,
      htab_mac_o   => s_htab_mac,
      htab_fid_o   => s_htab_fid,
      htab_drdy_i  => s_htab_drdy,
      htab_entry_i => s_htab_entry,

      rtu_ufifo_wr_req_o   => s_ufifo_wr_req,
      rtu_ufifo_wr_full_i  => s_ufifo_wr_full,
      rtu_ufifo_wr_empty_i => s_ufifo_wr_empty,
      rtu_ufifo_dmac_lo_o  => s_ufifo_dmac_lo,
      rtu_ufifo_dmac_hi_o  => s_ufifo_dmac_hi,
      rtu_ufifo_smac_lo_o  => s_ufifo_smac_lo,
      rtu_ufifo_smac_hi_o  => s_ufifo_smac_hi,
      rtu_ufifo_vid_o      => s_ufifo_vid,
      rtu_ufifo_prio_o     => s_ufifo_prio,
      rtu_ufifo_pid_o      => s_ufifo_pid,
      rtu_ufifo_has_vid_o  => s_ufifo_has_vid,
      rtu_ufifo_has_prio_o => s_ufifo_has_prio,
      rtu_aram_main_addr_o => s_aram_main_addr,
      rtu_aram_main_data_i => s_aram_main_data_i,
      rtu_aram_main_rd_o   => s_aram_main_rd,
      rtu_aram_main_data_o => s_aram_main_data_o,
      rtu_aram_main_wr_o   => s_aram_main_wr,
      rtu_agr_hcam_i       => s_agr_hcam_i,
      rtu_agr_hcam_o       => s_agr_hcam_o,
      rtu_agr_hcam_load_i  => s_agr_hcam_load,
      rtu_vlan_tab_addr_o  => s_vlan_tab_addr,
      rtu_vlan_tab_data_i  => s_vlan_tab_data,
      rtu_vlan_tab_rd_o    => s_vlan_tab_rd,
      rtu_gcr_g_ena_i      => s_global_ena,
      rtu_pcr_pass_all_i   => s_pcr_pass_all(c_rtu_num_ports - 1 downto 0),
      rtu_pcr_learn_en_i   => s_pcr_learn_en(c_rtu_num_ports - 1 downto 0),
      rtu_pcr_pass_bpdu_i  => s_pcr_pass_bpdu(c_rtu_num_ports - 1 downto 0),
      rtu_pcr_b_unrec_i    => s_pcr_b_unrec(c_rtu_num_ports - 1 downto 0),
      rtu_crc_poly_i       => s_rtu_gcr_poly_used  --x"1021"-- x"0589" -- x"8005" --x"1021" --x"8005", --
--    rtu_rw_bank_i                                => s_vlan_bsel
      );

  s_rtu_gcr_poly_used <= c_default_hash_poly when (s_rtu_gcr_poly_input = x"0000") else s_rtu_gcr_poly_input;

  mfifo_trigger <= gcr_mfifotrig_out and gcr_mfifotrig_load;



  U_Lookup : rtu_lookup_engine
    port map (
      clk_sys_i   => clk_sys_i,
      clk_match_i => clk_sys_i,
      rst_n_i     => rst_n_i,

      mfifo_rd_req_o   => s_rtu_mfifo_rd_req,
      mfifo_rd_empty_i => s_rtu_mfifo_rd_empty,
      mfifo_ad_sel_i   => s_rtu_mfifo_ad_sel,
      mfifo_ad_val_i   => s_rtu_mfifo_ad_val,
      mfifo_trigger_i  => mfifo_trigger,
      mfifo_busy_o     => gcr_mfifotrig_in,

      start_i => s_htab_start,
      ack_i   => s_htab_ack,
      found_o => s_htab_found,
      hash_i  => s_htab_hash,
      mac_i   => s_htab_mac,
      fid_i   => s_htab_fid,
      drdy_o  => s_htab_drdy,
      entry_o => s_htab_entry
      );


  --| WISHBONE I/F: interface with CPU and RAM/CAM

  WB_slave : wrsw_rtu_wb
    port map(
      rst_n_i   => rst_n_i,
      wb_clk_i  => clk_sys_i,
      wb_addr_i => wb_addr_i,
      wb_data_i => wb_data_i,
      wb_data_o => wb_data_o,
      wb_cyc_i  => wb_cyc_i,
      wb_sel_i  => wb_sel_i,
      wb_stb_i  => wb_stb_i,
      wb_we_i   => wb_we_i,
      wb_ack_o  => wb_ack_o,
      wb_irq_o  => wb_irq_o,

      clk_match_i => clk_sys_i,

      rtu_gcr_mfifotrig_o      => gcr_mfifotrig_out,
      rtu_gcr_mfifotrig_i      => gcr_mfifotrig_in,
      rtu_gcr_mfifotrig_load_o => gcr_mfifotrig_load,

      rtu_gcr_g_ena_o      => s_global_ena,
      rtu_gcr_poly_val_o   => s_rtu_gcr_poly_input,
      irq_nempty_i         => s_irq_nempty,  --'1',
      rtu_ufifo_wr_req_i   => s_ufifo_wr_req,
      rtu_ufifo_wr_full_o  => s_ufifo_wr_full,
      rtu_ufifo_wr_empty_o => s_ufifo_wr_empty,
      rtu_ufifo_dmac_lo_i  => s_ufifo_dmac_lo,
      rtu_ufifo_dmac_hi_i  => s_ufifo_dmac_hi,
      rtu_ufifo_smac_lo_i  => s_ufifo_smac_lo,
      rtu_ufifo_smac_hi_i  => s_ufifo_smac_hi,
      rtu_ufifo_vid_i      => s_ufifo_vid,
      rtu_ufifo_prio_i     => s_ufifo_prio,
      rtu_ufifo_pid_i      => s_ufifo_pid,
      rtu_ufifo_has_vid_i  => s_ufifo_has_vid,
      rtu_ufifo_has_prio_i => s_ufifo_has_prio,

      rtu_aram_main_addr_i => s_aram_main_addr,
      rtu_aram_main_data_o => s_aram_main_data_i,
      rtu_aram_main_rd_i   => s_aram_main_rd,
      rtu_aram_main_data_i => s_aram_main_data_o,
      rtu_aram_main_wr_i   => s_aram_main_wr,

      rtu_vlan_tab_addr_i => s_vlan_tab_addr,
      rtu_vlan_tab_data_o => s_vlan_tab_data,
      rtu_vlan_tab_rd_i   => s_vlan_tab_rd,

      rtu_agr_hcam_o       => s_agr_hcam_i,
      rtu_agr_hcam_i       => s_agr_hcam_o,
      rtu_agr_hcam_load_o  => s_agr_hcam_load,
      rtu_mfifo_rd_usedw_o => s_rtu_mfifo_rd_usedw,
      rtu_mfifo_rd_req_i   => s_rtu_mfifo_rd_req,
      rtu_mfifo_rd_empty_o => s_rtu_mfifo_rd_empty,
      rtu_mfifo_ad_sel_o   => s_rtu_mfifo_ad_sel,
      rtu_mfifo_ad_val_o   => s_rtu_mfifo_ad_val,

      rtu_pcr0_learn_en_o  => s_pcr_learn_en(0),
      rtu_pcr0_pass_all_o  => s_pcr_pass_all(0),
      rtu_pcr0_pass_bpdu_o => s_pcr_pass_bpdu(0),
      rtu_pcr0_fix_prio_o  => s_pcr_fix_prio(0),
      rtu_pcr0_prio_val_o  => s_pcr_prio_val(3*0 + 3 - 1 downto 3*0),
      rtu_pcr0_b_unrec_o   => s_pcr_b_unrec(0),

      rtu_pcr1_learn_en_o  => s_pcr_learn_en(1),
      rtu_pcr1_pass_all_o  => s_pcr_pass_all(1),
      rtu_pcr1_pass_bpdu_o => s_pcr_pass_bpdu(1),
      rtu_pcr1_fix_prio_o  => s_pcr_fix_prio(1),
      rtu_pcr1_prio_val_o  => s_pcr_prio_val(3*1 + 3 - 1 downto 3*1),
      rtu_pcr1_b_unrec_o   => s_pcr_b_unrec(1),

      rtu_pcr2_learn_en_o  => s_pcr_learn_en(2),
      rtu_pcr2_pass_all_o  => s_pcr_pass_all(2),
      rtu_pcr2_pass_bpdu_o => s_pcr_pass_bpdu(2),
      rtu_pcr2_fix_prio_o  => s_pcr_fix_prio(2),
      rtu_pcr2_prio_val_o  => s_pcr_prio_val(3*2 + 3 - 1 downto 3*2),
      rtu_pcr2_b_unrec_o   => s_pcr_b_unrec(2),

      rtu_pcr3_learn_en_o  => s_pcr_learn_en(3),
      rtu_pcr3_pass_all_o  => s_pcr_pass_all(3),
      rtu_pcr3_pass_bpdu_o => s_pcr_pass_bpdu(3),
      rtu_pcr3_fix_prio_o  => s_pcr_fix_prio(3),
      rtu_pcr3_prio_val_o  => s_pcr_prio_val(3*3 + 3 - 1 downto 3*3),
      rtu_pcr3_b_unrec_o   => s_pcr_b_unrec(3),

      rtu_pcr4_learn_en_o  => s_pcr_learn_en(4),
      rtu_pcr4_pass_all_o  => s_pcr_pass_all(4),
      rtu_pcr4_pass_bpdu_o => s_pcr_pass_bpdu(4),
      rtu_pcr4_fix_prio_o  => s_pcr_fix_prio(4),
      rtu_pcr4_prio_val_o  => s_pcr_prio_val(3*4 + 3 - 1 downto 3*4),
      rtu_pcr4_b_unrec_o   => s_pcr_b_unrec(4),

      rtu_pcr5_learn_en_o  => s_pcr_learn_en(5),
      rtu_pcr5_pass_all_o  => s_pcr_pass_all(5),
      rtu_pcr5_pass_bpdu_o => s_pcr_pass_bpdu(5),
      rtu_pcr5_fix_prio_o  => s_pcr_fix_prio(5),
      rtu_pcr5_prio_val_o  => s_pcr_prio_val(3*5 + 3 - 1 downto 3*5),
      rtu_pcr5_b_unrec_o   => s_pcr_b_unrec(5),

      rtu_pcr6_learn_en_o  => s_pcr_learn_en(6),
      rtu_pcr6_pass_all_o  => s_pcr_pass_all(6),
      rtu_pcr6_pass_bpdu_o => s_pcr_pass_bpdu(6),
      rtu_pcr6_fix_prio_o  => s_pcr_fix_prio(6),
      rtu_pcr6_prio_val_o  => s_pcr_prio_val(3*6 + 3 - 1 downto 3*6),
      rtu_pcr6_b_unrec_o   => s_pcr_b_unrec(6),

      rtu_pcr7_learn_en_o  => s_pcr_learn_en(7),
      rtu_pcr7_pass_all_o  => s_pcr_pass_all(7),
      rtu_pcr7_pass_bpdu_o => s_pcr_pass_bpdu(7),
      rtu_pcr7_fix_prio_o  => s_pcr_fix_prio(7),
      rtu_pcr7_prio_val_o  => s_pcr_prio_val(3*7 + 3 - 1 downto 3*7),
      rtu_pcr7_b_unrec_o   => s_pcr_b_unrec(7),


      rtu_pcr8_learn_en_o  => s_pcr_learn_en(8),
      rtu_pcr8_pass_all_o  => s_pcr_pass_all(8),
      rtu_pcr8_pass_bpdu_o => s_pcr_pass_bpdu(8),
      rtu_pcr8_fix_prio_o  => s_pcr_fix_prio(8),
      rtu_pcr8_prio_val_o  => s_pcr_prio_val(3*8 + 3 - 1 downto 3*8),
      rtu_pcr8_b_unrec_o   => s_pcr_b_unrec(8),

      rtu_pcr9_learn_en_o  => s_pcr_learn_en(9),
      rtu_pcr9_pass_all_o  => s_pcr_pass_all(9),
      rtu_pcr9_pass_bpdu_o => s_pcr_pass_bpdu(9),
      rtu_pcr9_fix_prio_o  => s_pcr_fix_prio(9),
      rtu_pcr9_prio_val_o  => s_pcr_prio_val(3*9 + 3 - 1 downto 3*9),
      rtu_pcr9_b_unrec_o   => s_pcr_b_unrec(9),
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
      rtu_pcr10_learn_en_o  => s_pcr_learn_en(10),
      rtu_pcr10_pass_all_o  => s_pcr_pass_all(10),
      rtu_pcr10_pass_bpdu_o => s_pcr_pass_bpdu(10),
      rtu_pcr10_fix_prio_o  => s_pcr_fix_prio(10),
      rtu_pcr10_prio_val_o  => s_pcr_prio_val(3*10 + 3 - 1 downto 3*10),
      rtu_pcr10_b_unrec_o   => s_pcr_b_unrec(10),

      rtu_pcr11_learn_en_o  => s_pcr_learn_en(11),
      rtu_pcr11_pass_all_o  => s_pcr_pass_all(11),
      rtu_pcr11_pass_bpdu_o => s_pcr_pass_bpdu(11),
      rtu_pcr11_fix_prio_o  => s_pcr_fix_prio(11),
      rtu_pcr11_prio_val_o  => s_pcr_prio_val(3*11 + 3 - 1 downto 3*11),
      rtu_pcr11_b_unrec_o   => s_pcr_b_unrec(11),

      rtu_pcr12_learn_en_o  => s_pcr_learn_en(12),
      rtu_pcr12_pass_all_o  => s_pcr_pass_all(12),
      rtu_pcr12_pass_bpdu_o => s_pcr_pass_bpdu(12),
      rtu_pcr12_fix_prio_o  => s_pcr_fix_prio(12),
      rtu_pcr12_prio_val_o  => s_pcr_prio_val(3*12 + 3 - 1 downto 3*12),
      rtu_pcr12_b_unrec_o   => s_pcr_b_unrec(12),

      rtu_pcr13_learn_en_o  => s_pcr_learn_en(13),
      rtu_pcr13_pass_all_o  => s_pcr_pass_all(13),
      rtu_pcr13_pass_bpdu_o => s_pcr_pass_bpdu(13),
      rtu_pcr13_fix_prio_o  => s_pcr_fix_prio(13),
      rtu_pcr13_prio_val_o  => s_pcr_prio_val(3*13 + 3 - 1 downto 3*13),
      rtu_pcr13_b_unrec_o   => s_pcr_b_unrec(13),

      rtu_pcr14_learn_en_o  => s_pcr_learn_en(14),
      rtu_pcr14_pass_all_o  => s_pcr_pass_all(14),
      rtu_pcr14_pass_bpdu_o => s_pcr_pass_bpdu(14),
      rtu_pcr14_fix_prio_o  => s_pcr_fix_prio(14),
      rtu_pcr14_prio_val_o  => s_pcr_prio_val(3*14 + 3 - 1 downto 3*14),
      rtu_pcr14_b_unrec_o   => s_pcr_b_unrec(14),

      rtu_pcr15_learn_en_o  => s_pcr_learn_en(15),
      rtu_pcr15_pass_all_o  => s_pcr_pass_all(15),
      rtu_pcr15_pass_bpdu_o => s_pcr_pass_bpdu(15),
      rtu_pcr15_fix_prio_o  => s_pcr_fix_prio(15),
      rtu_pcr15_prio_val_o  => s_pcr_prio_val(3*15 + 3 - 1 downto 3*15),
      rtu_pcr15_b_unrec_o   => s_pcr_b_unrec(15),

      rtu_pcr16_learn_en_o  => s_pcr_learn_en(16),
      rtu_pcr16_pass_all_o  => s_pcr_pass_all(16),
      rtu_pcr16_pass_bpdu_o => s_pcr_pass_bpdu(16),
      rtu_pcr16_fix_prio_o  => s_pcr_fix_prio(16),
      rtu_pcr16_prio_val_o  => s_pcr_prio_val(3*16 + 3 - 1 downto 3*16),
      rtu_pcr16_b_unrec_o   => s_pcr_b_unrec(16),

      rtu_pcr17_learn_en_o  => s_pcr_learn_en(17),
      rtu_pcr17_pass_all_o  => s_pcr_pass_all(17),
      rtu_pcr17_pass_bpdu_o => s_pcr_pass_bpdu(17),
      rtu_pcr17_fix_prio_o  => s_pcr_fix_prio(17),
      rtu_pcr17_prio_val_o  => s_pcr_prio_val(3*17 + 3 - 1 downto 3*17),
      rtu_pcr17_b_unrec_o   => s_pcr_b_unrec(17),

      rtu_pcr18_learn_en_o  => s_pcr_learn_en(18),
      rtu_pcr18_pass_all_o  => s_pcr_pass_all(18),
      rtu_pcr18_pass_bpdu_o => s_pcr_pass_bpdu(18),
      rtu_pcr18_fix_prio_o  => s_pcr_fix_prio(18),
      rtu_pcr18_prio_val_o  => s_pcr_prio_val(3*18 + 3 - 1 downto 3*18),
      rtu_pcr18_b_unrec_o   => s_pcr_b_unrec(18),

      rtu_pcr19_learn_en_o  => s_pcr_learn_en(19),
      rtu_pcr19_pass_all_o  => s_pcr_pass_all(19),
      rtu_pcr19_pass_bpdu_o => s_pcr_pass_bpdu(19),
      rtu_pcr19_fix_prio_o  => s_pcr_fix_prio(19),
      rtu_pcr19_prio_val_o  => s_pcr_prio_val(3*19 + 3 - 1 downto 3*19),
      rtu_pcr19_b_unrec_o   => s_pcr_b_unrec(19)

------------------------------------------------------------------------------------------
      );  



end architecture;  -- end of wrsw_rtu


