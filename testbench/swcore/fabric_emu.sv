/*
 
 White Rabbit endpoint fabric interface BFM/emulator
 
*/

`include "fabric_emu_defs.sv"
`include "fabric_emu_funcs.sv"

module fabric_emu
  (

// fabric clock & reset   
   input clk_i,
   input rst_n_i,

//////////////////////////////////////////////////////////////////////////////
// Fabric output (source)
//////////////////////////////////////////////////////////////////////////////

   `WRF_FULL_PORTS_SOURCE(rx),
   
//////////////////////////////////////////////////////////////////////////////
// Fabric input (sink)
//////////////////////////////////////////////////////////////////////////////

   `WRF_FULL_PORTS_SINK(tx),   

/////////////////////////////////////////////////////////////////////////
// Endpoint TXTSU emulation. See wrsw_endpoint.vhd for signal details ///
/////////////////////////////////////////////////////////////////////////

    input [4:0] txtsu_port_id_i,
    input [15:0] txtsu_fid_i,
    input [31:0] txtsu_tsval_i,
    input txtsu_valid_i,
    output txtsu_ack_o
);

   // max. number of packet in TX/RX queues
   parameter g_QUEUE_SIZE  = 128;

   // packet queues holding TXed and RXed packets
   CPacketQueue tx_queue, rx_queue;

   typedef struct  {
      bit sim_tx_underrun;
      bit sim_tx_abort;
      bit sim_rx_abort;
      bit sim_tx_error;
      bit sim_rx_error;
      bit sim_rx_throttle;
      bit sim_tx_throttle;

      int tx_underrun_delay;
      int tx_abort_delay;
      int rx_abort_delay;
      int tx_error_delay;
      int rx_error_delay;
      int rx_throttle_prob; // throttle event probability (0 = never, 100 = always - stalled WRF)
      int tx_throttle_prob; 
   } _settings_t ;

   _settings_t SIM;
   
   reg txtsu_ack_int;
   int rx_gen_oob      = 1;
   int ready 	       = 0;


// output regs
   reg [15:0] irx_data_o;
   reg [4:0] irx_ctrl_o;
   reg irx_bytesel_o;
   reg irx_sof_p1_o;
   reg irx_eof_p1_o;
   reg irx_valid_o;
   reg irx_rerror_p1_o;
   reg irx_idle_o;
   reg irx_tabort_p1_o;

   reg itx_dreq_o;
   reg itx_terror_p1_o;
   reg itx_rabort_p1_o;
   
   
   assign rx_data_o 	  = irx_data_o;
   assign rx_ctrl_o 	  = irx_ctrl_o;
   assign rx_bytesel_o 	  = irx_bytesel_o;
   assign rx_sof_p1_o 	  = irx_sof_p1_o;
   assign rx_eof_p1_o 	  = irx_eof_p1_o;
   assign rx_valid_o 	  = irx_valid_o;
   assign rx_rerror_p1_o  = irx_rerror_p1_o;
   assign rx_idle_o 	  = irx_idle_o;
   assign rx_tabort_p1_o  = irx_tabort_p1_o;

   assign tx_dreq_o 	  = itx_dreq_o;
   assign tx_terror_p1_o  = itx_terror_p1_o;
   assign tx_rabort_p1_o  = itx_rabort_p1_o;
  

   
   
