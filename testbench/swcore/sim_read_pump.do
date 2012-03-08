vlib work
vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/generic_ssram_dualport_singleclock.vhd
vcom ../../../modules/wrsw_swcore/swc_swcore_pkg.vhd
vcom ../../../modules/wrsw_swcore/swc_packet_mem_read_pump.vhd

vlog swc_read_pump_tb.sv

vsim work.main
radix -hexadecimal


add wave \
{sim:/main/clk } \
{sim:/main/rst } \
{sim:/main/page_addr } \
{sim:/main/page_req } \
{sim:/main/pgend } \
{sim:/main/drdy } \
{sim:/main/dreq } \
{sim:/main/sync } \
{sim:/main/addr } \
{sim:/main/d } \
{sim:/main/q } \
{sim:/main/pckend } \
{sim:/main/current_page_addr } \
{sim:/main/next_page_addr } \
{sim:/main/read_req } \
{sim:/main/read_data_valid } 
add wave \
{sim:/main/DUT/clk_i } \
{sim:/main/DUT/rst_n_i } \
{sim:/main/DUT/pgreq_i } \
{sim:/main/DUT/pgaddr_i } \
{sim:/main/DUT/pckend_o } \
{sim:/main/DUT/pgend_o } \
{sim:/main/DUT/drdy_o } \
{sim:/main/DUT/dreq_i } \
{sim:/main/DUT/sync_read_i } \
{sim:/main/DUT/ll_read_addr_o } \
{sim:/main/DUT/ll_read_data_i } \
{sim:/main/DUT/ll_read_req_o } \
{sim:/main/DUT/ll_read_valid_data_i } \
{sim:/main/DUT/d_o } \
{sim:/main/DUT/sync_i } \
{sim:/main/DUT/addr_o } \
{sim:/main/DUT/q_i } \
{sim:/main/DUT/out_reg } \
{sim:/main/DUT/cntr } \
{sim:/main/DUT/sync_d0 } \
{sim:/main/DUT/sync_d1 } \
{sim:/main/DUT/reg_not_empty } \
{sim:/main/DUT/cntr_full } \
{sim:/main/DUT/mem_addr } \
{sim:/main/DUT/allones } \
{sim:/main/DUT/zeros } \
{sim:/main/DUT/advance_addr } \
{sim:/main/DUT/load_out_reg } \
{sim:/main/DUT/pgend } \
{sim:/main/DUT/pckend } \
{sim:/main/DUT/current_page_addr } \
{sim:/main/DUT/next_page_addr } 

do wave.do

run 3us
wave zoomfull

