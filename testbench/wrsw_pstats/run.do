vlog -sv main.sv +incdir+"." +incdir+../../sim +incdir+../../ip_cores/wr-cores/sim
make -f Makefile
vsim -t 10fs work.main -voptargs="+acc"
set StdArithNoWarnings 1
set NumericStdNoWarnings 1
do wave.do
radix -hexadecimal
run 106us
wave zoomfull
radix -hexadecimal
