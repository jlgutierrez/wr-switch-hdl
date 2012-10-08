-------------------------------------------------------------------------------
-- Title      : Routing Table Unit (RTU)
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_rtu.vhd
-- Authors    : Tomasz Wlostowski, Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-27
-- Last update: 2012-06-25
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
use ieee.numeric_std.all;

library work;
use work.genram_pkg.all;
use work.wishbone_pkg.all;
use work.wrsw_shared_types_pkg.all;
use work.rtu_private_pkg.all;
use work.rtu_wbgen2_pkg.all;
use work.pack_unpack_pkg.all;

entity wrsw_rtu is
  generic (
    g_num_ports : integer);
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
    rtu_idle_o : out std_logic_vector(g_num_ports-1 downto 0);

-- request strobe, single HI pulse begins evaluation of the request. All
-- request input lines have to be valid when rq_strobe_p_i is asserted.
    rq_strobe_p_i : in std_logic_vector(g_num_ports-1 downto 0);

-- source and destination MAC addresses extracted from the packet header
    rq_smac_i : in std_logic_vector(c_wrsw_mac_addr_width * g_num_ports - 1 downto 0);
    rq_dmac_i : in std_logic_vector(c_wrsw_mac_addr_width * g_num_ports -1 downto 0);

-- VLAN id (extracted from the header for TRUNK ports and assigned by the port
-- for ACCESS ports)
    rq_vid_i : in std_logic_vector(c_wrsw_vid_width * g_num_ports - 1 downto 0);

-- HI means that packet has valid assigned a valid VID (low - packet is untagged)
    rq_has_vid_i : in std_logic_vector(g_num_ports -1 downto 0);

-- packet priority (either extracted from the header or assigned per port).
    rq_prio_i     : in std_logic_vector(c_wrsw_prio_width * g_num_ports -1 downto 0);
-- HI indicates that packet has assigned priority.
    rq_has_prio_i : in std_logic_vector(g_num_ports -1 downto 0);

-------------------------------------------------------------------------------
-- N-port RTU output interface (to the packet buffer
-------------------------------------------------------------------------------

-- response strobe. Single HI pulse indicates that a valid response for port N
-- request is available on rsp_dst_port_mask_o, rsp_drop_o and rsp_prio_o.
    rsp_valid_o : out std_logic_vector (g_num_ports-1 downto 0);

-- destination port mask. HI bits indicate that packet should be routed to
-- the corresponding port(s).
    rsp_dst_port_mask_o : out std_logic_vector(c_rtu_max_ports * g_num_ports - 1 downto 0);

-- HI -> packet must be dropped
    rsp_drop_o : out std_logic_vector(g_num_ports -1 downto 0);

-- Final packet priority (evaluated from port priority, tag priority, VLAN
-- priority or source/destination priority).
    rsp_prio_o         : out std_logic_vector (g_num_ports * c_wrsw_prio_width-1 downto 0);
-- Acknowledge from endpoin that the data has been read    
    rsp_ack_i          : in  std_logic_vector(g_num_ports -1 downto 0);
-- indication for the endpoint - says how busy is a port    
    port_almost_full_o : out std_logic_vector(g_num_ports -1 downto 0);
    port_full_o        : out std_logic_vector(g_num_ports -1 downto 0);

-------------------------------------------------------------------------------
-- TRU stuff
-------------------------------------------------------------------------------

    tru_req_valid_o         : out std_logic;
    tru_req_smac_o          : out std_logic_vector(c_wrsw_mac_addr_width-1 downto 0);
    tru_req_dmac_o          : out std_logic_vector(c_wrsw_mac_addr_width-1 downto 0);
    tru_req_fid_o           : out std_logic_vector(c_wrsw_fid_width    -1 downto 0);
    tru_req_isHP_o          : out std_logic;                     -- high priority packet flag
    tru_req_isBR_o          : out std_logic;                     -- broadcast packet flag
    tru_req_reqMask_o       : out std_logic_vector(g_num_ports-1  downto 0); -- mask indicating requesting port

    tru_resp_valid_i        : in  std_logic;
    tru_resp_port_mask_i    : in  std_logic_vector(g_num_ports-1 downto 0); -- mask with 1's at forward ports
    tru_resp_drop_i         : in  std_logic;
    tru_resp_respMask_i     : in  std_logic_vector(g_num_ports-1 downto 0); -- mask with 1 at requesting port

    tru_if_pass_all_o         : out std_logic_vector(g_num_ports-1  downto 0); 
    tru_if_forward_bpdu_only_o: out std_logic_vector(g_num_ports-1  downto 0); 
    tru_if_request_valid_o    : out std_logic_vector(g_num_ports-1  downto 0); 
    tru_if_priorities_o       : out std_logic_vector(g_num_ports*c_wrsw_prio_width-1 downto 0);

-------------------------------------------------------------------------------
-- Wishbone (synchronous to refclk2_i). See the wbgen2 file for register details
-------------------------------------------------------------------------------
    wb_adr_i   : in  std_logic_vector(13 downto 0);
    wb_dat_i   : in  std_logic_vector(31 downto 0);
    wb_dat_o   : out std_logic_vector(31 downto 0);
    wb_sel_i   : in  std_logic_vector(3 downto 0);
    wb_cyc_i   : in  std_logic;
    wb_stb_i   : in  std_logic;
    wb_ack_o   : out std_logic;
    wb_irq_o   : out std_logic;
    wb_we_i    : in  std_logic;
    wb_stall_o : out std_logic
    );

