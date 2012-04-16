#ifndef __SOFTPLL_NG_H
#define __SOFTPLL_NG_H

#include <stdio.h>
#include <stdlib.h>

/* Modes */
#define MODE_GRAND_MASTER 0
#define MODE_FREE_RUNNING_MASTER 1
#define MODE_SLAVE 2
#define MODE_DISABLED 3

void spll_init(int mode, int slave_ref_channel, int align_pps);

#endif
