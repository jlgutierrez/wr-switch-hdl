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
#define SEQ_CLEAR_DACS 9
#define SEQ_WAIT_CLEAR_DACS 10

struct softpll_state {
	int mode;
	int seq_state;
	int helper_locked;
	int dac_timeout;
	int default_dac_main;
	int delock_count;
	struct spll_helper_state helper;
	struct spll_external_state ext;
	struct spll_main_state mpll;
	struct spll_main_state aux[MAX_CHAN_AUX];
	struct spll_ptracker_state ptrackers[MAX_PTRACKERS];
};

static volatile struct softpll_state softpll;

static volatile int ptracker_mask = 0; /* fixme: should be done by spll_init() but spll_init is called to switch modes (and we won't like messing around with ptrackers there) */

void _irq_entry()
{
	volatile uint32_t trr;
	int src = -1, tag, i;
	struct softpll_state *s = (struct softpll_state *) &softpll;

/* check if there are more tags in the FIFO */
	while(! (SPLL->TRR_CSR & SPLL_TRR_CSR_EMPTY))
	{
		trr = SPLL->TRR_R0;
		src = SPLL_TRR_R0_CHAN_ID_R(trr);
		tag = SPLL_TRR_R0_VALUE_R(trr);


		switch(softpll.seq_state)
		{
            case SEQ_CLEAR_DACS:
                SPLL->DAC_HPLL = 65535;
                SPLL->DAC_MAIN = softpll.default_dac_main;
                SPLL->OCER |= 1;
                softpll.seq_state = SEQ_WAIT_CLEAR_DACS;
                softpll.dac_timeout = timer_get_tics();
                break;

            case SEQ_WAIT_CLEAR_DACS:
                if(timer_get_tics() - softpll.dac_timeout > 10000)
                    softpll.seq_state = (softpll.mode == SPLL_MODE_GRAND_MASTER ? SEQ_START_EXT : SEQ_START_HELPER);
                break;

			case SEQ_DISABLED:
				break;

			case SEQ_START_EXT:
				external_update((struct spll_external_state *) &s->ext, tag, src);
				external_start((struct spll_external_state *) &s->ext);
				softpll.seq_state = SEQ_WAIT_EXT;
				break;

			case SEQ_WAIT_EXT:
				if(external_locked((struct spll_external_state *) &s->ext))
					softpll.seq_state = SEQ_START_HELPER;
				break;

			case SEQ_START_HELPER:
				softpll.helper_locked = 0;
				helper_start((struct spll_helper_state *) &s->helper);
				softpll.seq_state = SEQ_WAIT_HELPER;
				break;

			case SEQ_WAIT_HELPER:
				if(softpll.helper.ld.locked && !softpll.helper_locked)
				{
					softpll.helper_locked = 1;

					if(softpll.mode == SPLL_MODE_SLAVE)
						softpll.seq_state = SEQ_START_MAIN;
					else {
						for(i=0;i<n_chan_ref; i++)
							if(ptracker_mask & (1<<i))
								ptracker_start((struct spll_ptracker_state *) &s->ptrackers[i]);
						softpll.seq_state = SEQ_READY;
					}
				}
				break;

			case SEQ_START_MAIN:
				mpll_start((struct spll_main_state *) &s->mpll);
				softpll.seq_state = SEQ_WAIT_MAIN;
				break;

			case SEQ_WAIT_MAIN:
				if(softpll.mpll.ld.locked)
				{
					softpll.seq_state = SEQ_READY;

					for(i=0;i<n_chan_ref; i++)
						if(ptracker_mask & (1<<i))
							ptracker_start((struct spll_ptracker_state *) &s->ptrackers[i]);
				}
				break;

			case SEQ_READY:
				if(!softpll.helper.ld.locked)
				{
//					SPLL->OCER = 0;
//					SPLL->RCER = 0;
					softpll.seq_state = SEQ_CLEAR_DACS;
					softpll.delock_count++;
				} else if (softpll.mode == SPLL_MODE_GRAND_MASTER && !external_locked((struct spll_external_state *) &s->ext))
				{
//					SPLL->OCER = 0;
//					SPLL->RCER = 0;
//					SPLL->ECCR = 0;
					softpll.seq_state = SEQ_START_EXT;
					softpll.delock_count++;
				} else if (softpll.mode == SPLL_MODE_SLAVE && !softpll.mpll.ld.locked)
				{
					softpll.seq_state = SEQ_CLEAR_DACS;
					softpll.delock_count++;
				};
				break;
		};


		switch(softpll.seq_state)
		{
			case SEQ_WAIT_EXT:
				external_update((struct spll_external_state *) &s->ext, tag, src);
				break;

			case SEQ_WAIT_HELPER:
				if(softpll.mode == SPLL_MODE_GRAND_MASTER)
					external_update((struct spll_external_state *) &s->ext, tag, src);
				helper_update((struct spll_helper_state *) &s->helper, tag, src);
				break;

			case SEQ_WAIT_MAIN:
			case SEQ_READY:
				helper_update((struct spll_helper_state *) &s->helper, tag, src);

				if(softpll.mode == SPLL_MODE_GRAND_MASTER)
					external_update((struct spll_external_state *) &s->ext, tag, src);
				if(softpll.mode == SPLL_MODE_SLAVE)
					mpll_update((struct spll_main_state *) &s->mpll, tag, src);

					for(i=0;i<n_chan_ref; i++)
						if(ptracker_mask & (1<<i))
							ptracker_update((struct spll_ptracker_state *) &s->ptrackers[i], tag, src);

				break;



		}


	}

	irq_count++;
	clear_irq();
}

