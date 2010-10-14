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

run 400us
wave zoomfull

