/*

White Rabbit Softcore PLL (SoftPLL) - common definitions

*/

/* PI regulator state */
typedef struct {
  	int ki, kp; 		/* integral and proportional gains (1<<PI_FRACBITS == 1.0f) */
  	int integrator;		/* current integrator value */
  	int bias;			/* DC offset always added to the output */
		int anti_windup;	/* when non-zero, anti-windup is enabled */
		int y_min;			/* min/max output range, used by claming and antiwindup algorithms */
		int y_max;			
		int x,y;            /* Current input and output value */
} spll_pi_t;


/* Processes a single sample (x) using PI controller (pi). Returns the value (y) which should
   be used to drive the actuator. */
static inline int pi_update(spll_pi_t *pi, int x)
{
	int i_new, y;
	pi->x = x;
	i_new = pi->integrator + x;
	
	y = ((i_new * pi->ki + x * pi->kp) >> PI_FRACBITS) + pi->bias;
	
	/* clamping (output has to be in <y_min, y_max>) and anti-windup:
	   stop the integretor if the output is already out of range and the output
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
	} else
		pi->integrator = i_new;

    pi->y = y;
    return y;
   
}

/* initializes the PI controller state. Currently almost a stub. */
static inline void pi_init(spll_pi_t *pi)
{
 	pi->integrator = 0;
}

/* lock detector state */
typedef struct {
  	int lock_cnt;
  	int lock_samples;
  	int delock_samples;
  	int threshold;
  	int locked;
} spll_lock_det_t;


/* Lock detector state machine. Takes an error sample (y) and checks if it's withing an acceptable range
   (i.e. <-ld.threshold, ld.threshold>. If it has been inside the range for (ld.lock_samples) cyckes, the 
   FSM assumes the PLL is locked. */
static inline int ld_update(spll_lock_det_t *ld, int y)
{
	if (abs(y) <= ld->threshold)
	{
		if(ld->lock_cnt < ld->lock_samples)
			ld->lock_cnt++;
		
		if(ld->lock_cnt == ld->lock_samples)
			ld->locked = 1;
	} else {
	 	if(ld->lock_cnt > ld->delock_samples)
	 		ld->lock_cnt--;
		
		if(ld->lock_cnt == ld->delock_samples)
		{
		 	ld->lock_cnt=  0;
		 	ld->locked = 0;
		}
	}
	return ld->locked;
}

static void ld_init(spll_lock_det_t *ld)
{
 	ld->locked = 0;
 	ld->lock_cnt = 0;
}

#define DBG_Y 0
#define DBG_ERR 1
#define DBG_TAG 2
#define DBG_REF 5
#define DBG_PERIOD 3
#define DBG_EVENT 4
#define DBG_SAMPLE_ID 6

#define DBG_HELPER 0x20
#define DBG_PRELOCK 0x40
#define DBG_EVT_START 1
#define DBG_EVT_LOCKED 2

static inline void spll_debug(int what, int value, int last)
{
	SPLL->DFR_SPLL = (last ? 0x80000000 : 0) | (value & 0xffffff) | (what << 24);
}