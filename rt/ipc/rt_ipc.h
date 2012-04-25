#ifndef __RT_IPC_H
#define __RT_IPC_H

#include <stdint.h>

#define RTS_PLL_CHANNELS 18

/* Individual channel flags */
/* Reference input frequency valid */
#define CHAN_REF_VALID (1<<0)
/* Frequency out of range */
#define CHAN_FREQ_OUT_OF_RANGE (1<<1)
/* Phase is drifting too fast */
#define CHAN_DRIFTING (1<<2)
/* Channel phase measurement is ready */
#define CHAN_PMEAS_READY (1<<3)
/* Channel not available/disabled */
#define CHAN_DISABLED (1<<4)
/* Channel is busy adjusting phase */
#define CHAN_SHIFTING (1<<5)

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
#define RTS_MODE_GM_EXTERNAL 1

/* Free-running grandmaster (uses local TCXO) */
#define RTS_MODE_GM_FREERUNNING 2

/* Boundary clock mode active (uses network reference) */
#define RTS_MODE_BC 3

/* PLL disabled */
#define RTS_MODE_DISABLED 4

/* null reference input */
#define REF_NONE 255


struct rts_pll_state {

/* State of an individual input channel (i.e. switch port) */
	struct channel {
		/* Switchover priority: 0 = highest, 1 - 254 = high..low, 255 = channel disabled (a master port) */
		uint32_t priority;
		/* channel phase setpoint in picoseconds. Used only when channel is a slave. */
		int32_t phase_setpoint;
		/* current phase shift in picoseconds. Used only when channel is a slave. */
		int32_t phase_current;
		/* TX-RX Loopback phase measurement in picoseconds. */
		int32_t phase_loopback;
		/* flags (per channel - see CHAN_xxx defines) */
		uint32_t flags;
	} channels[RTS_PLL_CHANNELS];

	/* flags (global - RTS_xxx defines) */
	uint32_t flags;

	/* duration of current holdover period in 10us units */
	int32_t holdover_duration;

	/* current reference source - or REF_NONE if free-running or grandmaster */
	uint32_t current_ref;

	/* mode of operation (RTS_MODE_xxx) */
	uint32_t mode;
};

/* API */

/* Queries the RT CPU PLL state */
int rts_get_state(struct rts_pll_state *state);

/* Sets the phase setpoint on a given channel */
int rts_adjust_phase(int channel, int32_t phase_setpoint);

/* Sets the RT subsystem mode (Boundary Clock or Grandmaster) */
int rts_set_mode(int mode);

/* Reference channel configuration (BC mode only) */
int rts_lock_channel(int channel, int priority);


#endif
