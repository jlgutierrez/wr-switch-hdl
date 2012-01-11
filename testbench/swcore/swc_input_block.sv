// Fabric emulator example, showing 2 fabric emulators connected together and exchanging packets.

`define c_clock_period        8
`define c_swc_page_addr_width 10
`define c_swc_usecount_width  4 
`define c_wrsw_prio_width     3
`define c_swc_ctrl_width      4
`define c_swc_data_width      16
`define c_wrsw_num_ports      11


`timescale 1ns / 1ps

`include "fabric_emu.sv"






module main;



   
   
   reg clk 		       = 0;
   reg rst_n 		     = 0;

   //`WRF_WIRES(a_to_input_block); // Emu A to B fabric
   

   wire [15:0] a_to_input_block_data;
   wire [3 :0] a_to_input_block_ctrl;
   wire        a_to_input_block_bytesel;
   wire        a_to_input_block_dreq;
   wire        a_to_input_block_valid;
   wire        a_to_input_block_sof_p1;
   wire        a_to_input_block_eof_p1;
   wire        a_to_input_block_rerror_p1;

   wire [15:0] input_block_to_a_data;
   wire [3 :0] input_block_to_a_ctrl;
   wire        input_block_to_a_bytesel;
   wire        input_block_to_a_dreq;
   wire        input_block_to_a_valid;
   wire        input_block_to_a_sof_p1;
   wire        input_block_to_a_eof_p1;
   wire        input_block_to_a_rerror_p1;
  
   `WRF_WIRES(ab); // Emu A to B fabric
   `WRF_WIRES(ba); // And the other way around
   
  
   
   wire                                  mmu_page_alloc_req;
   reg                                   mmu_page_alloc_done  = 0;
   reg  [`c_swc_page_addr_width - 1 : 0] mmu_pageaddr_in      = 0;        
   wire [`c_swc_page_addr_width - 1 : 0] mmu_pageaddr_out;         
   wire                                  mmu_force_free;      
   wire                                  mmu_set_usecnt ;      
   reg                                   mmu_set_usecnt_done  = 0; 
   wire [`c_swc_usecount_width - 1 : 0]  mmu_usecnt;           
   
   reg                                   rtu_rsp_valid        = 0;     
   wire                                  rtu_rsp_ack;       
   reg  [`c_wrsw_num_ports - 1 : 0]      rtu_dst_port_mask    = 0; 
   reg                                   rtu_drop             = 0;          
   reg  [`c_wrsw_prio_width - 1 : 0]     rtu_prio             = 0;     
   
   wire                                  mpm_pckstart; 
   wire [`c_swc_page_addr_width - 1 : 0] mpm_pageaddr;
   reg                                   mpm_pageend          = 0;
   wire [`c_swc_data_width - 1 : 0]      mpm_data; 
   wire [`c_swc_ctrl_width - 1 : 0]      mpm_ctrl; 
   wire                                  mpm_drdy;
   reg                                   mpm_full             = 0;     
   wire                                  mpm_flush;
   
   wire                                  pta_transfer_pck; 
   wire [`c_swc_page_addr_width - 1 : 0] pta_pageaddr;    
   wire [`c_wrsw_num_ports  - 1 : 0]     pta_mask;         
   wire [`c_wrsw_prio_width - 1 : 0]     pta_prio; 
   
   // generate clock and reset signals
   always #(`c_clock_period/2) clk <= ~clk;
   
   initial begin 
      repeat(3) @(posedge clk);
      rst_n  = 1;
   end

   
   swc_input_block 
    DUT (
    .clk_i                 (clk),
    .rst_n_i               (rst_n),
//-------------------------------------------------------------------------------
//-- Fabric I/F  
//-------------------------------------------------------------------------------  
    `_WRF_CONNECT_MANDATORY_SINK      (tx, a_to_input_block),
    
//-------------------------------------------------------------------------------
//-- I/F with Page allocator (MMU)
//-------------------------------------------------------------------------------    
    .mmu_page_alloc_req_o  (mmu_page_alloc_req), 
    .mmu_page_alloc_done_i (mmu_page_alloc_done), 
    .mmu_pageaddr_i        (mmu_pageaddr_in), 
    .mmu_pageaddr_o        (mmu_pageaddr_out), 
    .mmu_force_free_o      (mmu_force_free), 
    .mmu_set_usecnt_o      (mmu_set_usecnt),  
    .mmu_set_usecnt_done_i (mmu_set_usecnt_done), 
    .mmu_usecnt_o          (mmu_usecnt),  
    
//-------------------------------------------------------------------------------
//-- I/F with Routing Table Unit (RTU)
//-------------------------------------------------------------------------------      
    
    .rtu_rsp_valid_i       (rtu_rsp_valid),
    .rtu_rsp_ack_o         (rtu_rsp_ack),
    .rtu_dst_port_mask_i   (rtu_dst_port_mask),
    .rtu_drop_i            (rtu_drop),
    .rtu_prio_i            (rtu_prio),  
    
//-------------------------------------------------------------------------------
//-- I/F with Multiport Memory (MPU)
//-------------------------------------------------------------------------------    
    .mpm_pckstart_o        (mpm_pckstart),
    .mpm_pageaddr_o        (mpm_pageaddr),
    .mpm_pageend_i         (mpm_pageend),
    .mpm_data_o            (mpm_data),
    .mpm_ctrl_o            (mpm_ctrl),
    .mpm_drdy_o            (mpm_drdy),
    .mpm_full_i            (mpm_full),
    .mpm_flush_o           (mpm_flush),

//-------------------------------------------------------------------------------
//-- I/F with Page Transfer Arbiter (PTA)
//-------------------------------------------------------------------------------     
    .pta_transfer_pck_o    (pta_transfer_pck),
    .pta_pageaddr_o        (pta_pageaddr),
    .pta_mask_o            (pta_mask),
    .pta_prio_o            (pta_prio)

    );
    
    task wait_cycles;
       input [31:0] ncycles;
       begin : wait_body
    integer i;
 
    for(i=0;i<ncycles;i=i+1) @(posedge clk);
 
       end
    endtask // wait_cycles
    


   fabric_emu test_input_block
     (
      .clk_i(clk),
      .rst_n_i(rst_n),
      `WRF_CONNECT_SOURCE(rx, a_to_input_block),
      `WRF_CONNECT_SINK(tx, input_block_to_a)
      
      );

   // Two fabric emulators talking to each other
   fabric_emu U_emuA
     (
      .clk_i(clk),
      .rst_n_i(rst_n),
      //`WRF_CONNECT_SOURCE(rx, a_to_input_block),
      `WRF_CONNECT_SOURCE(rx, ba), // connect fabric source/sinks
      `WRF_CONNECT_SINK(tx, ab)
      //`WRF_CONNECT_SINK(tx,a_to_input_block)
      );

   fabric_emu U_emuB
     (
      .clk_i(clk),
      .rst_n_i(rst_n),
      `WRF_CONNECT_SOURCE(rx, ab),
      `WRF_CONNECT_SINK(tx, ba)
      );

   
   initial begin
      ether_header_t hdr;
      int buffer[1024];
      int i;


      wait(U_emuA.ready); // wait until both emulators are initialized
      wait(U_emuB.ready);
      
      
      hdr.src 	       = 'h123456789abcdef;
      hdr.dst 	       = 'hcafeb1badeadbef;
      hdr.ethertype    = 1234;
      hdr.is_802_1q    = 0;
      hdr.oob_type     = `OOB_TYPE_RXTS;
      hdr.timestamp_r  = 10000;
      hdr.timestamp_f  = 4;
      hdr.port_id      = 5;
      


      rtu_dst_port_mask    = 6; 
      rtu_drop             = 0;          
      rtu_prio             = 2;
      
      
      for(i=0;i<100;i++)
	        buffer[i]      = i;


      // simulate some flow throttling
      U_emuA.simulate_rx_throttling(1, 50);
      

      U_emuA.send(hdr, buffer, 100);

      rtu_rsp_valid        = 1;     
      test_input_block.send(hdr, buffer, 100);
      rtu_rsp_valid        = 0;     
      //hdr.src  = 'h0f0e0a0b0d00;
      
      //U_emuB.send(hdr, buffer, 50);

      
   end


   // Check if there's anything received by EMU B
   always @(posedge clk) if (U_emuB.poll())
     begin
	ether_frame_t frame;
	$display("Emulator B received a frame!");

	U_emuB.receive(frame);
	dump_frame_header("EmuB RX: ", frame);
	
	
     end

   // Check if there's anything received by EMU A
   always @(posedge clk) if (U_emuA.poll())
     begin
	ether_frame_t frame;
	$display("Emulator A received a frame!");

	U_emuA.receive(frame);
	dump_frame_header("EmuA RX: ", frame);
	
	
     end
   
      
   


endmodule // main
