
/* State of a Phase Tracker */

struct spll_ptracker_state {
	int id_a, id_b;
	int n_avg, acc, avg_count;
	int phase_val, ready;
	int tag_a, tag_b;
	int sample_n;
	int preserve_sign;
};


static void ptracker_init(struct spll_ptracker_state *s, int id_a, int id_b, int num_avgs)
{
	s->tag_a = s->tag_b = -1;

	s->id_a = id_a;
	s->id_b = id_b;
	s->ready = 0;
	s->n_avg = num_avgs;
	s->acc = 0;
	s->avg_count = 0;
	s->sample_n=  0;
	s->preserve_sign = 0;
}

static void ptracker_start(struct spll_ptracker_state *s)
{
	s->tag_a = s->tag_b = -1;
	s->ready = 0;
	s->acc = 0;
	s->avg_count = 0;
	s->sample_n=  0;
    s->preserve_sign = 0;

  spll_enable_tagger(s->id_a, 1);
  spll_enable_tagger(s->id_b, 1);
}

#define PTRACK_WRAP_LO (1<<(HPLL_N-2))
#define PTRACK_WRAP_HI (3*(1<<(HPLL_N-2)))

static int ptracker_update(struct spll_ptracker_state *s, int tag, int source)
{

	if(source == s->id_a)
		s->tag_a = tag;
	if(source == s->id_b)
		s->tag_b = tag;

	if(s->tag_a >= 0 && s->tag_b >= 0)
	{
		int delta = (s->tag_a - s->tag_b) & ((1<<HPLL_N) - 1);

		s->sample_n++;

		if(s->avg_count == 0)
		{

			if(delta <= PTRACK_WRAP_LO)
				s->preserve_sign = -1;
			else if (delta >= PTRACK_WRAP_HI)
				s->preserve_sign = 1;
			else
				s->preserve_sign = 0;

			s->avg_count++;
			s->acc = delta;
		} else {

			if(delta <= PTRACK_WRAP_LO && s->preserve_sign > 0)
				s->acc += delta + (1<<HPLL_N);
			else if (delta >= PTRACK_WRAP_HI && s->preserve_sign < 0)
				s->acc += delta - (1<<HPLL_N);
			else
				s->acc += delta;

			s->avg_count++;

			if(s->avg_count == s->n_avg)
			{
				s->phase_val = s->acc / s->n_avg;
				s->ready = 1;
				s->acc = 0;
				s->avg_count = 0;
			}

		}

		s->tag_b = s->tag_a = -1;
  }

	return SPLL_LOCKING;
}
