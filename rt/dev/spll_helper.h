
/* State of the Helper PLL producing a clock (clk_dmtd_i) which is
   slightly offset in frequency from the recovered/reference clock (clk_rx_i or clk_ref_i), so the
   Main PLL can use it to perform linear phase measurements. This structure keeps the state of the pre-locking
   stage */
struct spll_helper_prelock_state {
 	spll_pi_t pi; 
 	spll_lock_det_t ld;
 	int f_setpoint;
	int ref_select;
};


volatile int serr;
	
void helper_prelock_init(struct spll_helper_prelock_state *s)
{
	
	/* Frequency branch PI controller */
	s->pi.y_min = 5;
	s->pi.y_max = 65530;
	s->pi.anti_windup = 0;
	s->pi.kp = 28*32*16;
	s->pi.ki = 50*32*16;
	s->pi.bias = 32000;

	/* Freqency branch lock detection */
	s->ld.threshold = 2;
	s->ld.lock_samples = 100;
	s->ld.delock_samples = 90;
	
	s->f_setpoint = -131072 / (1<<HPLL_N);

	pi_init(&s->pi);
	ld_init(&s->ld);
}


void helper_prelock_enable(int ref_channel, int enable)
{
	volatile int dummy;
	
	SPLL->CSR = 0;

	dummy = SPLL->PER_HPLL; /* clean any pending frequency measurement to avoid distubing the control loop */
	if(enable)
		SPLL->CSR = SPLL_CSR_PER_SEL_W(ref_channel) | SPLL_CSR_PER_EN;
	else
		SPLL->CSR = 0;
	
}

#define SPLL_LOCKED 1
#define SPLL_LOCKING 0

int helper_prelock_update(struct spll_helper_prelock_state *s)
{
	int y;
	volatile uint32_t per = SPLL->PER_HPLL;
	
	if(per & SPLL_PER_HPLL_VALID)
	{
		short err = (short) (per & 0xffff);

		err -= s->f_setpoint;

		serr = (int)err;

		y = pi_update(&s->pi, err);
		SPLL->DAC_HPLL = y;

		spll_debug(DBG_Y | DBG_PRELOCK | DBG_HELPER, y, 0);
		spll_debug(DBG_ERR | DBG_PRELOCK | DBG_HELPER, err, 1);
		
		if(ld_update(&s->ld, err))
		{
			spll_debug(DBG_EVENT | DBG_PRELOCK | DBG_HELPER, DBG_EVT_LOCKED, 1);
			
			return SPLL_LOCKED;
		}
	}
	
	return SPLL_LOCKING;
}

struct spll_helper_phase_state {
	int p_adder;
 	int p_setpoint, tag_d0;
 	int ref_src;
 	int sample_n;
 	spll_pi_t pi; 
 	spll_lock_det_t ld;
};
	
void helper_phase_init(struct spll_helper_phase_state *s, int ref_channel)
{
	
	/* Phase branch PI controller */
	s->pi.y_min = 5;
	s->pi.y_max = 65530;
 	s->pi.kp = (int)(0.3 * 32.0 * 16.0);
	s->pi.ki = (int)(0.03 * 32.0 * 3.0); 


	s->pi.anti_windup = 0;
	s->pi.bias = 32000;
	
	/* Phase branch lock detection */
	s->ld.threshold = 200;
	s->ld.lock_samples = 1000;
	s->ld.delock_samples = 900;
	s->ref_src = ref_channel;
	s->p_setpoint = 0;	
	s->p_adder = 0;
	s->sample_n = 0;
	s->tag_d0 = 0;
	pi_init(&s->pi);
	ld_init(&s->ld);
}

void helper_phase_enable(int ref_channel, int enable)
{
	spll_enable_tagger(ref_channel, enable);
//		spll_debug(DBG_EVENT | DBG_HELPER, DBG_EVT_START, 1);
}

volatile int delta;

#define TAG_WRAPAROUND 100000000

int helper_phase_update(struct spll_helper_phase_state *s, int tag, int source)
{
	int err, y;

	if(source == s->ref_src)
	{
		spll_debug(DBG_TAG | DBG_HELPER, tag, 0);
		spll_debug(DBG_REF | DBG_HELPER, s->p_setpoint, 0);

		if(s->tag_d0 > tag)
			s->p_adder += (1<<TAG_BITS);
			
		err = (tag + s->p_adder) - s->p_setpoint;

		s->tag_d0 = tag;
		s->p_setpoint += (1<<HPLL_N);
		
		if(s->p_adder > TAG_WRAPAROUND)
		{
			s->p_adder -= TAG_WRAPAROUND;
			s->p_setpoint -= TAG_WRAPAROUND;
		}
		
		y = pi_update(&s->pi, err);
		SPLL->DAC_HPLL = y;

		spll_debug(DBG_SAMPLE_ID | DBG_HELPER, s->sample_n++, 0);
		spll_debug(DBG_Y | DBG_HELPER, y, 0);
		spll_debug(DBG_ERR | DBG_HELPER, err, 1);

		if(ld_update(&s->ld, err))
			return SPLL_LOCKED;
	}

	return SPLL_LOCKING;
}

#define HELPER_PRELOCKING 1
#define HELPER_PHASE 2
#define HELPER_LOCKED 3

struct spll_helper_state {
	struct spll_helper_prelock_state prelock;
	struct 	spll_helper_phase_state phase;
	int state;
	int ref_channel;
};

void helper_start(struct spll_helper_state *s, int ref_channel)
{
	s->state = HELPER_PRELOCKING;	
	s->ref_channel = ref_channel;
	
	helper_prelock_init(&s->prelock);
	helper_phase_init(&s->phase, ref_channel);
	helper_prelock_enable(ref_channel, 1);
	spll_debug(DBG_EVENT | DBG_PRELOCK | DBG_HELPER, DBG_EVT_START, 1);
}

int helper_update(struct spll_helper_state *s, int tag, int source)
{
	switch(s->state)
	{
		case HELPER_PRELOCKING:
			if(helper_prelock_update(&s->prelock) == SPLL_LOCKED)
			{
				s->state = HELPER_PHASE;
				helper_prelock_enable(s->ref_channel, 0);
				s->phase.pi.bias = s->prelock.pi.y;
				helper_phase_enable(s->ref_channel, 1);
			}
			return SPLL_LOCKING;
		case HELPER_PHASE:
			return helper_phase_update(&s->phase, tag, source);
	}
	return SPLL_LOCKING;
}