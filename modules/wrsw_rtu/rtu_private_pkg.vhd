-------------------------------------------------------------------------------
-- Title      : Routing Table Unit's Components Package 
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_rtu_components_pkg.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-05-09
-- Last update: 2012-06-25
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Routing Table Unit components
-- 
--
-------------------------------------------------------------------------------
--
-- Copyright (c) 2010 - 2012 CERN / BE-CO-HT
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
-- 2010-05-09  1.0      lipinskimm          Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;

use work.wishbone_pkg.all;              -- for test part (to be moved)
use work.wrsw_shared_types_pkg.all;
use work.rtu_wbgen2_pkg.all;
-- use work.rtu_wbgen2_pkg_old.all;

package rtu_private_pkg is

----------------------------------------------------------------------------------------
--| RTU top level
----------------------------------------------------------------------------------------

-- Number of switch ports (including NIC)
  
  constant c_wrsw_mac_addr_width     : integer                           := 48;
  constant c_wrsw_vid_width          : integer                           := 12;
  constant c_wrsw_prio_width         : integer                           := 3;
  constant c_wrsw_prio_levels        : integer                           := 8;
  constant c_wrsw_fid_width          : integer                           := 8;
  constant c_wrsw_hash_width         : integer                           := 9;
  constant c_wrsw_crc_width          : integer                           := 16;
  constant c_wrsw_cam_addr_width     : integer                           := 8;
  constant c_wrsw_entry_words_number : std_logic_vector(5 downto 0)      := "000101";
  constant c_wrsw_rtu_debugging      : std_logic                         := '0';
  constant c_default_hash_poly       : std_logic_vector(16 - 1 downto 0) := x"1021";

  constant c_PACKED_REQUEST_WIDTH : integer :=
    c_wrsw_mac_addr_width  -- src MAC
    + c_wrsw_mac_addr_width  -- dst MAC
    + c_wrsw_vid_width  -- VID
    + c_wrsw_prio_width  -- priority
    + 1  -- has_VID
    + 1; -- has_priority

  constant c_PACKED_RESPONSE_WIDTH  : integer :=
    c_rtu_max_ports                     -- DPM size
    + 1                                 -- drop bit
    + 1                                 -- bpdu bit
    + c_wrsw_prio_width;                -- priority
  
  
  type t_rtu_htab_entry is record
    valid     : std_logic;
    is_bpdu   : std_logic;
    go_to_cam : std_logic;
    cam_addr  : std_logic_vector(c_wrsw_cam_addr_width-1 downto 0);
    fid       : std_logic_vector(c_wrsw_fid_width-1 downto 0);
    mac       : std_logic_vector(47 downto 0);

    bucket_entry : std_logic_vector(1 downto 0);

    port_mask_src            : std_logic_vector(c_rtu_max_ports-1 downto 0);
    port_mask_dst            : std_logic_vector(c_rtu_max_ports-1 downto 0);
    drop_when_src            : std_logic;
    drop_when_dst            : std_logic;
    drop_unmatched_src_ports : std_logic;

    prio_src          : std_logic_vector(c_wrsw_prio_width-1 downto 0);
    has_prio_src      : std_logic;
    prio_override_src : std_logic;

    prio_dst          : std_logic_vector(c_wrsw_prio_width-1 downto 0);
    has_prio_dst      : std_logic;
    prio_override_dst : std_logic;
    
  end record;

  
  type t_rtu_vlan_tab_entry is record
    drop          : std_logic;
    prio_override : std_logic;
    prio          : std_logic_vector(c_wrsw_prio_width-1 downto 0);
    has_prio      : std_logic;
    fid           : std_logic_vector(7 downto 0);
    port_mask     : std_logic_vector(c_rtu_max_ports-1 downto 0);
  end record;

 
  constant c_ff_single_macs_number :	 integer := 4;
  constant c_ff_range_macs_number :	 integer := 1; -- not implemented
  
------------------ new stuff ------------------------
  constant c_bpd_range_lower  : std_logic_vector(47 downto 0) := x"0180C2000000";
