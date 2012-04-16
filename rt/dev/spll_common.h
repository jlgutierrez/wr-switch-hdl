/*

White Rabbit Softcore PLL (SoftPLL) - common definitions

Copyright (c) 2010 - 2012 CERN / BE-CO-HT (Tomasz Włostowski)
Licensed under LGPL 2.1.

spll_common.h - common data structures and functions

*/


/* Number of reference/output channels. Currently we support only one SoftPLL instantiation per project,
   so these can remain static. */
static int n_chan_ref, n_chan_out;

/* PI regulator state */
typedef struct {
  	int ki, kp; 			/* integral and proportional gains (1<<PI_FRACBITS == 1.0f) */
  	int integrator;		/* current integrator value */
  	int bias;					/* DC offset always added to the output */
		int anti_windup;	/* when non-zero, anti-windup is enabled */
		int y_min;				/* min/max output range, used by clapming and antiwindup algorithms */
		int y_max;			
		int x, y;         /* Current input (x) and output value (y) */
} spll_pi_t;

/* lock detector state */
typedef struct {
  	int lock_cnt; 			/* Lock sample counter */
  	int lock_samples;   /* Number of samples below the (threshold) to assume that we are locked */
  	int delock_samples; /* Accumulated number of samples that causes the PLL go get out of lock.
  												delock_samples < lock_samples.  */
  	int threshold; 			/* Error threshold */
  	int locked;					/* Non-zero: we are locked */
} spll_lock_det_t;

/* simple, 1st-order lowpass filter */
typedef struct {
		int alpha;
		int y_d;
} spll_lowpass_t;

/* Processes a single sample (x) with PI control algorithm (pi). Returns the value (y) to 
	 drive the actuator. */
static inline int pi_update(spll_pi_t *pi, int x)
{
	int i_new, y;
	pi->x = x;
	i_new = pi->integrator + x;
	
	y = ((i_new * pi->ki + x * pi->kp) >> PI_FRACBITS) + pi->bias;
	
	/* clamping (output has to be in <y_min, y_max>) and anti-windup:
	   stop the integrator if the output is already out of range and the output
	   is going further away from y_min/y_max. */
    if(y < pi->y_min)
    {
       	y = pi->y_min;
       	if((pi->anti_windup && (i_new > pi->integrator)) || !pi->anti_windup)
       		pi->integrator = i_new;
		} else if (y > pi->y_max) {
       	y = pi->y_max;
      	if((pi->anti_windup && (i_new < pi->integrator)) || !pi->anti_windup)
       		pi->integrator = i_new;
		} else /* No antiwindup/clamping? */
			pi->integrator = i_new;

    pi->y = y;
    return y;   
}

/* initializes the PI controller state. Currently almost a stub. */
static inline void pi_init(spll_pi_t *pi)
{
 	pi->integrator = 0;
}



/* Lock detector state machine. Takes an error sample (y) and checks if it's withing an acceptable range
   (i.e. <-ld.threshold, ld.threshold>. If it has been inside the range for (ld.lock_samples) cyckes, the 
   FSM assumes the PLL is locked. 
   
   Return value:
   0: PLL not locked
   1: PLL locked
   -1: PLL just got out of lock
 */
static inline int ld_update(spll_lock_det_t *ld, int y)
{
	if (abs(y) <= ld->threshold)
	{
		if(ld->lock_cnt < ld->lock_samples)
			ld->lock_cnt++;
		
		if(ld->lock_cnt == ld->lock_samples)
		{
			ld->locked = 1;
			return 1;
		}
	} else {
	 	if(ld->lock_cnt > ld->delock_samples)
	 		ld->lock_cnt--;
		
		if(ld->lock_cnt == ld->delock_samples)
		{
		 	ld->lock_cnt=  0;
		 	ld->locked = 0;
		 	return -1;
		}
	}
	return ld->locked;
}

static void ld_init(spll_lock_det_t *ld)
{
 	ld->locked = 0;
 	ld->lock_cnt = 0;
}

static void lowpass_init(spll_lowpass_t *lp, int alpha)
{
	lp->y_d = 0x80000000;
	lp->alpha = alpha;
}

static int lowpass_update(spll_lowpass_t *lp, int x)
{
	if(lp->y_d == 0x80000000)
	{
		lp->y_d = x;
		return x;
	} else {
		int scaled = (lp->alpha * (x - lp->y_d)) >> 15;
		lp->y_d = lp->y_d + (scaled >> 1) + (scaled & 1);
		return lp->y_d;
	}
}


/* Enables/disables DDMTD tag generation on a given (channel). 

Channels (0 ... n_chan_ref - 1) are the reference channels 	(e.g. transceivers' RX clocks 
	or a local reference)

Channels (n_chan_ref ... n_chan_out + n_chan_ref-1) are the output channels (local voltage 
	controlled oscillators). One output (usually the first one) is always used to drive the 
	oscillator which produces the reference clock for the transceiver. Other outputs can be
	used to discipline external oscillators (e.g. on FMCs). 
	
*/

static void spll_enable_tagger(int channel, int enable)
{
	if(channel >= n_chan_ref) /* Output channel? */
	{
		if(enable)
			SPLL->OCER |= 1<< (channel - n_chan_ref);
		else
			SPLL->OCER &= ~ (1<< (channel - n_chan_ref));
	} else { /* Reference channel */
		if(enable)
			SPLL->RCER |= 1<<channel;
		else
			SPLL->RCER &= ~ (1<<channel);
	}

//	TRACE("%s: ch %d, OCER 0x%x, RCER 0x%x\n", __FUNCTION__, channel, SPLL->OCER, SPLL->RCER);
}
