vlib work
vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/generic_ssram_dualport_singleclock.vhd
vcom ../../../modules/wrsw_swcore/swc_swcore_pkg.vhd
vcom ../../../modules/wrsw_swcore/swc_pck_transfer_input.vhd
vcom ../../../modules/wrsw_swcore/swc_pck_transfer_output.vhd
vcom ../../../modules/wrsw_swcore/swc_pck_transfer_arbiter.vhd

vlog -sv swc_pck_transfer_arbiter_tb.v

vsim work.main
radix -hexadecimal


do wave.do
add wave \
{sim:/main/DUT/clk_i } \
{sim:/main/DUT/rst_n_i } \
{sim:/main/DUT/ob_data_valid_o } \
{sim:/main/DUT/ob_ack_i } \
{sim:/main/DUT/ob_pageaddr_o } \
{sim:/main/DUT/ob_prio_o } \
{sim:/main/DUT/ib_transfer_pck_i } \
{sim:/main/DUT/ib_transfer_ack_o } \
{sim:/main/ib_busy } \
{sim:/main/DUT/ib_busy_o } \
{sim:/main/DUT/ib_pageaddr_i } \
{sim:/main/DUT/ib_mask_i } \
{sim:/main/DUT/ib_prio_i } \
{sim:/main/DUT/pto_pageaddr } \
{sim:/main/DUT/pto_output_mask } \
{sim:/main/DUT/pto_read_mask } \
{sim:/main/DUT/pto_prio } \
{sim:/main/DUT/pti_transfer_data_ack } \
{sim:/main/DUT/pti_transfer_data_valid } \
{sim:/main/DUT/pti_pageaddr } \
{sim:/main/DUT/pti_prio } \
{sim:/main/DUT/sync_sreg } \
{sim:/main/DUT/sync_cntr } \
{sim:/main/DUT/sync_cntr_ack } 

add wave \
{sim:/main/DUT/gen_output(0)/transfer_output/ob_pageaddr_o } \
{sim:/main/DUT/gen_output(0)/transfer_output/ob_prio_o } \
{sim:/main/DUT/gen_output(0)/transfer_output/pti_pageaddr_i } \
{sim:/main/DUT/gen_output(0)/transfer_output/pti_prio_i } \
{sim:/main/DUT/gen_output(0)/transfer_output/pti_transfer_data_ack } \
{sim:/main/DUT/gen_output(0)/transfer_output/ob_transfer_data_valid } \
{sim:/main/DUT/gen_output(0)/transfer_output/ob_pageaddr } \
{sim:/main/DUT/gen_output(0)/transfer_output/ob_prio } 

add wave \
{sim:/main/DUT/gen_input(0)/transfer_input/pto_pageaddr_o } \
{sim:/main/DUT/gen_input(0)/transfer_input/pto_output_mask_o } \
{sim:/main/DUT/gen_input(0)/transfer_input/pto_prio_o } \
{sim:/main/DUT/gen_input(0)/transfer_input/ib_pageaddr_i } \
{sim:/main/DUT/gen_input(0)/transfer_input/ib_mask_i } \
{sim:/main/DUT/gen_input(0)/transfer_input/ib_prio_i } \
{sim:/main/DUT/gen_input(0)/transfer_input/ib_transfer_ack } \
{sim:/main/DUT/gen_input(0)/transfer_input/ib_pageaddr } \
{sim:/main/DUT/gen_input(0)/transfer_input/ib_prio } \
{sim:/main/DUT/gen_input(0)/transfer_input/ib_mask } \
{sim:/main/DUT/gen_input(0)/transfer_input/pto_output_mask } \
{sim:/main/DUT/gen_input(0)/transfer_input/zeros } 

add wave \
{sim:/main/DUT/gen_input(1)/transfer_input/pto_transfer_pck_o } \
{sim:/main/DUT/gen_input(1)/transfer_input/pto_pageaddr_o } \
{sim:/main/DUT/gen_input(1)/transfer_input/pto_output_mask_o } \
{sim:/main/DUT/gen_input(1)/transfer_input/pto_prio_o } \
{sim:/main/DUT/gen_input(1)/transfer_input/ib_pageaddr_i } \
{sim:/main/DUT/gen_input(1)/transfer_input/ib_mask_i } \
{sim:/main/DUT/gen_input(1)/transfer_input/ib_prio_i } \
{sim:/main/DUT/gen_input(1)/transfer_input/ib_transfer_ack } \
{sim:/main/DUT/gen_input(1)/transfer_input/ib_pageaddr } \
{sim:/main/DUT/gen_input(1)/transfer_input/ib_prio } \
{sim:/main/DUT/gen_input(1)/transfer_input/ib_mask } \
{sim:/main/DUT/gen_input(1)/transfer_input/pto_output_mask } \
{sim:/main/DUT/gen_input(1)/transfer_input/zeros } 
add wave \
{sim:/main/DUT/gen_output(1)/transfer_output/ob_pageaddr_o } \
{sim:/main/DUT/gen_output(1)/transfer_output/ob_prio_o } \
{sim:/main/DUT/gen_output(1)/transfer_output/pti_pageaddr_i } \
{sim:/main/DUT/gen_output(1)/transfer_output/pti_prio_i } \
{sim:/main/DUT/gen_output(1)/transfer_output/pti_transfer_data_ack } \
{sim:/main/DUT/gen_output(1)/transfer_output/ob_transfer_data_valid } \
{sim:/main/DUT/gen_output(1)/transfer_output/ob_pageaddr } \
{sim:/main/DUT/gen_output(1)/transfer_output/ob_prio } 
add wave \
{sim:/main/DUT/gen_output(2)/transfer_output/ob_pageaddr_o } \
{sim:/main/DUT/gen_output(2)/transfer_output/ob_prio_o } \
{sim:/main/DUT/gen_output(2)/transfer_output/pti_pageaddr_i } \
{sim:/main/DUT/gen_output(2)/transfer_output/pti_prio_i } \
{sim:/main/DUT/gen_output(2)/transfer_output/pti_transfer_data_ack } \
{sim:/main/DUT/gen_output(2)/transfer_output/ob_transfer_data_valid } \
{sim:/main/DUT/gen_output(2)/transfer_output/ob_pageaddr } \
{sim:/main/DUT/gen_output(2)/transfer_output/ob_prio } 
add wave \
{sim:/main/DUT/gen_output(3)/transfer_output/ob_pageaddr_o } \
{sim:/main/DUT/gen_output(3)/transfer_output/ob_prio_o } \
{sim:/main/DUT/gen_output(3)/transfer_output/pti_pageaddr_i } \
{sim:/main/DUT/gen_output(3)/transfer_output/pti_prio_i } \
{sim:/main/DUT/gen_output(3)/transfer_output/pti_transfer_data_ack } \
{sim:/main/DUT/gen_output(3)/transfer_output/ob_transfer_data_valid } \
{sim:/main/DUT/gen_output(3)/transfer_output/ob_pageaddr } \
{sim:/main/DUT/gen_output(3)/transfer_output/ob_prio } 

run 1500ns
wave zoomfull

