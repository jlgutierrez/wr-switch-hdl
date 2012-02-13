`timescale 1ns/1ns

`include "simdrv_defs.svh"
`include "eth_packet.svh"

`define DEFAULT_SWC_PARAMS  '{2048, 64, 2, 16, 11, 1, 8, 8, 10000};

typedef struct {
    int g_num_pages;
    int g_page_size;
    int g_ratio;
    int g_data_width;
    int g_page_address_width;
    int g_partial_select_width;
   int  g_num_ports;
   int  g_fifo_size;
   int  g_max_packet_size;
} t_swcore_parameters;

function automatic int clogb2;               
   input [31:0]  value;
   begin
      for (clogb2 = 0; value > 0; clogb2 = clogb2 + 1)
        value = value >> 1;
   end
endfunction // for

function automatic int probability_hit(int seed, real prob);
     real rand_val;
      rand_val 	= real'($dist_uniform(seed, 0, 1000)) / 1000.0;
      
      if(rand_val < prob)
	return 1;
      else
	return 0;
    
   endfunction // probability_hit

function automatic int count_ones(bit[31:0] x);
   int n = 0, i;
   for(i=0;i<32;i++)
     if(x[i]) n++;
   return n;
endfunction // count_ones

`include "IShadowFBM.svh"
`include "ILinkedList.svh"
`include "mpm_top_svwrap.svh"

/* 
 
 Multiport memory port interfaces 
 
 */

interface IMPMWritePort(clk, rst_n);
   parameter t_swcore_parameters P = `DEFAULT_SWC_PARAMS;
   
   logic [P.g_data_width-1:0] d;
   logic                      d_valid , d_last ;
   logic [P.g_page_address_width-1:0] pg_addr ;
   logic                              dreq;
   logic                              pg_req;
   input                              clk;
   input                              rst_n;
   

   /* Modport connected to the input block */
   modport at_iblock
     (
      output d, d_valid, d_last, pg_addr,
      input  dreq, pg_req
      );
   
endinterface // IMPMWritePort

