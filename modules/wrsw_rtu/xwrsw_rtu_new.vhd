-------------------------------------------------------------------------------
-- Title      : eXtended Routing Table Unit (RTU)
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_rtu.vhd
-- Authors    : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2012-01-10
-- Last update: 2012-06-25
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description: With usable interface 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 Tomasz Wlostowski / CERN
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
-- 2012-01-10  1.0      twlostow created
-- 2010-11-29  1.1      mlipinsk connected prio, added temp_hack
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;
use ieee.numeric_std.all;

use work.wishbone_pkg.all;
use work.wrsw_shared_types_pkg.all;
use work.rtu_private_pkg.all;
use work.pack_unpack_pkg.all;
use work.genram_pkg.all;
-- use work.rtu_wbgen2_pkg_old.all;
use work.rtu_wbgen2_pkg.all;
use work.gencores_pkg.all;

entity xwrsw_rtu_new is
  
  generic (
    g_interface_mode                  : t_wishbone_interface_mode      := PIPELINED;
    g_address_granularity             : t_wishbone_address_granularity := BYTE;
    g_handle_only_single_req_per_port : boolean                        := FALSE;
    g_prio_num                        : integer;
    g_num_ports                       : integer;
    g_match_req_fifo_size             : integer                        := 32;    
    g_port_mask_bits                  : integer);

  port (
    clk_sys_i   : in std_logic;
    rst_n_i     : in std_logic;

    req_i       : in  t_rtu_request_array(g_num_ports-1 downto 0);
    req_full_o  : out std_logic_vector(g_num_ports-1 downto 0);

    rsp_o       : out t_rtu_response_array(g_num_ports-1 downto 0);
    rsp_ack_i   : in  std_logic_vector(g_num_ports-1 downto 0);

    tru_req_o   : out  t_tru_request;
    tru_resp_i  : in   t_tru_response;  
    rtu2tru_o   : out  t_rtu2tru;
    tru_enabled_i: in std_logic;
    wb_i        : in  t_wishbone_slave_in;
    wb_o        : out t_wishbone_slave_out
    );

