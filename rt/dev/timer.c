#include "board.h"

#include "timer.h"

uint32_t timer_get_tics()
{
  return *(volatile uint32_t *) (BASE_TIMER);
}

void timer_delay(uint32_t how_long)
{
  uint32_t t_start;

  t_start = timer_get_tics();

	if(t_start + how_long < t_start)
		while(t_start + how_long < timer_get_tics());

	while(t_start + how_long > timer_get_tics());
}
