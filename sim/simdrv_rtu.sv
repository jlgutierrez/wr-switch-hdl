
`include "regs/rtu_regs.vh"
// `include "regs/rtu_regs_old.vh"
`include "eth_packet.svh"
`include "simdrv_defs.svh"

typedef struct 
  {
     mac_addr_t src;
     mac_addr_t dst;
     int       pid;
  } rtu_ufifo_entry_t;


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
   extern task set_port_config(int port, bit pass_all, bit pass_bpdu, bit learn_en, bit dbg = 0);
   extern task add_static_rule(bit[7:0] dmac[], bit[31:0] dpm);
   extern task add_vlan_entry(int vlan_id, rtu_vlan_entry_t ent);
   extern task poll_ufifo();
   
  // RTU extension functions
   extern task rx_add_ff_mac_single(int mac_id, bit valid, bit[47:0] mac);
   extern task rx_add_ff_mac_range(int mac_id, bit valid, bit[47:0] mac_lower, bit[47:0] mac_upper);
   extern task rx_set_port_mirror(bit[31:0] mirror_src_mask, bit[31:0] mirror_dst_mask, bit rx, bit tx);
   extern task rx_set_hp_prio_mask(bit[7:0] hp_prio_mask);
   extern task rx_read_cpu_port();
   extern task rx_forward_on_fmatch_full();
   extern task rx_drop_on_fmatch_full();
   extern task rx_feature_ctrl(bit mr, bit mac_ptp, bit mac_ll, bit mac_single, bit  mac_range, bit mac_br);
   extern task rx_fw_to_CPU(bit hp, bit unrec);
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

   task read_aging_bitmap(ref bit bmap[]);
      int i,j;
      uint64_t rv;

      bmap = new[`RTU_HTAB_SIZE * `RTU_HTAB_BUCKET_SIZE]; 

      for(i=0;i<(`RTU_HTAB_SIZE * `RTU_HTAB_BUCKET_SIZE) / 32; i++)
        begin
           bus.read(base_addr + `BASE_RTU_ARAM + i*4, rv);
           bus.write(base_addr + `BASE_RTU_ARAM + i*4, 0);
           for(j=0;j<32;j++)
             if(rv & (1<<j)) bmap[i*32+j] = 1;
        end
   endtask // read_aging_bitmap
   
   
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

//   $display("MFIFOWrite addr %x len %d", addr, size);
   
   
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
//	$display("MFIFOWrite: %d %x",i,data[i]);
	
	bus.write(base_addr + `ADDR_RTU_MFIFO_R0, 0);
	bus.write(base_addr + `ADDR_RTU_MFIFO_R1, data[i]);
     end

   bus.write(base_addr + `ADDR_RTU_GCR, `RTU_GCR_MFIFOTRIG);

   while(1) begin
      bus.read(base_addr + `ADDR_RTU_GCR, rval);
      if(!(rval & `RTU_GCR_MFIFOTRIG)) break;
   end
   

endtask // CRTUSimDriver