--   constant c_bpd_range_upper  : std_logic_vector := x"0180C200000F";

  type t_mac_array is array(integer range <>) of std_logic_vector(47 downto 0);
  type t_rtu_special_traffic_config is record
    -- control
    ff_mac_br_ena      : std_logic;
    ff_mac_range_ena   : std_logic;
    ff_mac_single_ena  : std_logic;
    ff_mac_ll_ena      : std_logic;
    ff_mac_ptp_ena     : std_logic;
    mr_ena             : std_logic;
    hp_prio            : std_logic_vector(7 downto 0);
    dop_on_fmatch_full : std_logic;
    hp_fw_cpu_ena      : std_logic;
    unrec_fw_cpu_ena   : std_logic;
    -- config
    single_macs        : t_mac_array(c_ff_single_macs_number-1 downto 0);
    single_macs_valid  : std_logic_vector(c_ff_single_macs_number-1 downto 0);
    
    macs_range_up      : std_logic_vector(47 downto 0);
    macs_range_down    : std_logic_vector(47 downto 0);
    macs_range_valid   : std_logic;
    cpu_forward_mask   : std_logic_vector(c_rtu_max_ports-1 downto 0);
    mirror_port_src_tx : std_logic_vector(c_rtu_max_ports-1 downto 0);
    mirror_port_src_rx : std_logic_vector(c_rtu_max_ports-1 downto 0);
    mirror_port_dst    : std_logic_vector(c_rtu_max_ports-1 downto 0);
    dbg_force_fast_match_only : std_logic;
    dbg_force_full_match_only : std_logic;
  end record;
  type t_match_response is record
    valid     : std_logic; -- entry valid
    port_mask : std_logic_vector(c_RTU_MAX_PORTS-1 downto 0); -- forwarding mask
    prio      : std_logic_vector(2 downto 0); -- priority
    drop      : std_logic; -- drop on ingress
    nf        : std_logic; -- non-forward (link-limited) traffic (table 7-10,p51, IEEE 802.1D)
    ff        : std_logic; -- fast forward traffic
    hp        : std_logic; -- high priority traffic
  end record;

  function f_mac_in_range(in_mac, in_mac_lower, in_mac_upper   : std_logic_vector(47 downto 0)
                                                     ) return std_logic;
  function f_mac_reserved(in_mac: std_logic_vector(47 downto 0)
                                                     ) return std_logic;
  function f_fast_match_mac_lookup(match_config : t_rtu_special_traffic_config;
                                     in_mac       : std_logic_vector(47 downto 0)
                                     ) return std_logic; 
  function f_pick (condition : boolean; w_true : std_logic_vector; w_false : std_logic_vector)
                  return std_logic_vector;
  function f_fast_match_response(vlan_entry      : t_rtu_vlan_tab_entry;
                                 rq_prio         : std_logic_vector;
                                 rq_has_prio     : std_logic;
                                 rq_port_mask    : std_logic_vector;
                                 traffic_br      : std_logic;
                                 pcr_pass_all    : std_logic_vector;
                                 pcr_drop_nonvlan_at_ingress: std_logic_vector;
                                 port_mask_width : integer) 
                                 return t_match_response;
  function f_set_bit(data     : std_logic_vector;
                     bit_val  : std_logic;
                     bit_num  : integer          ) return std_logic_vector;
  function f_onehot_decode
    (x : std_logic_vector) return integer;
  function f_unmarshall_htab_entry (w0, w1, w2, w3, w4 : std_logic_vector) return t_rtu_htab_entry;
