-------------------------------------------------------------------------------
-- Title      : (Extended) Topology Resolution Unit 
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : xwrsw_tru.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-08-20
-- Last update: 2013-05-09
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
-- Copyright (c) 2012 - 2013 CERN / BE-CO-HT
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
use work.wrsw_shared_types_pkg.all;
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
    swc_block_oq_req_o : out t_global_pause_request;

    -- info to other moduels that TRU is enabled
    enabled_o          : out std_logic;
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
  signal s_bank_swap          : std_logic;
  signal s_port_if_ctrl       : std_logic_vector(g_num_ports-1 downto 0);
  signal s_pinject_ctr        : t_pinject_ctr_array(g_num_ports-1 downto 0);
  -- debugging pfilter + pinjection
  signal s_debug_port_sel     : integer range 0 to 2**8-1;
  signal s_pidr_inject        : std_logic_vector(g_num_ports-1 downto 0);
  signal s_debug_filter       : t_debug_stuff_array(g_num_ports-1 downto 0);
  signal s_ports_req_strobe   : std_logic_vector(g_num_ports-1 downto 0);
  signal s_req_s_hp           : std_logic;
  signal s_req_s_prio         : std_logic;
  signal s_tru_ena            : std_logic;
  signal s_swc_ctrl           : t_trans2sw;
  signal s_inject_sel         : t_inject_sel_array(g_num_ports-1 downto 0);
  signal s_ep                 : t_tru2ep_array(g_num_ports-1 downto 0);
  signal s_inject_ready_d     : std_logic_vector(g_num_ports-1 downto 0);
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
     tru_tab_bank_swap_i=> s_bank_swap,
     globIngMask_dbg_o  => s_regs_towb.ptrdr_ging_mask_i(g_num_ports-1 downto 0),
     txFrameMask_o      => s_tx_rt_reconf_FRM
    );
  s_regs_towb.ptrdr_ging_mask_i(31 downto g_num_ports) <= (others => '0');
  
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
       port_if_ctrl_o      => s_port_if_ctrl(i), --ep_o(i).ctrlWr,
       rtu_pass_all_i      => rtu_i.pass_all(i),
       endpoint_o          => s_endpoint_array(i), 
       reset_rxFlag_i      => s_config.gcr_rx_frame_reset(i)
       );
       ep_o(i).link_kill   <= not s_port_if_ctrl(i) when (s_tru_ena = '1') else '0';
   end generate G_ENDP;

  -- generating strobe to count packets which enter switch after receiving MARKER/sending PAUSE
  -- * if transition priority (trans_prio) configured to 0, then we use indication of HP frames
  --   from fast match
  s_req_s_hp    <= req_i.valid and req_i.isHP when (s_config.tcr_trans_prio_mode = '0') else
                   '0';
  -- * if trans_prio is set, we take packets with indicated priority (more for testing)
  s_req_s_prio  <= req_i.valid when (s_config.tcr_trans_prio_mode = '1' and 
                                     s_config.tcr_trans_prio = req_i.prio    ) else
                  '0';

  -- generating the strobe 
  s_ports_req_strobe <= req_i.reqMask(g_num_ports-1 downto 0) when (s_req_s_hp   = '1' or 
                                                                    s_req_s_prio = '1') else
                        (others => '0');
  
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
    ports_req_strobe_i     => s_ports_req_strobe, -- new shit
    sw_o                   => s_swc_ctrl,
    ep_o                   => s_trans_ep_ctr
    );
  s_trans_rxFrameMask <= s_endpoints.rxFrameMask(to_integer(unsigned(s_config.tcr_trans_rx_id)))(g_num_ports-1 downto 0);

  G_ENDP_CONX: for i in 0 to g_num_ports-1 generate
     s_endpoints.status(i)              <= s_endpoint_array(i).status  ;
     s_endpoints.stableUp(i)            <= s_endpoint_array(i).stableUp;
     s_endpoints.rxFramePerPortMask(i)(c_wrsw_pclass_number-1  downto 0) <= s_endpoint_array(i).rxFrameMask;
     s_endpoints.inject_ready(i)        <= s_endpoint_array(i).inject_ready;
  end generate G_ENDP_CONX;
  
  s_endpoints.status(s_endpoints.status'length-1 downto g_num_ports)             <= (others =>'0');
  s_endpoints.stableUp(s_endpoints.stableUp'length-1 downto g_num_ports)         <= (others =>'0'); 
  s_endpoints.inject_ready(s_endpoints.inject_ready'length-1 downto g_num_ports) <= (others =>'0'); 
  
  G_FRAME_MASK: for i in 0 to g_pclass_number-1 generate
     s_endpoints.rxFrameMask(i)    <= f_rxFrameMaskInv(s_endpoint_array,i,g_num_ports);
     s_endpoints.rxFrameMaskReg(i) <= f_rxFrameMaskRegInv(s_endpoint_array,i,g_num_ports);
  end generate G_FRAME_MASK;

  CTRL_PINJECT: process(clk_i, rst_n_i) -- this is not really optimal for resources... shit
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        CLEAR: for i in 0 to g_num_ports-1 loop
          s_inject_sel(i).dbg   <= '0';
          s_inject_sel(i).fwd   <= '0';
          s_inject_sel(i).blk   <= '0';
          s_inject_sel(i).pause <= '0';
          s_inject_ready_d(i)   <= '0';
        end loop;
      else
        
        -- below we register the info from different modules about hw-injection of frames.
        -- This is needed as one injection can be done at a time and many injection request
        -- can (theoretically) happen at the same time.
        -- We remember each request and hw-inject framess with the following priority:
        -- 1) dbg msg       - from WB
        -- 2) quick forward - from R-T Re-config module or transition (if a request is 
        --                    is made when other is being handled ... we don't care, since 
        --                    the effect is achieved with the handled one
        -- 3) quick block   - from transition
        -- 4) pause         - from transition (it can be delayed since we count the received
        --                    frames after we requested the PAUSE -- this is to accommodate
        --                    the delay between requesting the PAUSE frame and the pause 
        --                    stopping the traffic
        -- The stored values of s_inject_sel are used to select the values of 
        -- *inject_packet_sel* and *inject_user_value* to be fed into the module
        
        REMEMBER: for i in 0 to g_num_ports-1 loop
          if(s_pidr_inject(i) ='1' and s_inject_sel(i).dbg = '0') then
            s_inject_sel(i).dbg   <= '1';
          elsif(s_inject_ready_d(i) = '0' and ep_i(i).inject_ready = '1' and -- finished injection
                s_inject_sel(i).dbg = '1') then
            s_inject_sel(i).dbg   <= '0'; 
          end if;
             
          if((s_tx_rt_reconf_FRM(i) ='1' or s_trans_ep_ctr(i).hwframe_fwd = '1') and s_inject_sel(i).fwd = '0') then -- quick forward
            s_inject_sel(i).fwd   <= '1';
          elsif(s_inject_ready_d(i) = '0' and ep_i(i).inject_ready = '1' and -- finished injection
                s_inject_sel(i).dbg = '0' and s_inject_sel(i).fwd  = '1') then
            s_inject_sel(i).fwd   <= '0';
          end if;

          if(s_trans_ep_ctr(i).hwframe_blk ='1' and s_inject_sel(i).blk = '0') then -- quick block
            s_inject_sel(i).blk   <='1';
          elsif(s_inject_ready_d(i) = '0' and ep_i(i).inject_ready = '1' and -- finished injection
                s_inject_sel(i).dbg = '0' and s_inject_sel(i).fwd  = '0' and s_inject_sel(i).blk ='1') then
            s_inject_sel(i).blk   <='0';
          end if;
            
          if(s_trans_ep_ctr(i).pauseSend = '1' and s_inject_sel(i).pause ='0') then
            s_inject_sel(i).pause <='1';
          elsif(s_inject_ready_d(i) = '0' and ep_i(i).inject_ready = '1' and -- finished injection
                s_inject_sel(i).dbg = '0' and s_inject_sel(i).fwd  = '0' and  s_inject_sel(i).blk = '0' and 
                s_inject_sel(i).pause = '1') then 
            s_inject_sel(i).pause <='0';
          end if;
          
          s_inject_ready_d(i) <= ep_i(i).inject_ready; -- detect end of injection 
        end loop;     
      end if;
    end if;
  end process;  
  
  -- the proper mux to feed into injection control of Endpoints
  G_EP_O: for i in 0 to g_num_ports-1 generate
     
     s_ep(i).inject_packet_sel <= s_regs_fromwb.pidr_psel_o           when (s_inject_sel(i).dbg   ='1') else
                                  s_config.hwframe_tx_fwd(2 downto 0) when (s_inject_sel(i).fwd   ='1') else 
                                  s_config.hwframe_tx_blk(2 downto 0) when (s_inject_sel(i).blk   ='1') else
                                  "000"                               when (s_inject_sel(i).pause ='1') else 
                                  "000"; 

     s_ep(i).inject_user_value <= s_regs_fromwb.pidr_uval_o              when (s_inject_sel(i).dbg   ='1') else 
                                  x"00" & s_regs_fromwb.hwfc_tx_fwd_ub_o when (s_inject_sel(i).fwd   ='1') else 
                                  x"00" & s_regs_fromwb.hwfc_tx_blk_ub_o when (s_inject_sel(i).blk   ='1') else                              
                                  s_regs_fromwb.tcpbr_trans_pause_time_o when (s_inject_sel(i).pause ='1') else
                                  x"0000";

     s_ep(i).inject_req        <= '1' when (s_inject_sel(i).dbg   = '1' and ep_i(i).inject_ready = '1' and s_inject_ready_d(i) = '1') else        
                                  '1' when (s_inject_sel(i).fwd   = '1' and ep_i(i).inject_ready = '1' and s_inject_ready_d(i) = '1') else
                                  '1' when (s_inject_sel(i).blk   = '1' and ep_i(i).inject_ready = '1' and s_inject_ready_d(i) = '1') else
                                  '1' when (s_inject_sel(i).pause = '1' and ep_i(i).inject_ready = '1' and s_inject_ready_d(i) = '1') else
                                  '0';

     ep_o(i).inject_packet_sel <= s_ep(i).inject_packet_sel   when (s_tru_ena = '1') else (others => '0');
     ep_o(i).inject_user_value <= s_ep(i).inject_user_value   when (s_tru_ena = '1') else (others => '0');
     ep_o(i).inject_req        <= s_ep(i).inject_req          when (s_tru_ena = '1') else '0';
     ep_o(i).fc_pause_req      <= '0'; --s_trans_ep_ctr(i).pauseSend;
     ep_o(i).fc_pause_delay    <= (others => '0'); --s_trans_ep_ctr(i).pauseTime;
    
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
--     wb_addr_i          => wb_in.adr(3 downto 0),
    wb_addr_i          => wb_in.adr(4 downto 0),
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

 s_bank_swap <= s_regs_fromwb.gcr_tru_bank_o or s_bank_swap_on_trans ;

 CTRL_BANK: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        s_tru_tab_bank<= '0';
      else
        if(s_bank_swap = '1') then
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
  s_config.mcr_pattern_mode_sub          <= s_regs_fromwb.mcr_pattern_mode_sub_o    ;
  s_config.lacr_agg_df_hp_id             <= s_regs_fromwb.lacr_agg_df_hp_id_o       ;
  s_config.lacr_agg_df_br_id             <= s_regs_fromwb.lacr_agg_df_br_id_o       ;
  s_config.lacr_agg_df_un_id             <= s_regs_fromwb.lacr_agg_df_un_id_o       ;
--   s_config.lagt_gr_id_mask(0)            <= s_regs_fromwb.lagt_lagt_gr_id_mask_0_o  ;
--   s_config.lagt_gr_id_mask(1)            <= s_regs_fromwb.lagt_lagt_gr_id_mask_1_o  ;
--   s_config.lagt_gr_id_mask(2)            <= s_regs_fromwb.lagt_lagt_gr_id_mask_2_o  ;
--   s_config.lagt_gr_id_mask(3)            <= s_regs_fromwb.lagt_lagt_gr_id_mask_3_o  ;
--   s_config.lagt_gr_id_mask(4)            <= s_regs_fromwb.lagt_lagt_gr_id_mask_4_o  ;
--   s_config.lagt_gr_id_mask(5)            <= s_regs_fromwb.lagt_lagt_gr_id_mask_5_o  ;
--   s_config.lagt_gr_id_mask(6)            <= s_regs_fromwb.lagt_lagt_gr_id_mask_6_o  ;
--   s_config.lagt_gr_id_mask(7)            <= s_regs_fromwb.lagt_lagt_gr_id_mask_7_o  ;
  s_config.tcr_trans_ena                 <= s_regs_fromwb.tcgr_trans_ena_o          ;
  s_config.tcr_trans_clr                 <= s_regs_fromwb.tcgr_trans_clear_o        ;
  s_config.tcr_trans_mode                <= s_regs_fromwb.tcgr_trans_mode_o         ;
  s_config.tcr_trans_rx_id               <= s_regs_fromwb.tcgr_trans_rx_id_o        ;
  s_config.tcr_trans_prio                <= s_regs_fromwb.tcgr_trans_prio_o         ;
  s_config.tcr_trans_prio_mode           <= s_regs_fromwb.tcgr_trans_prio_mode_o    ;
  s_config.tcr_trans_port_a_id           <= s_regs_fromwb.tcpr_trans_port_a_id_o    ;
  s_config.tcr_trans_port_a_valid        <= s_regs_fromwb.tcpr_trans_port_a_valid_o ;
  s_config.tcr_trans_port_b_id           <= s_regs_fromwb.tcpr_trans_port_b_id_o    ;
  s_config.tcr_trans_port_b_valid        <= s_regs_fromwb.tcpr_trans_port_b_valid_o ;
  s_config.tcr_trans_pause_time          <= s_regs_fromwb.tcpbr_trans_pause_time_o  ;
  s_config.tcr_trans_block_time          <= s_regs_fromwb.tcpbr_trans_block_time_o  ;
  s_config.rtrcr_rtr_ena                 <= s_regs_fromwb.rtrcr_rtr_ena_o           ;
  s_config.rtrcr_rtr_reset               <= s_regs_fromwb.rtrcr_rtr_reset_o         ;
  s_config.rtrcr_rtr_mode                <= s_regs_fromwb.rtrcr_rtr_mode_o          ;
  s_config.rtrcr_rtr_rx                  <= s_regs_fromwb.rtrcr_rtr_rx_o            ;
  s_config.rtrcr_rtr_tx                  <= s_regs_fromwb.rtrcr_rtr_tx_o            ;
  
  s_config.hwframe_rx_fwd                <= s_regs_fromwb.hwfc_rx_fwd_id_o          ;
  s_config.hwframe_tx_fwd                <= s_regs_fromwb.hwfc_tx_fwd_id_o          ;
  s_config.hwframe_rx_blk                <= s_regs_fromwb.hwfc_rx_blk_id_o          ;
  s_config.hwframe_tx_blk                <= s_regs_fromwb.hwfc_tx_blk_id_o          ;
  
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
  swc_block_oq_req_o.ports   <= s_swc_ctrl.blockPortsMask  when (s_tru_ena = '1') else (others => '0');
  swc_block_oq_req_o.req     <= s_swc_ctrl.blockReq        when (s_tru_ena = '1') else '0';
  swc_block_oq_req_o.quanta  <= s_swc_ctrl.blockTime       when (s_tru_ena = '1') else (others => '0');
  swc_block_oq_req_o.classes <= s_swc_ctrl.blockQueuesMask when (s_tru_ena = '1') else (others => '0');
  
  enabled_o                  <= s_regs_fromwb.gcr_g_ena_o  ;
  s_tru_ena                  <= s_regs_fromwb.gcr_g_ena_o  ;
  --------------
  s_debug_port_sel <=  to_integer(unsigned(s_regs_fromwb.dps_pid_o));

  DEBUG_CTRL_GEN: for i in 0 to g_num_ports-1 generate
    s_pidr_inject(i) <= s_regs_fromwb.pidr_inject_o when (i = s_debug_port_sel) else
                        '0';
  end generate;
  
  DEBUG: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        CLEAR: for i in 0 to g_num_ports-1 loop
          s_debug_filter(i).pfdr_class <= (others =>'0');
          s_debug_filter(i).pfdr_cnt   <= (others =>'0');
        end loop;
        s_regs_towb.pidr_iready_i      <= '0';
        s_regs_towb.pfdr_class_i       <= (others =>'0');
        s_regs_towb.pfdr_cnt_i         <= (others =>'0');
      else
        REMEMBER: for i in 0 to g_num_ports-1 loop
          if(ep_i(i).pfilter_done ='1' and ep_i(i).pfilter_pclass /= x"00") then -- something filtered
            if(s_debug_port_sel = i and s_regs_fromwb.pfdr_clr_o = '1') then
              s_debug_filter(i).pfdr_class <= ep_i(i).pfilter_pclass;
              s_debug_filter(i).pfdr_cnt(7 downto 0)    <= x"01"; -- filtered
              s_debug_filter(i).pfdr_cnt(15 downto 8)   <= x"01";
            else
              s_debug_filter(i).pfdr_class <= ep_i(i).pfilter_pclass or s_debug_filter(i).pfdr_class;
              s_debug_filter(i).pfdr_cnt(7  downto 0)  <= std_logic_vector(unsigned(s_debug_filter(i).pfdr_cnt(7  downto 0))+1);          
              s_debug_filter(i).pfdr_cnt(15 downto 8)  <= std_logic_vector(unsigned(s_debug_filter(i).pfdr_cnt(15 downto 8))+1);          
            end if;  
          elsif(ep_i(i).pfilter_done ='1' and ep_i(i).pfilter_pclass = x"00") then -- non-recognzied pck
            if(s_debug_port_sel = i and s_regs_fromwb.pfdr_clr_o = '1') then
              s_debug_filter(i).pfdr_cnt(15 downto 8)   <= x"01";
            else        
              s_debug_filter(i).pfdr_cnt(15 downto 8)  <= std_logic_vector(unsigned(s_debug_filter(i).pfdr_cnt(15 downto 8))+1);          
            end if;             
          elsif(s_debug_port_sel = i and s_regs_fromwb.pfdr_clr_o = '1') then
            s_debug_filter(i).pfdr_class <= (others =>'0');
            s_debug_filter(i).pfdr_cnt   <= (others =>'0');
          end if;
        end loop; 

        s_regs_towb.pidr_iready_i <= ep_i(s_debug_port_sel).inject_ready;       
        s_regs_towb.pfdr_class_i  <= s_debug_filter(s_debug_port_sel).pfdr_class;
        s_regs_towb.pfdr_cnt_i    <= s_debug_filter(s_debug_port_sel).pfdr_cnt;
        
      end if;
    end if;
  end process;  

end rtl;