void spll_clear_dacs()
{
    SPLL->DAC_HPLL = 0;
	SPLL->DAC_MAIN = 0;
	timer_delay(10000);
}

void spll_init(int mode, int slave_ref_channel, int align_pps)
{
	char mode_str[20];
	volatile int dummy;
	int i;

	disable_irq();

	n_chan_ref = SPLL_CSR_N_REF_R(SPLL->CSR);
	n_chan_out = SPLL_CSR_N_OUT_R(SPLL->CSR);
	softpll.helper_locked = 0;
	softpll.mode = mode;
	softpll.default_dac_main = 0;
	softpll.delock_count = 0;

	SPLL->DAC_HPLL = 0;
	SPLL->DAC_MAIN = 0;

	//timer_delay(100000);

	SPLL->CSR= 0 ;
	SPLL->OCER = 0;
	SPLL->RCER = 0;
	SPLL->ECCR = 0;
	SPLL->RCGER = 0;
	SPLL->DCCR = 0;
	SPLL->DEGLITCH_THR = 1000;

	PPSG->ESCR = 0;
	PPSG->CR = PPSG_CR_CNT_EN | PPSG_CR_CNT_RST | PPSG_CR_PWIDTH_W(100);

	switch(mode)
	{
		case SPLL_MODE_DISABLED:
			strcpy(mode_str, "Disabled");
			softpll.seq_state = SEQ_DISABLED;
			break;

		case SPLL_MODE_GRAND_MASTER:
			strcpy(mode_str, "Grand Master");

			softpll.seq_state = SEQ_CLEAR_DACS;
			
			external_init(&softpll.ext, n_chan_ref + n_chan_out, align_pps);
			helper_init(&softpll.helper, n_chan_ref);

			mpll_init(&softpll.mpll, slave_ref_channel, n_chan_ref);

			for(i=0;i<n_chan_out-1;i++)
				mpll_init(&softpll.aux[i], slave_ref_channel, n_chan_ref + i + 1);
			break;

		case SPLL_MODE_FREE_RUNNING_MASTER:
			strcpy(mode_str, "Free-running Master");

			softpll.seq_state = SEQ_CLEAR_DACS;
			softpll.default_dac_main = 32000;
			helper_init(&softpll.helper, n_chan_ref);

			mpll_init(&softpll.mpll, slave_ref_channel, n_chan_ref);

			for(i=0;i<n_chan_out-1;i++)
				mpll_init(&softpll.aux[i], slave_ref_channel, n_chan_ref + i + 1);

			PPSG->ESCR = PPSG_ESCR_PPS_VALID | PPSG_ESCR_TM_VALID;
			break;

		case SPLL_MODE_SLAVE:
			strcpy(mode_str, "Slave");

			softpll.seq_state = SEQ_CLEAR_DACS;
			helper_init(&softpll.helper, slave_ref_channel);
			mpll_init(&softpll.mpll, slave_ref_channel, n_chan_ref);

			for(i=0;i<n_chan_out-1;i++)
				mpll_init(&softpll.aux[i], slave_ref_channel, n_chan_ref + i + 1);

//			PPSG->ESCR = PPSG_ESCR_PPS_VALID | PPSG_ESCR_TM_VALID;

			break;
	}

	for(i=0; i<n_chan_ref;i++)
		ptracker_init(&softpll.ptrackers[i], n_chan_ref, i, PTRACKER_AVERAGE_SAMPLES);


	TRACE("SPLL_Init: running as %s, %d ref channels, %d out channels\n", mode_str, n_chan_ref, n_chan_out);

	/* Purge tag buffer */
	while(! (SPLL->TRR_CSR & SPLL_TRR_CSR_EMPTY)) dummy = SPLL->TRR_R0;
	dummy = SPLL->PER_HPLL;

	SPLL->EIC_IER = 1;

	SPLL->OCER = 1;
//	_irq_entry();

	enable_irq();

/*	for(;;)
	{
		mprintf("irqcount %d Seqstate %d TmrTics %d m %d ast %d ", irq_count, softpll.seq_state, timer_get_tics(), softpll.mode, softpll.ext.realign_state);
		for(i=0;i<n_chan_ref;i++)
		{
			int ph, ready;
			ready =	spll_read_ptracker(i, &ph);
			mprintf("rp%d[%d]: %dps ", i, ready, ph);
		}
		mprintf("\n");
	}*/

}

