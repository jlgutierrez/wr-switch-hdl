vlib work
vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/generic_ssram_dualport_singleclock.vhd
vcom ../../../modules/wrsw_swcore/swc_multiport_linked_list.vhd
vcom ../../../modules/wrsw_swcore/swc_packet_mem_read_pump.vhd
vcom ../../../modules/wrsw_swcore/swc_packet_mem_write_pump.vhd
vcom ../../../modules/wrsw_swcore/swc_swcore_pkg.vhd
vcom ../../../modules/wrsw_swcore/swc_packet_mem.vhd

vlog -sv swc_packet_mem_tb.v

vsim work.main
radix -hexadecimal

do wave.do

run 15us
wave zoomfull

