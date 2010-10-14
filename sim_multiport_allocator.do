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

do wave.do

run 500us
wave zoomfull

