#ifndef __DEFS_H
#define __DEFS_H

#include <stdint.h>

static inline void writel(uint32_t data, void *where)
{
	* (volatile uint32_t *)where = data;
}

static inline uint32_t readl(void *where)
{
	return * (volatile uint32_t *)where;
}


#endif
