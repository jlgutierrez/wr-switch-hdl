#ifndef __TIMER_H
#define __TIMER_H

#include "defs.h"

#define TICS_PER_SECOND 100000

uint32_t timer_get_tics();
void timer_delay(uint32_t how_long);
int timer_expired(uint32_t t_start, uint32_t how_long);

#endif
