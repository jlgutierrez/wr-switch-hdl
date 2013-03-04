onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /main/rst_n
add wave -noupdate /main/DUT/nrst_cntrs
add wave -noupdate /main/clk_sys
add wave -noupdate /main/DUT/g_keep_ov
add wave -noupdate /main/TRIG_GEN/trig_o
add wave -noupdate -divider
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/mem_adr_d1
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/ov_cnt_o

add wave -noupdate -divider <NULL>
add wave -noupdate -divider <NULL>
add wave -noupdate /main/DUT/L2_events
add wave -noupdate /main/DUT/L3_events

add wave -noupdate -divider <NULL>
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/dbg_evt_ov_o
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/dbg_cnt_ov_o
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/cnt_ov
add wave  -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/ov_cnt_o
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/events_i
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/events_reg
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/events_clr
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/events_sub
add wave -noupdate -height 16 /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/cnt_state
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/mem_adr
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/mem_wr
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/mem_dat_in
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/mem_dat_out
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/events_grant
add wave -noupdate -expand /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/RAM_A1/gen_single_clk/U_RAM_SC/ram
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/ext_adr_i
add wave -noupdate /main/DUT/GEN_PCNT(0)/PER_PORT_CNT/ext_dat_o

add wave -noupdate -divider <NULL>
add wave -noupdate /main/DUT/L2_CNT/dbg_evt_ov_o
add wave -noupdate /main/DUT/L2_CNT/dbg_cnt_ov_o
add wave -noupdate /main/DUT/L2_CNT/events_reg
add wave -noupdate /main/DUT/L2_CNT/events_clr
add wave -noupdate /main/DUT/L2_CNT/events_sub
add wave -noupdate /main/DUT/L2_CNT/cnt_state
add wave -noupdate /main/DUT/L2_CNT/mem_adr
add wave -noupdate /main/DUT/L2_CNT/mem_wr
add wave -noupdate /main/DUT/L2_CNT/mem_dat_in
add wave -noupdate /main/DUT/L2_CNT/mem_dat_out
add wave -noupdate -expand /main/DUT/L2_CNT/RAM_A1/gen_single_clk/U_RAM_SC/ram
add wave -noupdate /main/DUT/L2_CNT/ext_adr_i
add wave -noupdate /main/DUT/L2_CNT/ext_dat_o

add wave -noupdate -divider
add wave -noupdate /main/DUT/irq
add wave -noupdate /main/DUT/CNTRS_IRQ/cnt_state

add wave -noupdate /main/DUT/CNTRS_IRQ/irq_i
add wave -noupdate /main/DUT/CNTRS_IRQ/events_reg
add wave -noupdate /main/DUT/CNTRS_IRQ/events_clr
add wave -noupdate /main/DUT/CNTRS_IRQ/events_sub
add wave -noupdate /main/DUT/CNTRS_IRQ/events_grant
add wave -noupdate -expand /main/DUT/CNTRS_IRQ/RAM_A1/gen_single_clk/U_RAM_SC/ram
add wave -noupdate /main/DUT/port_irq
add wave -noupdate /main/DUT/port_irq_reg
add wave -noupdate /main/DUT/port_irq_ack
add wave -noupdate /main/DUT/IRQ_cyc
add wave -noupdate /main/DUT/IRQ_adr
add wave -noupdate /main/DUT/IRQ_we
add wave -noupdate /main/DUT/IRQ_dat_out
add wave -noupdate /main/DUT/wb_int_o

add wave -noupdate -divider <NULL>
add wave -noupdate -divider <NULL>
add wave -noupdate /main/DUT/wb_adr_i
add wave -noupdate /main/DUT/wb_dat_i
add wave -noupdate /main/DUT/wb_dat_o
add wave -noupdate /main/DUT/wb_cyc_i
add wave -noupdate /main/DUT/wb_ack_o
add wave -noupdate /main/DUT/wb_stall_o
add wave -noupdate -height 16 /main/DUT/rd_state
add wave -noupdate /main/DUT/wb_regs_out.cr_rd_en_o
add wave -noupdate /main/DUT/wb_regs_out.cr_rd_en_load_o
add wave -noupdate /main/DUT/wb_regs_out.cr_port_o
add wave -noupdate /main/DUT/wb_regs_out.cr_addr_o
add wave -noupdate /main/DUT/wb_regs_in.cr_rd_en_i
add wave -noupdate /main/DUT/wb_regs_in.L1_cnt_val_i
add wave -noupdate -divider <NULL>
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
WaveRestoreZoom {0 fs} {111300 ns}
