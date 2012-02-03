`ifndef __SWC_PARAM_DEFS_SV
`define __SWC_PARAM_DEFS_SV

`define  c_mem_size                          65536            //c_swc_packet_mem_size,
`define  c_page_size                         64               //c_swc_page_size,
`define  c_prio_num                          8                // c_swc_output_prio_num,
`define  c_max_pck_size                      10 * 1024        // 10kB -- c_swc_max_pck_size,
`define  c_num_ports                         7                //c_swc_num_ports,
`define  c_data_width                        16               //c_swc_data_width,
`define  c_ctrl_width                        4                //c_swc_ctrl_width,
`define  c_pck_pg_free_fifo_size            ((65536/64)/2)    //c_swc_freeing_fifo_size,
`define  c_input_block_cannot_accept_data    "drop_pck"       //"stall_o", "rty_o" -- (xswc_input_block) Don't CHANGE !
`define  c_output_block_per_prio_fifo_size   64               //c_swc_output_fifo_size,

`define  c_packet_mem_multiply               16               //c_swc_packet_mem_multiply,
`define  c_input_block_fifo_size             (2 * 16)         //c_swc_input_fifo_size,     
`define  c_input_block_fifo_full_in_advance ((2 * 16) - 3)    // c_swc_fifo_full_in_advance

`define array_copy(a, ah, al, b, bl) \
   for (k=al; k<=ah; k=k+1) a[k] <= b[bl+k-al];

`define c_prio_num_width                    3

`endif