end wrsw_rtu;

architecture behavioral of wrsw_rtu is

  constant c_VLAN_TAB_ENTRY_WIDTH : integer := 46;
  type t_rq_fifo_request_array is array (integer range <>) of std_logic_vector(c_PACKED_REQUEST_WIDTH-1 downto 0);

  
  -- writes request FIFO
  signal rq_fifo_write_all : std_logic_vector(g_num_ports - 1 downto 0);
  signal rq_fifo_write_sng : std_logic;

  signal rq_fifo_d_requests : t_rq_fifo_request_array(0 to g_num_ports-1);
  signal rq_fifo_d_muxed    : std_logic_vector(g_num_ports+ c_PACKED_REQUEST_WIDTH -1 downto 0);


  signal rq_fifo_read, rq_fifo_full, rq_fifo_empty : std_logic;

  -- RESPONSE FIFO

  signal rsp_fifo_full : std_logic;


  --| RTU ENGINE
  -- request data read by RTU engine from rq_fifo
  signal rq_rtu_match_data  : std_logic_vector(g_num_ports + c_PACKED_REQUEST_WIDTH - 1 downto 0);
  -- response data outputed from RTU to rsp_fifo
  signal rsp_rtu_match_data : std_logic_vector(g_num_ports + c_PACKED_RESPONSE_WIDTH - 1 downto 0);

  --| HASH TABLE lookup engine 

  signal htab_rr_sel_w : std_logic;
  signal htab_rr_sel_r : std_logic;
  signal htab_rr_req   : std_logic_vector(1 downto 0);
  signal htab_rr_gnt   : std_logic_vector(1 downto 0);

