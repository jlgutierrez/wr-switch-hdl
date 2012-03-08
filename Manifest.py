modules = { 
    "local" : [
        "modules/wrsw_nic",
        "modules/wrsw_rt_subsystem",
        "modules/wrsw_txtsu",
        "modules/wrsw_rtu",
        "platform/virtex6/chipscope",
        "modules/softpll-new",
        "modules/wrsw_swcore/maciek-native" 
        ],
    
    "git" : [ "git://ohwr.org/hdl-core-lib/wr-cores.git::wishbonized" ]
    };


files = ["modules/wrsw_shared_types_pkg.vhd"];
