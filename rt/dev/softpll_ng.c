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

static volatile struct spll_helper_state helper;
static volatile struct spll_main_state mpll;

void _irq_entry()
{
	volatile uint32_t trr;
	int src = -1, tag;

	if(! (SPLL->CSR & SPLL_TRR_CSR_EMPTY))
	{
		trr = SPLL->TRR_R0;
		src = SPLL_TRR_R0_CHAN_ID_R(trr);
		tag = SPLL_TRR_R0_VALUE_R(trr);

		helper_update(&helper, tag, src);
		mpll_update(&mpll, tag, src);
	}

		irq_count++;
		clear_irq();
}

void spll_init()
{
	volatile int dummy;
	disable_irq();

	
	n_chan_ref = SPLL_CSR_N_REF_R(SPLL->CSR);
	n_chan_out = SPLL_CSR_N_OUT_R(SPLL->CSR);

	TRACE("SPLL_Init: %d ref channels, %d out channels\n", n_chan_ref, n_chan_out);
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
}

int spll_check_lock()
{
	return helper.ld.locked ? 1 : 0;
}

#define CHAN_TCXO 8

void spll_test()
{
	int i = 0;
	volatile	int dummy;


	spll_init();
	helper_init(&helper, 0);
	helper_start(&helper);
	mpll_init(&mpll, 0, CHAN_TCXO);
	enable_irq();

//	mpll_init(&mpll, 0, CHAN_TCXO);
	while(!helper.ld.locked) ;//TRACE("%d\n", helper.phase.ld.locked);
	TRACE("Helper locked, starting main\n");
	mpll_start(&mpll);

}

/*
#define CHAN_AUX 7
#define CHAN_EXT 6


int spll_gm_measure_ext_phase()
{
	SPLL->CSR = 0;
	SPLL->DCCR = SPLL_DCCR_GATE_DIV_W(25);
	SPLL->RCGER = (1<<CHAN_AUX);
	SPLL->RCGER = (1<<CHAN_EXT);
}
*/