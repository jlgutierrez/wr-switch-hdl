-------------------------------------------------------------------------------
-- Title      : (Extended) Topology Resolution Unit 
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : xwrsw_tru.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-08-20
-- Last update: 2012-09-13
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: Top level of the Topology Resolution Unit (TRU) with 
-- record input/output (Extended) to make it easier connecting with other
-- modules in the switch
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- THis unit takes care of hardware side of the topology resolutions - in 
-- other words, in a WR network we need to avoid network loops. A special
-- protocol is used to make sure there are not loops. THe hardware side of 
-- this protocol is a TRU module. TRU module is as universal as possible to 
-- enable support of many different S/W protocols (e.g. RSTP, LACP).
-- There is part of the Topology Resolution Protocol implementation in HW 
-- to make the stuff work really fast to minimize the number of frame lost
-- while we switch-over between redundant paths
-- 
-- 
-- It does the following:
-- 1. accepts request
-- 2. reads TRU TABLE
-- 3. checks Patterns to be used and ports state
-- 4. based on patterns/state/TRU_tab prepares forwarding decision.
-- 
-- Assumptions/requrements/etc:
-- - there is a single request in single cycle - RoundRobin access to this module by
--   all ports of RTU is assumed in the RTU
-- - every cycle a new request can be handled
-- - FID needs to be provided (VLAN table read by RTU
-- 
-- Pipelined response is available in 2 cycles. 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 Maciej Lipinski / CERN
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
-- 2012-08-20  1.0      mlipinsk Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

library work;
use work.wrsw_tru_pkg.all;
use work.genram_pkg.all;
use work.tru_wbgen2_pkg.all;       -- for wbgen-erated records
use work.wishbone_pkg.all;         -- wishbone_{interface_mode,address_granularity}

entity xwrsw_tru is
  generic(     
     g_num_ports          : integer := 6;
     g_tru_subentry_num   : integer := 8;
     g_pattern_width      : integer := 4;
     g_patternID_width    : integer := 4;
     g_stableUP_treshold  : integer := 100;
     g_tru_addr_width     : integer := 8;
     g_pclass_number      : integer := 8;
     g_mt_trans_max_fr_cnt: integer := 1000;
     g_prio_width         : integer := 3;
     g_pattern_mode_width : integer := 4;
     g_tru_entry_num      : integer := 256;
     g_interface_mode     : t_wishbone_interface_mode      := PIPELINED;
     g_address_granularity: t_wishbone_address_granularity := BYTE
     );
  port (
    clk_i          : in std_logic;
    rst_n_i        : in std_logic;

    -------------------------- request/rosponse (from/to RTU) ------------------------------
    req_i              : in  t_tru_request;
    resp_o             : out t_tru_response;    

    --------------------------- I/F with RTU -----------------------------------
    -- info from within RTU (i.e. config) necessary for TRU
    rtu_i              : in  t_rtu2tru;

    ----------------------- I/F with Endpoint------------------------------------
    -- multi-port access
    ep_i               : in  t_ep2tru_array(g_num_ports-1 downto 0);
    ep_o               : out t_tru2ep_array(g_num_ports-1 downto 0);
    
    ----------------------- I/F with SW core ------------------------------------
    -- multi-port access (bit per port)
    swc_o              : out std_logic_vector(g_num_ports-1 downto 0); -- for pausing

    ---------------------------- WB I/F -----------------------------------------
    wb_i : in  t_wishbone_slave_in;
    wb_o : out t_wishbone_slave_out    
          
    );
end xwrsw_tru;

architecture rtl of xwrsw_tru is
 
  constant c_tru_subentry_width : integer :=  (1+5*g_num_ports+g_pattern_mode_width);
  constant c_tru_entry_width    : integer :=  c_tru_subentry_width*g_tru_subentry_num;
  constant c_tru_addr_width     : integer :=  integer(CEIL(LOG2(real(g_tru_entry_num))));
  
  type t_tru_tab_subentry_array is array(integer range <>) of 
                                std_logic_vector(c_tru_subentry_width-1 downto 0); 
  type t_wr_sub_entry_array     is array(g_tru_subentry_num - 1 downto 0) of 
                                std_logic_vector(c_tru_subentry_width-1 downto 0);


  signal s_endpoint_array     : t_tru_endpoint_array(g_num_ports-1 downto 0);
  signal s_endpoints          : t_tru_endpoints;
  signal s_tru_tab_addr       : std_logic_vector(c_tru_addr_width-1 downto 0);
  signal s_tru_tab_entry      : t_tru_tab_entry(g_tru_subentry_num - 1 downto 0);
  signal s_config             : t_tru_config;
  signal s_tx_rt_reconf_FRM   : std_logic_vector(g_num_ports-1 downto 0);
  signal s_trans_ep_ctr       : t_trans2tru_array(g_num_ports-1 downto 0);
  signal s_trans_rxFrameMask  : std_logic_vector(g_num_ports-1 downto 0);
  signal s_tru_tab_rd_subentry_arr  : t_tru_tab_subentry_array(g_tru_subentry_num-1 downto 0);
  signal s_tru_rd_addr        : std_logic_vector(c_tru_addr_width+1-1 downto 0);
  signal s_tru_tab_bank       : std_logic;
  signal s_tru_tab_wr_subentry_arr : t_wr_sub_entry_array;
  signal s_tru_wr_ena         : std_logic_vector(g_tru_subentry_num-1 downto 0);
  signal s_tru_tab_wr_index   : integer range 0  to g_tru_subentry_num-1;
  signal s_tru_wr_addr        : std_logic_vector(c_tru_addr_width+1-1 downto 0);
  signal s_tru_wr_data        : std_logic_vector(c_tru_subentry_width-1 downto 0);
  signal s_transitionFinished : std_logic;
  signal s_transitionActive   : std_logic;
  signal s_bank_swap_on_trans : std_logic;
  signal s_regs_towb          : t_tru_in_registers;
  signal s_regs_fromwb        : t_tru_out_registers;
  signal wb_in                : t_wishbone_slave_in;
  signal wb_out               : t_wishbone_slave_out;
begin --rtl
   
  U_T_PORT: tru_port
  generic map(     
     g_num_ports        => g_num_ports,
     g_tru_subentry_num => g_tru_subentry_num,
     g_patternID_width  => g_patternID_width,
     g_pattern_width    => g_pattern_width,
     g_tru_addr_width   => c_tru_addr_width
    )
  port map(
     clk_i              => clk_i,
     rst_n_i            => rst_n_i,
     tru_req_i          => req_i,
     tru_resp_o         => resp_o,
     tru_tab_addr_o     => s_tru_tab_addr,
     tru_tab_entry_i    => s_tru_tab_entry,
     endpoints_i        => s_endpoints,
     config_i           => s_config,
     txFrameMask_o      => s_tx_rt_reconf_FRM
    );

  G_ENDP: for i in 0 to g_num_ports-1 generate
     U_T_ENDPOINT: tru_endpoint
     generic map(     
        g_num_ports        => g_num_ports,
        g_pclass_number    => g_pclass_number,
        g_tru_subentry_num => g_tru_subentry_num,
        g_patternID_width  => g_patternID_width,
        g_pattern_width    => g_pattern_width,
        g_stableUP_treshold=> g_stableUP_treshold
       )
     port map(
       clk_i               => clk_i,
       rst_n_i             => rst_n_i,
       port_if_i           => ep_i(i),
       port_if_ctrl_o      => ep_o(i).ctrlWr,
       rtu_pass_all_i      => rtu_i.pass_all(i),
       endpoint_o          => s_endpoint_array(i), 
       reset_rxFlag_i      => s_config.gcr_rx_frame_reset(i)
       );
   end generate G_ENDP;

  U_TRANSITION: tru_transition 
  generic map(     
     g_num_ports           => g_num_ports,
     g_mt_trans_max_fr_cnt => g_mt_trans_max_fr_cnt,
     g_prio_width          => g_prio_width
    )
  port map (
    clk_i                  => clk_i,
    rst_n_i                => rst_n_i,
    endpoints_i            => s_endpoints,
    config_i               => s_config,
    tru_tab_bank_i         => s_tru_tab_bank,
    tru_tab_bank_o         => s_bank_swap_on_trans,
    statTransActive_o      => s_transitionActive,
    statTransFinished_o    => s_transitionFinished,
    rxFrameMask_i          => s_trans_rxFrameMask,
    rtu_i                  => rtu_i,
    ep_o                   => s_trans_ep_ctr
    );
  s_trans_rxFrameMask <= s_endpoints.rxFrameMask(to_integer(unsigned(s_config.tcr_trans_rx_id)))(g_num_ports-1 downto 0);

  G_ENDP_CONX: for i in 0 to g_num_ports-1 generate
     s_endpoints.status(i)              <= s_endpoint_array(i).status  ;
     s_endpoints.stableUp(i)            <= s_endpoint_array(i).stableUp;
  end generate G_ENDP_CONX;
  
  s_endpoints.status(s_endpoints.status'length-1 downto g_num_ports) <= (others =>'0');
  s_endpoints.stableUp(s_endpoints.stableUp'length-1 downto g_num_ports)  <= (others =>'0'); 
  
  G_FRAME_MASK: for i in 0 to g_pclass_number-1 generate
     s_endpoints.rxFrameMask(i)    <= f_rxFrameMaskInv(s_endpoint_array,i,g_num_ports);
     s_endpoints.rxFrameMaskReg(i) <= f_rxFrameMaskRegInv(s_endpoint_array,i,g_num_ports);
  end generate G_FRAME_MASK;

  G_EP_O: for i in 0 to g_num_ports-1 generate
     ep_o(i).tx_pck            <= '1' when (s_tx_rt_reconf_FRM(i) ='1') else '0';
     G_TX_O: for j in 0 to g_pclass_number-1 generate
        ep_o(i).tx_pck_class(j) <= s_tx_rt_reconf_FRM(i) 
                                   when (j = to_integer(unsigned(s_config.rtrcr_rtr_rx))) else '0';
     end generate G_TX_O;
     ep_o(i).pauseSend         <= s_trans_ep_ctr(i).pauseSend;
     ep_o(i).pauseTime         <= s_trans_ep_ctr(i).pauseTime;
     ep_o(i).outQueueBlockMask <= s_trans_ep_ctr(i).outQueueBlockMask;
  end generate G_EP_O;
  
  G_TRU_TAB: for i in 0 to g_tru_subentry_num-1 generate
     U_TRU_TAB : generic_dpram
       generic map (
         g_data_width       => c_tru_subentry_width,
         g_size             => 2*g_tru_entry_num,
         g_with_byte_enable => false,
         g_dual_clock       => false)
       port map (
         rst_n_i => rst_n_i,
         clka_i  => clk_i,
         clkb_i => '0',
         bwea_i  => (others => '1'),
         wea_i   => s_tru_wr_ena(i),
         aa_i    => s_tru_wr_addr,
         da_i    => s_tru_wr_data,
         ab_i    => s_tru_rd_addr,
         qb_o    => s_tru_tab_rd_subentry_arr(i));
  end generate G_TRU_TAB;   

  s_tru_rd_addr               <= s_tru_tab_bank & s_tru_tab_addr;

  G1: for i in 0 to g_tru_subentry_num-1 generate
       s_tru_tab_entry(i)     <= f_unpack_tru_subentry(s_tru_tab_rd_subentry_arr(i),g_num_ports);
       s_tru_wr_ena(i)        <= s_regs_fromwb.ttr0_update_o when (i = s_tru_tab_wr_index) else '0';
  end generate G1;

  U_WB_ADAPTER : wb_slave_adapter
    generic map (
      g_master_use_struct  => true,
      g_master_mode        => CLASSIC,
      g_master_granularity => WORD,
      g_slave_use_struct   => true,
      g_slave_mode         => g_interface_mode,
      g_slave_granularity  => g_address_granularity)
    port map (
      clk_sys_i => clk_i,
      rst_n_i   => rst_n_i,
      slave_i   => wb_i,
      slave_o   => wb_o,
      master_i  => wb_out,
      master_o  => wb_in);

  U_WISHBONE_IF: tru_wishbone_slave
  port map(
    rst_n_i            => rst_n_i,
    wb_clk_i           => clk_i,
    wb_addr_i          => wb_in.adr(3 downto 0),
    wb_data_i          => wb_in.dat,
    wb_data_o          => wb_out.dat,
    wb_cyc_i           => wb_in.cyc,
    wb_sel_i           => wb_in.sel,
    wb_stb_i           => wb_in.stb,
    wb_we_i            => wb_in.we,
    wb_ack_o           => wb_out.ack,
    regs_i             => s_regs_towb,
    regs_o             => s_regs_fromwb
  );

 CTRL_BANK: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        s_tru_tab_bank<= '0';
      else
        if(s_regs_fromwb.gcr_tru_bank_o = '1' or s_bank_swap_on_trans = '1') then
          s_tru_tab_bank<= not s_tru_tab_bank;
        end if;
      end if;
    end if;
  end process;  
  
  s_regs_towb.gsr0_stat_bank_i           <= s_tru_tab_bank;
  s_regs_towb.gsr0_stat_stb_up_i         <= s_endpoints.stableUp(s_regs_towb.gsr0_stat_stb_up_i'length-1 downto 0);
  s_regs_towb.gsr1_stat_up_i             <= s_endpoints.status(s_regs_towb.gsr1_stat_up_i'length-1 downto 0);
  s_regs_towb.tsr_trans_stat_active_i    <= s_transitionActive;
  s_regs_towb.tsr_trans_stat_finished_i  <= s_transitionFinished; 
  
  s_config.gcr_g_ena                     <= s_regs_fromwb.gcr_g_ena_o               ;
  s_config.gcr_rx_frame_reset            <= s_regs_fromwb.gcr_rx_frame_reset_o      ;
  s_config.mcr_pattern_mode_rep          <= s_regs_fromwb.mcr_pattern_mode_rep_o    ;
  s_config.mcr_pattern_mode_add          <= s_regs_fromwb.mcr_pattern_mode_add_o    ;
  s_config.lacr_agg_gr_num               <= s_regs_fromwb.lacr_agg_gr_num_o         ;
  s_config.lacr_agg_df_br_id             <= s_regs_fromwb.lacr_agg_df_br_id_o       ;
  s_config.lacr_agg_df_un_id             <= s_regs_fromwb.lacr_agg_df_un_id_o       ;
  s_config.lagt_gr_id_mask(0)            <= s_regs_fromwb.lagt_lagt_gr_id_mask_0_o  ;
  s_config.lagt_gr_id_mask(1)            <= s_regs_fromwb.lagt_lagt_gr_id_mask_1_o  ;
  s_config.lagt_gr_id_mask(2)            <= s_regs_fromwb.lagt_lagt_gr_id_mask_2_o  ;
  s_config.lagt_gr_id_mask(3)            <= s_regs_fromwb.lagt_lagt_gr_id_mask_3_o  ;
  s_config.lagt_gr_id_mask(4)            <= s_regs_fromwb.lagt_lagt_gr_id_mask_4_o  ;
  s_config.lagt_gr_id_mask(5)            <= s_regs_fromwb.lagt_lagt_gr_id_mask_5_o  ;
  s_config.lagt_gr_id_mask(6)            <= s_regs_fromwb.lagt_lagt_gr_id_mask_6_o  ;
  s_config.lagt_gr_id_mask(7)            <= s_regs_fromwb.lagt_lagt_gr_id_mask_7_o  ;
  s_config.tcr_trans_ena                 <= s_regs_fromwb.tcgr_trans_ena_o          ;
  s_config.tcr_trans_clr                 <= s_regs_fromwb.tcgr_trans_clear_o        ;
  s_config.tcr_trans_mode                <= s_regs_fromwb.tcgr_trans_mode_o         ;
  s_config.tcr_trans_rx_id               <= s_regs_fromwb.tcgr_trans_rx_id_o        ;
  s_config.tcr_trans_prio                <= s_regs_fromwb.tcgr_trans_prio_o         ;
  s_config.tcr_trans_port_a_id           <= s_regs_fromwb.tcpr_trans_port_a_id_o    ;
  s_config.tcr_trans_port_a_pause        <= s_regs_fromwb.tcgr_trans_time_diff_o    ;
  s_config.tcr_trans_port_a_valid        <= s_regs_fromwb.tcpr_trans_port_a_valid_o ;
  s_config.tcr_trans_port_b_id           <= s_regs_fromwb.tcpr_trans_port_b_id_o    ;
  s_config.tcr_trans_port_b_pause        <= s_regs_fromwb.tcgr_trans_time_diff_o    ;
  s_config.tcr_trans_port_b_valid        <= s_regs_fromwb.tcpr_trans_port_b_valid_o ;
  s_config.rtrcr_rtr_ena                 <= s_regs_fromwb.rtrcr_rtr_ena_o           ;
  s_config.rtrcr_rtr_reset               <= s_regs_fromwb.rtrcr_rtr_reset_o         ;
  s_config.rtrcr_rtr_mode                <= s_regs_fromwb.rtrcr_rtr_mode_o          ;
  s_config.rtrcr_rtr_rx                  <= s_regs_fromwb.rtrcr_rtr_rx_o            ;
  s_config.rtrcr_rtr_tx                  <= s_regs_fromwb.rtrcr_rtr_tx_o            ;
  
  s_tru_tab_wr_index                     <= to_integer(unsigned(s_regs_fromwb.ttr0_sub_fid_o));
  s_tru_wr_addr                          <= (not s_tru_tab_bank) & s_regs_fromwb.ttr0_fid_o;
  s_tru_wr_data                          <= s_regs_fromwb.ttr0_patrn_mode_o                            &
                                            s_regs_fromwb.ttr5_patrn_mask_o   (g_num_ports-1 downto 0) &
                                            s_regs_fromwb.ttr4_patrn_match_o  (g_num_ports-1 downto 0) &  
                                            s_regs_fromwb.ttr3_ports_mask_o   (g_num_ports-1 downto 0) &  
                                            s_regs_fromwb.ttr2_ports_egress_o (g_num_ports-1 downto 0) &  
                                            s_regs_fromwb.ttr1_ports_ingress_o(g_num_ports-1 downto 0) &
                                            s_regs_fromwb.ttr0_mask_valid_o                            ;
 -- TODO:
  swc_o                <= (others =>'0');
 
end rtl;
