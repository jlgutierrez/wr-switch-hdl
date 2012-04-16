#include <stdio.h>
#include <stdlib.h>

#include "board.h"
#include "timer.h"
#include "trace.h"
#include "hw/softpll_regs.h"
#include "hw/pps_gen_regs.h"

#include "softpll_ng.h"

#include "irq.h"

volatile int irq_count = 0;

static volatile struct SPLL_WB *SPLL = (volatile struct SPLL_WB *) BASE_SOFTPLL;
static volatile struct PPSG_WB *PPSG = (volatile struct PPSG_WB *) BASE_PPS_GEN;

/* The includes below contain code (not only declarations) to enable the compiler
   to inline functions where necessary and save some CPU cycles */

#include "spll_defs.h"
#include "spll_common.h"
#include "spll_debug.h"
#include "spll_helper.h"
#include "spll_main.h"
#include "spll_ptracker.h"
#include "spll_external.h"

#define SEQ_START_EXT 1
#define SEQ_WAIT_EXT 2
#define SEQ_START_HELPER 3
#define SEQ_WAIT_HELPER 4
#define SEQ_START_MAIN 5
#define SEQ_WAIT_MAIN 6
#define SEQ_DISABLED 7
#define SEQ_READY 8

struct softpll_state {
	int mode;
	int seq_state;
	int helper_locked;
	struct spll_helper_state helper;
	struct spll_external_state ext;
	struct spll_main_state mpll;
	struct spll_ptracker_state ptrackers[MAX_PTRACKERS];
};

static volatile struct softpll_state softpll;


void _irq_entry()
{
	volatile uint32_t trr;
	int src = -1, tag, i;

/* check if there are more tags in the FIFO */
	if(! (SPLL->CSR & SPLL_TRR_CSR_EMPTY))
	{
		trr = SPLL->TRR_R0;
		src = SPLL_TRR_R0_CHAN_ID_R(trr);
		tag = SPLL_TRR_R0_VALUE_R(trr);


		switch(softpll.seq_state)
		{
			case SEQ_DISABLED:
				break;
			
			case SEQ_START_EXT:		
				external_update((struct spll_external_state *) &softpll.ext, tag, src);
				external_start((struct spll_external_state *)&softpll.ext);
				softpll.seq_state = SEQ_WAIT_EXT;
				break;

			case SEQ_WAIT_EXT:
				if(external_locked((struct spll_external_state *)&softpll.ext))
					softpll.seq_state = SEQ_START_HELPER;
				break;
				
			case SEQ_START_HELPER:
				softpll.helper_locked = 0;
				helper_start((struct spll_helper_state *)&softpll.helper);
				softpll.seq_state = SEQ_WAIT_HELPER;
				break;
			
			case SEQ_WAIT_HELPER:
				if(softpll.helper.ld.locked && !softpll.helper_locked)
				{
					softpll.helper_locked = 1;
					
					if(softpll.mode == MODE_SLAVE)
						softpll.seq_state = SEQ_START_MAIN;
					else {
//						for(i=0;i<n_chan_ref; i++)
//							ptracker_start((struct spll_ptracker_state *) &softpll.ptrackers[i]); 
						softpll.seq_state = SEQ_READY;
					}
				}
				break;

			case SEQ_START_MAIN: 
				mpll_start((struct spll_main_state *) &softpll.mpll);
				softpll.seq_state = SEQ_WAIT_MAIN;
				break;

			case SEQ_WAIT_MAIN: 
				if(softpll.mpll.ld.locked)
				{
					softpll.seq_state = SEQ_READY;

//					for(i=0;i<n_chan_ref; i++)
//							ptracker_start((struct spll_ptracker_state *) &softpll.ptrackers[i]); 
				}
				break;

			case SEQ_READY:
				if(!softpll.helper.ld.locked)
				{				
//					SPLL->OCER = 0;
//					SPLL->RCER = 0;
					//softpll.seq_state = SEQ_START_HELPER;
				} else if (softpll.mode == MODE_GRAND_MASTER && !external_locked((struct spll_external_state *) &softpll.ext))
				{
//					SPLL->OCER = 0;
//					SPLL->RCER = 0;
//					SPLL->ECCR = 0;
					softpll.seq_state = SEQ_START_EXT;
				} else if (softpll.mode == MODE_SLAVE && !softpll.mpll.ld.locked)
				{
					softpll.seq_state = SEQ_START_MAIN;
				};
				break;
		};


		switch(softpll.seq_state)
		{
			case SEQ_WAIT_EXT:
				external_update((struct spll_external_state *) &softpll.ext, tag, src);
				break;

			case SEQ_WAIT_HELPER:
				if(softpll.mode == MODE_GRAND_MASTER)
					external_update((struct spll_external_state *) &softpll.ext, tag, src);
				helper_update((struct spll_helper_state *)&softpll.helper, tag, src);
				break;

			case SEQ_WAIT_MAIN:
			case SEQ_READY:
				helper_update((struct spll_helper_state *)&softpll.helper, tag, src);

				if(softpll.mode == MODE_GRAND_MASTER)
					external_update((struct spll_external_state *) &softpll.ext, tag, src);
				if(softpll.mode == MODE_SLAVE)
					mpll_update((struct spll_main_state *) &softpll.mpll, tag, src);

				break;
				
					
							
		}
		

	}

	irq_count++;
	clear_irq();
}

