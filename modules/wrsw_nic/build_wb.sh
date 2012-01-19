#!/bin/bash

mkdir -p doc
wbgen2 -D ./doc/wrsw_nic.html -V nic_wishbone_slave.vhd --cstyle defines --lang vhdl -K ../../sim/regs/nic_regs.vh -p nic_wbgen2_pkg.vhd --hstyle record wr_nic.wb 