// monitor the reset line and initialize the fabric I/F when reset is active
   always@(posedge clk_i) 
     if(!rst_n_i) begin
	ready 		  = 0;

	// reset WRF source signals
	irx_data_o 	 <= 16'hxxxx;
	irx_ctrl_o 	 <= 4'hx;
	irx_bytesel_o 	 <= 1'bx;
      
	irx_sof_p1_o 	 <= 0;
	irx_eof_p1_o 	 <= 0;
	irx_valid_o 	 <= 0;
	irx_rerror_p1_o 	 <= 0;
	irx_tabort_p1_o  <= 0;

	// reset WRF sink signals
	itx_dreq_o 	 <= 1;
	itx_terror_p1_o  <= 0;
	itx_rabort_p1_o  <= 0;
	
	tx_queue 	  = new (g_QUEUE_SIZE);
	rx_queue 	  = new (g_QUEUE_SIZE);
	
	txtsu_ack_int 	 <= 0;
	
	wait_clk();
	wait_clk();
	
	ready  = 1;
     end

   // waits for 1 fabric clock cycle  
   task wait_clk;
      @(posedge clk_i);
   endtask // wait_clk
   

   // returns 1 with probability (prob/max_prob)
   function automatic int probability_hit(int prob, int max_prob);
     int rand_val;
      rand_val 	= $random % (max_prob+1);
      if(rand_val < 0) rand_val = -rand_val;

      if(rand_val < prob) 
	return 1;
      else
	return 0;
   endfunction // probability_hit
   
   
   // enables/disables RX fabric (data source) flow throttling. prob parameter defines the probability (0-100)
   // of throttle events
   task simulate_rx_throttling(input enable, int prob);
      SIM.sim_rx_throttle   = enable;
      SIM.rx_throttle_prob  = prob;
   endtask // simulate_tx_throttling

   // the same for TX fabric (data sink)
   task simulate_tx_throttling(input enable, int prob);
      SIM.sim_tx_throttle   = enable;
      SIM.tx_throttle_prob  = prob;
   endtask // simulate_tx_throttling

   // enables TX fabric source underrun simulation. When enabled, the fabric emulator will stop
   // transmitting the data after un_delay transmitted, causing an underrun error in the endopoint.
   task simulate_tx_underrun(input enable, input [31:0] un_delay);
      SIM.sim_tx_underrun    = enable;
      SIM.tx_underrun_delay  = un_delay;
   endtask // simulate_tx_underrun

   // Simulates an abort on data source after delay outputted words
   task simulate_rx_abort(input enable, input [31:0] delay);
      SIM.sim_rx_abort = enable;
      SIM.rx_abort_delay = delay;
   endtask 
   
   task simulate_tx_abort(input enable, input[31:0] delay);
      SIM.sim_tx_abort = enable;
      SIM.tx_abort_delay = delay;
   endtask 

   task simulate_rx_error(input enable, input [31:0] delay);
      SIM.sim_rx_error = enable;
      SIM.rx_error_delay = delay;
   endtask 
   
   task simulate_tx_error(input enable, input[31:0] delay);
      SIM.sim_tx_error = enable;
      SIM.tx_error_delay = delay;
   endtask 

// low-level packet send function: spits out tot_len data_vec[] and ctrl_vec[] values onto the WRF, simulating various error/abort/throttling conditions. Do not call directly.
   task send_fabric(input [15:0] data_vec[], 
		     input [3:0] ctrl_vec[], 
		     input int odd_len, 
		     input int tot_len, 
		     input int single_idx, 
		     output int error);
      int i;
      int rand_val;
      
      i	 = 0;
      error  = 0;

// wait untile the remote side wants some data from us      
      while(!rx_dreq_i) wait_clk();
      

