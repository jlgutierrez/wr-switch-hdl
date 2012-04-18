#include "defs.h"
#include "uart.h"
#include "timer.h"

#include "dev/softpll_ng.h"

#include "minipc.h"

//void _irq_entry() {};

main()
{
	uint32_t start_tics = 0;

	uart_init();
	ad9516_init();

	rts_init();
	rtipc_init();

	for(;;)
	{
			uint32_t tics = timer_get_tics();
			
			if(tics - start_tics > TICS_PER_SECOND)
			{
				spll_show_stats();
				start_tics = tics;
			}
	    rts_update();
	    rtipc_action();
	}

	return 0;
}
