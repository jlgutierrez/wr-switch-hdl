vlib work
#vcom ../../../platform/altera/generic_sync_fifo.vhd
#vcom ../../../platform/altera/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/platform_specific.vhd
vcom ../../../modules/wrsw_swcore/swc_swcore_pkg.vhd
vcom ../../../modules/wrsw_swcore/swc_packet_mem.vhd
vcom ../../../modules/wrsw_swcore/swc_page_alloc.vhd
vcom ../../../modules/wrsw_swcore/swc_multiport_page_allocator.vhd
vcom ../../../modules/wrsw_swcore/swc_multiport_linked_list.vhd
vcom ../../../modules/wrsw_swcore/swc_input_block.vhd
vcom ../../../modules/wrsw_swcore/swc_packet_mem_read_pump.vhd
vcom ../../../modules/wrsw_swcore/swc_packet_mem_write_pump.vhd
vcom ../../../modules/wrsw_swcore/swc_pck_transfer_input.vhd
vcom ../../../modules/wrsw_swcore/swc_pck_transfer_output.vhd
vcom ../../../modules/wrsw_swcore/swc_pck_transfer_arbiter.vhd
vcom ../../../modules/wrsw_swcore/swc_pck_pg_free_module.vhd
vcom ../../../modules/wrsw_swcore/swc_multiport_pck_pg_free_module.vhd
vcom ../../../modules/wrsw_swcore/swc_ob_prio_queue.vhd
vcom ../../../modules/wrsw_swcore/swc_output_block.vhd

vcom ../../../sim/vhdl_stdio/PCK_FIO_1993.vhd
vcom ../../../sim/vhdl_stdio/PCK_FIO_1993_BODY.vhd

vcom ../../../modules/wrsw_swcore/swc_core.vhd

#vlog -sv swc_core.v4.sv
#vlog -sv swc_core.sv

vsim work.main -voptargs="+acc"
radix -hexadecimal


do wave.do

run 300us
wave zoomfull

