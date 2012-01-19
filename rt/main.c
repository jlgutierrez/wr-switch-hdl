#include "defs.h"
#include "uart.h"
#include "timer.h"

void _irq_entry() {};

main()
{
	uart_init();
	ad9516_init();
	
	for(;;)
	{
		mprintf("Ping!\n");
		timer_delay(TICS_PER_SECOND);
	}
}