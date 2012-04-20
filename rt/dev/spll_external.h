
#include <timer.h>

/* Number of bits of the BB phase detector error counter. Bit [BB_ERROR_BITS] is the wrap-around bit */
#define BB_ERROR_BITS 16

/* Alignment FSM states */

/* 1st alignment stage, done before starting the ext channel PLL: alignment of the rising edge
   of the external clock (10 MHz), with the rising edge of the local reference (62.5/125 MHz)
   and the PPS signal. Because of non-integer ratio (6.25 or 12.5), the PLL must know which edges
   shall be kept at phase==0. We align to the edge of the 10 MHz clock which comes right after the edge
   of the PPS pulse (see drawing below):

PLL reference (62.5 MHz)   ____|^^^^|____|^^^^|____|^^^^|____|^^^^|____|^^^^|____|^^^^|____|^^^^|____|^^^^|____|^^^^|____|^^^^|____|^^^^|____|
External clock (10 MHz)    ^^^^^^^^^|________________________|^^^^^^^^^^^^^^^^^^^^^^^^^|________________________|^^^^^^^^^^^^^^^^^^^^^^^^^|___
External PPS               ___________|^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    */
#define REALIGN_STAGE1 1
#define REALIGN_STAGE1_WAIT 2


/* 2nd alignment stage, done after the ext channel PLL has locked. We make sure that the switch's internal PPS signal
   is produced exactly on the edge of PLL reference in-phase with 10 MHz clock edge, which has come right after the PPS input

PLL reference (62.5 MHz)   ____|^^^^|____|^^^^|____|^^^^|____|^^^^|____|^^^^|____|^^^^|____|^^^^|____|^^^^|____|^^^^|____|^^^^|____|^^^^|____|
External clock (10 MHz)    ^^^^^^^^^|________________________|^^^^^^^^^^^^^^^^^^^^^^^^^|________________________|^^^^^^^^^^^^^^^^^^^^^^^^^|___
External PPS               ___________|^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Internal PPS               __________________________________|^^^^^^^^^|______________________________________________________________________
                                                             ^ aligned clock edges and PPS
*/

#define REALIGN_STAGE2 3
#define REALIGN_STAGE2_WAIT 4

/* Error state - PPS signal missing or of bad frequency */
#define REALIGN_PPS_INVALID 5

/* Realignment is disabled (i.e. the switch inputs only the reference frequency, but not time)  */
#define REALIGN_DISABLED 6

/* Realignment done */
#define REALIGN_DONE 7


struct spll_external_state {
	int ref_src;
	int sample_n;
	int ph_err_offset, ph_err_cur, ph_err_d0, ph_raw_d0;
	int realign_clocks;
	int realign_state;
	int realign_timer;
 	spll_pi_t pi;
 	spll_lowpass_t lp_short, lp_long;
 	spll_lock_det_t ld;
};

static void external_init( struct spll_external_state *s, int ext_ref, int realign_clocks)
{

	s->pi.y_min = 5;
	s->pi.y_max = (1 << DAC_BITS) - 5;
 	s->pi.kp = (int)(300);
	s->pi.ki = (int)(1);

	s->pi.anti_windup = 1;
	s->pi.bias = 32768;

	/* Phase branch lock detection */
	s->ld.threshold = 250;
	s->ld.lock_samples = 10000;
	s->ld.delock_samples = 9990;
	s->ref_src = ext_ref;
	s->ph_err_cur = 0;
	s->ph_err_d0 = 0;
	s->ph_raw_d0 = 0;

	s->realign_clocks = realign_clocks;
	s->realign_state = (realign_clocks ? REALIGN_STAGE1 : REALIGN_DISABLED);

	pi_init(&s->pi);
	ld_init(&s->ld);
	lowpass_init(&s->lp_short, 4000);
	lowpass_init(&s->lp_long, 300);
}

