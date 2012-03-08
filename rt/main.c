#include "defs.h"
#include "uart.h"
#include "timer.h"

//void _irq_entry() {};

main()
{
	uart_init();
	ad9516_init();

	spll_test();
	
	for(;;)
	{
		mprintf("Ping [lock %d]!\n", spll_check_lock());
		timer_delay(TICS_PER_SECOND);
	}
}