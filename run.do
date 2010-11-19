vlib work

vlog -sv fabric_emu_demo.sv

vsim work.main -voptargs="+acc"
radix -hexadecimal
do wave.do

run 300us
wave zoomfull