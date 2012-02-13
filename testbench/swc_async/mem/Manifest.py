action = "simulation"
target = "xilinx"
fetchto = "../../../ip_cores"
vlog_opt = "+incdir+../../../sim +incdir+../../../ip_cores/general-cores/sim +incdir+../../../ip_cores/wr-cores/sim"

files = [ "main.sv" ]

modules = { "local" : [ "../../../modules/wrsw_swcore/mpm" ],
   					"git" : "git://ohwr.org/hdl-core-lib/general-cores.git::proposed_master"
}
					

					