interface IMPMReadPort(clk, rst_n);
   input     clk;
   input     rst_n;

   parameter t_swcore_parameters P = `DEFAULT_SWC_PARAMS;
   
   logic [P.g_data_width-1:0] d;
   logic [P.g_partial_select_width-1:0] d_sel;
   logic                                d_valid , d_last ;
   logic [P.g_page_address_width-1:0]   pg_addr ;
   logic                                dreq;
   logic                                pg_req, pg_valid;
   
   logic                                abort;

   modport at_oblock
     (
      input  d, d_valid, d_last, d_sel, pg_req,
      output pg_addr, pg_valid, abort
      );

endinterface // IMPMReadPort



/* Mockup of the real Page Transfer Arbiter */

class CPageTransferArb;

   typedef int page_queue_t [$];

   protected page_queue_t m_queues[];
   protected int m_num_ports;
   
   function new(int num_ports);
      m_num_ports = num_ports;
      m_queues = new[num_ports];
   endfunction // new

   task send(int page, int dest_mask);
      int i;
      
      for(i=0;i<m_num_ports;i++)
        if(dest_mask & (1<<i))
          begin
             $display("Send: page %d port %d", page, i);
             m_queues[i].push_back(page);
          end
      
   endtask // send
   
   function int    poll(int port);
      return m_queues[port].size() > 0;
   endfunction // poll
      
   function int recv(int port);
      return m_queues[port].pop_front();
   endfunction // recv

endclass // CPageTransferArb


class CInputBlockModel;

   virtual ILinkedList ll;
   virtual IMPMWritePort ib;
   virtual IShadowFBM fbm;

   CPageTransferArb pta;
   
   protected int m_cut_through;
   int     id;


   EthPacket sent_queue[$];
   
   
   function new(input virtual ILinkedList _ll,
                input virtual IMPMWritePort _wport,
                input virtual IShadowFBM _fbm, 
                CPageTransferArb _pta,
                input int _id =0);

      ll = _ll;
      ib = _wport;
      fbm = _fbm;
      pta = _pta;
      id = _id;

      ib.d_valid = 0;
      ib.d_last = 0;
      
      m_cut_through = 1;
   endfunction // new

   task handle_page_requests(ref int current_page, ref int pages[$], int remaining);
      if(ib.pg_req && (remaining >= 0))
        begin
           ll.set_valid(current_page);
           ll.alloc_page(current_page);
           pages.push_back(current_page);
           ib.pg_addr <= current_page;
        end
   endtask // handle_page_requests

   task handle_pta(ref int start_page, ref int first_in_chain, input int where_to);
      if(m_cut_through && first_in_chain)
        begin
           pta.send(start_page, where_to);
           first_in_chain = 0;
        end
   endtask // handle_pta
   
   
   task send(ref EthPacket pkt, input int where_to = 0);
      byte pdata[];
      u64_array_t pdata_p, readback_p;
      int  n_pages, i, remaining, page = -1, start_page;
      int  pages[$];
      int  first_in_chain = 1;
      static int total_sent = 0;
      

      
/* -----\/----- EXCLUDED -----\/-----
      pkt.dump();
 -----/\----- EXCLUDED -----/\----- */
      
      if(!where_to)
        where_to = id; // bounce back packets with no destination
      
      pkt.serialize(pdata);
      pdata_p=SimUtils.pack(pdata, 2, 1);

      $display("[port %d] send: %d bytes", id, pdata.size());

      
      ll.alloc_page(page); // allocate the 1st page of the packet
      ll.set_use_count(page, count_ones(where_to));
      start_page = page;
      
      
      ib.pg_addr <= page;
      pages.push_back(page);
      
      for(i=0;i<pdata_p.size();i++)
        begin
           remaining = pdata_p.size()-1-i;
           
           while(!ib.dreq)
             begin
                handle_page_requests(page, pages, remaining);
                handle_pta(page, first_in_chain, where_to);
                @(posedge ib.clk);
             end
           
           handle_page_requests(page, pages, remaining);
           handle_pta(page, first_in_chain, where_to);

           ib.d <= pdata_p[i];
           ib.d_valid <= 1;
           ib.d_last <= ((i == pdata_p.size()-1) ? 1 : 0);

           @(posedge ib.clk);

           ib.d_valid <= 0;
           ib.d_last <= 0;

        end // for (i=0;i<pdata_p.size();i++)

      ll.set_valid(page);
      ll.set_last(page, pdata_p.size(), 1 - pdata.size() % 2);

      sent_queue.push_back(pkt);
      
      $display("CHAIN[%d]: %s", total_sent++,ll.dump_chain(start_page));
      
      
       repeat(100) @(posedge ib.clk);

      
      readback_p = fbm.read(pages, pdata_p.size());

      
      if(readback_p != pdata_p)
        begin
           $display("WPort [%d]: FBM content corrupt after write [%d vs %d]", id, readback_p.size(), pdata_p.size());
           for(i=0;i<readback_p.size();i++)
             if (readback_p[i] !=pdata_p[i])
               $display("is %x shouldbe %x [addr : %x]", readback_p[i], pdata_p[i], pages[i/fbm.P.g_page_size] * (fbm.P.g_page_size/fbm.P.g_ratio) + (i % fbm.P.g_page_size)/fbm.P.g_ratio);
           
           $stop;
        end
      
   endtask // send

endclass // CInputBlockModel

class COutputBlockModel;

   virtual ILinkedList ll;
   virtual IMPMReadPort rp;

   CPageTransferArb pta;

   protected int id, seed;
   protected real throttle_prob;
   

   EthPacket rx_queue[$];
   
   function new(input virtual ILinkedList _ll,
                input virtual IMPMReadPort _rport,
                CPageTransferArb _pta,
                input int _id =0);

      ll = _ll;
      rp = _rport;
      pta = _pta;
      id = _id;

      rp.dreq = 0;
      rp.pg_valid = 0;
      throttle_prob = 0.2;
      seed = id;

      $display("OB::new [id %d]", id);
      
      
   endfunction // new

   task do_rx(int start_page);
      u64_array_t rbuf;
      byte_array_t pdata;
      
      
      int n, i;
      logic [7:0] dsel;
      int         prev ;
      EthPacket pkt;
      
      
      
      rbuf = new[ll.P.g_max_packet_size/2];
      
      while(!rp.pg_req)
        @(posedge rp.clk);
      rp.pg_valid <= 1;
      rp.pg_addr <= start_page;
      @(posedge rp.clk);

      forever 
        begin
          if(rp.d_valid)
            begin
               rbuf[n] = rp.d;
//               $display("RXD: %x", rbuf[n]);
               n++;
            end
           
           
           
          if(rp.d_last) 
            begin
               dsel = rp.d_sel;
               rp.dreq <= 0;
               @(posedge rp.clk);
               break;
            end
          rp.pg_valid <= 0;
           rp.dreq <= 1;
//!probability_hit(seed, throttle_prob);
          @(posedge rp.clk);
       end

      ll.free_chain(start_page);
      n = n * 2 + (dsel ? 0 : -1);
      pdata = SimUtils.unpack(rbuf, 2, n);
      pkt = new;

      pdata = new [n](pdata);
//      for(i=0;i<n;i++)
//        $display("Unpacked %x", pdata[i]);
      

      
      pkt.deserialize(pdata);
      $display("[port %d] recv: %d bytes", id, n);//pdata.size());

      rx_queue.push_back(pkt);
      
   endtask // do_rx
   
   
   task run();
      forever begin
         @(posedge rp.clk);
         
         if(pta.poll(id))
           begin
              int page;
              page = pta.recv(id);
              //           $display("[port %d] got page: %d", id, page);
              do_rx(page);
           end
      end // forever begin
   endtask // run
   
   
      
        
   
endclass // COutputBlockModel


module main;

   localparam t_swcore_parameters P = `DEFAULT_SWC_PARAMS;
   
   localparam int c_ll_entry_size = P.g_page_address_width + 2;   
   
   localparam time clk_io_period = 16ns;
   localparam time clk_core_period = clk_io_period / 5;
   
   reg            clk_core = 0, clk_io = 0;
   reg rst_n = 0;
   
   /* Clock generation */

   always #(clk_core_period/2) clk_core <= ~clk_core;
   always #(clk_io_period/2) clk_io <= ~clk_io;
   initial begin
      repeat (3) @(posedge clk_io);
      rst_n <= 1;
   end

   CPageTransferArb pta;
   CInputBlockModel IB[P.g_num_ports];
   COutputBlockModel OB[P.g_num_ports];
   
   ILinkedList ll
      (
      .clk_io_i(clk_io),
      .rst_n_i(rst_n)
      );


   IMPMWritePort wports  [P.g_num_ports] (clk_io, rst_n);
   IMPMReadPort rports  [P.g_num_ports] (clk_io, rst_n);
   
   virtual IMPMWritePort v_wports[P.g_num_ports];
   virtual IMPMReadPort v_rports[P.g_num_ports];
   virtual IShadowFBM v_sh_fbm;
   
   mpm_top_swwrap #(P)
     DUT (
          .clk_core_i(clk_core),
          .clk_io_i(clk_io),
          .rst_n_i(rst_n),
          .wport(wports),
          .rport(rports),
          .ll(ll)
         );

   IShadowFBM #(P) sh_fbm 
     (
      .clk_core_i(clk_core),
      .addr_i(DUT.Wrapped_MPM.fbm_wr_addr),
      .data_i(DUT.Wrapped_MPM.fbm_wr_data),
      .we_i(DUT.Wrapped_MPM.fbm_we));
   
        
                      
   task automatic send_some_stuff(ref CInputBlockModel ib, input int seed , input int n_tries , input int where_to);
      EthPacketGenerator gen = new;
      EthPacket pkt, tmpl, sent[$];
     
      int i;
      
      tmpl           = new;
      tmpl.src       = '{1,2,3,4,5,6};
      tmpl.dst       = '{'h00, 'h50, 'hca, 'hfe, 'hba, 'hbe};
      tmpl.has_smac  = 1;
      tmpl.is_q      = 0;
      
      tmpl.vid       = 100;
      tmpl.ethertype = 'h88f7;

      gen.set_randomization(EthPacketGenerator::SEQ_PAYLOAD /* | EthPacketGenerator::TX_OOB*/) ;
      gen.set_seed(seed);
      gen.set_template(tmpl);
      gen.set_size(64, 1000);
      
      
      for(i=0;i<n_tries;i++)
           begin
              pkt  = gen.gen(); 
              //$display("TrySend: size %d\n", pkt.payload.size());
              ib.send(pkt, where_to);
              sent.push_back(pkt);
           end

      
   endtask // send_some_stuff
   
   initial begin
      automatic int i;
      
      @(posedge rst_n);

      v_wports = wports;
      v_rports = rports;
      v_sh_fbm = sh_fbm;
      pta = new (P.g_num_ports);
      
      for(i=0;i<P.g_num_ports;i++)
        begin
           IB[i] = new (ll, v_wports[i], v_sh_fbm, pta, i);
           OB[i] = new (ll, v_rports[i], pta, i);
        end
      
      
         for(i=0;i<1;i++)
           fork
              automatic int k=i;
              
              send_some_stuff(IB[k], k, 500, 'h3ffff);
           join_none
      
      
      
   end // initial begin

   initial begin
      automatic int i;
      
      @(posedge rst_n);
      repeat(10) @(posedge clk_io);

      for(i=0;i<1/*P.g_num_ports*/;i++)
        fork
           automatic int k = i;
           OB[k].run();
        join_none
      i=0;
   end // initial begin
   
      initial begin
         automatic int i = 0;
         repeat(100) @(posedge clk_io);

         
         forever begin
         
         if(OB[0].rx_queue.size() > 0 && IB[0].sent_queue.size() > 0)
           begin
              EthPacket psent, precv;

              precv = OB[0].rx_queue.pop_front();
              psent = IB[0].sent_queue.pop_front();

              $display("checking %d", i);
           
           
              if(!precv.equal(psent))
                begin
                   $display("RX error [%d]: ",i);
                   precv.dump();
                   $display("Original:");
                   
                   psent.dump();
                   $stop;
                   
               end
              i++;
           end // if (OB[0].rx_queue.size() > 0 && IB[0].sent_queue.size() > 0)

         @(posedge clk_io);
         
      
         end // forever begin
         
   end
   

   
   

   
endmodule // main
