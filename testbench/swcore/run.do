make -f Makefile
#vlog +incdir+../../sim +incdir+../../ip_cores/wr-cores/sim main.sv

vsim -L secureip -L unisim -t 10fs work.main_generic -voptargs="+acc" +nowarn8684 +nowarn8683

set StdArithNoWarnings 1
set NumericStdNoWarnings 1
do wave.do
#do wave_allports.do
radix -hexadecimal
run 4000us
wave zoomfull
radix -hexadecimal