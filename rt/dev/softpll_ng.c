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


struct spll_pmeas_channel {
	int acc;
	int n_avgs, remaining;
	int current;
	int ready;
	int n_tags;
};

static volatile struct spll_helper_state helper;
static volatile struct spll_main_state mpll;
static volatile struct spll_pmeas_channel pmeas[MAX_CHAN_REF + MAX_CHAN_OUT];


static void pmeas_update(struct spll_pmeas_channel *chan, int tag)
{
	chan->n_tags++;
	chan->remaining--;
	chan->acc += tag & ((1<<HPLL_N)-1);
	py = tag;
	if(chan->remaining == 0)
	{
		chan->remaining = chan->n_avgs;
		chan->current = chan->acc / chan->n_avgs;
		chan->acc = 0;
		chan->ready = 1;
	}
}

static void pmeas_enable(int channel)
{
	pmeas[channel].n_avgs = 256;
	pmeas[channel].remaining = 256;
	pmeas[channel].current = 0;
	pmeas[channel].acc = 0;
	pmeas[channel].ready = 0;
	pmeas[channel].n_tags = 0;
	
	SPLL->RCER |= (1<<channel);
	
//	spll_pmeas_mask |= (1<<channel);
}

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

	SPLL->DAC_HPLL = 0;
	SPLL->DAC_MAIN = 0;
	timer_delay(10000);

	spll_init();

	uint32_t t1 = timer_get_tics();
	
	helper_init(&helper, 2);
	helper_start(&helper);
	mpll_init(&mpll, 2, CHAN_TCXO);
	enable_irq();
	while(!helper.ld.locked) ;//TRACE("%d\n", helper.phase.ld.locked);
	mpll_start(&mpll);
	while(!mpll.ld.locked) ;//TRACE("%d\n", helper.phase.ld.locked);

	uint32_t t2 = timer_get_tics();

	TRACE("SoftPLL locked (time = %d tics)\n", t2-t1);

/*	for(;;)
	{
		TRACE("Left...\n");
		mpll_set_phase_shift(&mpll, -4000);
		while(mpll_shifter_busy(&mpll));
		TRACE("Right...\n");
		mpll_set_phase_shift(&mpll, 4000);
		while(mpll_shifter_busy(&mpll));
	}*/
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