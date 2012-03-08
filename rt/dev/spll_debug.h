#define DBG_Y 0
#define DBG_ERR 1
#define DBG_TAG 2
#define DBG_REF 5
#define DBG_PERIOD 3
#define DBG_EVENT 4
#define DBG_SAMPLE_ID 6

#define DBG_HELPER 0x20
#define DBG_PRELOCK 0x40
#define DBG_EVT_START 1
#define DBG_EVT_LOCKED 2

static inline void spll_debug(int what, int value, int last)
{
	SPLL->DFR_SPLL = (last ? 0x80000000 : 0) | (value & 0xffffff) | (what << 24);
}