------------------------------------------------------

  component wrsw_rtu
    generic(
      g_num_ports: integer);
    port (
      clk_sys_i           : in  std_logic;
      clk_match_i         : in  std_logic;
      rst_n_i             : in  std_logic;
      rtu_idle_o          : out std_logic_vector(g_num_ports-1 downto 0);
      rq_strobe_p_i       : in  std_logic_vector(g_num_ports-1 downto 0);
      rq_smac_i           : in  std_logic_vector(c_wrsw_mac_addr_width * g_num_ports - 1 downto 0);
      rq_dmac_i           : in  std_logic_vector(c_wrsw_mac_addr_width * g_num_ports -1 downto 0);
      rq_vid_i            : in  std_logic_vector(c_wrsw_vid_width * g_num_ports - 1 downto 0);
      rq_has_vid_i        : in  std_logic_vector(g_num_ports -1 downto 0);
      rq_prio_i           : in  std_logic_vector(c_wrsw_prio_width * g_num_ports -1 downto 0);
      rq_has_prio_i       : in  std_logic_vector(g_num_ports -1 downto 0);
      rsp_valid_o         : out std_logic_vector (g_num_ports-1 downto 0);
      rsp_dst_port_mask_o : out std_logic_vector(c_rtu_max_ports * g_num_ports - 1 downto 0);
      rsp_drop_o          : out std_logic_vector(g_num_ports -1 downto 0);
      rsp_prio_o          : out std_logic_vector (g_num_ports * c_wrsw_prio_width-1 downto 0);
      rsp_ack_i           : in  std_logic_vector(g_num_ports -1 downto 0);
      port_almost_full_o  : out std_logic_vector(g_num_ports -1 downto 0);
      port_full_o         : out std_logic_vector(g_num_ports -1 downto 0);
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
----------------------------------------------------------------------------------
      wb_addr_i           : in  std_logic_vector(13 downto 0);
      wb_data_i           : in  std_logic_vector(31 downto 0);
      wb_data_o           : out std_logic_vector(31 downto 0);
      wb_sel_i            : in  std_logic_vector(3 downto 0);
      wb_cyc_i            : in  std_logic;
      wb_stb_i            : in  std_logic;
      wb_ack_o            : out std_logic;
      wb_irq_o            : out std_logic;
      wb_we_i             : in  std_logic);
  end component;
----------------------------------------------------------------------------------------
--| RTU port
----------------------------------------------------------------------------------------

  component rtu_port
    generic (
      g_num_ports  : integer;
      g_port_index : integer);
    port (
      clk_i                  : in  std_logic;
      rst_n_i                : in  std_logic;
      rtu_gcr_g_ena_i        : in  std_logic;
      rtu_idle_o             : out std_logic;
      rq_strobe_p_i          : in  std_logic;
      rq_smac_i              : in  std_logic_vector(c_wrsw_mac_addr_width - 1 downto 0);
      rq_dmac_i              : in  std_logic_vector(c_wrsw_mac_addr_width - 1 downto 0);
      rq_vid_i               : in  std_logic_vector(c_wrsw_vid_width - 1 downto 0);
      rq_has_vid_i           : in  std_logic;
      rq_prio_i              : in  std_logic_vector(c_wrsw_prio_width -1 downto 0);
      rq_has_prio_i          : in  std_logic;
      rsp_valid_o            : out std_logic;
      rsp_dst_port_mask_o    : out std_logic_vector(c_rtu_max_ports - 1 downto 0);
      rsp_drop_o             : out std_logic;
      rsp_prio_o             : out std_logic_vector (c_wrsw_prio_width-1 downto 0);
      rsp_ack_i              : in  std_logic;
      rq_fifo_write_o        : out std_logic;
      rq_fifo_full_i         : in  std_logic;
      rq_fifo_data_o         : out std_logic_vector(c_PACKED_REQUEST_WIDTH - 1 downto 0);
      rsp_write_i            : in  std_logic;
      rsp_match_data_i       : in  std_logic_vector(g_num_ports + c_PACKED_RESPONSE_WIDTH - 1 downto 0);
      rr_request_wr_access_o : out std_logic;
      rr_access_ena_i        : in  std_logic;
      port_almost_full_o     : out std_logic;
      port_full_o            : out std_logic;
      rq_rsp_cnt_dec_i       : in  std_logic;
      rtu_pcr_pass_bpdu_i    : in  std_logic;
      rtu_pcr_pass_all_i     : in  std_logic;
      rtu_pcr_fix_prio_i     : in  std_logic;
      rtu_pcr_prio_val_i     : in  std_logic_vector(c_wrsw_prio_width - 1 downto 0));
  end component;
  
  component rtu_port_new
    generic(
      g_num_ports        : integer;
      g_port_mask_bits   : integer; -- usually: g_num_ports + 1 for CPU
      g_match_req_fifo_size : integer;      
      g_port_index             : integer
      );
    port(
      clk_i                     : in std_logic;
      rst_n_i                   : in std_logic;
      rtu_idle_o                : out std_logic;
      rtu_rq_i                  : in  t_rtu_request;
      rtu_rq_abort_i            : in  std_logic;
      rtu_rsp_abort_i           : in  std_logic;
      rtu_rsp_o                 : out t_rtu_response;
      rtu_rsp_ack_i             : in std_logic;
      full_match_wr_req_o       : out std_logic;
      full_match_wr_data_o      : out std_logic_vector(c_PACKED_REQUEST_WIDTH - 1 downto 0);
      full_match_wr_done_i      : in  std_logic;
      full_match_wr_full_i      : in  std_logic;
      full_match_rd_data_i      : in std_logic_vector(g_num_ports + c_PACKED_RESPONSE_WIDTH - 1 downto 0);
      full_match_rd_valid_i     : in std_logic;
      fast_match_wr_req_o       : out std_logic;
      fast_match_wr_data_o      : out t_rtu_request;
      fast_match_rd_valid_i     : in std_logic;
      fast_match_rd_data_i      : in t_match_response;
      port_almost_full_o        : out std_logic;
      port_full_o               : out std_logic;
--       tru_o                     : out t_rtu2tru;
      rtu_str_config_i          : in t_rtu_special_traffic_config;
      rtu_gcr_g_ena_i           : in std_logic;  
--       rtu_pcr_pass_bpdu_i       : in std_logic_vector(c_rtu_max_ports -1 downto 0);
--       rtu_pcr_pass_all_i        : in std_logic_vector(c_rtu_max_ports -1 downto 0);
      rtu_pcr_pass_bpdu_i       : in std_logic;
      rtu_pcr_pass_all_i        : in std_logic;
      rtu_pcr_fix_prio_i        : in std_logic;
      rtu_pcr_prio_val_i        : in std_logic_vector(c_wrsw_prio_width - 1 downto 0)
      );
  end component;
