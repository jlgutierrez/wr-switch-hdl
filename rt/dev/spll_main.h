
#define MPLL_DISABLED -1
#define MPLL_FREQ 0
#define MPLL_PHASE 1

#define PER_REF_READY 1
#define PER_OUT_READY 2

/* State of the Main PLL */
struct spll_main_state {
	int state;

	struct {
	 	spll_pi_t pi; 
	 	spll_lock_det_t ld;
	 	int period_ref, period_out;
	 	int flags;
	} freq ;

	struct {
	 	spll_pi_t pi; 
	 	spll_lock_det_t ld;
	} phase ;
 	 	
 	int tag_ref_d, tag_out_d;
 	int phase_shift_target;
 	int phase_shift_current;
	int id_ref, id_out; /* IDs of the reference and the output channel */
	int sample_n;
};


volatile int serr;
	
void mpll_init(struct spll_main_state *s, int id_ref, int id_out)
{
	
	/* Frequency branch PI controller */
	s->freq.pi.y_min = 5;
	s->freq.pi.y_max = 65530;
	s->freq.pi.anti_windup = 0;
	s->freq.pi.bias = 32000;
	s->freq.pi.kp = 100;
	s->freq.pi.ki = 600;

	/* Freqency branch lock detection */
	s->freq.ld.threshold = 200;
	s->freq.ld.lock_samples = 1000;
	s->freq.ld.delock_samples = 990;
	s->freq.flags = 0;
	
	s->tag_ref_d = -1;
	s->tag_out_d = -1;
	s->phase_shift_current = 0;
	s->id_ref = id_ref;
	s->id_out = id_out;
	s->sample_n=  0;
	s->state = MPLL_DISABLED;

	pi_init(&s->freq.pi);
	ld_init(&s->freq.ld);
}

void mpll_start(struct spll_main_state *s)
{
	s->state = MPLL_FREQ;
	spll_enable_tagger(s->id_ref, 1);
	spll_enable_tagger(s->id_out, 1);
	spll_debug(DBG_EVENT | DBG_PRELOCK | DBG_MAIN, DBG_EVT_START, 1);
}

int mpll_freq_update(struct spll_main_state *s, int tag, int source)
{
	int err, y, tmp;

/* calculate the periods on both reference and output channel */
	if(source == s->id_ref)
	{
		//spll_debug(DBG_REF | DBG_PRELOCK | DBG_MAIN, tag, 1);
	
	  if(s->tag_ref_d >= 0)
      {
        tmp = tag - s->tag_ref_d;
        if(tmp < 0)
          tmp += (1<<TAG_BITS);
        s->freq.period_ref = tmp;
        s->freq.flags |= PER_REF_READY;
      }
			s->tag_ref_d = tag;
	
	} else if(source == s->id_out) {
		//spll_debug(DBG_TAG | DBG_PRELOCK | DBG_MAIN, tag, 1);

	  if(s->tag_out_d >= 0)
      {
        tmp = tag - s->tag_out_d;
        if(tmp < 0)
          tmp += (1<<TAG_BITS);
        s->freq.period_out = tmp;
        s->freq.flags |= PER_OUT_READY;
      }
			s->tag_out_d = tag;
	}

/* if we have two fresh period measurements, calculate the error and adjust the DAC */
	 if((s->freq.flags & PER_OUT_READY) && (s->freq.flags & PER_REF_READY))
  	{
  		s->freq.flags &= ~(PER_OUT_READY | PER_REF_READY);
      err = s->freq.period_ref - s->freq.period_out;

			y = pi_update(&s->freq.pi, err);
	    SPLL->DAC_MAIN = SPLL_DAC_MAIN_VALUE_W(y) | SPLL_DAC_MAIN_DAC_SEL_W(s->id_out);
  
			spll_debug(DBG_ERR | DBG_PRELOCK | DBG_MAIN, err, 0);
			spll_debug(DBG_SAMPLE_ID | DBG_PRELOCK | DBG_MAIN, s->sample_n++, 0);
	    spll_debug(DBG_Y | DBG_PRELOCK | DBG_MAIN, y, 1);

	    if(ld_update(&s->freq.ld, err))
  	    return SPLL_LOCKED;
   	}
	
	return SPLL_LOCKING;
}

int mpll_phase_update(struct spll_main_state *s, int tag, int source)
{

	return SPLL_LOCKING;
}

int mpll_update(struct spll_main_state *s, int tag, int source)
{
	switch(s->state)
	{
		case MPLL_DISABLED:
			break;
		case MPLL_FREQ:
			if(mpll_freq_update(s, tag, source) == SPLL_LOCKED)
			{
				s->state = MPLL_PHASE;
				s->phase.pi.bias = s->freq.pi.y;
			}
			return SPLL_LOCKING;
		case MPLL_PHASE:
			{
#if 0
				if(tag_ref >= 0)
		      dmpll->tag_ref_d0 = tag_ref;
      
			    tag_ref = dmpll->tag_ref_d0 ;
			    tag_fb += (dmpll->setpoint >> SETPOINT_FRACBITS);
			    tag_fb &= (1<<TAG_BITS) - 1;

    if(fb_ready)
    {
      tag_ref &= 0x3fff; //while (tag_ref > 16384 ) tag_ref-=16384; /* fixme */
      tag_fb &= 0x3fff; //while (tag_fb > 16384  ) tag_fb-=16384;

        err = tag_ref - tag_fb;
        y = pi_update(&dmpll->pi_phase, err);
      *dac = y;
      ld_update(&dmpll->ld_phase, err);
      if(dmpll->setpoint < dmpll->phase_shift)
        dmpll->setpoint++;
      else if(dmpll->setpoint > dmpll->phase_shift)
        dmpll->setpoint--;
    }
  }
#endif
			}
			break;
//			return helper_phase_update(&s->phase, tag, source);
	}
	return SPLL_LOCKING;
}