end xwrsw_rtu_new;
architecture behavioral of xwrsw_rtu_new is

  constant c_prio_num_width       : integer := integer(CEIL(LOG2(real(g_prio_num ))));
  constant c_g_num_ports_width    : integer := integer(CEIL(LOG2(real(g_num_ports ))));
  constant c_VLAN_TAB_ENTRY_WIDTH : integer := 46;
  constant c_match_req_fifo_size  : integer := g_match_req_fifo_size + g_num_ports;
  constant c_match_req_fifo_size_width : integer := integer(CEIL(LOG2(real(c_match_req_fifo_size ))));

  -- PORT_N -> MATCH_FIFO_ACCESS (round robin access to FIFO)
  signal rq_fifo_wr_access                  : std_logic_vector(g_num_ports-1 downto 0);
  signal rq_fifo_wr_data                    : std_logic_vector(g_num_ports*c_PACKED_REQUEST_WIDTH-1 downto 0);
  signal rq_fifo_wr_done                    : std_logic_vector(g_num_ports-1 downto 0);
  
  -- MATCH_FIFO_ACCESS -> U_ReqFifo (FIFO with request for MATCH engine)
  signal rr_mux_wr_vector                   : std_logic_vector(g_num_ports-1 downto 0);
  signal rr_mux_wr_data                     : std_logic_vector(c_PACKED_REQUEST_WIDTH-1 downto 0);
  signal rr_mux_wr_fifo_data                : std_logic_vector(g_num_ports+c_PACKED_REQUEST_WIDTH-1 downto 0);
  signal rr_mux_wr_req                      : std_logic;
  signal rr_mux_wr_id                       : std_logic_vector(c_g_num_ports_width-1 downto 0);
  
  -- U_ReqFifo -> rtu_match
  signal rq_fifo_read                       : std_logic;
  signal rq_fifo_qvalid                     : std_logic;
  signal rq_fifo_data                       : std_logic_vector(g_num_ports + c_PACKED_REQUEST_WIDTH - 1 downto 0);
  signal rq_fifo_full                       : std_logic;
  signal rq_fifo_almost_full                : std_logic;
  signal rq_fifo_full_for_ports             : std_logic;
  signal rq_fifo_empty                      : std_logic;
  
  -- rtu_match -> PORTs
  signal rsp_valid                          : std_logic;
  signal rsp_data                           : std_logic_vector(g_num_ports + c_PACKED_RESPONSE_WIDTH - 1 downto 0);
  
  -- PORT_N -> VLAN_READ_ACCESS
  signal vtab_rd_addr                       : std_logic_vector(c_wrsw_vid_width*g_num_ports-1 downto 0);
  signal vtab_rd_req                        : std_logic_vector(g_num_ports-1 downto 0);

  -- VLAN_READ_ACCESS -> VLAN TABLE
  signal rr_mux_vtab_addr                   : std_logic_vector(c_wrsw_vid_width-1 downto 0);
  signal rr_mux_vtab_addr_valid             : std_logic;
  
  -- VLAN TABLE/VLAN_READ_ACCESS -> PORTs
  --signal rr_mux_vtab_addr_id                : std_logic_vector(integer(CEIL(LOG2(real(c_wrsw_vid_width))))-1 downto 0);
  signal rr_mux_vtab_addr_id                : std_logic_vector(f_log2_size(g_num_ports)-1 downto 0);--(4 downto 0);
  signal rr_mux_vtab_addr_vector            : std_logic_vector(g_num_ports-1 downto 0);
  signal vtab_rd_valid                      : std_logic_vector(g_num_ports-1 downto 0);  
  signal vtab_rd_data                       : std_logic_vector(c_VLAN_TAB_ENTRY_WIDTH-1 downto 0);
  
  -- rtu_match -> rtu_lookup_engine (HTAB interface)
  signal htab_start                         : std_logic;
  signal htab_ack                           : std_logic;
  signal htab_hash                          : std_logic_vector(c_wrsw_hash_width-1 downto 0);
  signal htab_mac                           : std_logic_vector(47 downto 0);
  signal htab_fid                           : std_logic_vector(7 downto 0);
  signal htab_found                         : std_logic;
  signal htab_drdy                          : std_logic;
  signal htab_valid                         : std_logic;
  signal htab_entry                         : t_rtu_htab_entry;  

  -- U_WB_Slave <-> others
  type   t_pcr_prio_val_array is array(integer range <>) of std_logic_vector(c_wrsw_prio_width-1 downto 0);
  signal pcr_learn_en                       : std_logic_vector(c_rtu_max_ports - 1 downto 0);
  signal pcr_pass_all                       : std_logic_vector(c_rtu_max_ports - 1 downto 0);
  signal pcr_pass_bpdu                      : std_logic_vector(c_rtu_max_ports - 1 downto 0);
  signal pcr_fix_prio                       : std_logic_vector(c_rtu_max_ports - 1 downto 0);
  signal pcr_prio_val                       : t_pcr_prio_val_array(c_rtu_max_ports-1 downto 0);
  signal pcr_b_unrec                        : std_logic_vector(c_rtu_max_ports - 1 downto 0);
  signal regs_towb                          : t_rtu_in_registers;
  signal regs_fromwb                        : t_rtu_out_registers;
  signal current_pcr                        : integer;
  signal current_mac_ID                     : integer;
  signal rtu_gcr_poly_used                  : std_logic_vector(15 downto 0);
  signal mfifo_trigger                      : std_logic;
  signal current_MAC_entry                  : std_logic_vector(47 downto 0);

  --|HCAM - Hash collision memory
  signal aram_main_addr                     : std_logic_vector(7 downto 0);
  signal aram_main_data_i                   : std_logic_vector(31 downto 0);
  signal aram_main_data_o                   : std_logic_vector(31 downto 0);
  signal aram_main_rd                       : std_logic;
  signal aram_main_wr                       : std_logic;
  
  --
  signal rsp_fifo_empty                     : std_logic;
  signal irq_nempty                         : std_logic;

  signal wb_in                              : t_wishbone_slave_in;
  signal wb_out                             : t_wishbone_slave_out;

  signal vlan_tab_rd_vid                    : std_logic_vector(c_wrsw_vid_width-1 downto 0);
  signal vlan_tab_wr_data                   : std_logic_vector(c_VLAN_TAB_ENTRY_WIDTH-1 downto 0);
  signal vlan_tab_rd_data4match             : std_logic_vector(c_VLAN_TAB_ENTRY_WIDTH-1 downto 0);
  signal vlan_tab_rd_data4port              : std_logic_vector(c_VLAN_TAB_ENTRY_WIDTH-1 downto 0);
  signal vlan_tab_rd_entry4match            : t_rtu_vlan_tab_entry;
  signal vlan_tab_rd_entry4port             : t_rtu_vlan_tab_entry;

  signal port_full                          : std_logic_vector(g_num_ports-1 downto 0);
  signal port_idle                          : std_logic_vector(g_num_ports-1 downto 0);
  signal rtu_special_traffic_config         : t_rtu_special_traffic_config;
  signal zeros                              : std_logic_vector(c_rtu_max_ports-1 downto 0);
  
  signal match_req_fifo_cnt                 : unsigned(c_match_req_fifo_size_width-1 downto 0);
  
  signal tru_req                            : t_tru_request_array(g_num_ports-1 downto 0);
  signal tru_req_zero                       : t_tru_request;