void spll_init(int mode, int slave_ref_channel, int align_pps)
{
	char mode_str[20];
	volatile int dummy;
	
	disable_irq();

	n_chan_ref = SPLL_CSR_N_REF_R(SPLL->CSR);
	n_chan_out = SPLL_CSR_N_OUT_R(SPLL->CSR);
	softpll.helper_locked = 0;
	softpll.mode = mode;
	
	SPLL->DAC_HPLL = 0;
	SPLL->DAC_MAIN = 0;

	timer_delay(100000);	
	SPLL->CSR= 0 ;
	SPLL->OCER = 0;
	SPLL->RCER = 0;
	SPLL->ECCR = 0;
	SPLL->RCGER = 0;
	SPLL->DCCR = 0;
	SPLL->DEGLITCH_THR = 1000;

	PPSG->ESCR = 0;

	switch(mode)
	{
		case MODE_DISABLED:
			strcpy(mode_str, "Disabled");
			softpll.seq_state = SEQ_DISABLED;
			break;

		case MODE_GRAND_MASTER:
			strcpy(mode_str, "Grand Master");

			softpll.seq_state = SEQ_START_EXT;
			external_init(&softpll.ext, n_chan_ref + n_chan_out, align_pps);
			helper_init(&softpll.helper, n_chan_ref); 
			break;

		case MODE_FREE_RUNNING_MASTER:
			strcpy(mode_str, "Free-running Master");

			softpll.seq_state = SEQ_START_HELPER;
			helper_init(&softpll.helper, n_chan_ref); 
			break;

		case MODE_SLAVE:
			strcpy(mode_str, "Slave");

			softpll.seq_state = SEQ_START_HELPER;
			helper_init(&softpll.helper, slave_ref_channel); 
			mpll_init(&softpll.mpll, slave_ref_channel, n_chan_ref);
			break;
	}					

	TRACE("SPLL_Init: running as %s, %d ref channels, %d out channels\n", mode_str, n_chan_ref, n_chan_out);

	/* Purge tag buffer */
	while(! (SPLL->TRR_CSR & SPLL_TRR_CSR_EMPTY)) dummy = SPLL->TRR_R0;
	dummy = SPLL->PER_HPLL;

	SPLL->EIC_IER = 1;

	_irq_entry();

	enable_irq();

	for(;;) mprintf("irqcount %d Seqstate %d TmrTics %d m %d ast %d\n", irq_count, softpll.seq_state, timer_get_tics(), softpll.mode, softpll.ext.realign_state);
}

int spll_check_lock()
{
	return softpll.seq_state == SEQ_READY;
}
