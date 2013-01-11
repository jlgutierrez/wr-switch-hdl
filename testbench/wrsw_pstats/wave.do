onerror {resume}
quietly WaveActivateNextPane {} 0


add wave -noupdate /main/rst_n
add wave -noupdate /main/clk_sys
add wave -noupdate /main/TRIG_GEN/trig_o

add wave -noupdate /main/DUT/evt_overflow
add wave -noupdate /main/DUT/events_i
add wave -noupdate /main/DUT/events_reg
add wave -noupdate /main/DUT/events_clr
add wave -noupdate /main/DUT/events_sub
add wave -noupdate /main/DUT/real_state
add wave -noupdate /main/DUT/cnt_state
add wave -noupdate /main/DUT/mem_adr
add wave -noupdate /main/DUT/mem_wb_in.we
add wave -noupdate /main/DUT/mem_dat_in
add wave -noupdate /main/DUT/mem_dat_out
add wave -noupdate /main/DUT/rr_select
add wave -noupdate /main/DUT/RAM_A1/U_DPRAM/gen_single_clk/U_RAM_SC/ram

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