// generate a single-cycle pulse on SOF_P1
      irx_valid_o <= 0;
      irx_sof_p1_o 	  <= 1;		
      wait_clk();
      irx_sof_p1_o <= 0;
           
      while(i<tot_len) begin

	 // simulate TX abort condition
	 if(SIM.sim_tx_abort && i == SIM.tx_abort_delay) begin
	    irx_valid_o 	 <= 0;
	    irx_tabort_p1_o <= 1;
	    wait_clk();
	    irx_tabort_p1_o <= 0;
	    wait_clk();
	    return;
	 end
	 
	 // simulate TX (source-orginating) error
	 if(SIM.sim_tx_error && i == SIM.tx_error_delay) begin
	    irx_rerror_p1_o <= 1;
	    wait_clk();
	    irx_valid_o  <= 0;
	    irx_rerror_p1_o <= 0;
	    wait_clk();
	    return;
	    end

	 // packet sink requested transfer abort
	 if(rx_rabort_p1_i) begin
	    irx_valid_o     <= 0;
	    irx_sof_p1_o    <= 0;
	    irx_eof_p1_o    <= 0;
	    irx_tabort_p1_o <= 0;
	    error 	     = 1;
	    return;
	 end

	 // simulate TX buffer underrun
	 if(!rx_dreq_i || (SIM.sim_tx_underrun && (i >= SIM.tx_underrun_delay)))  begin
	    wait_clk();
	    continue;
	    
	 // simulate TX flow throttling
	 end else if(SIM.sim_tx_throttle && probability_hit(SIM.tx_throttle_prob, 100)) begin
	    irx_valid_o <= 0;
	    wait_clk();
	    continue;

	 // no errors and nothing to mimick? just send the frame...
	 end else begin
	    irx_valid_o   <= 1;
	    irx_data_o 	  <= data_vec[i];
	    irx_ctrl_o 	  <= ctrl_vec[i];

	    irx_bytesel_o  <= (single_idx == i && odd_len);

	    if(i == tot_len -1) begin
	       irx_eof_p1_o <= 1;
	       wait_clk();
	       irx_valid_o  <= 0;
	       
	       irx_eof_p1_o <= 0;
	    end
	    i++;
	 end

	 wait_clk();	 
	 irx_valid_o <= 0;
      end // while (i<tot_len)

/* -----\/----- EXCLUDED -----\/-----
      while(rx_dreq_i) begin
	 if(irx_rerror_p1_i) begin
	    error  = 1;
	    
	    $display("fabric_emu::send(): RX error during gap");
	    irx_valid_o 	 <= 0;
	    irx_sof_p1_o 	 <= 0;
	    irx_eof_p1_o 	 <= 0;
	    irx_tabort_p1_o <= 0;
	    return;
	 end
	 wait_clk();
      end
 -----/\----- EXCLUDED -----/\----- */
      
   endtask // _send_fabric

