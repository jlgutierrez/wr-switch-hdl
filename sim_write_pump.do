vlib work
vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/generic_ssram_dualport_singleclock.vhd
vcom ../../../modules/wrsw_swcore/swc_swcore_pkg.vhd
vcom ../../../modules/wrsw_swcore/swc_packet_mem_write_pump.vhd

vlog swc_write_pump_tb.v

vsim work.main
radix -hexadecimal

add wave \
{sim:/main/reg_full } \
{sim:/main/q } \
{sim:/main/we } \
{sim:/main/pgend } \
{sim:/main/current_page_addr } \
{sim:/main/next_page_addr } \
{sim:/main/next_page_addr_wr_req } 
add wave \
{sim:/main/DUT/clk_i } \
{sim:/main/DUT/rst_n_i } \
{sim:/main/DUT/pgaddr_i } \
{sim:/main/DUT/pgreq_i } \
{sim:/main/DUT/pgend_o } \
{sim:/main/DUT/pckstart_i } \
{sim:/main/DUT/d_i } \
{sim:/main/DUT/drdy_i } \
{sim:/main/DUT/full_o } \
{sim:/main/DUT/flush_i } \
{sim:/main/DUT/current_page_addr_o } \
{sim:/main/DUT/next_page_addr_o } \
{sim:/main/DUT/next_page_addr_wr_req_o } \
{sim:/main/DUT/next_page_addr_wr_done_i } \
{sim:/main/DUT/sync_i } \
{sim:/main/DUT/addr_o } \
{sim:/main/DUT/q_o } \
{sim:/main/DUT/we_o } \
{sim:/main/DUT/cntr } \
{sim:/main/DUT/in_reg } \
{sim:/main/DUT/reg_full } \
{sim:/main/DUT/mem_addr } \
{sim:/main/DUT/we_int } \
{sim:/main/DUT/flush_reg } \
{sim:/main/DUT/write_on_sync } \
{sim:/main/DUT/cntr_full } \
{sim:/main/DUT/allones } \
{sim:/main/DUT/pgend } \
{sim:/main/DUT/pckstart } \
{sim:/main/DUT/current_page_addr_int } \
{sim:/main/DUT/previous_page_addr_int } \
{sim:/main/DUT/ll_write_addr } \
{sim:/main/DUT/ll_write_data } \
{sim:/main/DUT/ll_wr_req } \
{sim:/main/DUT/state } 



do wave.do

run 30us
wave zoomfull

