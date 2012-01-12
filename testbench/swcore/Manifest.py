target = "altera"
action = "simulation"

fetchto = "../../ip_cores"

files = "swc_core.v4.sv" 

vlog_opt="+incdir+../../../sim "

modules = {"local":
		[ 
		  "../../platform/altera",
		  "../../modules/wrsw_swcore",
		],
	    "git" :
		[
		  "git://ohwr.org/hdl-core-lib/general-cores.git",
		],
	  }
