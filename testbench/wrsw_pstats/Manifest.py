action = "simulation"
files = "main.sv"
#fetchto = "../../ip_cores"

target = "xilinx"

vlog_opt="+incdir+../../sim"

modules ={"local" : ["../../ip_cores/general-cores",
                     "../../modules/wrsw_pstats" ] };
