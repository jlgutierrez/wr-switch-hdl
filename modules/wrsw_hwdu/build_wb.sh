#!/bin/bash

mkdir -p doc
wbgen2 -D ./doc/wrsw_hwdu.html -C hwdu_regs.h -V hwdu_wishbone_slave.vhd --cstyle struct --lang vhdl -K ../../sim/regs/hwdu_regs.vh -p hwdu_wbgen2_pkg.vhd --hstyle record wrsw_hwdu.wb 
