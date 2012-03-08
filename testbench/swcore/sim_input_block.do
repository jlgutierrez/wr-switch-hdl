vlib work
vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/swc_swcore_pkg.vhd
vcom ../../../modules/wrsw_swcore/swc_input_block.vhd

vlog -sv swc_input_block.sv

vsim work.main -voptargs="+acc"
radix -hexadecimal


do wave.do



run 3us
wave zoomfull