--HTAB interface

  signal htab_start : std_logic;
  signal htab_ack   : std_logic;
  signal htab_hash  : std_logic_vector(c_wrsw_hash_width-1 downto 0);
  signal htab_mac   : std_logic_vector(47 downto 0);
  signal htab_fid   : std_logic_vector(7 downto 0);
  signal htab_found : std_logic;
  signal htab_drdy  : std_logic;
  signal htab_valid : std_logic;
  signal htab_entry : t_rtu_htab_entry;

  signal mfifo_trigger : std_logic;

  signal vlan_tab_rd_vid                    : std_logic_vector(c_wrsw_vid_width-1 downto 0);
  signal vlan_tab_wr_data, vlan_tab_rd_data : std_logic_vector(c_VLAN_TAB_ENTRY_WIDTH-1 downto 0);
  signal vlan_tab_rd_entry                  : t_rtu_vlan_tab_entry;

  -- | UFIFO for learning
  --|IRQ
  signal irq_nempty : std_logic;

  --|HCAM - Hash collision memory
  signal aram_main_addr   : std_logic_vector(7 downto 0);
  signal aram_main_data_i : std_logic_vector(31 downto 0);
  signal aram_main_data_o : std_logic_vector(31 downto 0);
  signal aram_main_rd     : std_logic;
  signal aram_main_wr     : std_logic;


  type   t_pcr_prio_val_array is array(integer range <>) of std_logic_vector(c_wrsw_prio_width-1 downto 0);
  signal pcr_learn_en  : std_logic_vector(g_num_ports - 1 downto 0);
  signal pcr_pass_all  : std_logic_vector(g_num_ports - 1 downto 0);
  signal pcr_pass_bpdu : std_logic_vector(g_num_ports - 1 downto 0);
  signal pcr_fix_prio  : std_logic_vector(g_num_ports - 1 downto 0);
  signal pcr_prio_val  : t_pcr_prio_val_array(g_num_ports-1 downto 0);
  signal pcr_b_unrec   : std_logic_vector(g_num_ports - 1 downto 0);

  --| RESPONSE FIFO
  -- response FIFO empty
  signal rsp_fifo_empty          : std_logic;
  -- response FIFO read data
  type   t_rsp_fifo_data_a is array(g_num_ports - 1 downto 0) of std_logic_vector(c_RTU_MAX_PORTS + c_wrsw_prio_width + 1 - 1 downto 0);
  signal rsp_fifo_data_a         : t_rsp_fifo_data_a;
  signal rsp_fifo_data           : std_logic_vector(c_RTU_MAX_PORTS + c_wrsw_prio_width + 1 - 1 downto 0);
  -- output from the response fifo (this is split into rsp_fifo_data and rsp_fifo_sel)
  signal rsp_fifo_output         : std_logic_vector(g_num_ports + c_RTU_MAX_PORTS + c_wrsw_prio_width + 1 - 1 downto 0);
  -- says which port should read the datase
  signal rsp_fifo_sel            : std_logic_vector(g_num_ports - 1 downto 0);
  -- read response FIFO
  signal rsp_fifo_read_all       : std_logic_vector(g_num_ports - 1 downto 0);
  -- just for zero comparison
  signal rsp_fifo_read_all_zeros : std_logic_vector(g_num_ports - 1 downto 0);
  --signal rsp_fifo_read_sng : std_logic;
  signal rsp_fifo_read_port      : std_logic;
  signal rsp_fifo_read_fifo      : std_logic;
  -- driven by rtu_match
  signal rsp_fifo_write          : std_logic;

  signal rq_rsp_cnt_dec : std_logic_vector(g_num_ports - 1 downto 0);

  --| ARBITER TO REQUEST FIFO  
  -- request signals from ports to REQ_FIFO_ARBITER
  signal req_fifo_access : std_logic_vector(g_num_ports - 1 downto 0);
  -- access granted by REQ_FIFO_ARBITER to single port (if '1' access is granted
  signal gnt_fifo_access : std_logic_vector(g_num_ports - 1 downto 0);

  -- hash polynomial
  signal rtu_gcr_poly_input : std_logic_vector(15 downto 0);
  signal rtu_gcr_poly_used  : std_logic_vector(15 downto 0);
  signal rq_fifo_qvalid     : std_logic;

  signal regs_towb   : t_rtu_in_registers;
  signal regs_fromwb : t_rtu_out_registers;

  signal current_pcr : integer;

  function f_slice (
    x     : std_logic_vector;
    index : integer;
    len   : integer) return std_logic_vector is
  begin
    return x((index + 1) * len - 1 downto index * len);
  end f_slice;

begin

  irq_nempty <= regs_fromwb.ufifo_wr_empty_o;

  ---------------------------------------------------------------------------------------------------------------------
  --| REQUEST ROUND ROBIN ARBITER - governs access to REQUEST FIFO
  ---------------------------------------------------------------------------------------------------------------------
  U_req_fifo_arbiter : rtu_rr_arbiter
    generic map (
      g_width => g_num_ports)
    port map(
      clk_i   => clk_sys_i,
      rst_n_i => rst_n_i,
      req_i   => req_fifo_access,
      gnt_o   => gnt_fifo_access
      );

  ---------------------------------------------------------------------------------------------------------------------
  --| PORTS - g_num_ports number of I/O ports, a port:
  --| - inputs request to REQUEST FIFO
  --| - waits for the response,
  --| - reads response from RESPONSE FIFO
  ---------------------------------------------------------------------------------------------------------------------
  ports : for i in 0 to (g_num_ports - 1) generate

    U_PortX : rtu_port
      generic map (
        g_num_ports  => g_num_ports,
        g_port_index => i)
      port map(
        clk_i   => clk_sys_i,
        rst_n_i => rst_n_i,

        rtu_gcr_g_ena_i => regs_fromwb.gcr_g_ena_o,
        rtu_idle_o      => rtu_idle_o(i),

        rq_strobe_p_i => rq_strobe_p_i(i),
        rq_smac_i     => rq_smac_i(c_wrsw_mac_addr_width * (i+1)- 1 downto c_wrsw_mac_addr_width*i),
        rq_dmac_i     => rq_dmac_i(c_wrsw_mac_addr_width * (i+1)- 1 downto c_wrsw_mac_addr_width*i),
        rq_vid_i      => rq_vid_i(c_wrsw_vid_width * (i+1)- 1 downto c_wrsw_vid_width*i),
        rq_has_vid_i  => rq_has_vid_i(i),
        rq_prio_i     => rq_prio_i(c_wrsw_prio_width * (i+1)- 1 downto c_wrsw_prio_width*i),
        rq_has_prio_i => rq_has_prio_i(i),

        rsp_valid_o         => rsp_valid_o(i),
        rsp_dst_port_mask_o => rsp_dst_port_mask_o((i+1)*c_RTU_MAX_PORTS - 1 downto i*c_RTU_MAX_PORTS),
        rsp_drop_o          => rsp_drop_o(i),
        rsp_prio_o          => rsp_prio_o((i+1)*c_wrsw_prio_width - 1 downto i*c_wrsw_prio_width),

        -- this goes to the arbiter
        rq_fifo_write_o => rq_fifo_write_all(i),
        rq_fifo_full_i  => rq_fifo_full,
        rq_fifo_data_o  => rq_fifo_d_requests(i),

        rsp_write_i      => rsp_fifo_write,
        rsp_match_data_i => rsp_rtu_match_data,
        rsp_ack_i        => rsp_ack_i(i),

        rr_request_wr_access_o => req_fifo_access(i),
        rr_access_ena_i        => gnt_fifo_access(i),

        port_almost_full_o  => port_almost_full_o(i),
        port_full_o         => port_full_o(i),
        rq_rsp_cnt_dec_i    => rq_rsp_cnt_dec(i),  -- rq_rtu_match_data(i) -- and rq_fifo_read
        rtu_pcr_pass_bpdu_i => pcr_pass_bpdu(i),
        rtu_pcr_pass_all_i  => pcr_pass_all(i),
        rtu_pcr_fix_prio_i  => pcr_fix_prio(i),
        rtu_pcr_prio_val_i  => pcr_prio_val(i)
        );

  end generate;  -- end ports

------------------------------------------------------------------------
-- REQUEST FIFO BUS
-- Data from all ports into one match module
------------------------------------------------------------------------

  p_mux_fifo_req : process(rq_fifo_d_requests, gnt_fifo_access, rq_fifo_write_all)
    variable do_wr   : std_logic;
    variable do_data : std_logic_vector(c_PACKED_REQUEST_WIDTH-1 downto 0);
  begin

    do_data := (others => 'X');
    do_wr   := '0';

    if(gnt_fifo_access = rsp_fifo_read_all_zeros) then
      do_wr := '0';
    else
      for i in 0 to g_num_ports-1 loop
        if(gnt_fifo_access(i) = '1') then
          do_wr := rq_fifo_write_all(i);
        end if;
      end loop;  -- i
    end if;

    rq_fifo_write_sng <= do_wr;

    for i in 0 to g_num_ports-1 loop
      if(gnt_fifo_access(i) = '1') then
        do_data := rq_fifo_d_requests(i);
      end if;
    end loop;  -- i

    rq_fifo_d_muxed <= gnt_fifo_access & do_data;
  end process;



  -----------------------------------------------------------------------------
  -- REQUEST FIFO: takes requests from ports and makes it available for RTU MATCH
  -----------------------------------------------------------------------------

  U_ReqFifo : generic_shiftreg_fifo
    generic map (
      g_data_width => g_num_ports + c_PACKED_REQUEST_WIDTH,
      g_size       => 32
      )
    port map
    (
      rst_n_i   => rst_n_i,
      d_i       => rq_fifo_d_muxed,
      clk_i     => clk_sys_i,
      rd_i      => rq_fifo_read,        --rtu_match
      we_i      => rq_fifo_write_sng,
      q_o       => rq_rtu_match_data,
      q_valid_o => rq_fifo_qvalid,
      full_o    => rq_fifo_full
      );

  rq_fifo_empty <= not rq_fifo_qvalid;



  --------------------------------------------------------------------------------------------
  --| RTU MATCH: Routing Table Unit Engine
  --------------------------------------------------------------------------------------------
  -- to be added
  U_Match : rtu_match
    generic map (
      g_num_ports => g_num_ports)
    port map(

      clk_i             => clk_sys_i,
      rst_n_i           => rst_n_i,
      rq_fifo_read_o    => rq_fifo_read,
      rq_fifo_empty_i   => rq_fifo_empty,
      rq_fifo_input_i   => rq_rtu_match_data,
      rsp_fifo_write_o  => rsp_fifo_write,
      rsp_fifo_full_i   => rsp_fifo_full,
      rsp_fifo_output_o => rsp_rtu_match_data,

      htab_start_o => htab_start,
      htab_ack_o   => htab_ack,
      htab_found_i => htab_found,
      htab_hash_o  => htab_hash,
      htab_mac_o   => htab_mac,
      htab_fid_o   => htab_fid,
      htab_drdy_i  => htab_drdy,
      htab_entry_i => htab_entry,

      rtu_ufifo_wr_req_o   => regs_towb.ufifo_wr_req_i,
      rtu_ufifo_wr_full_i  => regs_fromwb.ufifo_wr_full_o,
      rtu_ufifo_wr_empty_i => regs_fromwb.ufifo_wr_empty_o,
      rtu_ufifo_dmac_lo_o  => regs_towb.ufifo_dmac_lo_i,
      rtu_ufifo_dmac_hi_o  => regs_towb.ufifo_dmac_hi_i,
      rtu_ufifo_smac_lo_o  => regs_towb.ufifo_smac_lo_i,
      rtu_ufifo_smac_hi_o  => regs_towb.ufifo_smac_hi_i,
      rtu_ufifo_vid_o      => regs_towb.ufifo_vid_i,
      rtu_ufifo_prio_o     => regs_towb.ufifo_prio_i,
      rtu_ufifo_pid_o      => regs_towb.ufifo_pid_i,
      rtu_ufifo_has_vid_o  => regs_towb.ufifo_has_vid_i,
      rtu_ufifo_has_prio_o => regs_towb.ufifo_has_prio_i,

      rtu_aram_main_addr_o => aram_main_addr,
      rtu_aram_main_data_i => aram_main_data_i,
      rtu_aram_main_rd_o   => aram_main_rd,
      rtu_aram_main_data_o => aram_main_data_o,
      rtu_aram_main_wr_o   => aram_main_wr,

      vlan_tab_addr_o  => vlan_tab_rd_vid,
      vlan_tab_entry_i => vlan_tab_rd_entry,

      rtu_gcr_g_ena_i     => regs_fromwb.gcr_g_ena_o,
      rtu_pcr_pass_all_i  => pcr_pass_all(g_num_ports - 1 downto 0),
      rtu_pcr_learn_en_i  => pcr_learn_en(g_num_ports - 1 downto 0),
      rtu_pcr_pass_bpdu_i => pcr_pass_bpdu(g_num_ports - 1 downto 0),
      rtu_pcr_b_unrec_i   => pcr_b_unrec(g_num_ports - 1 downto 0),
      rtu_crc_poly_i      => rtu_gcr_poly_used  --x"1021"-- x"0589" -- x"8005" --x"1021" --x"8005", --
--    rtu_rw_bank_i                                => s_vlan_bsel
      );

  rtu_gcr_poly_used <= c_default_hash_poly when (regs_fromwb.gcr_poly_val_o = x"0000") else rtu_gcr_poly_input;

  mfifo_trigger <= regs_fromwb.gcr_mfifotrig_o and regs_fromwb.gcr_mfifotrig_load_o;

  U_Lookup : rtu_lookup_engine
    port map (
      clk_sys_i   => clk_sys_i,
      clk_match_i => clk_sys_i,
      rst_n_i     => rst_n_i,

      mfifo_rd_req_o   => regs_towb.mfifo_rd_req_i,
      mfifo_rd_empty_i => regs_fromwb.mfifo_rd_empty_o,
      mfifo_ad_sel_i   => regs_fromwb.mfifo_ad_sel_o,
      mfifo_ad_val_i   => regs_fromwb.mfifo_ad_val_o,
      mfifo_trigger_i  => mfifo_trigger,
      mfifo_busy_o     => regs_towb.gcr_mfifotrig_i,

      start_i => htab_start,
      ack_i   => htab_ack,
      found_o => htab_found,
      hash_i  => htab_hash,
      mac_i   => htab_mac,
      fid_i   => htab_fid,
      drdy_o  => htab_drdy,
      entry_o => htab_entry
      );


  --| WISHBONE I/F: interface with CPU and RAM/CAM

  U_WB_Slave : rtu_wishbone_slave
    port map(
      rst_n_i   => rst_n_i,
      clk_sys_i => clk_sys_i,

      wb_adr_i   => wb_adr_i(8 downto 0),
      wb_dat_i   => wb_dat_i,
      wb_dat_o   => wb_dat_o,
      wb_cyc_i   => wb_cyc_i,
      wb_sel_i   => wb_sel_i,
      wb_stb_i   => wb_stb_i,
      wb_we_i    => wb_we_i,
      wb_ack_o   => wb_ack_o,
      wb_int_o   => wb_irq_o,
      wb_stall_o => open,

      clk_match_i => clk_sys_i,

      regs_o => regs_fromwb,
      regs_i => regs_towb,

      irq_nempty_i => irq_nempty,       --'1',

      rtu_aram_addr_i => aram_main_addr,
      rtu_aram_data_o => aram_main_data_i,
      rtu_aram_rd_i   => aram_main_rd,
      rtu_aram_data_i => aram_main_data_o,
      rtu_aram_wr_i   => aram_main_wr
      );  

  current_pcr             <= to_integer(unsigned(regs_fromwb.psr_port_sel_o));
  regs_towb.psr_n_ports_i <= std_logic_vector(to_unsigned(g_num_ports, 8));

  -- indirectly addressed PCR registers - this is to allow easy generic-based
  -- scaling of the number of ports
  p_pcr_registers : process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      regs_towb.pcr_learn_en_i  <= pcr_learn_en(current_pcr);
      regs_towb.pcr_pass_all_i  <= pcr_pass_all(current_pcr);
      regs_towb.pcr_pass_bpdu_i <= pcr_pass_bpdu(current_pcr);
      regs_towb.pcr_fix_prio_i  <= pcr_fix_prio(current_pcr);
      regs_towb.pcr_prio_val_i  <= pcr_prio_val(current_pcr);
      regs_towb.pcr_b_unrec_i   <= pcr_b_unrec(current_pcr);

      if(regs_fromwb.pcr_learn_en_load_o = '1') then
        pcr_learn_en(current_pcr)  <= regs_fromwb.pcr_learn_en_o;
        pcr_pass_all(current_pcr)  <= regs_fromwb.pcr_pass_all_o;
        pcr_pass_bpdu(current_pcr) <= regs_fromwb.pcr_pass_bpdu_o;
        pcr_fix_prio(current_pcr)  <= regs_fromwb.pcr_fix_prio_o;
        pcr_prio_val(current_pcr)  <= regs_fromwb.pcr_prio_val_o;
        pcr_b_unrec(current_pcr)   <= regs_fromwb.pcr_b_unrec_o;



      end if;
    end if;
  end process;


  U_VLAN_Table : generic_dpram
    generic map (
      g_data_width       => c_VLAN_TAB_ENTRY_WIDTH,
      g_size             => 4096,
      g_with_byte_enable => false,
      g_dual_clock       => false)
    port map (
      rst_n_i => rst_n_i,
      clka_i  => clk_sys_i,
      clkb_i => '0',
      bwea_i  => "111111",
      wea_i   => regs_fromwb.vtr1_update_o,
      aa_i    => regs_fromwb.vtr1_vid_o,
      da_i    => vlan_tab_wr_data,
      ab_i    => vlan_tab_rd_vid,
      qb_o    => vlan_tab_rd_data);

  vlan_tab_wr_data <= regs_fromwb.vtr2_port_mask_o
                      & regs_fromwb.vtr1_fid_o
                      & regs_fromwb.vtr1_drop_o
                      & regs_fromwb.vtr1_prio_override_o
                      & regs_fromwb.vtr1_prio_o
                      & regs_fromwb.vtr1_has_prio_o;

  f_unpack6(vlan_tab_rd_data,
            vlan_tab_rd_entry.port_mask,
            vlan_tab_rd_entry.fid,
            vlan_tab_rd_entry.drop,
            vlan_tab_rd_entry.prio_override,
            vlan_tab_rd_entry.prio,
            vlan_tab_rd_entry.has_prio);

end architecture;  -- end of wrsw_rtu


