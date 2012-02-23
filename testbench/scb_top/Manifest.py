target = "xilinx"
action = "simulation"
syn_device = "XC6VLX130T"
fetchto = "../../ip_cores"
vlog_opt = "+incdir+../../sim +incdir+../../sim/wr-hdl"

files = [ "main.sv" ]

#modules = { "local" : ["../../", "../../top/scb_test"] }
modules = { "local" : ["../../", "../../top/bare_top"] }
					

					
