#!/bin/bash

mkdir -p doc
wbgen2 -D ./doc/wrsw_watchdog.html -V wdog_wishbone_slave.vhd --cstyle defines --lang vhdl -K ../../sim/regs/wdog_regs.vh -p wdog_wbgen2_pkg.vhd --hstyle record wrsw_watchdog.wb 
