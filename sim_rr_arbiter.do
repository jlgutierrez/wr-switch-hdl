vlib work
vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/generic_ssram_dualport_singleclock.vhd
vcom ../../../modules/wrsw_swcore/swc_prio_encoder.vhd
vcom ../../../modules/wrsw_swcore/swc_rr_arbiter.vhd

vlog swc_rr_arbiter_tb.v

vsim work.main
radix -hexadecimal

do wave.do

run 1us
wave zoomfull

