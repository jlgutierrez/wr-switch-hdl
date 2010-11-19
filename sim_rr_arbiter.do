vlib work
vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/generic_ssram_dualport_singleclock.vhd
vcom ../../../modules/wrsw_swcore/swc_prio_encoder.vhd
vcom ../../../modules/wrsw_swcore/swc_rr_arbiter.vhd

vlog swc_rr_arbiter_tb.v

vsim work.main
radix -hexadecimal

add wave \
{sim:/main/next } \
{sim:/main/grant } \
{sim:/main/grant_valid } 
add wave \
{sim:/main/dut/g_num_ports } \
{sim:/main/dut/g_num_ports_log2 } \
{sim:/main/dut/rst_n_i } \
{sim:/main/dut/clk_i } \
{sim:/main/dut/next_i } \
{sim:/main/dut/request_i } \
{sim:/main/dut/grant_o } \
{sim:/main/dut/grant_valid_o } \
{sim:/main/dut/request_mask } \
{sim:/main/dut/request_vec_masked } \
{sim:/main/dut/rq_decoded } \
{sim:/main/dut/rq_decoded_mask } \
{sim:/main/dut/rq_zero } \
{sim:/main/dut/rq_wait_next } 

do wave.do

run 1us
wave zoomfull

