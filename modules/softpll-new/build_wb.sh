#!/bin/bash

wbgen2 -C softpll_regs.h -V spll_wb_slave.vhd -K ../../sim/softpll_regs_ng.vh -C softpll_regs.h --hstyle record -p spll_wbgen2_pkg.vhd  spll_wb_slave.wb 