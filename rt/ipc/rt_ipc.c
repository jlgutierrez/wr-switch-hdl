/*
 * Mini-ipc: an example freestanding server, based in memory
 *
 * Copyright (C) 2011,2012 CERN (www.cern.ch)
 * Author: Alessandro Rubini <rubini@gnudd.com>
 *
 * This code is copied from trivial-server, and made even more trivial
 */

#include <string.h>
#include <errno.h>
#include <sys/types.h>

#include "minipc.h"

#define RTIPC_EXPORT_STRUCTURES
#include "rt_ipc.h"

#include <softpll_ng.h>

static struct rts_pll_state pstate;

static void clear_state()
{
	int i;
	for(i=0;i<RTS_PLL_CHANNELS;i++)
	{
	    pstate.channels[i].priority = 0;
	    pstate.channels[i].phase_setpoint = 0;
	    pstate.channels[i].phase_loopback = 0;
	    pstate.channels[i].flags = CHAN_REF_VALID;
    }
    pstate.flags = 0;
    pstate.current_ref = 0;
    pstate.mode = RTS_MODE_DISABLED;
}

/* Sets the phase setpoint on a given channel */
int rts_adjust_phase(int channel, int32_t phase_setpoint)
{
//    TRACE("Adjusting phase: ref channel %d, setpoint=%d ps.\n", channel, phase_setpoint);
    spll_set_phase_shift(0, phase_setpoint);
    pstate.channels[channel].phase_setpoint = phase_setpoint;
    return 0;
}

/* Sets the RT subsystem mode (Boundary Clock or Grandmaster) */
int rts_set_mode(int mode)
{
	int i;

	const struct {
		int mode_rt;
		int mode_spll;
		int do_init;
		char *desc;
	} options[] = {
		{ RTS_MODE_GM_EXTERNAL, SPLL_MODE_GRAND_MASTER, 1, "Grand Master (external clock)" },
		{ RTS_MODE_GM_FREERUNNING, SPLL_MODE_FREE_RUNNING_MASTER, 1, "Grand Master (free-running clock)" },
		{ RTS_MODE_BC, SPLL_MODE_SLAVE, 0, "Boundary Clock (slave)" },
		{ RTS_MODE_DISABLED, SPLL_MODE_DISABLED, 1, "PLL disabled" },
		{ 0,0,0, NULL }
	};

	pstate.mode = mode;

	for(i=0;options[i].desc != NULL;i++)
		if(mode == options[i].mode_rt)
		{
			TRACE("RT: Setting mode to %s.\n", options[i].desc);
			if(options[i].do_init)
				spll_init(options[i].mode_spll, 0, 1);
			else
				spll_init(SPLL_MODE_DISABLED, 0, 0);
		}

	return 0;
}

/* Reference channel configuration (BC mode only) */
int rts_lock_channel(int channel, int priority)
{
	if(pstate.mode != RTS_MODE_BC)
	{
        TRACE("trying to lock while not in slave mode,..\n");
		return -1;
    }


	TRACE("RT [slave]: Locking to: %d (prio %d)\n", channel, priority);
	spll_init(SPLL_MODE_SLAVE, channel, 0);
    pstate.current_ref = channel;

	return 0;
}

int rts_init()
{
    TRACE("Initializing the RT Subsystem...\n");
    clear_state();
}

void rts_update()
{
    int i;
    int n_ref;
		int enabled;
		
    spll_get_num_channels(&n_ref, NULL);

    pstate.flags = (spll_check_lock(0) ? RTS_DMTD_LOCKED | RTS_REF_LOCKED : 0);
    for(i=0;i<RTS_PLL_CHANNELS;i++)
    {
#define CH pstate.channels[i]
        CH.flags = 0;
        CH.phase_loopback = 0;
        CH.phase_current = 0;
//        CH.phase_setpoint = 0;
        CH.phase_loopback = 0;

        if(i >= n_ref)
            CH.flags = CHAN_DISABLED;
        else {
            if(i==pstate.current_ref)
            {
                spll_get_phase_shift(0, &CH.phase_current, NULL);
		            if(spll_shifter_busy(0))
		            	CH.flags |= CHAN_SHIFTING;
						}
            if(spll_read_ptracker(i, &CH.phase_loopback, &enabled))
	            CH.flags |= CHAN_PMEAS_READY;
	          
	          CH.flags |= (enabled ? CHAN_PTRACKER_ENABLED : 0);

        }

#undef CH
    }
}


/* fixme: this assumes the host is BE */
static int htonl(int i)
{
    return i;
}


static int rts_get_state_func(const struct minipc_pd *pd, uint32_t *args, void *ret)
{
    struct rts_pll_state *tmp = (struct rts_pll_state *)ret;
    int i;

//    TRACE("IPC Call: %s [rv at %x]\n", __FUNCTION__, ret);

    /* gaaaah, somebody should write a SWIG plugin for generating this stuff. */
    tmp->current_ref = htonl(pstate.current_ref);
    tmp->flags = htonl(pstate.flags);
    tmp->holdover_duration = htonl(pstate.holdover_duration);
    tmp->mode = htonl(pstate.mode);
		tmp->delock_count = spll_get_delock_count();
		
    for(i=0; i<RTS_PLL_CHANNELS;i++)
    {
        tmp->channels[i].priority = htonl(pstate.channels[i].priority);
        tmp->channels[i].phase_setpoint = htonl(pstate.channels[i].phase_setpoint);
        tmp->channels[i].phase_current = htonl(pstate.channels[i].phase_current);
        tmp->channels[i].phase_loopback = htonl(pstate.channels[i].phase_loopback);
        tmp->channels[i].flags = htonl(pstate.channels[i].flags);
    }

    return 0;
}

static int rts_set_mode_func(const struct minipc_pd *pd, uint32_t *args, void *ret)
{
    *(int *) ret = rts_set_mode(args[0]);
}


static int rts_lock_channel_func(const struct minipc_pd *pd, uint32_t *args, void *ret)
{
    *(int *) ret = rts_lock_channel(args[0], (int)args[1]);
}

static int rts_adjust_phase_func(const struct minipc_pd *pd, uint32_t *args, void *ret)
{
    *(int *) ret = rts_adjust_phase((int)args[0], (int)args[1]);
}

static int rts_enable_ptracker_func(const struct minipc_pd *pd, uint32_t *args, void *ret)
{
    *(int *) ret = spll_enable_ptracker((int)args[0], (int)args[1]);
}



/* The mailbox is mapped at 0x7000 in the linker script */
static __attribute__((section(".mbox"))) _mailbox[1024];
static struct minipc_ch *server;

int rtipc_init()
{

	server = minipc_server_create("mem:7000", 0);
	if (!server)
		return 1;

	rtipc_rts_set_mode_struct.f = rts_set_mode_func;
	rtipc_rts_get_state_struct.f = rts_get_state_func;
	rtipc_rts_lock_channel_struct.f = rts_lock_channel_func;
	rtipc_rts_adjust_phase_struct.f = rts_adjust_phase_func;
	rtipc_rts_enable_ptracker_struct.f = rts_enable_ptracker_func;
	
	minipc_export(server, &rtipc_rts_set_mode_struct);
	minipc_export(server, &rtipc_rts_get_state_struct);
	minipc_export(server, &rtipc_rts_lock_channel_struct);
  minipc_export(server, &rtipc_rts_adjust_phase_struct);
  minipc_export(server, &rtipc_rts_enable_ptracker_struct);


	return 0;
}


void rtipc_action()
{
		minipc_server_action(server, 1000);
}
