target = "altera" # "xilinx" # 
action = "simulation"

#fetchto = "../../ip_cores"

files = "swc_core.v4.sv" 

vlog_opt="+incdir+../../../sim "

modules = {"local":
		[ 
		  "../../ip_cores/wr-cores",
		  "../../ip_cores/general-cores/modules/genrams/",
		  "../../modules/wrsw_swcore",
		],
	    #"git" :
		#[
		  #"git://ohwr.org/hdl-core-lib/general-cores.git",
		#],
	  }
