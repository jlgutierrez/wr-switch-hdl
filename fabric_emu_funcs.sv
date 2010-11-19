`timescale 1ns/1ps

/* Ethernet FCS calculator class */
class CCRC32;
   protected bit [31:0] crc;
   protected bit [31:0] crc_tab[256];

   function new();
      reg [31:0] c, poly;
      int i, j;

      poly  = 32'hEDB88320;
      
      for (i = 0; i < 256; i++) begin
	 c = i;
	 for (j = 8; j > 0; j--) begin
	    if (c & 1)
	      c = (c >> 1) ^ poly;
	    else
	      c >>= 1;
	    end
	 crc_tab[i]  = c;

      end
      crc  = 32'hffffffff;
   endfunction // new   

   function bit[31:0] bitrev(bit[31:0] x, int n);
      reg [31:0] y= 0;
      int i;
      for(i=0;i<n;i++) if(x & (1<<i)) y|= 1<< (n-1-i);
      bitrev=y;
   endfunction
   
   task update_int(bit[7:0] x);
      crc = ((crc >> 8) & 32'h00FFFFFF) ^ crc_tab[(crc ^ bitrev(x,8)) & 32'hFF];
   endtask

   task update(input [15:0] x, int bytesel);
      
	update_int(x[15:8]);
      if(!bytesel)
	update_int(x[7:0]);
   endtask // update

   function bit[31:0] get();
      get  = bitrev(crc ^ 32'hffffffff, 32);
   endfunction // get
endclass

/* Simple packet queue */
class CPacketQueue;
   protected int head, tail, count;
   protected int size;
   protected ether_frame_t d[];
   
   
   function new (int _size);
      size   = _size;
      head   = 0;
      tail   = 0;
      count  = 0;
   
      
      d      = new [_size];
      
   endfunction // new
  	      
   task push(input ether_frame_t frame);
      if(count == size) begin
	$display("CPacketQueue::push(): queue overflow");
	 $stop();
	 end

      
      
      d[head]  = frame;
      head++; if(head == size) head = 0;
      count++;
   endtask // push

   task pop (output ether_frame_t frame);
      if(count <= 0)  begin
	$display("CPacketQueue::pop(): queue empty");
	 $stop();
      end

      frame  = d[tail];
      tail++; if(tail == size) tail = 0;
      count--;
      
   endtask // pop
   
   function int get_count();
     return count;
   endfunction // get_count

/* Looks for a packet with matching OOB frame identifier and updates it with the new timestamp value */
   
   function int update_tx_timestamp(input [15:0] oob_fid,
				    input [4:0] port_id,
				    input [31:0] ts_value);

      int i;

      i = tail;

      
      
      while(i != head)
	begin	   

	   
	   
	   if(d[i].hdr.oob_type == `OOB_TYPE_TXTS && d[i].hdr.oob_fid == oob_fid) begin
	      
	      d[i].hdr.timestamp_r 	  = ts_value[27:0];
	      d[i].hdr.timestamp_f 	  = ts_value[31:28];
	      d[i].hdr.has_timestamp  = 1;
	      return 1;
	   end
	   
	   i++;
	   if(i == count) i = 0;
	   
	end 
      return 0;
   endfunction // update_tx_timestamp
endclass // CPacketQueue

 // converts a nbytes-long number (hex) to hexadecimal string
function automatic string hex_2_str(input [47:0] hex, int nbytes);
   int i;
   string s = "";
   string hexchars = "0123456789abcdef";
   reg [47:0] t;
   t = hex;
   for(i=0; i<2*nbytes; i++) begin
      s= {hexchars[t&'hf], s};
      t=t>>4;
   end
   return s;
endfunction // hex_2_str

   // formats an Ethernet frame header as a nice looking string
function automatic string format_ether_header(input ether_header_t hdr);
   string s = {"DST: ", hex_2_str(hdr.dst, 6), 
	       " SRC: ", hex_2_str(hdr.src, 6),
	       " Type: 0x",hex_2_str(hdr.ethertype, 2) };
   
   if(hdr.is_802_1q) s = {s, " VLAN: 0x", hex_2_str({4'b0,hdr.vid}, 2), " PRIO: ", hex_2_str({5'b0, hdr.prio},1) };
   return s;
endfunction // automatic

  
task dump_frame_header(string s, ether_frame_t frame);
   $display("%s %s length = %d %s %s", s, format_ether_header(frame.hdr), frame.size, frame.error?"ERROR":"OK", frame.hdr.has_timestamp?"TS":"NoTS");
endtask // dump_frame_header