vlib work
vcom ../../../modules/wrsw_swcore/swc_swcore_pkg.vhd
vcom ../../../modules/wrsw_swcore/swc_ob_prio_queue.vhd

vlog -sv swc_ob_prio_quque_tb.v

#vsim work.main
#radix -hexadecimal

#do wave.do

#add wave \
#{sim:/main/DUT/clk_i } \
#{sim:/main/DUT/rst_n_i } \
#{sim:/main/DUT/write_i } \
#{sim:/main/DUT/read_i } \
#{sim:/main/DUT/wr_en_o } \
#{sim:/main/DUT/wr_addr_o } \
#{sim:/main/DUT/rd_addr_o } \
#{sim:/main/DUT/head } \
#{sim:/main/DUT/tail } \
#{sim:/main/DUT/not_full } \
#{sim:/main/DUT/not_empty } 

restart
run 15us
wave zoomfull

