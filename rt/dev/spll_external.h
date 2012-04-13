
#define BB_ERROR_BITS 16

struct spll_external_state {
	int ref_src;
	int sample_n;
	int ph_err_offset, ph_err_cur, ph_err_d0, ph_raw_d0;
 	spll_pi_t pi; 
 	spll_lowpass_t lp_short, lp_long; 
 	spll_lock_det_t ld;
};
	
static void external_init(struct spll_external_state *s, int ext_ref)
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
		
	pi_init(&s->pi);
	ld_init(&s->ld);
	lowpass_init(&s->lp_short, 4000);
	lowpass_init(&s->lp_long, 1000);
}

static int external_update(struct spll_external_state *s, int tag, int source)
{
	int err, y, y2, yd, ylt;

	if(source == s->ref_src)
	{
		int wrap = tag & (1<<BB_ERROR_BITS) ? 1 : 0;
	
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

		SPLL->DAC_MAIN = y2 & 0xffff;

		spll_debug(DBG_ERR | DBG_EXT, ylt, 0);
		spll_debug(DBG_SAMPLE_ID | DBG_EXT, s->sample_n++, 0);
		spll_debug(DBG_Y | DBG_EXT, y2, 1);

		if(ld_update(&s->ld, y2 - ylt))
			return SPLL_LOCKED;
		}
	return SPLL_LOCKING;
}


static void external_start(struct spll_external_state *s, int align_pps)
{
	s->sample_n = 0;
	SPLL->ECCR = SPLL_ECCR_EXT_EN;
	mprintf("ExtStartup\n");
	spll_debug(DBG_EVENT |  DBG_EXT, DBG_EVT_START, 1);
	
	if(align_pps)
	{
		SPLL->ECCR |= SPLL_ECCR_ALIGN_EN;
		while (! (SPLL->ECCR & SPLL_ECCR_ALIGN_DONE));
	}
}

