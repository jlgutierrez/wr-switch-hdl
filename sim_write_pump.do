vlib work
vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/generic_ssram_dualport_singleclock.vhd
vcom ../../../modules/wrsw_swcore/swc_swcore_pkg.vhd
vcom ../../../modules/wrsw_swcore/swc_packet_mem_write_pump.vhd

vlog swc_write_pump_tb.v

vsim work.main
radix -hexadecimal

do wave.do

run 30us
wave zoomfull

