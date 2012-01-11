vlib work
vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/generic_ssram_dualport_singleclock.vhd
vcom ../../../modules/wrsw_swcore/swc_swcore_pkg.vhd
vcom ../../../modules/wrsw_swcore/swc_prio_encoder.vhd
vcom ../../../modules/wrsw_swcore/swc_page_alloc.vhd


vlog swc_page_alloc_tb.v

vsim work.main
radix -hexadecimal

do wave.do

add wave \
{sim:/main/idle } \
{sim:/main/nomem } \
{sim:/main/pgaddr_o } \
{sim:/main/pgaddr_valid } 
add wave \
{sim:/main/dut/g_num_pages } \
{sim:/main/dut/g_page_addr_bits } \
{sim:/main/dut/g_use_count_bits } \
{sim:/main/dut/clk_i } \
{sim:/main/dut/rst_n_i } \
{sim:/main/dut/alloc_i } \
{sim:/main/dut/free_i } \
{sim:/main/dut/force_free_i } \
{sim:/main/dut/set_usecnt_i } \
{sim:/main/dut/usecnt_i } \
{sim:/main/dut/pgaddr_i } \
{sim:/main/dut/pgaddr_o } \
{sim:/main/dut/pgaddr_valid_o } \
{sim:/main/dut/idle_o } \
{sim:/main/dut/done_o } \
{sim:/main/dut/nomem_o } \
{sim:/main/dut/l1_bitmap } \
{sim:/main/dut/l1_first_free } \
{sim:/main/dut/l1_mask } \
{sim:/main/dut/l0_mask } \
{sim:/main/dut/l0_first_free } \
{sim:/main/dut/state } \
{sim:/main/dut/free_blocks } \
{sim:/main/dut/l0_wr_data } \
{sim:/main/dut/l0_rd_data } \
{sim:/main/dut/l0_wr_addr } \
{sim:/main/dut/l0_rd_addr } \
{sim:/main/dut/l0_wr } \
{sim:/main/dut/usecnt_mem_wraddr } \
{sim:/main/dut/usecnt_mem_rdaddr } \
{sim:/main/dut/usecnt_mem_wr } \
{sim:/main/dut/usecnt_mem_rddata } \
{sim:/main/dut/usecnt_mem_wrdata } 

run 400us
wave zoomfull

