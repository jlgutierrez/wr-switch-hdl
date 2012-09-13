target = "xilinx" #  "altera" # 
action = "simulation"
  
vlog_opt = "+incdir+../../sim +incdir+../../sim/wr-hdl"

files = [ 
         "tru.sv"                
        ]
modules = {"local": 
                [
                 "../../modules/wrsw_tru",
                 "../../ip_cores/wr-cores/ip_cores/general-cores/modules/genrams/"
                ],
             }