----------------------------------------------------------------------------------------
--| Round Robin Arbiter
----------------------------------------------------------------------------------------

  component rtu_rr_arbiter is
    generic (
      g_width : natural);
    port (
      clk_i, rst_n_i : in  std_logic;
      req_i          : in  std_logic_vector(g_width - 1 downto 0);
      gnt_o          : out std_logic_vector(g_width - 1 downto 0)
      );
  end component;

----------------------------------------------------------------------------------------
--| WISHBONE
----------------------------------------------------------------------------------------

  component rtu_lookup_engine
    generic (
      g_num_ports : integer;
      g_hash_size : integer := c_wrsw_hash_width);
    port (
      clk_match_i      : in  std_logic;
      clk_sys_i        : in  std_logic;
      rst_n_i          : in  std_logic;
      mfifo_rd_req_o   : out std_logic;
      mfifo_rd_empty_i : in  std_logic;
      mfifo_ad_sel_i   : in  std_logic;
      mfifo_ad_val_i   : in  std_logic_vector(31 downto 0);
      mfifo_trigger_i  : in  std_logic;
      mfifo_busy_o     : out std_logic;
      start_i          : in  std_logic;
      ack_i            : in  std_logic;
      found_o          : out std_logic;
      hash_i           : in  std_logic_vector(g_hash_size-1 downto 0);
      mac_i            : in  std_logic_vector(c_wrsw_mac_addr_width -1 downto 0);
      fid_i            : in  std_logic_vector(c_wrsw_fid_width - 1 downto 0);
      drdy_o           : out std_logic;
      port_i           : in std_logic_vector(g_num_ports -1 downto 0); -- ML (24/03/2013): aging bugfix
      src_dst_i        : in std_logic;                                 -- ML (24/03/2013): aging bugfix
      entry_o          : out t_rtu_htab_entry);
  end component;

