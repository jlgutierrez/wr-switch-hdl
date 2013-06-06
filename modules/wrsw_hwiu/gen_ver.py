#!/usr/bin/python

import sys
import subprocess
import datetime

c_PKG_FILE    = "/modules/wrsw_hwiu/gw_ver_pkg.vhd"
c_PKG_LIB     = "library ieee;\nuse ieee.std_logic_1164.all;\n"
c_PKG_HEAD    = "--generated automatically by gen_ver.py script--\npackage hwver_pkg is\n"
c_BUILD_DAT   = "constant c_build_date : std_logic_vector(31 downto 0) := x\""
c_SWITCH_HDL  = "constant c_switch_hdl_ver : std_logic_vector(31 downto 0) := x\""
c_GENCORES    = "constant c_gencores_ver : std_logic_vector(31 downto 0) := x\""
c_WRCORES     = "constant c_wrcores_ver : std_logic_vector(31 downto 0) := x\""
c_PKG_TAIL    = "end package;\n";

def main():
  tl = subprocess.Popen("git rev-parse --show-toplevel", stdout=subprocess.PIPE, shell=True)
  toplevel = tl.stdout.read()[0:-1] #remove trailing \n
  f = open(toplevel+c_PKG_FILE, 'w')
  f.write(c_PKG_LIB+c_PKG_HEAD)
  #### DATE
  day = datetime.datetime.today().day
  mon = datetime.datetime.today().month
  year = (datetime.datetime.today().year)%100
  date = day<<24 | mon<<16 | year<<8
  f.write(c_BUILD_DAT+hex(date)[2:].zfill(8)+"\";\n")
  hash = subprocess.Popen("git log --pretty=format:'%h' -n 1", stdout=subprocess.PIPE, shell=True)
  f.write(c_SWITCH_HDL+hash.stdout.read().zfill(8)+"\";\n")
  hash = subprocess.Popen("(cd "+toplevel+"; git submodule status ip_cores/general-cores)", stdout=subprocess.PIPE, shell=True)
  f.write(c_GENCORES+hash.stdout.read()[1:8].zfill(8)+"\";\n")
  hash = subprocess.Popen("(cd "+toplevel+"; git submodule status ip_cores/wr-cores)", stdout=subprocess.PIPE, shell=True)
  f.write(c_WRCORES+hash.stdout.read()[1:8].zfill(8)+"\";\n")
  f.write(c_PKG_TAIL)
  f.close()

if __name__ == '__main__':
    main()
