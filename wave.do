onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -format Logic /main/clk
add wave -noupdate -format Logic /main/rst
add wave -noupdate -format Logic /main/stb
add wave -noupdate -format Logic /main/cyc
add wave -noupdate -format Logic /main/we
add wave -noupdate -format Literal /main/addr
add wave -noupdate -format Literal /main/data_o
add wave -noupdate -format Literal /main/data_i
add wave -noupdate -format Logic /main/stall
add wave -noupdate -format Logic /main/ack
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {505000 ps} 0}
configure wave -namecolwidth 362
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
update
WaveRestoreZoom {0 ps} {3681818 ps}
