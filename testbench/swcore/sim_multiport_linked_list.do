vlib work

vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/generic_ssram_dualport_singleclock.vhd
vcom ../../../modules/wrsw_swcore/swc_swcore_pkg.vhd
vcom ../../../modules/wrsw_swcore/swc_prio_encoder.vhd
vcom ../../../modules/wrsw_swcore/swc_rr_arbiter.vhd
vcom ../../../modules/wrsw_swcore/swc_multiport_linked_list.vhd

vlog swc_multiport_linked_list_tb.v

vsim work.main
radix -hexadecimal

do wave.do

add wave \
{sim:/main/done_write } \
{sim:/main/done_free } \
{sim:/main/done_free_pck } \
{sim:/main/done_read } \
{sim:/main/data_out } 
add wave \
{sim:/main/DUT/rst_n_i } \
{sim:/main/DUT/clk_i } \
{sim:/main/DUT/write_i } \
{sim:/main/DUT/free_i } \
{sim:/main/DUT/read_pump_read_i } \
{sim:/main/DUT/free_pck_read_i } \
{sim:/main/DUT/write_done_o } \
{sim:/main/DUT/free_done_o } \
{sim:/main/DUT/read_pump_read_done_o } \
{sim:/main/DUT/free_pck_read_done_o } \
{sim:/main/DUT/read_pump_addr_i } \
{sim:/main/DUT/free_pck_addr_i } \
{sim:/main/DUT/write_addr_i } \
{sim:/main/DUT/free_addr_i } \
{sim:/main/DUT/write_data_i } \
{sim:/main/DUT/data_o } \
{sim:/main/DUT/ll_write_enable } \
{sim:/main/DUT/ll_write_addr } \
{sim:/main/DUT/ll_free_addr } \
{sim:/main/DUT/ll_wr_addr } \
{sim:/main/DUT/ll_rd_addr } \
{sim:/main/DUT/ll_write_data } \
{sim:/main/DUT/ll_wr_data } \
{sim:/main/DUT/ll_read_data } \
{sim:/main/DUT/write_request_vec } \
{sim:/main/DUT/read_request_vec } \
{sim:/main/DUT/write_request_grant } \
{sim:/main/DUT/read_request_grant } \
{sim:/main/DUT/write_request_grant_valid } \
{sim:/main/DUT/read_request_grant_valid } \
{sim:/main/DUT/in_sel_write } \
{sim:/main/DUT/in_sel_read } \
{sim:/main/DUT/write_done_feedback } \
{sim:/main/DUT/write_done } \
{sim:/main/DUT/free_done_feedback } \
{sim:/main/DUT/free_done } \
{sim:/main/DUT/read_pump_read_done_feedback } \
{sim:/main/DUT/read_pump_read_done } \
{sim:/main/DUT/free_pck_read_done_feedback } \
{sim:/main/DUT/free_pck_read_done } 

run 500us
wave zoomfull