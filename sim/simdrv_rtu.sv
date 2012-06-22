
`include "regs/rtu_regs.vh"

typedef struct
  {
   bit valid;
   bit end_of_bucket;
   bit is_bpdu;
   bit [7:0] mac[0:5];
   bit [7:0] fid;
   bit [31:0] port_mask_src;
   bit[31:0] port_mask_dst;
   bit drop_when_source;
   bit drop_when_dest;
   bit drop_unmatched_src_ports;
   bit [2:0] prio_src;
   bit has_prio_src;
   bit prio_override_src;
   bit [2:0] prio_dst;
   bit has_prio_dst;
   bit prio_override_dst;
   bit go_to_cam;
   bit [3:0] cam_addr;
   }  rtu_filtering_entry_t ;


typedef struct {
   bit[31:0] port_mask;
   bit[7:0] fid;
   bit[2:0] prio;
   bit has_prio;      
   bit prio_override; 
   bit drop;          
} rtu_vlan_entry_t;

`define RTU_HTAB_SIZE 512
`define RTU_HTAB_BUCKET_SIZE 4

class CRTUSimDriver;
  
   const int bucket_size = 8;
   
   extern task set_bus(CBusAccessor _bus, int _base_addr);
   extern task add_hash_entry(rtu_filtering_entry_t ent);
   extern task set_port_config(int port, bit pass_all, bit pass_bpdu, bit learn_en);

   extern task add_static_rule(bit[7:0] dmac[], bit[31:0] dpm);
   extern task add_vlan_entry(int vlan_id, rtu_vlan_entry_t ent);
   

   
   //   extern task run();
   extern protected task htab_write(int hash, int bucket, rtu_filtering_entry_t ent);
   extern protected task mfifo_write(int addr, int size, bit[31:0] data[]);

  
   
   extern protected function bit[15:0] mac_hash(bit[7:0] mac[], bit[7:0] fid);
   extern protected function bit[15:0] crc16(bit[15:0] init_crc, bit[15:0] message);
   
   
   protected CBusAccessor bus;
   protected int base_addr;
   protected bit[31:0] hash_poly;

   
   protected task set_hash_poly(bit[15:0] poly);
      hash_poly  = ('h10000 | poly) << 3;
   endtask // set_hash_poly

   task enable();
      bus.write(base_addr + `ADDR_RTU_GCR, ('h1021 << 8) | `RTU_GCR_G_ENA);
   endtask // enable

   task set_bank(int bank);
      uint64_t rval;
      
/* -----\/----- EXCLUDED -----\/-----
      bus.read(base_addr + `ADDR_RTU_GCR, rval);
      if(bank)
	rval[1:0] = 2'h3;
      else
	rval[1:0]= 2'h0;
      bus.write(base_addr + `ADDR_RTU_GCR, rval);
 -----/\----- EXCLUDED -----/\----- */
      
   endtask // enable
   
   
   protected rtu_filtering_entry_t htab[`RTU_HTAB_SIZE][`RTU_HTAB_BUCKET_SIZE];
   
endclass // CRTUSimDriver

task CRTUSimDriver::set_bus(CBusAccessor _bus, int _base_addr);
   int i, j;
   
   $display("CRTUSimDriver::created (base address 0x%x)", _base_addr);

   for(i=0;i<`RTU_HTAB_SIZE;i++)
     for(j=0;j<`RTU_HTAB_BUCKET_SIZE;j++)
       htab[i][j].valid  = 1'b0;
  
   bus 		    = _bus;
   base_addr 	    = _base_addr;

   set_hash_poly('h1021);
   
endtask // CRTUSimDriver

task CRTUSimDriver::mfifo_write(int addr, int size, bit[31:0] data[]);
   uint64_t rval;
   int i;

   $display("MFIFOWrite addr %x len %d", addr, size);
   
   
   bus.write(base_addr + `ADDR_RTU_MFIFO_R0, 1);
   bus.write(base_addr + `ADDR_RTU_MFIFO_R0, 1);
 //`RTU_MFIFO_R0_AD_SEL);
   bus.write(base_addr + `ADDR_RTU_MFIFO_R1, addr);

   for(i=0;i<size;i++)
     begin
	while(1) begin
	   bus.read(base_addr + `ADDR_RTU_MFIFO_CSR, rval);
	   if(!(rval & `RTU_MFIFO_CSR_FULL)) break;
	   
	end
	$display("MFIFOWrite: %d %x",i,data[i]);
	
	bus.write(base_addr + `ADDR_RTU_MFIFO_R0, 0);
	bus.write(base_addr + `ADDR_RTU_MFIFO_R1, data[i]);
     end

   bus.write(base_addr + `ADDR_RTU_GCR, `RTU_GCR_MFIFOTRIG);

   while(1) begin
      bus.read(base_addr + `ADDR_RTU_GCR, rval);
      if(!(rval & `RTU_GCR_MFIFOTRIG)) break;
   end
   

endtask // CRTUSimDriver

     

task CRTUSimDriver::htab_write(int hash, int bucket, rtu_filtering_entry_t ent);
   bit[31:0] d[5];

   d[0] = (('hFF & ent.mac[0])                        << 24)  |
          (('hFF & ent.mac[1])                        << 16)  |
          (('hFF & ent.fid)                           <<  4)  | 
        (('h1  & ent.go_to_cam)                     <<  3)  | 
        (('h1  & ent.is_bpdu)                       <<  2)  | 
//        (('h1  & ent.end_of_bucket)                 <<  1)  | 
        (('h1  & ent.valid )                             )  ;	      

    d[1] = 
        (('hFF & ent.mac[2])                        << 24)  |
        (('hFF & ent.mac[3])                        << 16)  |
        (('hFF & ent.mac[4])                        <<  8)  |
        (('hFF & ent.mac[5])                             )  ;

   d[2] = 
        (('h1 & ent.drop_when_dest)                 << 28)  | 
        (('h1 & ent.prio_override_dst)              << 27)  | 
        (('h7 & ent.prio_dst)                       << 24)  | 
        (('h1 & ent.has_prio_dst)                   << 23)  | 
        (('h1 & ent.drop_unmatched_src_ports)       << 22)  | 
        (('h1 & ent.drop_when_source)               << 21)  | 
        (('h1 & ent.prio_override_src)              << 20)  |
	    (('h7 & ent.prio_src)                       << 17)  | 
        (('h1 & ent.has_prio_src)                   << 16)  | 
        (('h1FF & ent.cam_addr)                          )  ;		      

   d[3] = 
        (('hFFFF & ent.port_mask_dst)               << 16)  | 
        (('hFFFF & ent.port_mask_src)                    )  ;

   d[4]  = 0;

   mfifo_write(hash * 8 * 4 + bucket * 8, 5, d);

endtask // CRTUSimDriver


task CRTUSimDriver::add_hash_entry(rtu_filtering_entry_t ent);  

   int bucket= 0 ,i;
   
   bit[15:0] hash;

   hash  = mac_hash(ent.mac, ent.fid);


   for(i=0;i<`RTU_HTAB_BUCKET_SIZE;i++)
     if(htab[hash][bucket].valid)
       bucket++;

   if(bucket == `RTU_HTAB_BUCKET_SIZE)
     begin
        $error("No free buckets for hash %x", hash);
     end
   
   
   $display("MACHash: %x, bucket %d", hash, bucket);
   
   htab_write(hash, bucket, ent);
   htab[hash][bucket] = ent;
        
endtask // CRTUSimDriver

task CRTUSimDriver::set_port_config(int port, bit pass_all, bit pass_bpdu, bit learn_en);
   uint64_t rv;
   
   bus.read(base_addr + `ADDR_RTU_PSR, rv);
   $display("PSel: %d supported ports\n", (rv>>8) & 'hff);
   
   
   bus.write(base_addr + `ADDR_RTU_PSR, port);
   bus.write(base_addr + `ADDR_RTU_PCR, `RTU_PCR_B_UNREC | 3);
endtask // CRTUSimDriver

function bit[15:0] CRTUSimDriver::crc16(bit[15:0] init_crc, bit[15:0] message);
   bit[31:0] remainder;	
   int b;

    // Initially, the dividend is the remainder.
    remainder = message^init_crc;
    // For each bit position in the message....
    for (b = 20; b > 0; --b) begin
        // If the uppermost bit is a 1...
        if (remainder & 'h80000) 
            // XOR the previous remainder with the divisor.
            remainder ^= hash_poly;

        //Shift the next bit of the message into the remainder.
        remainder = (remainder << 1);
    end

    return (remainder >> 4);
endfunction
   
function bit[15:0] CRTUSimDriver::mac_hash(bit[7:0] mac[], bit[7:0] fid);
   bit[15:0] hash;
   hash  = 'hffff;

   hash  = crc16(hash, fid);
   hash  = crc16(hash, (mac[0] <<8) | mac[1]);
   hash  = crc16(hash, (mac[2] <<8) | mac[3]);
   hash  = crc16(hash, (mac[4] <<8) | mac[5]);
   return hash & (`RTU_HTAB_SIZE-1); 
endfunction // mac_hash


task CRTUSimDriver::add_static_rule(bit[7:0] dmac[], bit[31:0] dpm);
   rtu_filtering_entry_t ent;

   ent.mac 	      = dmac;
   ent.valid 	      = 1'b1;
//   ent.end_of_bucket  = 1;
   ent.is_bpdu = 0;
   ent.fid = 0;
   ent.port_mask_dst = dpm;   
   ent.port_mask_src = 32'hffffffff;
   ent.drop_when_source=0;
   ent.drop_when_dest=0;
   ent.drop_unmatched_src_ports=0;
   ent.has_prio_src=0;
   ent.prio_override_src=0;
   ent.has_prio_dst=0;
   ent.prio_override_dst=0;
   ent.go_to_cam=0;

   add_hash_entry(ent);
   

endtask // CRTUSimDriver

task CRTUSimDriver::add_vlan_entry(int vlan_id, rtu_vlan_entry_t ent);
 bit[31:0] val;

 val = (('h1    & ent.drop)                             << 31)  | 
       (('h1    & ent.prio_override)                    << 30)  |
       (('h7    & ent.prio)                             << 27)  |
       (('h1    & ent.has_prio)                         << 26)  |
       (('hFF   & ent.fid)                              << 16)  |
       (('hFFFF & ent.port_mask)                             )  ;
 
   bus.write(base_addr + `BASE_RTU_VLAN_TAB + (vlan_id * 4), val);
   bus.write(base_addr + `BASE_RTU_VLAN_TAB + (vlan_id * 4), val);
   
endtask // CRTUSimDriver

