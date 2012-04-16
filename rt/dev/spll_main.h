
#define MPLL_TAG_WRAPAROUND 100000000

/* State of the Main PLL */
struct spll_main_state {
	int state;

 	spll_pi_t pi; 
 	spll_lock_det_t ld;

	int adder_ref, adder_out, tag_ref, tag_out, tag_ref_d, tag_out_d; 	 	
 	int phase_shift_target;
 	int phase_shift_current;
	int id_ref, id_out; /* IDs of the reference and the output channel */
	int sample_n;
};


static void mpll_init(struct spll_main_state *s, int id_ref, int id_out)
{
	/* Frequency branch PI controller */
	s->pi.y_min = 5;
	s->pi.y_max = 65530;
	s->pi.anti_windup = 1;
	s->pi.bias = 65000;
	s->pi.kp = 1100;
	s->pi.ki = 30;

	/* Freqency branch lock detection */
	s->ld.threshold = 120;
	s->ld.lock_samples = 400;
	s->ld.delock_samples = 390;
	s->id_ref = id_ref;
	s->id_out = id_out;

}

static void mpll_start(struct spll_main_state *s)
{
	s->adder_ref = s->adder_out = 0;
	s->tag_ref = -1;
	s->tag_out = -1;
	s->tag_ref_d = -1;
	s->tag_out_d = -1;
	
	s->phase_shift_target = 0;
	s->phase_shift_current = 0;
	s->sample_n=  0;

	pi_init(&s->pi);
	ld_init(&s->ld);

	spll_enable_tagger(s->id_ref, 1);
	spll_enable_tagger(s->id_out, 1);
	spll_debug(DBG_EVENT | DBG_MAIN, DBG_EVT_START, 1);
}


static int mpll_update(struct spll_main_state *s, int tag, int source)
{
	int err, y, tmp;

	if(source == s->id_ref)
		s->tag_ref = tag;
	if(source == s->id_out)
		s->tag_out = tag;

	if(s->tag_ref >= 0 && s->tag_out >= 0)
	{
		if(s->tag_ref_d >= 0 && s->tag_ref_d > s->tag_ref)
			s->adder_ref += (1<<TAG_BITS);
		if(s->tag_out_d >= 0 && s->tag_out_d > s->tag_out)
			s->adder_out += (1<<TAG_BITS);
			
		s->tag_ref_d = s->tag_ref;
		s->tag_out_d = s->tag_out;
	
		err = s->adder_ref + s->tag_ref -  s->adder_out - s->tag_out;
		
		if(s->adder_ref > MPLL_TAG_WRAPAROUND && s->adder_out > MPLL_TAG_WRAPAROUND)
		{
			s->adder_ref -= MPLL_TAG_WRAPAROUND;
			s->adder_out -= MPLL_TAG_WRAPAROUND;
		}
		
    y = pi_update(&s->pi, err);
		SPLL->DAC_MAIN = SPLL_DAC_MAIN_VALUE_W(y) | SPLL_DAC_MAIN_DAC_SEL_W(s->id_out);

		spll_debug(DBG_MAIN | DBG_REF, s->tag_ref, 0);
		spll_debug(DBG_MAIN | DBG_TAG, s->tag_out, 0);
		spll_debug(DBG_MAIN | DBG_ERR, err, 0);
		spll_debug(DBG_MAIN | DBG_SAMPLE_ID, s->sample_n++, 0);
		spll_debug(DBG_MAIN | DBG_Y, y, 1);

		s->tag_out = -1;
		s->tag_ref = -1;	

	  if(s->phase_shift_current < s->phase_shift_target)
	  {
      s->phase_shift_current++;
      s->adder_ref++;
		} else if(s->phase_shift_current > s->phase_shift_target) {
      s->phase_shift_current--;
      s->adder_ref--;
		}	
		
   	if(ld_update(&s->ld, err))
   		return SPLL_LOCKED;

  }

	return SPLL_LOCKING;
}

static int mpll_set_phase_shift(struct spll_main_state *s, int desired_shift)
{
	s->phase_shift_target = desired_shift;
}

static int mpll_shifter_busy(struct spll_main_state *s)
{
	return s->phase_shift_target != s->phase_shift_current;
}