onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /main/DUT/rst_n_i
add wave -noupdate /main/DUT/phys_rdy
add wave -noupdate -group TB_EP -expand -group EP0 {/main/DUT/genblk1[0]/DUT/snk_dat_i}
add wave -noupdate -group TB_EP -expand -group EP0 {/main/DUT/genblk1[0]/DUT/snk_adr_i}
add wave -noupdate -group TB_EP -expand -group EP0 {/main/DUT/genblk1[0]/DUT/snk_sel_i}
add wave -noupdate -group TB_EP -expand -group EP0 {/main/DUT/genblk1[0]/DUT/snk_cyc_i}
add wave -noupdate -group TB_EP -expand -group EP0 {/main/DUT/genblk1[0]/DUT/snk_stb_i}
add wave -noupdate -group TB_EP -expand -group EP0 {/main/DUT/genblk1[0]/DUT/snk_we_i}
add wave -noupdate -group TB_EP -expand -group EP0 {/main/DUT/genblk1[0]/DUT/snk_stall_o}
add wave -noupdate -group TB_EP -expand -group EP0 {/main/DUT/genblk1[0]/DUT/snk_ack_o}
add wave -noupdate -group TB_EP -expand -group EP0 {/main/DUT/genblk1[0]/DUT/snk_err_o}
add wave -noupdate -group TB_EP -expand -group EP0 {/main/DUT/genblk1[0]/DUT/snk_rty_o}
add wave -noupdate -group TB_EP -expand -group EP1 {/main/DUT/genblk1[1]/DUT/snk_dat_i}
add wave -noupdate -group TB_EP -expand -group EP1 {/main/DUT/genblk1[1]/DUT/snk_adr_i}
add wave -noupdate -group TB_EP -expand -group EP1 {/main/DUT/genblk1[1]/DUT/snk_sel_i}
add wave -noupdate -group TB_EP -expand -group EP1 {/main/DUT/genblk1[1]/DUT/snk_cyc_i}
add wave -noupdate -group TB_EP -expand -group EP1 {/main/DUT/genblk1[1]/DUT/snk_stb_i}
add wave -noupdate -group TB_EP -expand -group EP1 {/main/DUT/genblk1[1]/DUT/snk_we_i}
add wave -noupdate -group TB_EP -expand -group EP1 {/main/DUT/genblk1[1]/DUT/snk_stall_o}
add wave -noupdate -group TB_EP -expand -group EP1 {/main/DUT/genblk1[1]/DUT/snk_ack_o}
add wave -noupdate -group TB_EP -expand -group EP1 {/main/DUT/genblk1[1]/DUT/snk_err_o}
add wave -noupdate -group TB_EP -expand -group EP1 {/main/DUT/genblk1[1]/DUT/snk_rty_o}
add wave -noupdate -group TB_EP -expand -group EP6 {/main/DUT/genblk1[6]/DUT/snk_dat_i}
add wave -noupdate -group TB_EP -expand -group EP6 {/main/DUT/genblk1[6]/DUT/snk_adr_i}
add wave -noupdate -group TB_EP -expand -group EP6 {/main/DUT/genblk1[6]/DUT/snk_sel_i}
add wave -noupdate -group TB_EP -expand -group EP6 {/main/DUT/genblk1[6]/DUT/snk_cyc_i}
add wave -noupdate -group TB_EP -expand -group EP6 {/main/DUT/genblk1[6]/DUT/snk_stb_i}
add wave -noupdate -group TB_EP -expand -group EP6 {/main/DUT/genblk1[6]/DUT/snk_we_i}
add wave -noupdate -group TB_EP -expand -group EP6 {/main/DUT/genblk1[6]/DUT/snk_stall_o}
add wave -noupdate -group TB_EP -expand -group EP6 {/main/DUT/genblk1[6]/DUT/snk_ack_o}
add wave -noupdate -group TB_EP -expand -group EP6 {/main/DUT/genblk1[6]/DUT/snk_err_o}
add wave -noupdate -group TB_EP -expand -group EP6 {/main/DUT/genblk1[6]/DUT/snk_rty_o}
add wave -noupdate -group TB_EP -expand -group EP7 {/main/DUT/genblk1[7]/DUT/snk_dat_i}
add wave -noupdate -group TB_EP -expand -group EP7 {/main/DUT/genblk1[7]/DUT/snk_adr_i}
add wave -noupdate -group TB_EP -expand -group EP7 {/main/DUT/genblk1[7]/DUT/snk_sel_i}
add wave -noupdate -group TB_EP -expand -group EP7 {/main/DUT/genblk1[7]/DUT/snk_cyc_i}
add wave -noupdate -group TB_EP -expand -group EP7 {/main/DUT/genblk1[7]/DUT/snk_stb_i}
add wave -noupdate -group TB_EP -expand -group EP7 {/main/DUT/genblk1[7]/DUT/snk_we_i}
add wave -noupdate -group TB_EP -expand -group EP7 {/main/DUT/genblk1[7]/DUT/snk_stall_o}
add wave -noupdate -group TB_EP -expand -group EP7 {/main/DUT/genblk1[7]/DUT/snk_ack_o}
add wave -noupdate -group TB_EP -expand -group EP7 {/main/DUT/genblk1[7]/DUT/snk_err_o}
add wave -noupdate -group TB_EP -expand -group EP7 {/main/DUT/genblk1[7]/DUT/snk_rty_o}
add wave -noupdate -expand -group EP0 /main/DUT/WRS_Top/U_Wrapped_SCBCore/dbg_rtu_bug(0)
add wave -noupdate -expand -group EP0 /main/DUT/WRS_Top/U_Wrapped_SCBCore/rtu_req(0).valid
add wave -noupdate -expand -group EP0 /main/DUT/WRS_Top/U_Wrapped_SCBCore/rtu_rsp_ack(0)
add wave -noupdate -expand -group EP0 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/U_Wrapped_Endpoint/U_Rx_Path/rxbuf_full
add wave -noupdate -expand -group EP0 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/U_Wrapped_Endpoint/U_Rx_Path/fab_pipe
add wave -noupdate -expand -group EP0 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/U_Wrapped_Endpoint/U_Rx_Path/dreq_pipe
add wave -noupdate -expand -group EP0 -height 16 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/U_Wrapped_Endpoint/U_Rx_Path/U_RX_Wishbone_Master/state
add wave -noupdate -expand -group EP0 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/U_Wrapped_Endpoint/U_Rx_Path/U_RX_Wishbone_Master/sof_reg
add wave -noupdate -expand -group EP0 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/U_Wrapped_Endpoint/U_Rx_Path/U_RX_Wishbone_Master/snk_fab_i.sof
add wave -noupdate -expand -group EP0 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/U_Wrapped_Endpoint/U_Rx_Path/U_RX_Wishbone_Master/snk_dreq_o
add wave -noupdate -expand -group EP0 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/U_Wrapped_Endpoint/src_in.stall
add wave -noupdate -expand -group EP0 -expand /main/DUT/WRS_Top/U_Wrapped_SCBCore/endpoint_src_out(0)
add wave -noupdate -expand -group EP0 -expand /main/DUT/WRS_Top/U_Wrapped_SCBCore/endpoint_src_in(0)
add wave -noupdate -expand -group EP0 /main/DUT/WRS_Top/U_Wrapped_SCBCore/endpoint_snk_in(0)
add wave -noupdate -expand -group EP0 /main/DUT/WRS_Top/U_Wrapped_SCBCore/endpoint_snk_out(0)
add wave -noupdate -expand -group EP0 -expand -group rtu_req(0) /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/rtu_full_i
add wave -noupdate -expand -group EP0 -expand -group rtu_req(0) /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/rtu_almost_full_i
add wave -noupdate -expand -group EP0 -expand -group rtu_req(0) /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/rtu_rq_strobe_p1_o
add wave -noupdate -expand -group EP0 -expand -group rtu_req(0) /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/rtu_rq_abort_o
add wave -noupdate -expand -group EP0 -expand -group rtu_req(0) /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/rtu_rq_smac_o
add wave -noupdate -expand -group EP0 -expand -group rtu_req(0) /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/rtu_rq_dmac_o
add wave -noupdate -expand -group EP0 -expand -group rtu_req(0) /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/rtu_rq_vid_o
add wave -noupdate -expand -group EP0 -expand -group rtu_req(0) /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/rtu_rq_has_vid_o
add wave -noupdate -expand -group EP0 -expand -group rtu_req(0) /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/rtu_rq_prio_o
add wave -noupdate -expand -group EP0 -expand -group rtu_req(0) /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/gen_endpoints_and_phys(0)/U_Endpoint_X/rtu_rq_has_prio_o
add wave -noupdate -expand -group EP0 -expand /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/rsp(0)
add wave -noupdate -expand -group EP0 /main/clk_sys
add wave -noupdate -expand -group EP0 -group RTU_port -height 16 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/port_state
add wave -noupdate -expand -group EP0 -group RTU_port /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/rtu_str_config_i.dop_on_fmatch_full
add wave -noupdate -expand -group EP0 -group RTU_port /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/drop
add wave -noupdate -expand -group EP0 -group RTU_port /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/dbg_fwd_mask
add wave -noupdate -expand -group EP0 -group RTU_port -expand /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/nice_dbg_o
add wave -noupdate -expand -group EP0 -group RTU_port /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/full_match_aboard
add wave -noupdate -expand -group EP0 -group RTU_port /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/full_match_aboard_d
add wave -noupdate -expand -group EP0 -group RTU_port /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/fast_valid_reg
add wave -noupdate -expand -group EP0 -group RTU_port /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/full_valid_reg
add wave -noupdate -expand -group EP0 -group RTU_port -group FULL_MATCH /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/U_Full_Match/rsp_fifo_write_o
add wave -noupdate -expand -group EP0 -group RTU_port -group FULL_MATCH -height 16 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/U_Full_Match/mstate
add wave -noupdate -expand -group EP0 -group RTU_port /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/full_match_in.valid
add wave -noupdate -expand -group EP0 -group RTU_port /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/rq_rsp_cnt
add wave -noupdate -expand -group EP0 -group RTU_port /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/full_match_req_in_progress
add wave -noupdate -expand -group EP0 -group RTU_port /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/delayed_full_match_wr_req
add wave -noupdate -expand -group EP0 -group RTU_port -expand /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/rtu_rsp_o
add wave -noupdate -expand -group EP0 -group RTU_port /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/rtu_rsp_ack_i
add wave -noupdate -expand -group EP0 -group RTU_port /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/fast_match
add wave -noupdate -expand -group EP0 -group RTU_port /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_RTU/ports(0)/U_PortX/full_match
add wave -noupdate -expand -group EP0 -expand -group Watchdog /main/DUT/WRS_Top/U_Wrapped_SCBCore/GEN_SWC_RST/WDOG/nomem_cnt
add wave -noupdate -expand -group EP0 -expand -group Watchdog /main/DUT/WRS_Top/U_Wrapped_SCBCore/GEN_SWC_RST/WDOG/nomem_trig
add wave -noupdate -expand -group EP0 -expand -group Watchdog /main/DUT/WRS_Top/U_Wrapped_SCBCore/GEN_SWC_RST/WDOG/reset_mode
add wave -noupdate -expand -group EP0 -expand -group Watchdog /main/DUT/WRS_Top/U_Wrapped_SCBCore/GEN_SWC_RST/WDOG/rst_cnt
add wave -noupdate -expand -group EP0 -expand -group Watchdog /main/DUT/WRS_Top/U_Wrapped_SCBCore/GEN_SWC_RST/WDOG/rst_trig
add wave -noupdate -expand -group EP0 -expand -group Watchdog /main/DUT/WRS_Top/U_Wrapped_SCBCore/GEN_SWC_RST/WDOG/rst_trig_d0
add wave -noupdate -expand -group EP0 -expand -group Watchdog /main/DUT/WRS_Top/U_Wrapped_SCBCore/GEN_SWC_RST/WDOG/swcrst_n_o
add wave -noupdate -expand -group EP0 -expand -group Watchdog /main/DUT/WRS_Top/U_Wrapped_SCBCore/GEN_SWC_RST/WDOG/wb_regs_out.cr_port_load_o
add wave -noupdate -expand -group EP0 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/nomem_o
add wave -noupdate -expand -group EP0 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/res_full_o
add wave -noupdate -expand -group EP0 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/res_almost_full_o
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/dbg_rtu_cnt(0)
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/swc_dbg.ib(0).sof_cnt
add wave -noupdate -expand -group EP0 -expand -group SWC_Input -radix unsigned /main/DUT/WRS_Top/U_Wrapped_SCBCore/dbg_cnt_eq(0)
add wave -noupdate -expand -group EP0 -expand -group SWC_Input -radix unsigned /main/DUT/WRS_Top/U_Wrapped_SCBCore/dbg_cnt_dif(0)
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/dbg_rtu_bug(0)
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/hwiu_dbg1
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/hwiu_dbg2
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/hwiu_val1
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/hwiu_val2
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/snk_cyc_int
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/snk_cyc_d0
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/snk_stb_int
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/snk_o.stall
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/snk_stall_force_h
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/snk_stall_force_l
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/lw_sync_first_stage
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/lw_sync_second_stage
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/lw_sync_2nd_stage_chk
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/pckstart_page_in_advance
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/pckinter_page_in_advance
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/tp_ff_done_reg
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/ffree_mask
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/ffree_pre_mask
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/mmu_force_free_req
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/mmu_force_free_addr
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/mmu_force_free_o
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/mmu_force_free_done_i
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/current_pckstart_pageaddr
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/rp_ll_entry_addr
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/pckstart_pageaddr
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/pckinter_pageaddr
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/rtu_rsp_valid_i
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/rtu_dst_port_mask_i
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/rtu_rsp_ack_o
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/rcv_pckstart_new
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/pcknew_reg
add wave -noupdate -expand -group EP0 -expand -group SWC_Input -height 16 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/s_page_alloc
add wave -noupdate -expand -group EP0 -expand -group SWC_Input -height 16 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/s_rcv_pck
add wave -noupdate -expand -group EP0 -expand -group SWC_Input -height 16 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/s_transfer_pck
add wave -noupdate -expand -group EP0 -expand -group SWC_Input -height 16 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/s_ll_write
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/new_pck_first_page
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/new_pck_first_page_ack
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/new_pck_first_page_p1
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/lw_pckstart_pg_clred
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/pckstart_pg_clred
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/rp_rcv_first_page
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/pckstart_pageaddr_clred
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/current_pckstart_pageaddr
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/current_pckstart_ll_stored
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/dbg_last_ffreed_pg
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/finish_rcv_pck
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/ll_wr_req
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/ll_wr_done_i
add wave -noupdate -expand -group EP0 -expand -group SWC_Input -childformat {{/main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/ll_entry.size -radix unsigned}} -expand -subitemconfig {/main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/ll_entry.size {-radix unsigned}} /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/ll_entry
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/mpm_dvalid_o
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/mpm_pg_addr_o
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/mpm_data_o
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/in_pck_dat
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/in_pck_dat_d0
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/mpm_dlast
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/mpm_pg_req_i
add wave -noupdate -expand -group EP0 -expand -group SWC_Input -radix unsigned /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/page_word_cnt
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/in_pck_sof
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/in_pck_sof_reg
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/in_pck_sof_reg_ack
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/in_pck_eof
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/in_pck_err
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/rp_in_pck_error
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/nice_dbg_o
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/mmu_page_alloc_req_o
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/mmu_page_alloc_done_i
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/pckstart_page_alloc_req
add wave -noupdate -expand -group EP0 -expand -group SWC_Input /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(0)/INPUT_BLOCK/pckinter_page_alloc_req
add wave -noupdate /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/pg_nomem
add wave -noupdate /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/alloc_i
add wave -noupdate /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/alloc_done_o
add wave -noupdate /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/ports(0)
add wave -noupdate /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/gen_blocks(8)/INPUT_BLOCK/clk_i
add wave -noupdate /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/grant_ib_d0
add wave -noupdate -group PAGE_ALLOC /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/ALLOC_CORE/initializing
add wave -noupdate -group PAGE_ALLOC /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/ALLOC_CORE/done_o
add wave -noupdate -group PAGE_ALLOC /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/ALLOC_CORE/q_write_p1
add wave -noupdate -group PAGE_ALLOC -radix unsigned /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/ALLOC_CORE/free_pages
add wave -noupdate -group PAGE_ALLOC /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/ALLOC_CORE/alloc_i
add wave -noupdate -group PAGE_ALLOC /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/ALLOC_CORE/alloc_req_d0.alloc
add wave -noupdate -group PAGE_ALLOC /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/ALLOC_CORE/dbg_alloc_done
add wave -noupdate -group PAGE_ALLOC /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/ALLOC_CORE/q_read_p0
add wave -noupdate -group PAGE_ALLOC /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/ALLOC_CORE/out_nomem
add wave -noupdate -group PAGE_ALLOC /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/ALLOC_CORE/out_nomem_d0
add wave -noupdate -group PAGE_ALLOC /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/ALLOC_CORE/out_nomem_d1
add wave -noupdate -group PAGE_ALLOC /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/ALLOC_CORE/pg_adv_valid
add wave -noupdate -group PAGE_ALLOC /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/MEMORY_MANAGEMENT_UNIT/ALLOC_CORE/rd_ptr_p0
add wave -noupdate -expand -group FREE(0) /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/PCK_PAGES_FREEEING_MODULE/lpd_gen(0)/LPD/ib_force_free_i
add wave -noupdate -expand -group FREE(0) /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/PCK_PAGES_FREEEING_MODULE/lpd_gen(0)/LPD/ib_force_free_done_o
add wave -noupdate -expand -group FREE(0) /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/PCK_PAGES_FREEEING_MODULE/lpd_gen(0)/LPD/ib_force_free_pgaddr_i
add wave -noupdate -expand -group FREE(0) -height 16 /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/PCK_PAGES_FREEEING_MODULE/lpd_gen(0)/LPD/state
add wave -noupdate -expand -group FREE(0) /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/PCK_PAGES_FREEEING_MODULE/lpd_gen(0)/LPD/fifo_full
add wave -noupdate -expand -group FREE(0) /main/DUT/WRS_Top/U_Wrapped_SCBCore/gen_network_stuff/U_Swcore/PCK_PAGES_FREEEING_MODULE/lpd_gen(0)/LPD/fifo_clean
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {104100070290 fs} 1} {{Cursor 2} {115415611850 fs} 1}
configure wave -namecolwidth 264
configure wave -valuecolwidth 40
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 fs} {166723200 ps}