// Main send function. inputs a frame with ethernet header hdr and a payload (without FCS)
// of length "length"
   task send(input ether_header_t hdr, input int payload[], input int length);
      
      reg [`c_wrsw_ctrl_size - 1 : 0] ctrl_vec[0:2000];
      reg [15:0] data_vec[0:2000];
      reg [31:0] fcs_val;
      int i;
      int tot_len;
      int odd_len;
      int single_idx;
      int error;
      
      CCRC32 crc_gen;
      ether_frame_t frame;

      if(!ready) begin
	$error("Attempt to call fabric_emu::send() when the emulator is being reset");
	return;
      end

      
//     $display("Endpoint::send %s [%d bytes]", format_ether_header(hdr), length);

      ctrl_vec[0] 		= `c_wrsw_ctrl_dst_mac; data_vec [0] = hdr.dst[47:32];
      ctrl_vec[1] 		= `c_wrsw_ctrl_dst_mac; data_vec [1] = hdr.dst[31:16];
      ctrl_vec[2] 		= `c_wrsw_ctrl_dst_mac; data_vec [2] = hdr.dst[15:0];


      if(!hdr.no_mac) begin
	 ctrl_vec[3] 		= `c_wrsw_ctrl_src_mac; data_vec [3] = hdr.src[47:32];
	 ctrl_vec[4] 		= `c_wrsw_ctrl_src_mac; data_vec [4] = hdr.src[31:16];
	 ctrl_vec[5] 		= `c_wrsw_ctrl_src_mac; data_vec [5] = hdr.src[15:0];
      end else begin
	 ctrl_vec[3] 		= `c_wrsw_ctrl_none; data_vec [3] = 0;
	 ctrl_vec[4] 		= `c_wrsw_ctrl_none; data_vec [4] = 0;
	 ctrl_vec[5] 		= `c_wrsw_ctrl_none; data_vec [5] = 0;
      end
      
      if(hdr.is_802_1q) begin
	 ctrl_vec[6] 		= `c_wrsw_ctrl_none; data_vec[6] = 'h8100;
	 ctrl_vec[7] 		= `c_wrsw_ctrl_ethertype; data_vec[7] = hdr.ethertype;
	 ctrl_vec[8] 		= `c_wrsw_ctrl_vid_prio; data_vec[8] = hdr.vid | (hdr.prio << 13);
	 tot_len 		= 9;
	 
      end else begin
	 ctrl_vec[6] 		= `c_wrsw_ctrl_ethertype; data_vec[6] = hdr.ethertype;
	 tot_len 		= 7;
      end

      for(int i = 0; i<(length+1) / 2; i++)
      begin
	 data_vec[tot_len + i] 	= (payload[i*2] << 8) | payload[i*2+1];
	 ctrl_vec[tot_len + i] 	= `c_wrsw_ctrl_payload;
      end

      tot_len 			= tot_len + (length + 1) / 2;
      odd_len 			= (length & 1);

      single_idx 		= tot_len-1;
      
      crc_gen 			= new;

      for(int i = 0; i< tot_len; i++)
	crc_gen.update(data_vec[i], (i==single_idx && odd_len ? 1 : 0));

      fcs_val 			= crc_gen.get();

      // insert the OOB (if applicable)
      if(hdr.oob_type == `OOB_TYPE_TXTS) begin
	 if(hdr.oob_fid == 0)
	   hdr.oob_fid 		= $random;
	 
	 data_vec[tot_len] 	= hdr.oob_fid;
	 
	 ctrl_vec[tot_len] 	= `c_wrsw_ctrl_tx_oob;
	 tot_len ++;
      end else if (hdr.oob_type == `OOB_TYPE_RXTS) begin
	 bit[47:0] oob_data;

	 oob_data  = 0;
	 oob_data[32+4:32] = hdr.port_id;
	 oob_data[31:28] = hdr.timestamp_f;
	 oob_data[27:0] = hdr.timestamp_r;

	 data_vec[tot_len]  = oob_data[47:32]; ctrl_vec[tot_len] = `c_wrsw_ctrl_rx_oob; tot_len++;
	 data_vec[tot_len]  = oob_data[31:16]; ctrl_vec[tot_len] = `c_wrsw_ctrl_rx_oob; tot_len++;
	 data_vec[tot_len]  = oob_data[16:0]; ctrl_vec[tot_len] = `c_wrsw_ctrl_rx_oob; tot_len++;
	 
      end
      
      frame.error 	    = 0;
      frame.hdr 	    = hdr;
      frame.hdr.has_timestamp   = 0;
      frame.fcs 	    = fcs_val;
      for(i=0;i<length;i++)
	frame.payload[i]    = payload[i];
      
      frame.size 	    = length;

// generate the frame on the TX fabric
      send_fabric(data_vec, ctrl_vec, odd_len, tot_len, single_idx, error);

      frame.error  = error;
      
      tx_queue.push(frame);
   endtask // send

   // Handles WRF packet sink input
   task automatic rx_process();

      reg [`c_wrsw_ctrl_size - 1 : 0] ctrl_vec[0:2000];
      reg [15:0] data_vec[0:2000];
      int bytesel_saved;
      ether_frame_t frame;
      int error;
      int rand_val;
      
      int i, data_start, tot_len, payload_len;

      i 	     = 0;
      bytesel_saved  = 0;
      
      wait_clk();

      while(1) begin //while(!tx_eof_p1_i && !tx_rerror_p1_i) begin

	 // simulate the flow throttling	 
	 if(SIM.sim_rx_throttle && probability_hit(SIM.rx_throttle_prob, 100))
	   itx_dreq_o <= 0;
	 else
	   itx_dreq_o <= 1;

	 // simulate the RX abort
	 if(SIM.sim_rx_abort && i >= SIM.rx_abort_delay)
	   begin
	      itx_rabort_p1_o <= 1;
	      wait_clk();
	      itx_rabort_p1_o <= 0;
	      return;
	      end
	 
	 // got a valid data word? Put it in the buffer
	 if(tx_valid_i) begin
	    ctrl_vec[i]  = tx_ctrl_i;
	    data_vec[i]  = tx_data_i;
	 //   $display("tx_data_i %x", tx_data_i);
	    
	    if(tx_bytesel_i && tx_ctrl_i == `c_wrsw_ctrl_payload) bytesel_saved 	= 1;
	    i++;
	 end
      
      if(tx_eof_p1_i || tx_rerror_p1_i) break;
      
	 wait_clk();
      end

      error    = tx_rerror_p1_i;
      tot_len  = i;
      
      frame.hdr.dst[47:32] = data_vec[0];
      frame.hdr.dst[31:16] = data_vec[1];
      frame.hdr.dst[15:0] = data_vec[2];

      frame.hdr.src[47:32] = data_vec[3];
      frame.hdr.src[31:16] = data_vec[4];
      frame.hdr.src[15:0] = data_vec[5];

      if(data_vec[6] == 16'h8100) begin // 802.1q header
	 frame.hdr.is_802_1q 	 = 1;
	 frame.hdr.ethertype 	 = data_vec[7];
	 frame.hdr.vid 		 = data_vec[8] & 16'h0fff;
	 frame.hdr.prio 	 = (data_vec[8] >> 13);
	 data_start 		 = 9;
      end else begin
     	 frame.hdr.is_802_1q 	 = 0;
	 frame.hdr.ethertype 	 = data_vec[6];
	 data_start 		 = 7;
      end

      payload_len 		 = 0;
      
      for(i=0; ctrl_vec[data_start + i] == `c_wrsw_ctrl_payload && i < tot_len; i++)
	begin
	   frame.payload[2*i] 	 = data_vec[data_start + i][15:8];
	   frame.payload[2*i+1]  = data_vec[data_start + i][7:0];
	   payload_len = payload_len + 2;
	end

      if(bytesel_saved)
	payload_len --;
      

      
      if(tot_len > i && ctrl_vec[data_start + i] == `c_wrsw_ctrl_rx_oob) begin
	 frame.hdr.has_timestamp  = 1;
	 frame.hdr.port_id 	      = data_vec[data_start+i][15:11];
	 frame.hdr.timestamp_r    = {data_vec[data_start+i+1][11:0],data_vec[data_start+i+2]} ;
	 frame.hdr.timestamp_f    = data_vec[data_start+i+1][15:12];
      end
      frame.size 	      = payload_len;
      frame.error 	      = error;

     // dump_frame_header("RX: ", frame);
      rx_queue.push(frame);
      
      
   endtask // rx_process

   task emulate_txtsu();
      if(txtsu_valid_i && !txtsu_ack_int) begin

	 if(tx_queue.update_tx_timestamp( txtsu_fid_i, txtsu_port_id_i,txtsu_tsval_i))
//	   $display("emulate_txtsu(): got TX timestamp for FID: 0x%04x", txtsu_fid_i);
	   
	 wait_clk();
	 txtsu_ack_int <= 1;
      end else
	txtsu_ack_int  <= 0;
      
   endtask // sim_txtsu
   
   initial forever begin
      itx_dreq_o <= 1;
      wait_clk();
      if(tx_sof_p1_i) rx_process();
   end

   initial forever begin
      wait_clk();
      if(txtsu_valid_i) emulate_txtsu();
      end
   assign txtsu_ack_o  = txtsu_ack_int;

   function int poll();
      if(!ready) return 0;
      return rx_queue.get_count();
   endfunction // UNMATCHED !!

   task automatic receive(output ether_frame_t fra);
      rx_queue.pop(fra);
   endtask
   
   
endmodule 

   