begin 

  zeros <= (others => '0');
  irq_nempty <= regs_fromwb.ufifo_wr_empty_o;
  req_full_o <= not port_idle;

 tru_req_zero.valid   <= '0';
 tru_req_zero.smac    <= (others =>'0');
 tru_req_zero.dmac    <= (others =>'0');
 tru_req_zero.fid     <= (others =>'0');
 tru_req_zero.isHP    <= '0';
 tru_req_zero.isBR    <= '0';
 tru_req_zero.reqMask <= (others =>'0');

-- ??????????//
--   gen_term_unused : for i in g_num_ports to g_num_ports-1 generate
--     rq_strobe_p(i) <= '0';
--     rsp_ack(i)   <= '1';
--   end generate gen_term_unused;

  U_Adapter : wb_slave_adapter
    generic map (
      g_master_use_struct  => true,
      g_master_mode        => CLASSIC,
      g_master_granularity => WORD,
      g_slave_use_struct   => true,
      g_slave_mode         => g_interface_mode,
      g_slave_granularity  => g_address_granularity)
    port map (
      clk_sys_i => clk_sys_i,
      rst_n_i   => rst_n_i,
      slave_i   => wb_i,
      slave_o   => wb_o,
      master_i  => wb_out,
      master_o  => wb_in);

  wb_out.err <= '0';
  wb_out.rty <= '0';
  --------------------------------------------------------------------------------------------

  --------------------------------------------------------------------------------------------


  --------------------------------------------------------------------------------------------
  --| PORTS - g_num_ports number of I/O ports, a port:
  --| - inputs request to REQUEST FIFO
  --| - waits for the response,
  --| - reads response from RESPONSE FIFO
  --------------------------------------------------------------------------------------------
  ports : for i in 0 to (g_num_ports - 1) generate

    U_PortX : rtu_port_new
      generic map (
        g_num_ports      => g_num_ports,
        g_port_mask_bits => g_port_mask_bits,
        g_port_index     => i)
      port map(
        clk_i                    => clk_sys_i,
        rst_n_i                  => rst_n_i,

        rtu_idle_o               => port_idle(i), -- TODO: req_full_o ??/
        rtu_rq_i                 => req_i(i),
        rtu_rq_aboard_i          => '0', -- new stuff from SWcore
        rtu_rsp_o                => rsp_o(i),
        rtu_rsp_ack_i            => rsp_ack_i(i),
        
        rq_fifo_wr_access_o      => rq_fifo_wr_access(i),
        rq_fifo_wr_data_o        => rq_fifo_wr_data((i+1)*c_PACKED_REQUEST_WIDTH-1 downto i*c_PACKED_REQUEST_WIDTH),
        rq_fifo_wr_done_i        => rr_mux_wr_vector(i),
        rq_fifo_full_i           => rq_fifo_full_for_ports,
    
        match_data_i             => rsp_data,
        match_data_valid_i       => rsp_valid,

        vtab_rd_addr_o           => vtab_rd_addr((i+1)*c_wrsw_vid_width-1 downto i*c_wrsw_vid_width),
        vtab_rd_req_o            => vtab_rd_req(i),
        vtab_rd_entry_i          => vlan_tab_rd_entry4port,
        vtab_rd_valid_i          => rr_mux_vtab_addr_vector(i),

        port_almost_full_o       => open,
        port_full_o              => port_full(i),

        tru_req_o                => tru_req(i),--tru_req_o, -- multiplex !!!!!!!!!!!!
        tru_rsp_i                => tru_resp_i,
        tru_enabled_i            => tru_enabled_i,
    
        rtu_str_config_i         => rtu_special_traffic_config,

        rtu_gcr_g_ena_i          => regs_fromwb.gcr_g_ena_o,
        rtu_pcr_pass_bpdu_i      => pcr_pass_bpdu,
        rtu_pcr_pass_all_i       => pcr_pass_all,
        rtu_pcr_fix_prio_i       => pcr_fix_prio(i),
        rtu_pcr_prio_val_i       => pcr_prio_val(i)
        );
  end generate;  -- end ports
 
  
  ------------------------------------------------------------------------
  -- REQUEST FIFO BUS
  -- Data from all ports into one match module
  ------------------------------------------------------------------------

  MATCH_FIFO_ACCESS: gc_arbitrated_mux
    generic map (
      g_num_inputs => g_num_ports,
      g_width      => c_PACKED_REQUEST_WIDTH)
    port map(
      clk_i        => clk_sys_i,
      rst_n_i      => rst_n_i,
      d_i          => rq_fifo_wr_data,
      d_valid_i    => rq_fifo_wr_access,
      d_req_o      => rq_fifo_wr_done,
      q_o          => rr_mux_wr_data,
      q_valid_o    => rr_mux_wr_req,
      q_input_id_o => rr_mux_wr_id 
    );
  
  rr_mux_wr_vector    <= f_set_bit(zeros(g_num_ports-1 downto 0),'1',to_integer(unsigned(rr_mux_wr_id))) when (rr_mux_wr_req='1') else (others=>'0');
  rr_mux_wr_fifo_data <= rr_mux_wr_vector & rr_mux_wr_data when (rr_mux_wr_req='1') else (others =>'0');
 
  --------------------------------------------------------------------------------------------
  -- REQUEST FIFO: takes requests from ports and makes it available for RTU MATCH
  -- This is tricky!!!!
  -- We have a FIFO which is shared by all the ports, it means that in the worst case
  -- all the ports can request access at the very same time and the FIFO, after the requests
  -- are arbitrated by RR, will need to accept all the requests (no way to block it after
  -- handling).
  -- This is why, the size of the fifo is: c_match_req_fifo_size =requested_size + port_num
  -- The process below makes sure to indicate to the ports that the FIFO is full when the
  -- number of entries reaches "requested_size", so it is still possible to accommodated in
  -- the FIFO simultaneous requetss from all the ports (a bit waste of resources but seems 
  -- necessary, any good/better ideas welcome ;)
  --------------------------------------------------------------------------------------------
  
  U_ReqFifo : generic_shiftreg_fifo
    generic map (
      g_data_width => g_num_ports + c_PACKED_REQUEST_WIDTH,
      g_size       => c_match_req_fifo_size --32
      )
    port map
    (
      rst_n_i   => rst_n_i,
      clk_i     => clk_sys_i,
      we_i      => rr_mux_wr_req,
      d_i       => rr_mux_wr_fifo_data,
      rd_i      => rq_fifo_read,        --rtu_match     
      q_o       => rq_fifo_data,
      q_valid_o => rq_fifo_qvalid,
      full_o    => rq_fifo_full
      );

  p_reqFifo_cnt : process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if(rst_n_i = '0') then
        match_req_fifo_cnt   <= (others =>'0');
      else
        if(rr_mux_wr_req = '1' and rq_fifo_read ='0') then
          match_req_fifo_cnt <= match_req_fifo_cnt + 1;
        elsif(rr_mux_wr_req = '0' and rq_fifo_read ='1') then
          match_req_fifo_cnt <= match_req_fifo_cnt - 1;
        end if;
      end if;
    end if;
  end process p_reqFifo_cnt;

  rq_fifo_almost_full <= '1' when (match_req_fifo_cnt > to_unsigned(g_match_req_fifo_size,c_match_req_fifo_size_width)) else '0';
  rq_fifo_empty       <= not rq_fifo_qvalid;
  rq_fifo_full_for_ports <= rq_fifo_full or rq_fifo_almost_full;
  
  ------------------------------------------------------------------------
  -- REQUEST VLAN TABLE access
  -- Requests from all ports to read VLAN TABLE
  ------------------------------------------------------------------------

  VLAN_READ_ACCESS: gc_arbitrated_mux
    generic map (
      g_num_inputs => g_num_ports,
      g_width      => c_wrsw_vid_width)
    port map(
      clk_i        => clk_sys_i,
      rst_n_i      => rst_n_i,
      d_i          => vtab_rd_addr,
      d_valid_i    => vtab_rd_req,
      d_req_o      => open,
      q_o          => rr_mux_vtab_addr,
      q_valid_o    => rr_mux_vtab_addr_valid,
      q_input_id_o => rr_mux_vtab_addr_id 
    );

  rr_mux_vtab_addr_vector <= f_set_bit(zeros(g_num_ports-1 downto 0),'1',to_integer(unsigned(rr_mux_vtab_addr_id))) when (rr_mux_vtab_addr_valid='1') else (others => '0');

  p_vlan_read_access : process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if(rst_n_i = '0') then
        vtab_rd_valid  <= (others =>'0');
      else
        if(rr_mux_vtab_addr_valid = '1') then
          vtab_rd_valid <= rr_mux_vtab_addr_vector;
        else
          vtab_rd_valid <= (others => '0');
        end if;
      end if;
    end if;
  end process p_vlan_read_access;

  p_tru_mux: process(vtab_rd_valid, tru_req)
  begin
    if(vtab_rd_valid = zeros(g_num_ports-1 downto 0)) then
      tru_req_o <= tru_req_zero;
    else
      for i in 0 to g_num_ports-1 loop
        if(vtab_rd_valid(i) = '1') then
          tru_req_o <= tru_req(i);
        end if;
      end loop;
    end if;
  end process p_tru_mux;
  --------------------------------------------------------------------------------------------
  --| RTU MATCH: Routing Table Unit Engine
  --------------------------------------------------------------------------------------------
  -- to be added
  U_Match : rtu_match
    generic map (
      g_num_ports => g_num_ports)
    port map(

      clk_i                => clk_sys_i,
      rst_n_i              => rst_n_i,
      rq_fifo_read_o       => rq_fifo_read,
      rq_fifo_empty_i      => rq_fifo_empty,
      rq_fifo_input_i      => rq_fifo_data,
      rsp_fifo_write_o     => rsp_valid,
      rsp_fifo_full_i      => '0', --rsp_fifo_full,
      rsp_fifo_output_o    => rsp_data,

      htab_start_o         => htab_start,
      htab_ack_o           => htab_ack,
      htab_found_i         => htab_found,
      htab_hash_o          => htab_hash,
      htab_mac_o           => htab_mac,
      htab_fid_o           => htab_fid,
      htab_drdy_i          => htab_drdy,
      htab_entry_i         => htab_entry,

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

      vlan_tab_addr_o      => vlan_tab_rd_vid,
      vlan_tab_entry_i     => vlan_tab_rd_entry4match,

      rtu_gcr_g_ena_i      => regs_fromwb.gcr_g_ena_o,
      rtu_pcr_pass_all_i   => pcr_pass_all(g_num_ports - 1 downto 0),
      rtu_pcr_learn_en_i   => pcr_learn_en(g_num_ports - 1 downto 0),
      rtu_pcr_pass_bpdu_i  => pcr_pass_bpdu(g_num_ports - 1 downto 0),
      rtu_pcr_b_unrec_i    => pcr_b_unrec(g_num_ports - 1 downto 0),
      rtu_crc_poly_i       => rtu_gcr_poly_used  --x"1021"-- x"0589" -- x"8005" --x"1021" --x"8005", --
--    rtu_rw_bank_i                                => s_vlan_bsel
      );

  rtu_gcr_poly_used <= c_default_hash_poly when (regs_fromwb.gcr_poly_val_o = x"0000") else regs_fromwb.gcr_poly_val_o;

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

