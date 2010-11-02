SRCS_VHDL = platform_specific.vhd \
alt_clock_divider.vhd \
generic_async_fifo_2stage.vhd \
generic_clock_mux3.vhd \
generic_pipelined_multiplier.vhd \
generic_ssram_dualport.vhd \
generic_sync_fifo.vhd \
generic_ssram_dualport_singleclock.vhd \
generic_ssram_dp_rw_rw.vhd

WORK = work

include ../../scripts/modules.mk
