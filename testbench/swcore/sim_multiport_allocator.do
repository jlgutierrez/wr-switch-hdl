vlib work
vcom ../../../modules/wrsw_swcore/swc_swcore_pkg.vhd
vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/generic_ssram_dualport_singleclock.vhd
vcom ../../../modules/wrsw_swcore/swc_prio_encoder.vhd
vcom ../../../modules/wrsw_swcore/swc_rr_arbiter.vhd
vcom ../../../modules/wrsw_swcore/swc_page_alloc.vhd
vcom ../../../modules/wrsw_swcore/swc_multiport_page_allocator.vhd

vlog swc_multiport_allocator_tb.v

vsim work.main
radix -hexadecimal

add wave \
{sim:/main/pgaddr_alloc } \
{sim:/main/done_alloc } \
{sim:/main/done_free } \
{sim:/main/done_force_free } \
{sim:/main/done_set_usecnt } 
add wave \
{sim:/main/DUT/rst_n_i } \
{sim:/main/DUT/clk_i } \
{sim:/main/DUT/alloc_i } \
{sim:/main/DUT/free_i } \
{sim:/main/DUT/force_free_i } \
{sim:/main/DUT/set_usecnt_i } \
{sim:/main/DUT/alloc_done_o } \
{sim:/main/DUT/free_done_o } \
{sim:/main/DUT/force_free_done_o } \
{sim:/main/DUT/set_usecnt_done_o } \
{sim:/main/DUT/pgaddr_free_i } \
{sim:/main/DUT/usecnt_i } \
{sim:/main/DUT/pgaddr_alloc_o } \
{sim:/main/DUT/nomem_o } \
{sim:/main/DUT/pg_alloc } \
{sim:/main/DUT/pg_free } \
{sim:/main/DUT/pg_force_free } \
{sim:/main/DUT/pg_set_usecnt } \
{sim:/main/DUT/pg_usecnt } \
{sim:/main/DUT/pg_addr_alloc } \
{sim:/main/DUT/pg_addr_free } \
{sim:/main/DUT/pg_addr_valid } \
{sim:/main/DUT/pg_idle } \
{sim:/main/DUT/pg_done } \
{sim:/main/DUT/pg_nomem } \
{sim:/main/DUT/request_vec } \
{sim:/main/DUT/request_grant } \
{sim:/main/DUT/request_next } \
{sim:/main/DUT/request_grant_valid } \
{sim:/main/DUT/in_sel } \
{sim:/main/DUT/alloc_done_feedback } \
{sim:/main/DUT/alloc_done } \
{sim:/main/DUT/free_done_feedback } \
{sim:/main/DUT/free_done } \
{sim:/main/DUT/force_free_done_feedback } \
{sim:/main/DUT/force_free_done } \
{sim:/main/DUT/set_usecnt_done_feedback } \
{sim:/main/DUT/set_usecnt_done } 

do wave.do

run 500us
wave zoomfull

