-------------------------------------------------------------------------------
-- Title      : Routing Table Unit's Components Package 
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_rtu_components_pkg.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-05-09
-- Last update: 2012-01-25
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Routing Table Unit components
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
-- Date        Version  Author          Description
-- 2010-05-09  1.0      lipinskimm          Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.wishbone_pkg.all;              -- for test part (to be moved)
package wrsw_rtu_private_pkg is

----------------------------------------------------------------------------------------
--| RTU top level
----------------------------------------------------------------------------------------

-- Number of switch ports (including NIC)
  constant c_wrsw_num_ports_max      : integer                           := 20; -- need for WB I/F
  constant c_wrsw_num_ports          : integer                           := 16;
  constant c_wrsw_mac_addr_width     : integer                           := 48;
  constant c_wrsw_vid_width          : integer                           := 12;
  constant c_wrsw_prio_width         : integer                           := 3;
  constant c_wrsw_prio_levels        : integer                           := 8;
  constant c_rtu_num_ports           : integer                           := 15;--10;  --c_wrsw_num_ports - 1;
  constant c_wrsw_fid_width          : integer                           := 8;
  constant c_wrsw_hash_width         : integer                           := 9;
  constant c_wrsw_crc_width          : integer                           := 16;
  constant c_wrsw_cam_addr_width     : integer                           := 8;
  constant c_wrsw_entry_words_number : std_logic_vector(5 downto 0)      := "000101";
  constant c_wrsw_rtu_debugging      : std_logic                         := '0';
  constant c_default_hash_poly       : std_logic_vector(16 - 1 downto 0) := x"1021";


  type t_rtu_htab_entry is record
    valid     : std_logic;
    is_bpdu   : std_logic;
    go_to_cam : std_logic;
    cam_addr  : std_logic_vector(c_wrsw_cam_addr_width-1 downto 0);
    fid       : std_logic_vector(c_wrsw_fid_width-1 downto 0);
    mac       : std_logic_vector(47 downto 0);

    bucket_entry : std_logic_vector(1 downto 0);

    port_mask_src            : std_logic_vector(c_wrsw_num_ports-1 downto 0);
    port_mask_dst            : std_logic_vector(c_wrsw_num_ports-1 downto 0);
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

  component wrsw_rtu
    port (
      clk_sys_i           : in  std_logic;
      clk_match_i         : in  std_logic;
      rst_n_i             : in  std_logic;
      rtu_idle_o          : out std_logic_vector(c_rtu_num_ports-1 downto 0);
      rq_strobe_p_i       : in  std_logic_vector(c_rtu_num_ports-1 downto 0);
      rq_smac_i           : in  std_logic_vector(c_wrsw_mac_addr_width * c_rtu_num_ports - 1 downto 0);
      rq_dmac_i           : in  std_logic_vector(c_wrsw_mac_addr_width * c_rtu_num_ports -1 downto 0);
      rq_vid_i            : in  std_logic_vector(c_wrsw_vid_width * c_rtu_num_ports - 1 downto 0);
      rq_has_vid_i        : in  std_logic_vector(c_rtu_num_ports -1 downto 0);
      rq_prio_i           : in  std_logic_vector(c_wrsw_prio_width * c_rtu_num_ports -1 downto 0);
      rq_has_prio_i       : in  std_logic_vector(c_rtu_num_ports -1 downto 0);
      rsp_valid_o         : out std_logic_vector (c_rtu_num_ports-1 downto 0);
      rsp_dst_port_mask_o : out std_logic_vector(c_wrsw_num_ports * c_rtu_num_ports - 1 downto 0);
      rsp_drop_o          : out std_logic_vector(c_rtu_num_ports -1 downto 0);
      rsp_prio_o          : out std_logic_vector (c_rtu_num_ports * c_wrsw_prio_width-1 downto 0);
      rsp_ack_i           : in  std_logic_vector(c_rtu_num_ports -1 downto 0);
      port_almost_full_o  : out std_logic_vector(c_rtu_num_ports -1 downto 0);
      port_full_o         : out std_logic_vector(c_rtu_num_ports -1 downto 0);
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
  component wrsw_rtu_port
    generic (
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
      rsp_dst_port_mask_o    : out std_logic_vector(c_wrsw_num_ports - 1 downto 0);
      rsp_drop_o             : out std_logic;
      rsp_prio_o             : out std_logic_vector (c_wrsw_prio_width-1 downto 0);
      rsp_ack_i              : in  std_logic;
      rq_fifo_write_o        : out std_logic;
      rq_fifo_full_i         : in  std_logic;
      rq_fifo_data_o         : out std_logic_vector(c_wrsw_mac_addr_width + c_wrsw_mac_addr_width + c_wrsw_vid_width + c_wrsw_prio_width + 2 - 1 downto 0);
      rsp_write_i            : in  std_logic;
      rsp_match_data_i       : in  std_logic_vector(c_wrsw_num_ports + c_wrsw_prio_width + 1 +c_rtu_num_ports - 1 downto 0);
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
----------------------------------------------------------------------------------------
--| Round Robin Arbiter
----------------------------------------------------------------------------------------

  component wrsw_rr_arbiter is
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
      entry_o          : out t_rtu_htab_entry);
  end component;

  component wrsw_rtu_wb
    port (
      rst_n_i                  : in  std_logic;
      wb_clk_i                 : in  std_logic;
      wb_addr_i                : in  std_logic_vector(13 downto 0);
      wb_data_i                : in  std_logic_vector(31 downto 0);
      wb_data_o                : out std_logic_vector(31 downto 0);
      wb_cyc_i                 : in  std_logic;
      wb_sel_i                 : in  std_logic_vector(3 downto 0);
      wb_stb_i                 : in  std_logic;
      wb_we_i                  : in  std_logic;
      wb_ack_o                 : out std_logic;
      wb_irq_o                 : out std_logic;
      clk_match_i              : in  std_logic;
      rtu_gcr_g_ena_o          : out std_logic;
      rtu_gcr_mfifotrig_o      : out std_logic;
      rtu_gcr_mfifotrig_i      : in  std_logic;
      rtu_gcr_mfifotrig_load_o : out std_logic;
      rtu_gcr_poly_val_o       : out std_logic_vector(15 downto 0);
      irq_nempty_i             : in  std_logic;
      rtu_ufifo_wr_req_i       : in  std_logic;
      rtu_ufifo_wr_full_o      : out std_logic;
      rtu_ufifo_wr_empty_o     : out std_logic;
      rtu_ufifo_dmac_lo_i      : in  std_logic_vector(31 downto 0);
      rtu_ufifo_dmac_hi_i      : in  std_logic_vector(15 downto 0);
      rtu_ufifo_smac_lo_i      : in  std_logic_vector(31 downto 0);
      rtu_ufifo_smac_hi_i      : in  std_logic_vector(15 downto 0);
      rtu_ufifo_vid_i          : in  std_logic_vector(11 downto 0);
      rtu_ufifo_prio_i         : in  std_logic_vector(2 downto 0);
      rtu_ufifo_pid_i          : in  std_logic_vector(3 downto 0);
      rtu_ufifo_has_vid_i      : in  std_logic;
      rtu_ufifo_has_prio_i     : in  std_logic;
      rtu_aram_main_addr_i     : in  std_logic_vector(7 downto 0);
      rtu_aram_main_data_o     : out std_logic_vector(31 downto 0);
      rtu_aram_main_rd_i       : in  std_logic;
      rtu_aram_main_data_i     : in  std_logic_vector(31 downto 0);
      rtu_aram_main_wr_i       : in  std_logic;
      rtu_vlan_tab_addr_i      : in  std_logic_vector(11 downto 0);
      rtu_vlan_tab_data_o      : out std_logic_vector(31 downto 0);
      rtu_vlan_tab_rd_i        : in  std_logic;
      rtu_agr_hcam_o           : out std_logic_vector(31 downto 0);
      rtu_agr_hcam_i           : in  std_logic_vector(31 downto 0);
      rtu_agr_hcam_load_o      : out std_logic;
      rtu_mfifo_rd_req_i       : in  std_logic;
      rtu_mfifo_rd_empty_o     : out std_logic;
      rtu_mfifo_rd_usedw_o     : out std_logic_vector(5 downto 0);
      rtu_mfifo_ad_sel_o       : out std_logic;
      rtu_mfifo_ad_val_o       : out std_logic_vector(31 downto 0);
      rtu_pcr0_learn_en_o      : out std_logic;
      rtu_pcr0_pass_all_o      : out std_logic;
      rtu_pcr0_pass_bpdu_o     : out std_logic;
      rtu_pcr0_fix_prio_o      : out std_logic;
      rtu_pcr0_prio_val_o      : out std_logic_vector(2 downto 0);
      rtu_pcr0_b_unrec_o       : out std_logic;
      rtu_pcr1_learn_en_o      : out std_logic;
      rtu_pcr1_pass_all_o      : out std_logic;
      rtu_pcr1_pass_bpdu_o     : out std_logic;
      rtu_pcr1_fix_prio_o      : out std_logic;
      rtu_pcr1_prio_val_o      : out std_logic_vector(2 downto 0);
      rtu_pcr1_b_unrec_o       : out std_logic;
      rtu_pcr2_learn_en_o      : out std_logic;
      rtu_pcr2_pass_all_o      : out std_logic;
      rtu_pcr2_pass_bpdu_o     : out std_logic;
      rtu_pcr2_fix_prio_o      : out std_logic;
      rtu_pcr2_prio_val_o      : out std_logic_vector(2 downto 0);
      rtu_pcr2_b_unrec_o       : out std_logic;
      rtu_pcr3_learn_en_o      : out std_logic;
      rtu_pcr3_pass_all_o      : out std_logic;
      rtu_pcr3_pass_bpdu_o     : out std_logic;
      rtu_pcr3_fix_prio_o      : out std_logic;
      rtu_pcr3_prio_val_o      : out std_logic_vector(2 downto 0);
      rtu_pcr3_b_unrec_o       : out std_logic;
      rtu_pcr4_learn_en_o      : out std_logic;
      rtu_pcr4_pass_all_o      : out std_logic;
      rtu_pcr4_pass_bpdu_o     : out std_logic;
      rtu_pcr4_fix_prio_o      : out std_logic;
      rtu_pcr4_prio_val_o      : out std_logic_vector(2 downto 0);
      rtu_pcr4_b_unrec_o       : out std_logic;
      rtu_pcr5_learn_en_o      : out std_logic;
      rtu_pcr5_pass_all_o      : out std_logic;
      rtu_pcr5_pass_bpdu_o     : out std_logic;
      rtu_pcr5_fix_prio_o      : out std_logic;
      rtu_pcr5_prio_val_o      : out std_logic_vector(2 downto 0);
      rtu_pcr5_b_unrec_o       : out std_logic;
      rtu_pcr6_learn_en_o      : out std_logic;
      rtu_pcr6_pass_all_o      : out std_logic;
      rtu_pcr6_pass_bpdu_o     : out std_logic;
      rtu_pcr6_fix_prio_o      : out std_logic;
      rtu_pcr6_prio_val_o      : out std_logic_vector(2 downto 0);
      rtu_pcr6_b_unrec_o       : out std_logic;
      rtu_pcr7_learn_en_o      : out std_logic;
      rtu_pcr7_pass_all_o      : out std_logic;
      rtu_pcr7_pass_bpdu_o     : out std_logic;
      rtu_pcr7_fix_prio_o      : out std_logic;
      rtu_pcr7_prio_val_o      : out std_logic_vector(2 downto 0);
      rtu_pcr7_b_unrec_o       : out std_logic;
      rtu_pcr8_learn_en_o      : out std_logic;
      rtu_pcr8_pass_all_o      : out std_logic;
      rtu_pcr8_pass_bpdu_o     : out std_logic;
      rtu_pcr8_fix_prio_o      : out std_logic;
      rtu_pcr8_prio_val_o      : out std_logic_vector(2 downto 0);
      rtu_pcr8_b_unrec_o       : out std_logic;
      rtu_pcr9_learn_en_o      : out std_logic;
      rtu_pcr9_pass_all_o      : out std_logic;
      rtu_pcr9_pass_bpdu_o     : out std_logic;
      rtu_pcr9_fix_prio_o      : out std_logic;
      rtu_pcr9_prio_val_o      : out std_logic_vector(2 downto 0);
      rtu_pcr9_b_unrec_o       : out std_logic;
      rtu_pcr10_learn_en_o     : out std_logic;
      rtu_pcr10_pass_all_o     : out std_logic;
      rtu_pcr10_pass_bpdu_o    : out std_logic;
      rtu_pcr10_fix_prio_o     : out std_logic;
      rtu_pcr10_prio_val_o     : out std_logic_vector(2 downto 0);
      rtu_pcr10_b_unrec_o      : out std_logic;
      rtu_pcr11_learn_en_o     : out std_logic;
      rtu_pcr11_pass_all_o     : out std_logic;
      rtu_pcr11_pass_bpdu_o    : out std_logic;
      rtu_pcr11_fix_prio_o     : out std_logic;
      rtu_pcr11_prio_val_o     : out std_logic_vector(2 downto 0);
      rtu_pcr11_b_unrec_o      : out std_logic;
      rtu_pcr12_learn_en_o     : out std_logic;
      rtu_pcr12_pass_all_o     : out std_logic;
      rtu_pcr12_pass_bpdu_o    : out std_logic;
      rtu_pcr12_fix_prio_o     : out std_logic;
      rtu_pcr12_prio_val_o     : out std_logic_vector(2 downto 0);
      rtu_pcr12_b_unrec_o      : out std_logic;
      rtu_pcr13_learn_en_o     : out std_logic;
      rtu_pcr13_pass_all_o     : out std_logic;
      rtu_pcr13_pass_bpdu_o    : out std_logic;
      rtu_pcr13_fix_prio_o     : out std_logic;
      rtu_pcr13_prio_val_o     : out std_logic_vector(2 downto 0);
      rtu_pcr13_b_unrec_o      : out std_logic;
      rtu_pcr14_learn_en_o     : out std_logic;
      rtu_pcr14_pass_all_o     : out std_logic;
      rtu_pcr14_pass_bpdu_o    : out std_logic;
      rtu_pcr14_fix_prio_o     : out std_logic;
      rtu_pcr14_prio_val_o     : out std_logic_vector(2 downto 0);
      rtu_pcr14_b_unrec_o      : out std_logic;
      rtu_pcr15_learn_en_o     : out std_logic;
      rtu_pcr15_pass_all_o     : out std_logic;
      rtu_pcr15_pass_bpdu_o    : out std_logic;
      rtu_pcr15_fix_prio_o     : out std_logic;
      rtu_pcr15_prio_val_o     : out std_logic_vector(2 downto 0);
      rtu_pcr15_b_unrec_o      : out std_logic;
      rtu_pcr16_learn_en_o     : out std_logic;
      rtu_pcr16_pass_all_o     : out std_logic;
      rtu_pcr16_pass_bpdu_o    : out std_logic;
      rtu_pcr16_fix_prio_o     : out std_logic;
      rtu_pcr16_prio_val_o     : out std_logic_vector(2 downto 0);
      rtu_pcr16_b_unrec_o      : out std_logic;
      rtu_pcr17_learn_en_o     : out std_logic;
      rtu_pcr17_pass_all_o     : out std_logic;
      rtu_pcr17_pass_bpdu_o    : out std_logic;
      rtu_pcr17_fix_prio_o     : out std_logic;
      rtu_pcr17_prio_val_o     : out std_logic_vector(2 downto 0);
      rtu_pcr17_b_unrec_o      : out std_logic;
      rtu_pcr18_learn_en_o     : out std_logic;
      rtu_pcr18_pass_all_o     : out std_logic;
      rtu_pcr18_pass_bpdu_o    : out std_logic;
      rtu_pcr18_fix_prio_o     : out std_logic;
      rtu_pcr18_prio_val_o     : out std_logic_vector(2 downto 0);
      rtu_pcr18_b_unrec_o      : out std_logic;
      rtu_pcr19_learn_en_o     : out std_logic;
      rtu_pcr19_pass_all_o     : out std_logic;
      rtu_pcr19_pass_bpdu_o    : out std_logic;
      rtu_pcr19_fix_prio_o     : out std_logic;
      rtu_pcr19_prio_val_o     : out std_logic_vector(2 downto 0);
      rtu_pcr19_b_unrec_o      : out std_logic

);
  end component;
----------------------------------------------------------------------------------------
--| CRC-based hash calculation
----------------------------------------------------------------------------------------
  component wrsw_rtu_crc
    port (
      mac_addr_i : in  std_logic_vector(c_wrsw_mac_addr_width - 1 downto 0);
      fid_i      : in  std_logic_vector(c_wrsw_fid_width - 1 downto 0);
      crc_poly_i : in  std_logic_vector(c_wrsw_crc_width - 1 downto 0);
      hash_o     : out std_logic_vector(c_wrsw_hash_width - 1 downto 0)
      );
  end component;


  component wrsw_rtu_match
    port(

      -----------------------------------------------------------------
      --| General IOs
      -----------------------------------------------------------------
      -- clock (62.5 MHz refclk/2)
      clk_i   : in std_logic;
      -- reset (synchronous, active low)
      rst_n_i : in std_logic;

      -------------------------------------------------------------------------------
      -- input request
      -------------------------------------------------------------------------------

      -- read request FIFO.
      rq_fifo_read_o : out std_logic;

      -- request FIFO is empty - there is no work for us:(
      rq_fifo_empty_i : in std_logic;

      -- input from request FIFO        
      rq_fifo_input_i : in std_logic_vector(c_rtu_num_ports +  -- request port ID
                                            c_wrsw_mac_addr_width +  -- destination MAC
                                            c_wrsw_mac_addr_width +  -- source MAC
                                            c_wrsw_vid_width +   -- VLAN ID
                                            c_wrsw_prio_width +  -- PRIORITY 
                                            1 +                -- has_prio    
                                            1 - 1 downto 0);   -- has vid

      -------------------------------------------------------------------------------
      -- output response
      -------------------------------------------------------------------------------

      -- write data to response FIFO
      rsp_fifo_write_o : out std_logic;

      -- response FIFO is full
      rsp_fifo_full_i   : in  std_logic;
      -- ouput response (to response FIFO):    
      rsp_fifo_output_o : out std_logic_vector(c_rtu_num_ports +  -- request port ID
                                               c_wrsw_num_ports +  -- forward port mask  
                                               c_wrsw_prio_width +  -- priority
                                               1 - 1 downto 0);   -- drop

      htab_start_o : out std_logic;
      --  htab_idle_i: in std_logic;
      htab_ack_o   : out std_logic;
      htab_found_i : in  std_logic;
      htab_hash_o  : out std_logic_vector(c_wrsw_hash_width - 1 downto 0);
      htab_mac_o   : out std_logic_vector(c_wrsw_mac_addr_width -1 downto 0);
      htab_fid_o   : out std_logic_vector(c_wrsw_fid_width - 1 downto 0);
      htab_drdy_i  : in  std_logic;
--    htab_valid_i : in  std_logic;

      htab_entry_i : in t_rtu_htab_entry;

      -------------------------------------------------------------------------------
      -- Unrecongized FIFO (operated by WB)
      -------------------------------------------------------------------------------  
      -- FIFO write request
      rtu_ufifo_wr_req_o : out std_logic;

      -- FIFO full flag
      rtu_ufifo_wr_full_i : in std_logic;

      -- FIFO empty flag
      rtu_ufifo_wr_empty_i : in  std_logic;
      rtu_ufifo_dmac_lo_o  : out std_logic_vector(31 downto 0);
      rtu_ufifo_dmac_hi_o  : out std_logic_vector(15 downto 0);
      rtu_ufifo_smac_lo_o  : out std_logic_vector(31 downto 0);
      rtu_ufifo_smac_hi_o  : out std_logic_vector(15 downto 0);
      rtu_ufifo_vid_o      : out std_logic_vector(c_wrsw_vid_width - 1 downto 0);
      rtu_ufifo_prio_o     : out std_logic_vector(2 downto 0);
      rtu_ufifo_pid_o      : out std_logic_vector(3 downto 0);
      rtu_ufifo_has_vid_o  : out std_logic;
      rtu_ufifo_has_prio_o : out std_logic;


      -------------------------------------------------------------------------------
      -- Aging registers(operated by WB)
      ------------------------------------------------------------------------------- 
      -- Ports for RAM: Aging bitmap for main hashtable
      rtu_aram_main_addr_o : out std_logic_vector(7 downto 0);

      -- Read data output
      rtu_aram_main_data_i : in std_logic_vector(31 downto 0);

      -- Read strobe input (active high)
      rtu_aram_main_rd_o : out std_logic;

      -- Write data input
      rtu_aram_main_data_o : out std_logic_vector(31 downto 0);

      -- Write strobe (active high)
      rtu_aram_main_wr_o : out std_logic;

      -- Port for std_logic_vector field: 'Aging register value' in reg: 'Aging register for HCAM'
      rtu_agr_hcam_i      : in  std_logic_vector(31 downto 0);
      rtu_agr_hcam_o      : out std_logic_vector(31 downto 0);
      rtu_agr_hcam_load_i : in  std_logic;

      -------------------------------------------------------------------------------
      -- VLAN TABLE
      -------------------------------------------------------------------------------   

      rtu_vlan_tab_addr_o : out std_logic_vector(c_wrsw_vid_width - 1 downto 0);
      rtu_vlan_tab_data_i : in  std_logic_vector(31 downto 0);
      rtu_vlan_tab_rd_o   : out std_logic;

      -------------------------------------------------------------------------------
      -- CTRL registers
      ------------------------------------------------------------------------------- 
      -- RTU Global Enable : Global RTU enable bit. Overrides all port settings. 
      --   0: RTU is disabled. All packets are dropped.
      ---  1: RTU is enabled.
      rtu_gcr_g_ena_i : in std_logic;

      -- PASS_ALL [read/write]: Pass all packets
      -- 1: all packets are passed (depending on the rules in RT table).
      -- 0: all packets are dropped on this port. 
      rtu_pcr_pass_all_i : in std_logic_vector(c_rtu_num_ports - 1 downto 0);

      -- LEARN_EN : Learning enable
      -- 1: enables learning process on this port. Unrecognized requests will be put into UFIFO
      -- 0: disables learning. Unrecognized requests will be either broadcast or dropped. 
      rtu_pcr_learn_en_i : in std_logic_vector(c_rtu_num_ports - 1 downto 0);

      -- PASS_BPDU : Pass BPDUs
      -- 1: BPDU packets (with dst MAC 01:80:c2:00:00:00) are passed according to RT rules. This setting overrides PASS_ALL.
      -- 0: BPDU packets are dropped. 
      rtu_pcr_pass_bpdu_i : in std_logic_vector(c_rtu_num_ports - 1 downto 0);

      -- [TODO implemented] B_UNREC : Unrecognized request behaviour
      -- Sets the port behaviour for all unrecognized requests:
      -- 0: packet is dropped
      -- 1: packet is broadcast     
      rtu_pcr_b_unrec_i : in std_logic_vector(c_rtu_num_ports - 1 downto 0);

      -------------------------------------------------------------------------------
      -- HASH based on CRC
      -------------------------------------------------------------------------------   
      rtu_crc_poly_i : in std_logic_vector(c_wrsw_crc_width - 1 downto 0)

      );
  end component;

  function f_unmarshall_htab_entry (w0, w1, w2, w3 : std_logic_vector) return t_rtu_htab_entry;

end package wrsw_rtu_private_pkg;


package body wrsw_rtu_private_pkg is


function f_unmarshall_htab_entry (w0, w1, w2, w3 : std_logic_vector) return t_rtu_htab_entry is
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
  t.port_mask_src := w3(c_wrsw_num_ports -1 downto 0);
  t.port_mask_dst := w3(16 + c_wrsw_num_ports -1 downto 16);

  -- zbt adddr
  -- MAC addr (used only interally, no need to output)   
  t.mac(47 downto 32) := w0(31 downto 16);
  t.mac(31 downto 0)  := w1(31 downto 0);

  return t;
end function f_unmarshall_htab_entry;



end wrsw_rtu_private_pkg;
