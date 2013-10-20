make -f Makefile
vlog +incdir+../../sim +incdir+../../ip_cores/wr-cores/sim main.sv

vsim -L secureip -L unisim -t 10fs work.main -voptargs="+acc" +nowarn8684 +nowarn8683

set StdArithNoWarnings 1
set NumericStdNoWarnings 1
do wave.do
radix -hexadecimal
run 1000us
wave zoomfull
radix -hexadecimal