----------------------------------------------------------------------------------------
--| CRC-based hash calculation
----------------------------------------------------------------------------------------
  component rtu_crc
    port (
      mac_addr_i : in  std_logic_vector(c_wrsw_mac_addr_width - 1 downto 0);
      fid_i      : in  std_logic_vector(c_wrsw_fid_width - 1 downto 0);
      crc_poly_i : in  std_logic_vector(c_wrsw_crc_width - 1 downto 0);
      hash_o     : out std_logic_vector(c_wrsw_hash_width - 1 downto 0)
      );
  end component;

  component rtu_match
    generic (
      g_num_ports : integer);
    port (
      clk_i                : in  std_logic;
      rst_n_i              : in  std_logic;
      rq_fifo_read_o       : out std_logic;
      rq_fifo_empty_i      : in  std_logic;
      rq_fifo_input_i      : in  std_logic_vector(g_num_ports + c_PACKED_REQUEST_WIDTH - 1 downto 0);
      rsp_fifo_write_o     : out std_logic;
      rsp_fifo_full_i      : in  std_logic;
      rsp_fifo_output_o    : out std_logic_vector(g_num_ports + c_PACKED_RESPONSE_WIDTH - 1 downto 0);
      htab_start_o         : out std_logic;
      htab_ack_o           : out std_logic;
      htab_found_i         : in  std_logic;
      htab_hash_o          : out std_logic_vector(c_wrsw_hash_width - 1 downto 0);
      htab_mac_o           : out std_logic_vector(c_wrsw_mac_addr_width -1 downto 0);
      htab_fid_o           : out std_logic_vector(c_wrsw_fid_width - 1 downto 0);
      htab_drdy_i          : in  std_logic;
      htab_entry_i         : in  t_rtu_htab_entry;
      htab_port_o          : out std_logic_vector(g_num_ports-1 downto 0); -- ML (24/03/2013): aging bugfix
      htab_src_dst_o       : out std_logic;                                -- ML (24/03/2013): aging bugfix
      rtu_ufifo_wr_req_o   : out std_logic;
      rtu_ufifo_wr_full_i  : in  std_logic;
      rtu_ufifo_wr_empty_i : in  std_logic;
      rtu_ufifo_dmac_lo_o  : out std_logic_vector(31 downto 0);
      rtu_ufifo_dmac_hi_o  : out std_logic_vector(15 downto 0);
      rtu_ufifo_smac_lo_o  : out std_logic_vector(31 downto 0);
      rtu_ufifo_smac_hi_o  : out std_logic_vector(15 downto 0);
      rtu_ufifo_vid_o      : out std_logic_vector(c_wrsw_vid_width - 1 downto 0);
      rtu_ufifo_prio_o     : out std_logic_vector(2 downto 0);
      rtu_ufifo_pid_o      : out std_logic_vector(7 downto 0);
      rtu_ufifo_has_vid_o  : out std_logic;
      rtu_ufifo_has_prio_o : out std_logic;
      rtu_aram_main_addr_o : out std_logic_vector(7 downto 0);
      rtu_aram_main_data_i : in  std_logic_vector(31 downto 0);
      rtu_aram_main_rd_o   : out std_logic;
      rtu_aram_main_data_o : out std_logic_vector(31 downto 0);
      rtu_aram_main_wr_o   : out std_logic;
      vlan_tab_addr_o      : out std_logic_vector(c_wrsw_vid_width - 1 downto 0);
      vlan_tab_entry_i     : in  t_rtu_vlan_tab_entry;
      rtu_gcr_g_ena_i      : in  std_logic;
      rtu_pcr_pass_all_i   : in  std_logic_vector(g_num_ports - 1 downto 0);
      rtu_pcr_learn_en_i   : in  std_logic_vector(g_num_ports - 1 downto 0);
      rtu_pcr_pass_bpdu_i  : in  std_logic_vector(g_num_ports - 1 downto 0);
      rtu_pcr_b_unrec_i    : in  std_logic_vector(g_num_ports - 1 downto 0);
      rtu_b_unrec_fw_cpu_i : in std_logic;
      rtu_cpu_mask_i       : in std_logic_vector(c_RTU_MAX_PORTS-1 downto 0); 
      rtu_crc_poly_i       : in  std_logic_vector(c_wrsw_crc_width - 1 downto 0));
  end component;


  component rtu_wishbone_slave
    port (
      rst_n_i         : in  std_logic;
      clk_sys_i       : in  std_logic;
      wb_adr_i        : in  std_logic_vector(8 downto 0);
      wb_dat_i        : in  std_logic_vector(31 downto 0);
      wb_dat_o        : out std_logic_vector(31 downto 0);
      wb_cyc_i        : in  std_logic;
      wb_sel_i        : in  std_logic_vector(3 downto 0);
      wb_stb_i        : in  std_logic;
      wb_we_i         : in  std_logic;
      wb_ack_o        : out std_logic;
      wb_stall_o      : out std_logic;
      wb_int_o        : out std_logic;
      clk_match_i     : in  std_logic;
      irq_nempty_i    : in  std_logic;
      rtu_aram_addr_i : in  std_logic_vector(7 downto 0);
      rtu_aram_data_o : out std_logic_vector(31 downto 0);
      rtu_aram_rd_i   : in  std_logic;
      rtu_aram_data_i : in  std_logic_vector(31 downto 0);
      rtu_aram_wr_i   : in  std_logic;
      regs_i          : in  t_rtu_in_registers;
      regs_o          : out t_rtu_out_registers);
  end component;

  component rtu_wishbone_slave_old
    port (
      rst_n_i         : in  std_logic;
      clk_sys_i       : in  std_logic;
      wb_adr_i        : in  std_logic_vector(8 downto 0);
      wb_dat_i        : in  std_logic_vector(31 downto 0);
      wb_dat_o        : out std_logic_vector(31 downto 0);
      wb_cyc_i        : in  std_logic;
      wb_sel_i        : in  std_logic_vector(3 downto 0);
      wb_stb_i        : in  std_logic;
      wb_we_i         : in  std_logic;
      wb_ack_o        : out std_logic;
      wb_stall_o      : out std_logic;
      wb_int_o        : out std_logic;
      clk_match_i     : in  std_logic;
      irq_nempty_i    : in  std_logic;
      rtu_aram_addr_i : in  std_logic_vector(7 downto 0);
      rtu_aram_data_o : out std_logic_vector(31 downto 0);
      rtu_aram_rd_i   : in  std_logic;
      rtu_aram_data_i : in  std_logic_vector(31 downto 0);
      rtu_aram_wr_i   : in  std_logic;
      regs_i          : in  t_rtu_in_registers;
      regs_o          : out t_rtu_out_registers);
  end component;

  component rtu_fast_match is
    generic (
      g_num_ports : integer;
      g_port_mask_bits : integer);
    port(
      clk_i                     : in  std_logic;
      rst_n_i                   : in  std_logic;
      match_req_i               : in  std_logic_vector(g_num_ports-1 downto 0);
      match_req_data_i          : in  t_rtu_request_array(g_num_ports-1 downto 0);
      match_rsp_data_o          : out t_match_response;
      match_rsp_valid_o         : out std_logic_vector(g_num_ports-1 downto 0);
      vtab_rd_addr_o            : out std_logic_vector(c_wrsw_vid_width-1 downto 0);
      vtab_rd_entry_i           : in  t_rtu_vlan_tab_entry;
      tru_req_o                 : out t_tru_request;
      tru_rsp_i                 : in  t_tru_response;  
      tru_enabled_i             : in  std_logic;
      rtu_str_config_i          : in  t_rtu_special_traffic_config;
      rtu_pcr_pass_all_i        : in  std_logic_vector(c_rtu_max_ports -1 downto 0)
      );
  end component;

