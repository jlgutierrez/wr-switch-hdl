/*

White Rabbit Softcore PLL (SoftPLL) - common definitions

Copyright (c) 2010 - 2012 CERN / BE-CO-HT (Tomasz Włostowski)
Licensed under LGPL 2.1.

spll_debug.h - debugging/diagnostic interface

The so-called debug inteface is a large, interrupt-driven FIFO which passes
various realtime parameters (e.g. error value, tags, DAC drive) to an external
application where they are further analyzed. It's very useful for optimizing PI coefficients
and/or lock thresholds.

The data is organized as a stream of samples, where each sample can store a number of parameters.
For example, a stream samples with Y and ERR parameters can be used to evaluate the impact of
integral/proportional gains on the response of the system.

*/

#define DBG_Y 0
#define DBG_ERR 1
#define DBG_TAG 2
#define DBG_REF 5
#define DBG_PERIOD 3
#define DBG_EVENT 4
#define DBG_SAMPLE_ID 6

#define DBG_HELPER 0x20  /* Sample source: Helper PLL */
#define DBG_EXT 0x40     /* Sample source: External Reference PLL */
#define DBG_MAIN 0x0	   /* ...          : Main PLL */

#define DBG_EVT_START 1  /* PLL has just started */
#define DBG_EVT_LOCKED 2 /* PLL has just become locked */


/* Writes a parameter to the debug FIFO.

value: value of the parameter.
what: type of the parameter and its' source. For example, 
	- DBG_ERR | DBG_HELPER means that (value) contains the phase error of the helper PLL.
	- DBG_EVENT indicates an asynchronous event. (value) must contain the event type (DBG_EVT_xxx)

last: when non-zero, indicates the last parameter in a sample. 
*/

static inline void spll_debug(int what, int value, int last)
{
	SPLL->DFR_SPLL = (last ? 0x80000000 : 0) | (value & 0xffffff) | (what << 24);
}
