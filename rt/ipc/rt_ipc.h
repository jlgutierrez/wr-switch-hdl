#include <stdint.h>

#define RTS_PLL_CHANNELS 32

/* Individual channel flags */
/* Reference input frequency valid */
#define CHAN_REF_VALID (1<<0)
/* Frequency out of range */
#define CHAN_FREQ_OUT_OF_RANGE (1<<1)
/* Phase is drifting too fast */
#define CHAN_DRIFTING (1<<2)

#define LOCK_DISABLED -1


/* DMTD clock is present */
#define RTS_DMTD_LOCKED (1<<0)

/* 125 MHz reference locked */
#define RTS_REF_LOCKED (1<<1)

/* External 10 MHz reference present */
#define RTS_EXT_10M_VALID (1<<2)

/* External 1-PPS present */
#define RTS_EXT_PPS_VALID (1<<3)

/* External 10 MHz frequency out-of-range */
#define RTS_EXT_10M_OUT_OF_RANGE (1<<4)

/* External 1-PPS frequency out-of-range */
#define RTS_EXT_PPS_OUT_OF_RANGE (1<<5)

/* Holdover mode active */
#define RTS_HOLDOVER_ACTIVE (1<<6)

/* Grandmaster mode active (uses 10 MHz / 1-PPS reference) */
#define RTS_MODE_GRANDMASTER (1<<7)

/* Boundary clock mode active (uses network reference) */
#define RTS_MODE_BC (1<<8)

/* When set, phase_loopback contains a valid phase measurement */
#define RTS_LOOPBACK_PHASE_READY (1<<9)

/* null reference input */
#define REF_NONE 255


struct rts_pll_state {

/* State of an individual input channel (i.e. switch port) */
	struct channel {
		/* Switchover priority: 0 = highest, 1 - 254 = high..low, 255 = channel disabled (a master port) */
		uint32_t priority; 
		/* channel phase setpoint in picoseconds << 16. Used only when channel is a slave. */
		int32_t phase_setpoint; 
		/* TX-RX Loopback phase measurement in picoseconds << 16. */
		int32_t phase_looback;
		/* flags (per channel - see CHAN_xxx defines) */
		uint32_t flags; 
	} channels[RTS_PLL_CHANNELS];

	/* flags (global - RTS_xxx defines) */	
	uint32_t flags; 

	/* duration of current holdover period in 10us units */
	int32_t holdover_duration;
	
	/* current reference source - or REF_NONE if free-running or grandmaster */
	uint32_t current_ref;
};

/* API */

/* Queries the RT CPU PLL state */
int rts_get_state(struct rts_pll_state *state);

/* Sets the phase setpoint on a given channel */
int rts_adjust_phase(uint8_t channel, int32_t phase_setpoint);

/* Sets the RT subsystem mode (Boundary Clock or Grandmaster) */
int rts_set_mode(uint32_t mode);

/* Reference channel configuration (BC mode only) */
int rts_lock_channel(uint32_t channel, int32_t priority);