static inline void realign_fsm( struct spll_external_state *s)
{
	 uint32_t eccr;


	switch(s->realign_state)
	{
		case REALIGN_STAGE1:
			SPLL->ECCR |= SPLL_ECCR_ALIGN_EN;

			s->realign_state = REALIGN_STAGE1_WAIT;
			s->realign_timer = timer_get_tics();
			break;

		case REALIGN_STAGE1_WAIT:

			if(SPLL->ECCR & SPLL_ECCR_ALIGN_DONE)
				s->realign_state = REALIGN_STAGE2;
			else if (timer_get_tics() - s->realign_timer > 2*TICS_PER_SECOND)
			{
				SPLL->ECCR &= ~SPLL_ECCR_ALIGN_EN;
				s->realign_state = REALIGN_PPS_INVALID;
			}
			break;

		case REALIGN_STAGE2:
			if(s->ld.locked)
			{
				PPSG->CR =  PPSG_CR_CNT_RST | PPSG_CR_CNT_EN;
				PPSG->ADJ_UTCLO = 0;
				PPSG->ADJ_UTCHI = 0;
				PPSG->ADJ_NSEC = 0;
				PPSG->ESCR = PPSG_ESCR_SYNC;

				s->realign_state = REALIGN_STAGE2_WAIT;
				s->realign_timer = timer_get_tics();
			}
			break;

		case REALIGN_STAGE2_WAIT:
			if(PPSG->ESCR & PPSG_ESCR_SYNC)
			{
				PPSG->ESCR = PPSG_ESCR_PPS_VALID | PPSG_ESCR_TM_VALID;
				s->realign_state = REALIGN_DONE;
			} else if (timer_get_tics() - s->realign_timer > 2*TICS_PER_SECOND)
			{
				PPSG->ESCR = 0;
				s->realign_state = REALIGN_PPS_INVALID;
			}
			break;

		case REALIGN_PPS_INVALID:
		case REALIGN_DISABLED:
		case REALIGN_DONE:
			return ;
	}
}

static int external_update( struct spll_external_state *s, int tag, int source)
{
	int err, y, y2, yd, ylt;

	if(source == s->ref_src)
	{
		int wrap = tag & (1<<BB_ERROR_BITS) ? 1 : 0;

		realign_fsm(s);

		tag &= ((1<<BB_ERROR_BITS) - 1);



//		mprintf("err %d\n", tag);
		if(wrap)
		{
	  	if(tag > s->ph_raw_d0)
		 		s->ph_err_offset -= (1<<BB_ERROR_BITS);
		  else if(tag <= s->ph_raw_d0)
  	    s->ph_err_offset += (1<<BB_ERROR_BITS);
		}

		s->ph_raw_d0 = tag;

		err = (tag + s->ph_err_offset) - s->ph_err_d0;
		s->ph_err_d0 = (tag + s->ph_err_offset);

		y = pi_update(&s->pi, err);

	  y2 = lowpass_update(&s->lp_short, y);
	  ylt = lowpass_update(&s->lp_long, y);

		if(! (SPLL->ECCR & SPLL_ECCR_EXT_REF_PRESENT)) /* no reference? de-lock now */
		{
			ld_init(&s->ld);
			y2 = 32000;
		}

		SPLL->DAC_MAIN = y2 & 0xffff;

		spll_debug(DBG_ERR | DBG_EXT, ylt, 0);
		spll_debug(DBG_SAMPLE_ID | DBG_EXT, s->sample_n++, 0);
		spll_debug(DBG_Y | DBG_EXT, y2, 1);

		if(ld_update(&s->ld, y2 - ylt))
			return SPLL_LOCKED;
		}
	return SPLL_LOCKING;
}


static void external_start( struct spll_external_state *s)
{
//	mprintf("ExtStartup\n");

	SPLL->ECCR = 0;

	s->sample_n = 0;
	s->realign_state = (s->realign_clocks ? REALIGN_STAGE1 : REALIGN_DISABLED);

	SPLL->ECCR = SPLL_ECCR_EXT_EN;

	spll_debug(DBG_EVENT |  DBG_EXT, DBG_EVT_START, 1);
}

static inline int external_locked( struct spll_external_state *s)
{
	return (s->ld.locked && (s->realign_clocks ? s->realign_state == REALIGN_DONE : 1));
}
