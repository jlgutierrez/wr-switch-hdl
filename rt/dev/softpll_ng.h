#ifndef __SOFTPLL_NG_H
#define __SOFTPLL_NG_H

#include <stdio.h>
#include <stdlib.h>

/* Modes */
#define SPLL_MODE_GRAND_MASTER 1
#define SPLL_MODE_FREE_RUNNING_MASTER 2
#define SPLL_MODE_SLAVE 3
#define SPLL_MODE_DISABLED 4


void spll_init(int mode, int slave_ref_channel, int align_pps);
void spll_shutdown();
void spll_start_channel(int channel);
void spll_stop_channel(int channel);
int spll_check_lock(int channel);
void spll_set_phase_shift(int channel, int32_t value_picoseconds);
void spll_get_phase_shift(int channel, int32_t *current, int32_t *target);
int spll_read_ptracker(int channel, int32_t *phase_ps, int *enabled);
void spll_get_num_channels(int *n_ref, int *n_out);
int spll_shifter_busy(int channel);
int spll_get_delock_count();

#endif