end package rtu_private_pkg;


package body rtu_private_pkg is


  function f_unmarshall_htab_entry (w0, w1, w2, w3, w4 : std_logic_vector) return t_rtu_htab_entry is
    variable t : t_rtu_htab_entry;
  begin
    t.bucket_entry := "ZZ";
    t.valid        := w0(0);
    t.is_bpdu      := w0(2);
    t.go_to_cam    := w0(3);
    t.cam_addr     := w2(c_wrsw_cam_addr_width-1 downto 0);
    t.has_prio_src := w2(16);
    t.prio_src     := w2(17 + c_wrsw_prio_width -1 downto 17);
    t.fid          := w0(4 + c_wrsw_fid_width - 1 downto 4);

    t.prio_override_src        := w2(20);
    t.drop_when_src            := w2(21);
    t.drop_unmatched_src_ports := w2(22);
    t.has_prio_dst             := w2(23);
    t.prio_dst                 := w2(24 + c_wrsw_prio_width - 1 downto 24);
    t.prio_override_dst        := w2(27);
    t.drop_when_dst            := w2(28);

    -- src/dst masks
    t.port_mask_src(15 downto 0)                  := w3(15 downto 0);
    t.port_mask_dst(15 downto 0)                  := w3(31 downto 16);
    t.port_mask_src(c_rtu_max_ports-1 downto 16) := w4(c_rtu_max_ports-16-1 downto 0);
    t.port_mask_dst(c_rtu_max_ports-1 downto 16) := w4(c_rtu_max_ports-1 downto 16);

    -- zbt adddr
    -- MAC addr (used only interally, no need to output)   
    t.mac(47 downto 32) := w0(31 downto 16);
    t.mac(31 downto 0)  := w1(31 downto 0);

    return t;
  end function f_unmarshall_htab_entry;