--   U_WB_Slave : rtu_wishbone_slave_old
  U_WB_Slave : rtu_wishbone_slave
    port map(
      rst_n_i   => rst_n_i,
      clk_sys_i => clk_sys_i,

      wb_adr_i   => wb_in.adr(8 downto 0),
      wb_dat_i   => wb_in.dat,
      wb_dat_o   => wb_out.dat,
      wb_cyc_i   => wb_in.cyc,
      wb_sel_i   => wb_in.sel,
      wb_stb_i   => wb_in.stb,
      wb_we_i    => wb_in.we,
      wb_ack_o   => wb_out.ack,
      wb_int_o   => wb_out.int,
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

  irq_nempty                     <= regs_fromwb.ufifo_wr_empty_o;
  
  current_mac_ID                 <= to_integer(unsigned(regs_fromwb.rx_ff_mac_r1_id_o));
  current_MAC_entry              <= regs_fromwb.rx_ff_mac_r1_hi_id_o & regs_fromwb.rx_ff_mac_r0_lo_o;
  regs_towb.rx_ff_mac_r1_id_i    <= std_logic_vector(to_unsigned(c_ff_single_macs_number, 8));
  regs_towb.rx_ff_mac_r1_hi_id_i <= std_logic_vector(to_unsigned(c_ff_range_macs_number, 16));

  regs_towb.gcr_rtu_version_i    <= x"2";

  -- RTU Extension index-access configration regiters for Fast Forward MACs 
  p_rx_registers : process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if(rst_n_i = '0') then   
        rtu_special_traffic_config.single_macs          <= (others => std_logic_vector(to_unsigned(0, 48)));
        rtu_special_traffic_config.single_macs_valid    <= (others => '0');
        rtu_special_traffic_config.macs_range_valid     <= '0';
        rtu_special_traffic_config.macs_range_up        <= (others => '0');
        rtu_special_traffic_config.macs_range_down      <= (others => '0');
        rtu_special_traffic_config.mirror_port_dst      <= (others => '0');
        rtu_special_traffic_config.mirror_port_src_rx   <= (others => '0');
        rtu_special_traffic_config.mirror_port_src_tx   <= (others => '0');
      else
        -- output selected mirror mask    
        if(regs_fromwb.rx_mp_r0_dst_src_o = '0') then  -- mirror destination mask
          regs_towb.rx_mp_r1_mask_i                     <= rtu_special_traffic_config.mirror_port_dst;   
        else                                           -- mirror source mask
          if(regs_fromwb.rx_mp_r0_rx_tx_o = '0') then  -- * rx
            regs_towb.rx_mp_r1_mask_i                   <= rtu_special_traffic_config.mirror_port_src_rx;
          else                                         -- * tx
            regs_towb.rx_mp_r1_mask_i                   <= rtu_special_traffic_config.mirror_port_src_tx;
          end if;               
        end if;
        -- register selected mirror mask
        if(regs_fromwb.rx_mp_r1_mask_load_o = '1') then
          if(regs_fromwb.rx_mp_r0_dst_src_o = '0') then  -- mirror destination mask
            rtu_special_traffic_config.mirror_port_dst      <= regs_fromwb.rx_mp_r1_mask_o;   
          else                                           -- mirror source mask
            if(regs_fromwb.rx_mp_r0_rx_tx_o = '0') then  -- * rx
              rtu_special_traffic_config.mirror_port_src_rx <= regs_fromwb.rx_mp_r1_mask_o;
            else                                         -- * tx
              rtu_special_traffic_config.mirror_port_src_tx <= regs_fromwb.rx_mp_r1_mask_o;
            end if; -- rx_mp_r0_rx_tx_o      
          end if; -- rx_mp_r0_dst_src_o
        end if; -- rx_mp_r1_mask_load_o
        
        -- register selected Fast Forward MAC
        if(regs_fromwb.rx_ff_mac_r1_hi_id_load_o = '1') then
          if(regs_fromwb.rx_ff_mac_r1_type_o = '0') then-- TYPE: single MAC
            rtu_special_traffic_config.single_macs(current_mac_ID)       <= current_MAC_entry;
            rtu_special_traffic_config.single_macs_valid(current_mac_ID) <= regs_fromwb.rx_ff_mac_r1_valid_o;
          else                                           -- TYPE: range MAC
            if(regs_fromwb.rx_ff_mac_r1_id_o(7) = '0') then  --lower range
              rtu_special_traffic_config.macs_range_down      <= current_MAC_entry;            
            else                                                 -- upper range
              rtu_special_traffic_config.macs_range_up        <= current_MAC_entry;         
            end if;
            rtu_special_traffic_config.macs_range_valid       <= regs_fromwb. rx_ff_mac_r1_valid_o;
          end if;
        end if;
      end if;
    end if;
  end process;

  rtu_special_traffic_config.hp_prio              <= regs_fromwb.rx_hp_ctr_prio_mask_o;
  rtu_special_traffic_config.bpd_forward_mask     <= regs_fromwb.rx_llf_ff_mask_o;
  rtu_special_traffic_config.dop_on_fmatch_full   <= regs_fromwb.rx_hp_ctr_at_fmatch_too_slow_o;

  U_VLAN_Table_for_full_match : generic_dpram
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
      qb_o    => vlan_tab_rd_data4match);

  U_VLAN_Table_for_fast_match : generic_dpram
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
      ab_i    => rr_mux_vtab_addr,  -- address
      qb_o    => vlan_tab_rd_data4port); -- data

  vlan_tab_wr_data <= regs_fromwb.vtr2_port_mask_o
                      & regs_fromwb.vtr1_fid_o
                      & regs_fromwb.vtr1_drop_o
                      & regs_fromwb.vtr1_prio_override_o
                      & regs_fromwb.vtr1_prio_o
                      & regs_fromwb.vtr1_has_prio_o;

  f_unpack6(vlan_tab_rd_data4match,
            vlan_tab_rd_entry4match.port_mask,
            vlan_tab_rd_entry4match.fid,
            vlan_tab_rd_entry4match.drop,
            vlan_tab_rd_entry4match.prio_override,
            vlan_tab_rd_entry4match.prio,
            vlan_tab_rd_entry4match.has_prio);

  f_unpack6(vlan_tab_rd_data4port,
            vlan_tab_rd_entry4port.port_mask,
            vlan_tab_rd_entry4port.fid,
            vlan_tab_rd_entry4port.drop,
            vlan_tab_rd_entry4port.prio_override,
            vlan_tab_rd_entry4port.prio,
            vlan_tab_rd_entry4port.has_prio);

----------------------------------------------------------------------------------------------

--   rtu_special_traffic_config.single_macs(0)       <= x"FFFFFFFFFFFF";       
--   rtu_special_traffic_config.single_macs(1)       <= x"1234567890AB"; 
--   rtu_special_traffic_config.single_macs(2)       <= (others => '0');
--   rtu_special_traffic_config.single_macs(3)       <= (others => '0');
-- 
--   rtu_special_traffic_config.single_macs_valid    <= "0011";
--   rtu_special_traffic_config.hp_prio              <= "10000000";
--   rtu_special_traffic_config.macs_range_valid     <= '0';
--   rtu_special_traffic_config.macs_range_up        <= (others => '0');
--   rtu_special_traffic_config.macs_range_down      <= (others => '0');
--   rtu_special_traffic_config.bpd_forward_mask     <= f_set_bit(zeros,'1',g_num_ports);
--   rtu_special_traffic_config.mirrored_port_src    <= (others => '0');
--   rtu_special_traffic_config.mirrored_port_dst    <= (others => '0');
  
  
--   rtu_special_traffic_config.tru_enabled          <= '1';
end behavioral;
