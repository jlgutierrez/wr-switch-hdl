vlib work
vcom ../../../modules/wrsw_swcore/swc_swcore_pkg.vhd
vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/generic_ssram_dualport_singleclock.vhd
vcom ../../../platform/altera/generic_async_fifo_2stage.vhd
vcom ../../../modules/wrsw_swcore/swc_prio_encoder.vhd
vcom ../../../modules/wrsw_swcore/swc_rr_arbiter.vhd
vcom ../../../modules/wrsw_swcore/swc_multiport_lost_pck_dealloc.vhd

vlog swc_multiport_lost_pck_dealloc_tb.v

vsim work.main
radix -hexadecimal


do wave.do

add wave \
{sim:/main/DUT/rst_n_i } \
{sim:/main/DUT/clk_i } \
{sim:/main/DUT/ib_force_free_i } \
{sim:/main/DUT/ib_force_free_done_o } \
{sim:/main/DUT/ib_pgaddr_free_i } \
{sim:/main/DUT/ob_force_free_i } \
{sim:/main/DUT/ob_force_free_done_o } \
{sim:/main/DUT/ob_pgaddr_free_i } \
{sim:/main/DUT/request_grant } \
{sim:/main/DUT/request_grant_valid } \
{sim:/main/DUT/in_sel } \
{sim:/main/DUT/force_free_done_feedback } \
{sim:/main/DUT/force_free_done } \
{sim:/main/DUT/ib_force_free_done } \
{sim:/main/DUT/fifo_full } \
{sim:/main/DUT/pgaddr } \
{sim:/main/DUT/request } \
{sim:/main/DUT/pg_addr_free } 

run 500us
wave zoomfull

