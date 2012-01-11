vlib work
vcom ../../../modules/wrsw_swcore/swc_prio_encoder.vhd
vlog swc_prio_encoder_tb.v

vsim work.main
radix -hexadecimal

do wave.do

run 100us
wave zoomfull