void spll_shutdown()
{
	SPLL->OCER = 0;
	SPLL->RCER = 0;
	SPLL->ECCR = 0;
	SPLL->EIC_IDR = 1;
}

void spll_start_channel(int channel)
{
	if (softpll.seq_state != SEQ_READY || !channel)
		return;

	mpll_start(&softpll.aux[channel-1]);
}

void spll_stop_channel(int channel)
{
	if(!channel)
		return -1;

	mpll_stop(&softpll.aux[channel-1]);
}

int spll_check_lock(int channel)
{
		if(!channel)
			return (softpll.seq_state == SEQ_READY);
		else
			return (softpll.seq_state == SEQ_READY) && softpll.aux[channel-1].ld.locked;
}

static int32_t from_picos(int32_t ps)
{
	return (int32_t) ((int64_t)ps * (int64_t)(1<<HPLL_N) / (int64_t)CLOCK_PERIOD_PICOSECONDS);
}

static int32_t to_picos(int32_t units)
{
	return (int32_t) (((int64_t)units * (int64_t)CLOCK_PERIOD_PICOSECONDS) >> HPLL_N);
}

/* Channel 0 = local PLL reference, 1...N = aux oscillators */
void spll_set_phase_shift(int channel, int32_t value_picoseconds)
{
	volatile struct spll_main_state *st = (!channel ? &softpll.mpll : &softpll.aux[channel-1]);
	mpll_set_phase_shift(st, from_picos(value_picoseconds));
}

void spll_get_phase_shift(int channel, int32_t *current, int32_t *target)
{
	volatile struct spll_main_state *st = (!channel ? &softpll.mpll : &softpll.aux[channel-1]);
    if(current) *current = to_picos(st->phase_shift_current);
	if(target) *target = to_picos(st->phase_shift_target);
}

int spll_read_ptracker(int channel, int32_t *phase_ps, int *enabled)
{
	volatile struct spll_ptracker_state *st = &softpll.ptrackers[channel];
    int phase = st->phase_val;
    if(phase < 0) phase += (1<<HPLL_N);
    else if (phase >= (1<<HPLL_N)) phase -= (1<<HPLL_N);

	*phase_ps = to_picos(phase);
	if(enabled)
		*enabled = ptracker_mask & (1<<st->id_b) ? 1 : 0;
	return st->ready;
}

void spll_get_num_channels(int *n_ref, int *n_out)
{
    if(n_ref) *n_ref = n_chan_ref;
    if(n_out) *n_out = n_chan_out;
}

void spll_show_stats()
{
    if(softpll.mode > 0)
    TRACE("Irq_count %d Sequencer_state %d mode %d Alignment_state %d HL%d EL%d ML%d HY=%d MY=%d DelCnt=%d\n",
            irq_count, softpll.seq_state, softpll.mode, softpll.ext.realign_state,
            softpll.helper.ld.locked, softpll.ext.ld.locked, softpll.mpll.ld.locked,
            softpll.helper.pi.y, softpll.mpll.pi.y, softpll.delock_count);

}

int spll_shifter_busy(int channel)
{
		if(!channel)
			return mpll_shifter_busy(&softpll.mpll);
		else
			return mpll_shifter_busy(&softpll.aux[channel-1]);
}

void spll_enable_ptracker(int ref_channel, int enable)
{
	if(enable) {
		spll_enable_tagger(ref_channel, 1);
		ptracker_start((struct spll_ptracker_state *) &softpll.ptrackers[ref_channel]);
		ptracker_mask |= (1<<ref_channel);
		TRACE("Enabling ptracker channel: %d\n", ref_channel);

	} else {
		ptracker_mask &= ~(1<<ref_channel);
		if(ref_channel != softpll.mpll.id_ref)
			spll_enable_tagger(ref_channel, 0);
		TRACE("Disabling ptracker tagger: %d\n", ref_channel);
	}
}


int spll_get_delock_count()
{
	return softpll.delock_count;
}