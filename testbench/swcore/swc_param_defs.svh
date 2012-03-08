`ifndef __SWC_PARAM_DEFS_SV
`define __SWC_PARAM_DEFS_SV

/******************** port number ****************************** 
 * here you can define the number of ports of the swcore.
 * It affects both: testbench and DUT !
 * It means that the DUT will be configured to the set number of
 * ports and testbench will be adapted to handle this number of 
 * ports
 * 
 * REMARKS:
 * 1) Currently, the testbench implementation is not fully generic
 *    (this is on the TODO list). this means that you need to 
 *    modify appropriately :
 *    function initPckSrcAndSink() in swc_core_generic.sv
 *    
 * 2) The max possible number of ports (which works) is 16, this
 *    is caused by the limitation of the *swc_prio_encoder*.
 *    This bug can be easily fixed, but the swcore will be deeply
 *    re-done very soon, so there is no use to do it before.
 * 
 */
////////////////////////////////////////////////////////////////
`define  c_num_ports                         16 //MAX: 16     //
////////////////////////////////////////////////////////////////

`define  c_prio_num                          8                // c_swc_output_prio_num, [does not work, output block]
`define  c_max_pck_size                      10 * 1024        // 10kB -- c_swc_max_pck_size,
`define  c_max_oob_size                      3                // max size of OOB or USER data

`define  c_mpm_mem_size                      65536            //c_swc_packet_mem_size,
`define  c_mpm_page_size                     64               //c_swc_page_size,
`define  c_mpm_ratio                         2
`define  c_mpm_fifo_size                     4
`define  c_mpm_fetch_next_pg_in_advance      0

// these are hard-coded into testbench
`define  c_wb_data_width                     16               //c_swc_data_width,
`define  c_wb_addr_width                     2                //
`define  c_wb_sel_width                      2                //
`define  c_wb_ob_ignore_ack                  0            //

`define  c_pck_pg_free_fifo_size            ((65536/64)/2)    //c_swc_freeing_fifo_size,
`define  c_input_block_cannot_accept_data    "drop_pck"       //"stall_o", "rty_o" -- (xswc_input_block) Don't CHANGE !
`define  c_output_block_per_prio_fifo_size   64               //c_swc_output_fifo_size,

`define array_copy(a, ah, al, b, bl) \
   for (k=al; k<=ah; k=k+1) a[k] <= b[bl+k-al];

`define c_prio_num_width                    3

`endif