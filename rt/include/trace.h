#ifndef __FREESTANDING_TRACE_H__
#define __FREESTANDING_TRACE_H__

int mprintf(char const *format, ...);

#define TRACE(...) mprintf(__VA_ARGS__)

#endif