------------------ new stuff ------------------------

   function f_mac_in_range(in_mac, in_mac_lower, in_mac_upper   : std_logic_vector(47 downto 0)
                                                     ) return std_logic is
     variable ret : std_logic;
   begin
     
     ret := '0';
     if((in_mac <= in_mac_upper) and (in_mac >= in_mac_lower)) then
       ret :='1';
     end if;

     return ret;
   end function f_mac_in_range;

   function f_mac_reserved(in_mac : std_logic_vector(47 downto 0)
                                                    ) return std_logic is
     variable ret : std_logic;
   begin
     
     ret := '0';
     if(in_mac(47 downto 8) = c_bpd_range_lower(47 downto 8)) then
       ret :='1';
     end if;

     return ret;
   end function f_mac_reserved;

   function f_fast_match_mac_lookup(match_config : t_rtu_special_traffic_config;
                                     in_mac       : std_logic_vector(47 downto 0)
                                     ) return std_logic is
     variable ret : std_logic;
   begin
     
     ret := '0';
     
     -- pre-configured destination MAC
     if(match_config.ff_mac_single_ena = '1') then
       for i in 0 to c_ff_single_macs_number-1 loop
         if(match_config.single_macs_valid(i) = '1' and in_mac = match_config.single_macs(i)) then
           ret := '1';
         end if;
       end loop;
     end if;
     
     -- pre-configured range of destination addresses
     if(match_config.ff_mac_range_ena = '1') then
       if(match_config.macs_range_valid = '1') then
         if((in_mac <= match_config.macs_range_up) and (in_mac >= match_config.macs_range_down)) then
           ret :='1';
         end if;
       end if;
     end if;

     return ret;
   end function f_fast_match_mac_lookup;


  function f_pick (
    condition : boolean;
    w_true    : std_logic_vector;
    w_false   : std_logic_vector) return std_logic_vector is

  begin
    if(condition) then
      return w_true;
    else
      return w_false;
    end if;
  end function f_pick;

  function f_fast_match_response(vlan_entry      : t_rtu_vlan_tab_entry;
                                 rq_prio         : std_logic_vector;
                                 rq_has_prio     : std_logic;
                                 rq_port_mask    : std_logic_vector;
                                 traffic_br      : std_logic;
                                 pcr_pass_all    : std_logic_vector;
                                 pcr_drop_nonvlan_at_ingress: std_logic_vector;
                                 port_mask_width : integer) 
                                 return t_match_response is
    variable rsp : t_match_response;
    variable egress_allowed_on_vlan : std_logic;
  begin
    ------- mask -----------
     rsp.port_mask := (others =>'0');
    
    ------- prio ----------
    if(vlan_entry.has_prio = '1') then -- regardless of vlan_entry.prio_override value
      rsp.prio    := vlan_entry.prio;
    elsif(rq_has_prio = '1') then
      rsp.prio    := rq_prio;
    else
      rsp.prio    := (others =>'0');      
    end if;
    
    ------ drop ----------
    if(((rq_port_mask and pcr_drop_nonvlan_at_ingress(rq_port_mask'length-1 downto 0)) = rq_port_mask) and
       ((rq_port_mask and vlan_entry.port_mask(rq_port_mask'length-1 downto 0))       /= rq_port_mask)) then
      rsp.drop      := '1';
      rsp.port_mask := (others =>'0');
    elsif(vlan_entry.drop = '1') then
      rsp.drop      := '1';
      rsp.port_mask := (others =>'0');      
    elsif(traffic_br = '1') then
      rsp.port_mask := vlan_entry.port_mask and pcr_pass_all; -- broadcast also to NIC !!!!!!
      rsp.drop   := '0';
    else
      rsp.drop   := '0';
      rsp.port_mask(port_mask_width-1 downto 0) := vlan_entry.port_mask(port_mask_width-1 downto 0) and 
                                                   pcr_pass_all(port_mask_width-1 downto 0);
    end if;
    
    ------ filled in later -----------
--     rsp.bpdu   := '0';
    rsp.ff     := '0';
    rsp.nf     := '0';
    rsp.hp     := '0';
    rsp.valid  := '0';
    
    return rsp;
    
  end function f_fast_match_response;

  function f_set_bit(data     : std_logic_vector;
                     bit_val  : std_logic;
                     bit_num  : integer          ) return std_logic_vector is
    variable ret : std_logic_vector(data'length-1 downto 0);
  begin
    ret          := data;
    ret(bit_num) := bit_val;
    return ret;
  end function f_set_bit;
  function f_onehot_decode
    (x : std_logic_vector) return integer is
  begin
    for i in 0 to x'length-1 loop
      if(x(i) = '1') then
        return i;
      end if;
    end loop;  -- i
    return 0;
  end f_onehot_decode;
--   function doPortMask(
--               s_fast_match                                         : std_logic: -- info what kind of input we have
--               s_rtu_pcr_pass_bpdu, s_rtu_pcr_pass_all              : std_logic; -- general config
--               s_dst_entry_is_bpdu                                  : std_logic; -- info from full match
--               s_vlan_prio_override, s_vlan_has_prio, s_rq_has_prio : std_logic; -- validity of different priorities
--               s_rq_prio, s_vlan_prio                               : std_logic_vector; -- different priorities
--               s_vlan_port_mask, s_full_match_mask, s_tru_mask      : std_logic_vector; -- different masks
--               s_vlan_drop, s_tru_drop                              : std_logic;
--               ) return t_rtu_response is
--     variable s_rsp_drop          : t_rtu_response;
-- 
--    begin 
--    
--            rsp.valid             := '1';
--            rsp.port_mask         := (others=>'0');
--            rsp.prio              := (others=>'0');
--            rsp.drop              :='0';
-- 
--            if(s_fast_match = '1')  then -------------- we need to do some additional work (normally done in match)
--               
--               if(s_rtu_pcr_pass_all = '0') then -- we assume here that the PBDU is forwarded to FULL Match
--                 rsp.port_mask        := (others => '0');
--                 rsp.prio             := (others => '0');
--                 rsp.drop             := '1';
--                 rsp.valid            := '1';
-- 
--               else
-- 
--                 rsp.port_mask       := s_vlan_port_mask;
-- 
--                 if (s_vlan_prio_override = '1' and s_vlan_has_prio = '1') then
--                   -- take vlan priority
--                   rsp.prio := s_vlan_prio;
--                 else
--                   if (s_vlan_has_prio = '1') then
--                     -- take vlan priority
--                     rsp.prio := s_vlan_prio;
--                   elsif (s_port_has_prio = '1') then
--                     -- take port priority
--                     rsp.prio := s_port_prio;
--                   else
--                     -- nothning matching
--                     rsp.prio := (others => '0');
--                   end if;  -- if (s_vlan_has_prio = '1') then
--                 end if;  -- (s_vlan_prio_override = '1' and s_vlan_has_prio = '1') 
--               end if;  -- (s_rtu_pcr_pass_all = '0') 
--               
--               rsp.port_mask := rsp.port_mask and s_tru_mask;
--               rsp.drop      := s_tru_drop or s_vlan_drop;
--               ---
--               ---                    POSSIBLE BUG 
--               --- what about if the source port is not in the VLAN ??
--               ---
--               
--            end if; --   if(s_fast_match = '1') 
--            
--            -- we had normal match and it was BPDU pck, so it should be sent to all
--            -- ports, regardless of TRU decision
--            if(s_dst_entry_is_bpdu = '1' and s_fast_match = '0') then
--              rsp.port_mask := s_full_match_mask;
--            elsif(s_dst_entry_is_bpdu = '0' and s_fast_match = '0') then
--              rsp.port_mask := s_full_match_mask and s_tru_mask;
--            else
--              rsp.port_mask := rsp.port_mask and s_tru_mask
--            end if;
-- 
-- 
--   
--   end doPortMask;


end rtu_private_pkg;
