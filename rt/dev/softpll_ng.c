#include <stdio.h>

#include "board.h"
#include "hw/softpll_regs.h"

#include "irq.h"

volatile int irq_count = 0,eee,yyy,py;

static volatile struct SPLL_WB *SPLL = (volatile struct SPLL_WB *) BASE_SOFTPLL;

/* The includes below contain code (not only declarations) to enable the compiler
   to inline functions where necessary and save some CPU cycles */
#include "spll_defs.h"
#include "spll_common.h"
#include "spll_helper.h"


struct spll_pmeas_channel {
	int acc;
	int n_avgs, remaining;
	int current;
	int ready;
	int n_tags;
};

static volatile uint32_t spll_pmeas_mask = 0;


volatile struct spll_helper_state helper;
volatile struct spll_pmeas_channel pmeas[32];

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
	
	spll_pmeas_mask |= (1<<channel);
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
		eee = tag;

		helper_update(&helper, tag, src);

/*	if(spll_pmeas_mask & (1<<src))
		pmeas_update(&pmeas[src], tag);*/
	}

//		yyy=helper.phase.pi.y;
		irq_count++;
		clear_irq();
}

void spll_init()
{
	volatile int dummy;
	disable_irq();

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
	return helper.phase.ld.locked ? 1 : 0;
}

void spll_test()
{
	int i = 0;
	volatile	int dummy;


	spll_init();
	helper_start(&helper, 8);
	enable_irq();
	
	while(!spll_check_lock()) { TRACE("%d %d %x %x\n",irq_count, delta, SPLL->TRR_CSR, SPLL->OCER); }

	
	SPLL->DCCR = SPLL_DCCR_GATE_DIV_W(24);
	SPLL->RCGER = (1<<7) | (1<<6);
	pmeas_enable(7);
	pmeas_enable(6);
	for(;;) {
		TRACE("RCER %x Phase %d/%d rdy %d/%d, py %d\n", SPLL->RCER, pmeas[7].current, pmeas[6].current, pmeas[7].ready, pmeas[6].ready, py);
	}

}

#define CHAN_AUX 7
#define CHAN_EXT 6


/* measures external reference vs local clock phase */
int spll_gm_measure_ext_phase()
{
	SPLL->CSR = 0;
	SPLL->DCCR = SPLL_DCCR_GATE_DIV_W(25);
	SPLL->RCGER = (1<<CHAN_AUX);
	SPLL->RCGER = (1<<CHAN_EXT);
}