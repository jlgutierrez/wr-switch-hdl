#include "defs.h"
#include "uart.h"
#include "timer.h"


#include "minipc.h"

//void _irq_entry() {};

main()
{
	uart_init();
	ad9516_init();
	char tmp[100];
	
//	spll_test();
	ipc_test();	
}