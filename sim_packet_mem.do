vlib work
vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/generic_ssram_dualport_singleclock.vhd
vcom ../../../modules/wrsw_swcore/swc_swcore_pkg.vhd
vcom ../../../modules/wrsw_swcore/swc_packet_mem_write_pump.vhd
vcom ../../../modules/wrsw_swcore/swc_packet_mem_read_pump.vhd
vcom ../../../modules/wrsw_swcore/swc_packet_mem.vhd

vlog -sv swc_packet_mem_tb.v

vsim work.main
radix -hexadecimal

add wave \
{sim:/main/clk } \
{sim:/main/rst } \
{sim:/main/wr_pagereq } \
{sim:/main/wr_pageend } \
{sim:/main/wr_pageaddr } \
{sim:/main/wr_ctrl } \
{sim:/main/wr_data } \
{sim:/main/wr_drdy } \
{sim:/main/wr_full } \
{sim:/main/wr_flush } \
{sim:/main/rd_dreq } \
{sim:/main/rd_drdy } \
{sim:/main/rd_ctrl } \
{sim:/main/rd_data } 


add wave \
{sim:/main/DUT/wr_pagereq_i } \
{sim:/main/DUT/wr_pageaddr_i } \
{sim:/main/DUT/wr_pageend_o } \
{sim:/main/DUT/wr_ctrl_i } \
{sim:/main/DUT/wr_data_i } \
{sim:/main/DUT/wr_drdy_i } \
{sim:/main/DUT/wr_full_o } \
{sim:/main/DUT/wr_flush_i } \
{sim:/main/DUT/rd_pagereq_i } \
{sim:/main/DUT/rd_pageaddr_i } \
{sim:/main/DUT/rd_pageend_o } \
{sim:/main/DUT/rd_drdy_o } \
{sim:/main/DUT/rd_dreq_i } \
{sim:/main/DUT/rd_data_o } \
{sim:/main/DUT/rd_ctrl_o } \
{sim:/main/DUT/wr_pump_addr_out } \
{sim:/main/DUT/wr_pump_data_in } \
{sim:/main/DUT/wr_pump_data_out } \
{sim:/main/DUT/wr_pump_we } \
{sim:/main/DUT/ram_wr_data_muxed } \
{sim:/main/DUT/ram_wr_addr_muxed } \
{sim:/main/DUT/ram_we_muxed } \
{sim:/main/DUT/rd_pump_addr_out } \
{sim:/main/DUT/rd_pump_data_out } \
{sim:/main/DUT/ram_rd_data } \
{sim:/main/DUT/ram_rd_addr_muxed } \
{sim:/main/DUT/sync_sreg } \
{sim:/main/DUT/sync_sreg_rd } \
{sim:/main/DUT/sync_cntr } \
{sim:/main/DUT/sync_cntr_rd } 

add wave \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/clk_i } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/rst_n_i } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/pgreq_i } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/pgaddr_i } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/pgend_o } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/drdy_o } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/dreq_i } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/d_o } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/sync_i } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/addr_o } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/q_i } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/out_reg } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/cntr } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/sync_d0 } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/sync_d1 } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/reg_not_empty } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/cntr_full } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/mem_addr } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/allones } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/advance_addr } \
{sim:/main/DUT/gen_read_pumps(0)/rdpump/load_out_reg } 
add wave \
{sim:/main/DUT/gen_read_pumps(1)/rdpump/addr_o } 
add wave \
{sim:/main/DUT/gen_read_pumps(2)/rdpump/addr_o } 
add wave \
{sim:/main/DUT/gen_read_pumps(3)/rdpump/addr_o } 
add wave \
{sim:/main/DUT/gen_read_pumps(4)/rdpump/addr_o } 
add wave \
{sim:/main/DUT/gen_read_pumps(5)/rdpump/addr_o } 
add wave \
{sim:/main/DUT/gen_read_pumps(6)/rdpump/addr_o } 
add wave \
{sim:/main/DUT/gen_read_pumps(7)/rdpump/addr_o } 
add wave \
{sim:/main/DUT/gen_read_pumps(8)/rdpump/addr_o } 
add wave \
{sim:/main/DUT/gen_read_pumps(9)/rdpump/addr_o } 
add wave \
{sim:/main/DUT/gen_read_pumps(10)/rdpump/addr_o } 


do wave.do

run 5us
wave zoomfull

