#include <stdio.h>
#include <stdlib.h>

#include "board.h"
#include "timer.h"
#include "trace.h"
#include "hw/softpll_regs.h"

#include "irq.h"

volatile int irq_count = 0,eee,yyy,py;

static volatile struct SPLL_WB *SPLL = (volatile struct SPLL_WB *) BASE_SOFTPLL;

/* The includes below contain code (not only declarations) to enable the compiler
   to inline functions where necessary and save some CPU cycles */


#include "spll_defs.h"
#include "spll_common.h"
#include "spll_debug.h"
#include "spll_helper.h"
#include "spll_main.h"
#include "spll_ptracker.h"
#include "spll_external.h"

#define CHAN_TCXO 4
#define CHAN_EXT 5

static volatile struct spll_helper_state helper;
static volatile struct spll_external_state extpll;
static volatile struct spll_main_state mpll;
static volatile struct spll_ptracker_state ptrackers[MAX_PTRACKERS];

#define MODE_GRAND_MASTER 0
#define MODE_FREERUNNING_MASTER 1
#define MODE_SLAVE 2

static volatile int mode = MODE_GRAND_MASTER;
static volatile int helper_locked = 0;


void _irq_entry()
{
	volatile uint32_t trr;
	int src = -1, tag;
	int i;

	if(! (SPLL->CSR & SPLL_TRR_CSR_EMPTY))
	{
		trr = SPLL->TRR_R0;
		src = SPLL_TRR_R0_CHAN_ID_R(trr);
		tag = SPLL_TRR_R0_VALUE_R(trr);

		switch(mode) {
			case MODE_GRAND_MASTER:
				external_update(&extpll, tag, src);
				break;
		};

//		helper_update(&helper, tag, src);

/*		if(helper.ld.locked && !helper_locked)
		{
			for(i=0;i<n_chan_ref; i++)
				ptracker_init(&ptrackers[i], CHAN_TCXO, i, 512);
		}

		if(helper.ld.locked)
		{
			for(i=0;i<n_chan_ref; i++)
				ptracker_update(&ptrackers[i], tag, src);
			
		} else {
			for(i=0;i<n_chan_ref; i++)
				ptrackers[i].ready = 0;
		}
*/
/*
		if(helper.ld.locked && !helper_locked)
		{
			if(!master_mode) mpll_start(&mpll);
			helper_locked=  1;
		}
		

		if(helper.ld.locked && !master_mode)
		{
			mpll_update(&mpll, tag, src);	
		}*/

		
	}

	irq_count++;
	clear_irq();
}

void spll_init(int _master_mode, int ref_channel)
{
	volatile int dummy;
	disable_irq();

	n_chan_ref = SPLL_CSR_N_REF_R(SPLL->CSR);
	n_chan_out = SPLL_CSR_N_OUT_R(SPLL->CSR);

	helper_locked = 0;
//	master_mode = _master_mode;

	TRACE("SPLL_Init: %s mode, %d ref channels, %d out channels\n", _master_mode ? "Master" : "Slave", n_chan_ref, n_chan_out);
	SPLL->DAC_HPLL = 0;
	timer_delay(100000);	
	SPLL->CSR= 0 ;
	SPLL->OCER = 0;
	SPLL->RCER = 0;
	SPLL->RCGER = 0;
	SPLL->DCCR = 0;
	SPLL->DEGLITCH_THR = 1000;
	while(! (SPLL->TRR_CSR & SPLL_TRR_CSR_EMPTY)) dummy = SPLL->TRR_R0;
	dummy = SPLL->PER_HPLL;
	SPLL->EIC_IER = 1;

//	helper_init(&helper, master_mode ? CHAN_TCXO : ref_channel);

//	if(!master_mode)
//		mpll_init(&mpll, ref_channel, CHAN_TCXO);
	
//	helper_start(&helper);
	external_init(&extpll, CHAN_EXT);
	external_start(&extpll, 1);

	enable_irq();

	for(;;) mprintf("irqcount %d t %d lock %d\n", irq_count, eee, extpll.ld.locked);
}

int spll_check_lock()
{
	return 0;
//	return helper.ld.locked & (mpll.ld.locked || master_mode) ? 1 : 0;
}
