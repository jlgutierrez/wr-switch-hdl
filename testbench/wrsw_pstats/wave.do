onerror {resume}
quietly WaveActivateNextPane {} 0


add wave -noupdate /main/rst_n
add wave -noupdate /main/clk_sys
add wave -noupdate /main/TRIG_GEN/trig_o

add wave -divider 
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/evt_overflow
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/events_i
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/events_reg
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/events_clr
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/events_sub
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/cnt_state
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/mem_adr
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/mem_wr
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/mem_dat_in
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/mem_dat_out
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/rr_select
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/RAM_A1/gen_single_clk/U_RAM_SC/ram
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/ext_cyc_i
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/ext_adr_i
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/ext_we_i
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/ext_dat_o

add wave -divider
add wave -noupdate /main/DUT/GEN_PCNT(1)/PER_PORT_CNT/evt_overflow
add wave -noupdate /main/DUT/GEN_PCNT(1)/PER_PORT_CNT/events_i
add wave -noupdate /main/DUT/GEN_PCNT(1)/PER_PORT_CNT/events_reg
add wave -noupdate /main/DUT/GEN_PCNT(1)/PER_PORT_CNT/events_clr
add wave -noupdate /main/DUT/GEN_PCNT(1)/PER_PORT_CNT/events_sub
add wave -noupdate /main/DUT/GEN_PCNT(1)/PER_PORT_CNT/cnt_state
add wave -noupdate /main/DUT/GEN_PCNT(1)/PER_PORT_CNT/mem_adr
add wave -noupdate /main/DUT/GEN_PCNT(1)/PER_PORT_CNT/mem_wr
add wave -noupdate /main/DUT/GEN_PCNT(1)/PER_PORT_CNT/mem_dat_in
add wave -noupdate /main/DUT/GEN_PCNT(1)/PER_PORT_CNT/mem_dat_out
add wave -noupdate /main/DUT/GEN_PCNT(1)/PER_PORT_CNT/rr_select
add wave -noupdate /main/DUT/GEN_PCNT(1)/PER_PORT_CNT/RAM_A1/gen_single_clk/U_RAM_SC/ram
add wave -noupdate /main/DUT/GEN_PCNT(1)/PER_PORT_CNT/ext_cyc_i
add wave -noupdate /main/DUT/GEN_PCNT(1)/PER_PORT_CNT/ext_adr_i
add wave -noupdate /main/DUT/GEN_PCNT(1)/PER_PORT_CNT/ext_we_i
add wave -noupdate /main/DUT/GEN_PCNT(1)/PER_PORT_CNT/ext_dat_o

add wave -divider
add wave -noupdate /main/DUT/wb_adr_i
add wave -noupdate /main/DUT/wb_dat_i
add wave -noupdate /main/DUT/wb_dat_o
add wave -noupdate /main/DUT/wb_cyc_i
add wave -noupdate /main/DUT/wb_ack_o
add wave -noupdate /main/DUT/wb_stall_o
add wave -noupdate /main/DUT/rd_state
add wave -noupdate /main/DUT/wb_regs_out.cr_rd_en_o
add wave -noupdate /main/DUT/wb_regs_out.cr_rd_en_load_o
add wave -noupdate /main/DUT/wb_regs_out.cr_port_o
add wave -noupdate /main/DUT/wb_regs_out.cr_addr_o
add wave -noupdate /main/DUT/wb_regs_in.cr_rd_en_i
add wave -noupdate /main/DUT/wb_regs_in.cnt_val_i


add wave -divider
add wave -noupdate /main/DUMMY/regs

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {90685000000 fs} 0}
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {90556826170 fs} {90813173830 fs}
