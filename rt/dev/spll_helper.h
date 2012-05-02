
/* State of the Helper PLL producing a clock (clk_dmtd_i) which is
   slightly offset in frequency from the recovered/reference clock (clk_rx_i or clk_ref_i), so the
   Main PLL can use it to perform linear phase measurements. 
   */
   
#define SPLL_LOCKED 1
#define SPLL_LOCKING 0

#define HELPER_TAG_WRAPAROUND 100000000

/* Maximum abs value of the phase error. If the error is bigger, it's clamped to this value. */
#define HELPER_ERROR_CLAMP 150000

struct spll_helper_state {
	int p_adder;						/* anti wrap-around adder */
 	int p_setpoint, tag_d0;
 	int ref_src;
 	int sample_n;
 	int delock_count;
 	spll_pi_t pi; 
 	spll_lock_det_t ld;
};
	
static void helper_init(struct spll_helper_state *s, int ref_channel)
{
	
	/* Phase branch PI controller */
	s->pi.y_min = 5;
	s->pi.y_max = (1 << DAC_BITS) - 5;
 	s->pi.kp = (int)(0.3 * 32.0 * 16.0);// / 2;
	s->pi.ki = (int)(0.03 * 32.0 * 3.0);// / 2; 
	
	s->pi.anti_windup = 1;
	
	/* Phase branch lock detection */
	s->ld.threshold = 200;
	s->ld.lock_samples = 10000;
	s->ld.delock_samples = 100;
	s->ref_src = ref_channel;
	s->delock_count = 0;
}

static int helper_update(struct spll_helper_state *s, int tag, int source)
{
	int err, y;

	if(source == s->ref_src)
	{
		spll_debug(DBG_TAG | DBG_HELPER, tag, 0);
		spll_debug(DBG_REF | DBG_HELPER, s->p_setpoint, 0);

		if(s->tag_d0 < 0)
		{
			s->p_setpoint = tag;
			s->tag_d0 = tag;

			return SPLL_LOCKING;
		}
		
		if(s->tag_d0 > tag)
			s->p_adder += (1<<TAG_BITS);
			
		err = (tag + s->p_adder) - s->p_setpoint;

		if(HELPER_ERROR_CLAMP)
		{
			if(err < -HELPER_ERROR_CLAMP) err = -HELPER_ERROR_CLAMP;
			if(err > HELPER_ERROR_CLAMP) err = HELPER_ERROR_CLAMP;
		}	
	
		if((tag + s->p_adder) > HELPER_TAG_WRAPAROUND && s->p_setpoint > HELPER_TAG_WRAPAROUND)
		{
			s->p_adder -= HELPER_TAG_WRAPAROUND;
			s->p_setpoint -= HELPER_TAG_WRAPAROUND;
		}

		s->p_setpoint += (1<<HPLL_N);
		s->tag_d0 = tag;
		
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



static void helper_start(struct spll_helper_state *s)
{
 /* Set the bias to the upper end of tuning range. This is to ensure that
 		the HPLL will always lock on positive frequency offset. */
	s->pi.bias = s->pi.y_max;

	s->p_setpoint = 0;	
	s->p_adder = 0;
	s->sample_n = 0;
	s->tag_d0 = -1;

	pi_init(&s->pi);
	ld_init(&s->ld);

	spll_enable_tagger(s->ref_src, 1);
	spll_debug(DBG_EVENT |  DBG_HELPER, DBG_EVT_START, 1);
}

