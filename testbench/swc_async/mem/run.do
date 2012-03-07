#make -f Makefile
vsim -L secureip -L unisim -t 10fs work.main -voptargs="+acc"
set StdArithNoWarnings 1
set NumericStdNoWarnings 1
do wave.do
run 80us
radix -hexadecimal
wave zoomfull