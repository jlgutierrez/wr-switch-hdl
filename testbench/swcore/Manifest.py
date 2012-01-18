target = "altera" # "xilinx" # 
action = "simulation"

#fetchto = "../../ip_cores"

#files = "swc_core.v4.sv"

files = [
  "xswc_core_7_ports_wrapper.vhd",
  "xswcore_wrapper.svh",
  "xswc_core.sv"
  ]

#vlog_opt="+incdir+../../../sim "
vlog_opt="+incdir+../../ip_cores/wr-cores/sim +incdir+../../ip_cores/wr-cores/sim/fabric_emu"

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