task CRTUSimDriver::poll_ufifo();
   uint64_t csr, r0, r1, r2, r3 ,r4;
   rtu_ufifo_entry_t ent;
   
   bus.read(base_addr + `ADDR_RTU_UFIFO_CSR, csr);
   
   
   if(csr & `RTU_UFIFO_CSR_EMPTY)
     return;

   bus.read(base_addr + `ADDR_RTU_UFIFO_R0, r0);
   bus.read(base_addr + `ADDR_RTU_UFIFO_R1, r1);
   bus.read(base_addr + `ADDR_RTU_UFIFO_R2, r2);
   bus.read(base_addr + `ADDR_RTU_UFIFO_R3, r3);
   bus.read(base_addr + `ADDR_RTU_UFIFO_R4, r4);

   ent.pid = (r4 & `RTU_UFIFO_R4_PID)>> `RTU_UFIFO_R4_PID_OFFSET;
 
    // destination mac
    ent.dst[5]   = 'hFF &  r0;
    ent.dst[4]   = 'hFF & (r0 >> 8);
    ent.dst[3]   = 'hFF & (r0 >> 16);
    ent.dst[2]   = 'hFF & (r0 >> 24);
    ent.dst[1]   = 'hFF &  r1;
    ent.dst[0]   = 'hFF & (r1 >> 8);
    // source mac
    ent.src[5]   = 'hFF &  r2;
    ent.src[4]   = 'hFF & (r2 >> 8);
    ent.src[3]   = 'hFF & (r2 >> 16);
    ent.src[2]   = 'hFF & (r2 >> 24);
    ent.src[1]   = 'hFF &  r3;
    ent.src[0]   = 'hFF & (r3 >> 8);

   $display("ureq: pid %d DST [%02x:%02x:%02x:%02x:%02x:%02x] SRC: [%02x:%02x:%02x:%02x:%02x:%02x", ent.pid,
            ent.dst[0], ent.dst[1], ent.dst[2], ent.dst[3], ent.dst[4], ent.dst[5],
            ent.src[0], ent.src[1], ent.src[2], ent.src[3], ent.src[4], ent.src[5]);
   
endtask
     

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

   d[4] = 
        (('hFFFF & (ent.port_mask_dst >> 16))               << 16)  | 
        (('hFFFF & (ent.port_mask_src >> 16))                    )  ;


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

task CRTUSimDriver::set_port_config(int port, bit pass_all, bit pass_bpdu, bit learn_en, bit dbg = 0);
   uint64_t rv, tmp;
   
   bus.read(base_addr + `ADDR_RTU_PSR, rv);
   if(dbg) $display("PSel: %d supported ports, configuration for port %d:", (rv>>8) & 'hff, port);
   

   if(learn_en  == 1) begin tmp = tmp | `RTU_PCR_LEARN_EN; if(dbg)  $display("learn"); end;
   if(pass_all  == 1) begin tmp = tmp | `RTU_PCR_PASS_ALL; if(dbg)  $display("pass all"); end;
   if(pass_bpdu == 1) begin tmp = tmp | `RTU_PCR_PASS_BPDU;if(dbg)  $display("pass bpdu"); end;
 
   tmp = `RTU_PCR_B_UNREC | tmp; if(dbg) $display("broadcast unrecognized");
 
   bus.write(base_addr + `ADDR_RTU_PSR, port);
   bus.write(base_addr + `ADDR_RTU_PCR, tmp);

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
   uint64_t vtr1, vtr2;


   vtr2 = ent.port_mask;
   vtr1 = `RTU_VTR1_UPDATE 
          | (ent.drop ? `RTU_VTR1_DROP : 0)
          | (ent.prio_override ? `RTU_VTR1_PRIO_OVERRIDE : 0)
          | (ent.has_prio ? `RTU_VTR1_HAS_PRIO : 0)
          | ((ent.prio & 'h7) << `RTU_VTR1_PRIO_OFFSET)
          | ((ent.fid & 'hff) << `RTU_VTR1_FID_OFFSET)
          | (vlan_id & `RTU_VTR1_VID) ;
   
      bus.write(base_addr + `ADDR_RTU_VTR2, vtr2);
      bus.write(base_addr + `ADDR_RTU_VTR1, vtr1);
   $display("[CRTUSimDriver::add_vlan_entry] drop=%1d, has_prio=%1d, prio=%1d,\
prio_override=%1d, fid=%1d, vlan_id=%1d", ent.drop, ent.has_prio, ent.prio, 
                                          ent.prio_override, ent.fid, vlan_id);
   
endtask // CRTUSimDriver

task CRTUSimDriver::rx_add_ff_mac_single(int mac_id, bit valid, bit[47:0] mac);
   uint64_t mac_hi, mac_lo;


   mac_lo = `RTU_RX_FF_MAC_R0_LO     & (mac[31:0]  << `RTU_RX_FF_MAC_R0_LO_OFFSET);
   mac_hi = `RTU_RX_FF_MAC_R1_HI_ID  & (mac[47:32] << `RTU_RX_FF_MAC_R1_HI_ID_OFFSET) |
            `RTU_RX_FF_MAC_R1_ID     & (mac_id     << `RTU_RX_FF_MAC_R1_ID_OFFSET)    |
            `RTU_RX_FF_MAC_R1_TYPE   & (0          << `RTU_RX_FF_MAC_R1_TYPE_OFFSET)  |     
            `RTU_RX_FF_MAC_R1_VALID  & (valid      << `RTU_RX_FF_MAC_R1_VALID_OFFSET);
                
   bus.write(base_addr + `ADDR_RTU_RX_FF_MAC_R0, mac_lo);
   bus.write(base_addr + `ADDR_RTU_RX_FF_MAC_R1, mac_hi);
 
   $display("RTU eXtension: set fast forward single mac (id=%d, valid=%d) of 0xd",mac_id, valid,mac);
   
endtask // CRTUSimDriver

task CRTUSimDriver::rx_add_ff_mac_range(int mac_id, bit valid, bit[47:0] mac_lower, bit[47:0] mac_upper);
   uint64_t mac_hi, mac_lo;
   int m_mac_id; // modified mac id
   
   // writting lower boundary of the mac range
   m_mac_id = (~(1 << 7) ) & mac_id; // lower range (highest bit is low)

   mac_lo = `RTU_RX_FF_MAC_R0_LO     & (mac_lower[31:0]  << `RTU_RX_FF_MAC_R0_LO_OFFSET);
   mac_hi = `RTU_RX_FF_MAC_R1_HI_ID  & (mac_lower[47:32] << `RTU_RX_FF_MAC_R1_HI_ID_OFFSET) |
            `RTU_RX_FF_MAC_R1_ID     & (m_mac_id      << `RTU_RX_FF_MAC_R1_ID_OFFSET)    |
            `RTU_RX_FF_MAC_R1_TYPE   & (1             << `RTU_RX_FF_MAC_R1_TYPE_OFFSET)  |     
            `RTU_RX_FF_MAC_R1_VALID  & (valid         << `RTU_RX_FF_MAC_R1_VALID_OFFSET);
                
   bus.write(base_addr + `ADDR_RTU_RX_FF_MAC_R0, mac_lo);
   bus.write(base_addr + `ADDR_RTU_RX_FF_MAC_R1, mac_hi);
 
   // writting upper boundary of the mac range
   m_mac_id = (1 << 7) | mac_id; // upper range high (highest bit is low)

   mac_lo = `RTU_RX_FF_MAC_R0_LO     & (mac_upper[31:0]  << `RTU_RX_FF_MAC_R0_LO_OFFSET);
   mac_hi = `RTU_RX_FF_MAC_R1_HI_ID  & (mac_upper[47:32] << `RTU_RX_FF_MAC_R1_HI_ID_OFFSET) |
            `RTU_RX_FF_MAC_R1_ID     & (m_mac_id      << `RTU_RX_FF_MAC_R1_ID_OFFSET)    |
            `RTU_RX_FF_MAC_R1_TYPE   & (1             << `RTU_RX_FF_MAC_R1_TYPE_OFFSET)  |     
            `RTU_RX_FF_MAC_R1_VALID  & (valid         << `RTU_RX_FF_MAC_R1_VALID_OFFSET) ;
                
   bus.write(base_addr + `ADDR_RTU_RX_FF_MAC_R0, mac_lo);
   bus.write(base_addr + `ADDR_RTU_RX_FF_MAC_R1, mac_hi);
   
   $display("RTU eXtension: set fast forward mac range: (id=%d, valid=%d):", mac_id, valid);
   $display("\t lower_mac = 0x%x",mac_lower);
   $display("\t upper_mac = 0x%x",mac_upper);

endtask // CRTUSimDriver

task CRTUSimDriver::rx_set_port_mirror(bit[31:0] mirror_src_mask, bit[31:0] mirror_dst_mask, bit rx, bit tx);
   uint64_t mp_src_rx, mp_src_tx, mp_dst, mp_sel;

   $display("RTU eXtension: set port mirroring:" );

   mp_dst    = `RTU_RX_MP_R1_MASK  & (mirror_dst_mask<< `RTU_RX_MP_R1_MASK_OFFSET);
   mp_src_tx = 0;
   mp_src_rx = 0;

   mp_sel    =  (0 << `RTU_RX_MP_R0_DST_SRC_OFFSET); // destinatioon
   bus.write(base_addr + `ADDR_RTU_RX_MP_R0, mp_sel);
   bus.write(base_addr + `ADDR_RTU_RX_MP_R1, mp_dst);

   if(rx) begin
     mp_src_rx = `RTU_RX_MP_R1_MASK  & (mirror_src_mask<< `RTU_RX_MP_R1_MASK_OFFSET); 
     mp_sel    = 0;
     mp_sel    =(1 << `RTU_RX_MP_R0_DST_SRC_OFFSET) | (0 << `RTU_RX_MP_R0_RX_TX_OFFSET); 
     bus.write(base_addr + `ADDR_RTU_RX_MP_R0, mp_sel);   
     bus.write(base_addr + `ADDR_RTU_RX_MP_R1, mp_src_rx);
    
   end;

   if(tx) begin
     mp_src_tx = `RTU_RX_MP_R1_MASK  & (mirror_src_mask<< `RTU_RX_MP_R1_MASK_OFFSET); 
     mp_sel    = 0;
     mp_sel    =(1 << `RTU_RX_MP_R0_DST_SRC_OFFSET) | (1 << `RTU_RX_MP_R0_RX_TX_OFFSET); 
     bus.write(base_addr + `ADDR_RTU_RX_MP_R0, mp_sel);   
     bus.write(base_addr + `ADDR_RTU_RX_MP_R1, mp_src_tx);   
   end;

   $display("\t mirror output port(s) mask                 (dst)    = 0x%x",mp_dst);
   $display("\t ingress traffic mirror source port(s) mask (src_rx) = 0x%x",mp_src_rx);   
   $display("\t egress  traffic mirror source port(s) mask (src_tx) = 0x%x",mp_src_tx);
   
   
endtask // CRTUSimDriver

task CRTUSimDriver::rx_set_hp_prio_mask(bit[7:0] hp_prio_mask);
   uint64_t mask;

   mask = `RTU_RX_CTR_PRIO_MASK  & (hp_prio_mask << `RTU_RX_CTR_PRIO_MASK_OFFSET);
                
   bus.write(base_addr + `ADDR_RTU_RX_CTR, mask);
   $display("RTU eXtension: set hp priorities (for which priorities traffic is considered HP), mask=0x%x",hp_prio_mask );
endtask // CRTUSimDriver

task CRTUSimDriver::rx_read_cpu_port();
   uint64_t mask;

   bus.read(base_addr + `ADDR_RTU_CPU_PORT, mask);
   $display("RTU eXtension: CPU port (to which link-limited traffic is forwarded) mask=0x%x",mask );
endtask // CRTUSimDriver

task CRTUSimDriver::rx_forward_on_fmatch_full();
   uint64_t rd_mask, wr_mask;
   bus.read(base_addr + `ADDR_RTU_RX_CTR, rd_mask);
   $display("RTU eXtension: forward (broadcast) on full_match full");
   wr_mask = `RTU_RX_CTR_AT_FMATCH_TOO_SLOW | rd_mask;
   bus.write(base_addr + `ADDR_RTU_RX_CTR, wr_mask);
endtask // CRTUSimDriver
task CRTUSimDriver::rx_drop_on_fmatch_full();
   uint64_t mask;
   bus.read(base_addr + `ADDR_RTU_RX_CTR, mask);
   mask = (~`RTU_RX_CTR_AT_FMATCH_TOO_SLOW) & mask;
   bus.write(base_addr + `ADDR_RTU_RX_CTR, mask);
   $display("RTU eXtension: drop on full_match full");
endtask // CRTUSimDriver


task CRTUSimDriver::rx_feature_ctrl(bit mr, bit mac_ptp, bit mac_ll, bit mac_single, bit  mac_range, bit mac_br);
   uint64_t mask;
   bus.read(base_addr + `ADDR_RTU_RX_CTR, mask);
//    $display("RTU eXtension features debugging: 1: read mask: 0x%x",mask);
//    mask = !(`RTU_RX_CTR_MR_ENA        |
//             `RTU_RX_CTR_FF_MAC_PTP    |
//             `RTU_RX_CTR_FF_MAC_LL     |
//             `RTU_RX_CTR_FF_MAC_SINGLE |
//             `RTU_RX_CTR_FF_MAC_RANGE  |
//             `RTU_RX_CTR_FF_MAC_BR     |
//             32'h00000000) &
//              mask; 
   mask = 'hFFFFFFC0 & mask; 
   /*$display("RTU eXtension features debugging: 2: cleared mask: 0x%x",mask);*/         
   mask =(((mr          << `RTU_RX_CTR_MR_ENA_OFFSET)        & `RTU_RX_CTR_MR_ENA)        |     
          ((mac_ptp     << `RTU_RX_CTR_FF_MAC_PTP_OFFSET)    & `RTU_RX_CTR_FF_MAC_PTP)    |  
          ((mac_ll      << `RTU_RX_CTR_FF_MAC_LL_OFFSET)     & `RTU_RX_CTR_FF_MAC_LL)     | 
          ((mac_single  << `RTU_RX_CTR_FF_MAC_SINGLE_OFFSET) & `RTU_RX_CTR_FF_MAC_SINGLE) |  
          ((mac_range   << `RTU_RX_CTR_FF_MAC_RANGE_OFFSET)  & `RTU_RX_CTR_FF_MAC_RANGE)  |  
          ((mac_br      << `RTU_RX_CTR_FF_MAC_BR_OFFSET)     & `RTU_RX_CTR_FF_MAC_BR)   ) |
           mask;
//    $display("RTU eXtension features debugging: 1: written mask: 0x%x",mask);
   bus.write(base_addr + `ADDR_RTU_RX_CTR, mask);
   $display("RTU eXtension features:");
   if(mr        ) $display("\t Port Mirroring                           - enabled"); 
   else           $display("\t Port Mirroring                           - disabled"); 
   if(mac_ptp   ) $display("\t PTP fast forward                         - enabled"); 
   else           $display("\t PTP fast forward                         - disabled");
   if(mac_br    ) $display("\t Broadcast fast forward                   - enabled"); 
   else           $display("\t Broadcast fast forward                   - disabled");  
   if(mac_ll    ) $display("\t Link-limited traffic (BPDU) fast forward - enabled"); 
   else           $display("\t Link-limited traffic (BPDU) fast forward - disabled");
   if(mac_single) $display("\t Single configured MACs fast forward      - enabled"); 
   else           $display("\t Single configured MACs fast forward      - disabled"); 
   if(mac_range ) $display("\t Range of configured MACs fast forward    - enabled"); 
   else           $display("\t Range of configured MACs fast forward    - disabled"); 
   
endtask // CRTUSimDriver

task CRTUSimDriver::rx_fw_to_CPU(bit hp, bit unrec);
   uint64_t mask;
   bus.read(base_addr + `ADDR_RTU_RX_CTR, mask);
   mask = 'hFFF0FFFF & mask; 
   /*$display("RTU eXtension features debugging: 2: cleared mask: 0x%x",mask);*/         
   mask =(((hp    << `RTU_RX_CTR_HP_FW_CPU_ENA_OFFSET)    & `RTU_RX_CTR_HP_FW_CPU_ENA)   |
          ((unrec << `RTU_RX_CTR_UREC_FW_CPU_ENA_OFFSET)  & `RTU_RX_CTR_UREC_FW_CPU_ENA))|
           mask;
//    $display("RTU eXtension features debugging: 1: written mask: 0x%x",mask);
   bus.write(base_addr + `ADDR_RTU_RX_CTR, mask);
   $display("RTU eXtension features [forward to CPU]:");
   if(hp        ) $display("\t Forward HP to CPU                        - enabled"); 
   else           $display("\t Forward HP to CPU                        - disabled"); 
   if(unrec     ) $display("\t Forward unrecognized broadcast to CPU    - enabled"); 
   else           $display("\t Forward unrecognized broadcast to CPU    - disabled");
   
endtask // CRTUSimDriver