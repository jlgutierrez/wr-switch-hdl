target = "xilinx"
action = "simulation"
syn_device = "XC6VLX130T"
fetchto = "../../ip_cores"
vlog_opt = "+incdir+../../sim +incdir+../../sim/wr-hdl"

files = [ "main.sv" ]

modules ={"local" : ["../../ip_cores/general-cores",
                     "../../modules/wrsw_pstats",
                     "../../modules/wrsw_pstats/wrsw_dummy"] };
