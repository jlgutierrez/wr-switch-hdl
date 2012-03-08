vlib work
vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/generic_ssram_dualport_singleclock.vhd
vcom ../../../modules/wrsw_swcore/swc_prio_encoder.vhd
vcom ../../../modules/wrsw_swcore/swc_ob_prio_queue.vhd
vcom ../../../modules/wrsw_swcore/swc_swcore_pkg.vhd
vcom ../../../modules/wrsw_swcore/swc_output_block.vhd

vlog -sv swc_output_block_tb.v

vsim work.main
radix -hexadecimal

do wave.do

add wave \
{sim:/main/DUT/clk_i } \
{sim:/main/DUT/rst_n_i } \
{sim:/main/DUT/pta_transfer_data_valid_i } \
{sim:/main/DUT/pta_pageaddr_i } \
{sim:/main/DUT/pta_prio_i } \
{sim:/main/DUT/pta_pck_size_i } \
{sim:/main/DUT/pta_transfer_data_ack_o } \
{sim:/main/DUT/mpm_pgreq_o } \
{sim:/main/DUT/mpm_pgaddr_o } \
{sim:/main/DUT/mpm_pckend_i } \
{sim:/main/DUT/mpm_pgend_i } \
{sim:/main/DUT/mpm_drdy_i } \
{sim:/main/DUT/mpm_dreq_o } \
{sim:/main/DUT/mpm_data_i } \
{sim:/main/DUT/mpm_ctrl_i } \
{sim:/main/DUT/rx_sof_p1_o } \
{sim:/main/DUT/rx_eof_p1_o } \
{sim:/main/DUT/rx_dreq_i } \
{sim:/main/DUT/rx_ctrl_o } \
{sim:/main/DUT/rx_data_o } \
{sim:/main/DUT/rx_valid_o } \
{sim:/main/DUT/rx_bytesel_o } \
{sim:/main/DUT/rx_idle_o } \
{sim:/main/DUT/rx_rerror_p1_o } \
{sim:/main/DUT/wr_addr } \
{sim:/main/DUT/rd_addr } \
{sim:/main/DUT/wr_prio } \
{sim:/main/DUT/rd_prio } \
{sim:/main/DUT/not_full_array } \
{sim:/main/DUT/not_empty_array } \
{sim:/main/DUT/read_array } \
{sim:/main/DUT/read } \
{sim:/main/DUT/write_array } \
{sim:/main/DUT/write } \
{sim:/main/DUT/wr_en } \
{sim:/main/DUT/rd_data_valid } \
{sim:/main/DUT/zeros } \
{sim:/main/DUT/wr_array } \
{sim:/main/DUT/rd_array } \
{sim:/main/DUT/state } \
{sim:/main/DUT/pgreq } \
{sim:/main/DUT/wr_data } \
{sim:/main/DUT/rd_data } \
{sim:/main/DUT/rd_pck_size } \
{sim:/main/DUT/current_pck_size } \
{sim:/main/DUT/cnt_pck_size } \
{sim:/main/DUT/rx_sof_p1 } \
{sim:/main/DUT/rx_eof_p1 } \
{sim:/main/DUT/rx_valid } 
run 1us
wave zoomfull

