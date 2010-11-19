vlib work
vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/swc_swcore_pkg.vhd
vcom ../../../modules/wrsw_swcore/swc_input_block.vhd

vlog -sv swc_input_block.sv

vsim work.main -voptargs="+acc"
radix -hexadecimal


do wave.do

add wave \
{sim:/main/clk } \
{sim:/main/a_to_input_block_data } \
{sim:/main/a_to_input_block_ctrl } \
{sim:/main/a_to_input_block_bytesel } \
{sim:/main/a_to_input_block_dreq } \
{sim:/main/a_to_input_block_valid } \
{sim:/main/a_to_input_block_sof_p1 } \
{sim:/main/a_to_input_block_eof_p1 } \
{sim:/main/a_to_input_block_rerror_p1 } \
{sim:/main/mmu_page_alloc_req } \
{sim:/main/mmu_page_alloc_done } \
{sim:/main/mmu_pageaddr_in } \
{sim:/main/mmu_pageaddr_out } \
{sim:/main/mmu_force_free } \
{sim:/main/mmu_set_usecnt } \
{sim:/main/mmu_set_usecnt_done } \
{sim:/main/mmu_usecnt } \
{sim:/main/rtu_rsp_valid } \
{sim:/main/rtu_rsp_ack } \
{sim:/main/rtu_dst_port_mask } \
{sim:/main/rtu_drop } \
{sim:/main/rtu_prio } \
{sim:/main/mpm_pckstart } \
{sim:/main/mpm_pageaddr } \
{sim:/main/mpm_pageend } \
{sim:/main/mpm_data } \
{sim:/main/mpm_drdy } \
{sim:/main/mpm_full } \
{sim:/main/mpm_flush } \
{sim:/main/pta_transfer_pck } \
{sim:/main/pta_pageaddr } \
{sim:/main/pta_mask } \
{sim:/main/pta_prio } \
{sim:/main/rst } 
add wave \
{sim:/main/DUT/clk_i } \
{sim:/main/DUT/rst_n_i } \
{sim:/main/DUT/tx_sof_p1_i } \
{sim:/main/DUT/tx_eof_p1_i } \
{sim:/main/DUT/tx_data_i } \
{sim:/main/DUT/tx_ctrl_i } \
{sim:/main/DUT/tx_valid_i } \
{sim:/main/DUT/tx_bytesel_i } \
{sim:/main/DUT/tx_dreq_o } \
{sim:/main/DUT/tx_abort_p1_i } \
{sim:/main/DUT/tx_rerror_p1_i } \
{sim:/main/DUT/mmu_page_alloc_req_o } \
{sim:/main/DUT/mmu_page_alloc_done_i } \
{sim:/main/DUT/mmu_pageaddr_i } \
{sim:/main/DUT/mmu_pageaddr_o } \
{sim:/main/DUT/mmu_force_free_o } \
{sim:/main/DUT/mmu_set_usecnt_o } \
{sim:/main/DUT/mmu_set_usecnt_done_i } \
{sim:/main/DUT/mmu_usecnt_o } \
{sim:/main/DUT/rtu_rsp_valid_i } \
{sim:/main/DUT/rtu_rsp_ack_o } \
{sim:/main/DUT/rtu_dst_port_mask_i } \
{sim:/main/DUT/rtu_drop_i } \
{sim:/main/DUT/rtu_prio_i } \
{sim:/main/DUT/mpm_pckstart_o } \
{sim:/main/DUT/mpm_pageaddr_o } \
{sim:/main/DUT/mpm_pagereq_o } \
{sim:/main/DUT/mpm_pageend_i } \
{sim:/main/DUT/mpm_data_o } \
{sim:/main/DUT/mpm_drdy_o } \
{sim:/main/DUT/mpm_full_i } \
{sim:/main/DUT/mpm_flush_o } \
{sim:/main/DUT/pta_transfer_pck_o } \
{sim:/main/DUT/pta_pageaddr_o } \
{sim:/main/DUT/pta_mask_o } \
{sim:/main/DUT/pta_prio_o } \
{sim:/main/DUT/page_in_advance_allocated } \
{sim:/main/DUT/mmu_page_alloc_req } \
{sim:/main/DUT/rtu_rsp_valid_d1 } \
{sim:/main/DUT/tx_dreq } \
{sim:/main/DUT/rtu_drop } \
{sim:/main/DUT/usecnt } \
{sim:/main/DUT/set_usecnt } \
{sim:/main/DUT/mpm_pckstart } \
{sim:/main/DUT/mpm_pagereq } \
{sim:/main/DUT/mpm_flush } 

run 3us
wave zoomfull

