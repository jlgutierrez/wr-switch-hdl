vlib work
vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/generic_ssram_dualport_singleclock.vhd
vcom ../../../modules/wrsw_swcore/swc_swcore_pkg.vhd
vcom ../../../modules/wrsw_swcore/swc_pck_transfer_input.vhd

vlog -sv swc_pck_transfer_input_tb.v

vsim work.main
radix -hexadecimal


do wave.do

add wave \
{sim:/main/DUT/clk_i } \
{sim:/main/DUT/rst_n_i } \
{sim:/main/DUT/pto_transfer_pck_o } \
{sim:/main/DUT/pto_pageaddr_o } \
{sim:/main/DUT/pto_output_mask_o } \
{sim:/main/DUT/pto_read_mask_i } \
{sim:/main/DUT/pto_prio_o } \
{sim:/main/DUT/ib_transfer_pck_i } \
{sim:/main/DUT/ib_pageaddr_i } \
{sim:/main/DUT/ib_mask_i } \
{sim:/main/DUT/ib_prio_i } \
{sim:/main/DUT/ib_transfer_ack_o } \
{sim:/main/DUT/ib_transfer_ack } \
{sim:/main/DUT/ib_pageaddr } \
{sim:/main/DUT/ib_prio } \
{sim:/main/DUT/ib_mask } \
{sim:/main/DUT/pto_read_mask } \
{sim:/main/DUT/pto_output_mask } \
{sim:/main/DUT/zeros } 
run 15us
wave zoomfull

