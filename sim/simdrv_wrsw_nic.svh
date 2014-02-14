`ifndef __SIMDRV_WR_NIC_SVH
`define __SIMDRV_WR_NIC_SVH 1

`timescale 1ns/1ps

`include "simdrv_defs.svh"
`include "eth_packet.svh"
`include "wb_packet_source.svh"
`include "wb_packet_sink.svh"

`include "regs/nic_regs.vh"

`define MAX_PACKET_SIZE 1536

// fake, simulated spinlock
typedef struct {
   int locked;
} spinlock_t;

// RX and TX descriptor definitions 
typedef struct {
   bit   empty;
   bit    error;
   bit[5:0]    port_id;
   bit    got_ts;
   bit[27:0] ts_r; 
   bit[3:0]  ts_f; 
   bit[15:0] length;  
   bit[15:0] offset;
}  nic_rx_descriptor_t ;

typedef struct	{
   bit   ready;
   bit    error;
   bit pad_e;
   bit ts_e;
   
   bit[15:0] ts_id;
   bit[31:0] dpm;
   bit[15:0] length;  
   bit[15:0] offset;
}   nic_tx_descriptor_t ;


`define NUM_RX_DESC 8
`define NUM_TX_DESC 8
`define PACKET_QUEUE_SIZE 64
`define BASE_NIC_MEM 'h8000


class CSimDrv_NIC;
  
   bit little_endian;
   int tx_oob_fid;
   
   int rx_head_idx;
   int tx_head_idx;
   int tx_irq_enabled;
   int tx_queue_active 	= 0;

   protected uint16_t untag_tab[256];

   spinlock_t tx_lock;

   EthPacket rx_queue[$], tx_queue[$];
   CBusAccessor acc_regs;
   
   uint64_t base_addr;
   
   function new(CBusAccessor regs_, uint64_t base_addr_, bit little_endian_=1);
      base_addr      = base_addr_;
      acc_regs       = regs_;
      little_endian = little_endian_;
  endfunction // new   

   function automatic logic[31:0] swap_endian(input [31:0] data);
      if(little_endian)
	return {data[7:0], data[15:8], data[23:16], data[31:24]};
      else
	return data;
   endfunction // swap_endian

   task writel(uint32_t addr, uint32_t val);
      acc_regs.write(base_addr + addr, val, 4);
   endtask // writel

   task readl(uint32_t addr, output uint32_t val);
      uint64_t tmp;
      acc_regs.read(base_addr + addr, tmp, 4);
      val  = tmp;
   endtask // readl
   
   
   task automatic enable_rx();
     bit[31:0] tmp;
    
      readl(`ADDR_NIC_CR, tmp);
      writel(`ADDR_NIC_CR, tmp | `NIC_CR_RX_EN);
      writel(`ADDR_NIC_EIC_IER, `NIC_EIC_IER_RCOMP); // enable RX interrupt
   endtask // automatic

   task automatic enable_tx();
      bit[31:0] tmp;
      
      tx_irq_enabled  = 1;

      readl(`ADDR_NIC_CR, tmp);
      writel(`ADDR_NIC_CR, tmp | `NIC_CR_TX_EN);
      writel(`ADDR_NIC_EIC_IER, `NIC_EIC_IER_TCOMP | `NIC_EIC_IER_TXERR); // enable TXCOMP & TXERR interrupts
   endtask // automatic
   
   task automatic disable_tx();
      bit[31:0] tmp;
      
      readl(`ADDR_NIC_CR, tmp);
      tmp = tmp & ~(`NIC_CR_TX_EN);
      writel(`ADDR_NIC_CR, tmp);
      writel(`ADDR_NIC_EIC_IDR, `NIC_EIC_IER_TCOMP | `NIC_EIC_IER_TXERR); // enable TXCOMP & TXERR interrupts

      tx_irq_enabled  = 0;
   endtask // automatic

   task automatic disable_rx();
      bit[31:0] tmp;

      readl(`ADDR_NIC_CR, tmp);
      tmp = tmp & (~`NIC_CR_RX_EN);
      writel(`ADDR_NIC_CR, tmp);
      writel(`ADDR_NIC_EIC_IDR, `NIC_EIC_IER_RCOMP); // disable RX interrupt
   endtask // automatic

   task automatic write_rx_desc(int idx, nic_rx_descriptor_t desc);
// IF RX is enabled, make sure we're not chaging the address/length of an active (empty) descriptor. 
      writel(`BASE_NIC_DRX + (idx * 16 + 8), (desc.length << 16) | desc.offset);
      writel(`BASE_NIC_DRX + (idx * 16), { 30'h0 , 1'b0, desc.empty} );
   endtask // write_rx_desc

   task automatic write_tx_desc(int idx, nic_tx_descriptor_t desc);
// IF RX is enabled, make sure we're not chaging the address/length of an active (empty) descriptor. 
      writel(`BASE_NIC_DTX + (idx * 16 + 8), (desc.dpm));
      writel(`BASE_NIC_DTX + (idx * 16 + 4), (desc.length << 16) | desc.offset);
      writel(`BASE_NIC_DTX + (idx * 16), { desc.ts_id, 12'h0, desc.pad_e, desc.ts_e , 1'b0, desc.ready} );
   endtask // write_tx_desc

   task automatic read_rx_desc(int idx, output nic_rx_descriptor_t desc);
      bit [31:0] tmp;
//      $display("IDx %d\n", idx);
      
      readl(`BASE_NIC_DRX + (idx * 16 + 0), tmp);
//      $display("r0 %x", tmp);
      desc.port_id  = tmp[13:8];
      desc.got_ts   = tmp[14];
      desc.error    = tmp[1];
      desc.empty    = tmp[0];

      readl(`BASE_NIC_DRX + (idx * 16 + 4), tmp);
//      $display("r1 %x", tmp);
      desc.ts_f = tmp[31:28];
      desc.ts_r = tmp[27:0];
      readl(`BASE_NIC_DRX + (idx * 16 + 8), tmp);
//      $display("r2 %x", tmp);
      desc.length = tmp[31:16];
      desc.offset = tmp[15:0];
   endtask // write_rx_desc

   task automatic read_tx_desc(int idx, output nic_tx_descriptor_t desc);
      bit[31:0] tmp;

      
      readl(`BASE_NIC_DTX + (idx * 16 + 0), tmp);
      desc.ts_id  = tmp[31:16];
      desc.pad_e  = tmp[3];
      desc.ts_e   = tmp[2];
      desc.error  = tmp[1];
      desc.ready  = tmp[0];

      readl(`BASE_NIC_DTX + (idx * 16 + 4), tmp);
      desc.length   = tmp[31:16];
      desc.offset  = tmp[15:0];

      readl(`BASE_NIC_DTX + (idx * 16 + 8), tmp);
      desc.dpm 	   = tmp;

   endtask // read_tx_desc

   task automatic create_rx_desc(int idx, int offset, int length);
      nic_rx_descriptor_t desc;
      desc.offset  = offset;
      desc.length  = length;
      desc.empty   = 1;
      desc.error   = 0;
      desc.got_ts  = 0;
      write_rx_desc(idx, desc);
   endtask // automatic

   task automatic create_tx_desc(int idx, int offset, int length, int ts_e);
      nic_tx_descriptor_t desc;
      desc.offset  = offset;
      desc.length  = length;
      desc.ready   = 1;
      desc.pad_e   = (length < 59) ? 1: 0;
      desc.ts_e    = ts_e;
      desc.ts_id   = (ts_e ? tx_oob_fid ++ : 0);
      
      desc.dpm 	   = 32'hffffffff;
      write_tx_desc(idx, desc);
   endtask // automatic

      int count;

   task automatic nic_hw_rx(nic_rx_descriptor_t desc);
      EthPacket pkt;
      int i, n;
      string s;

      u64_array_t pbuff;
      byte_array_t payload, p2;
      
      pbuff = new[2048];

      count++;
//      $display("Cnt %d [dsize %d]", count, desc.length);
      
      
      for(i=0; i<(desc.length+8)/4 ; i++)
	begin
	   bit [31:0] tmp;
	   
	   readl(`BASE_NIC_MEM + desc.offset + i * 4, tmp);
	   tmp 	     = swap_endian(tmp);
	   pbuff[i]  = tmp;
	   
	end

      pkt = new;

      payload = SimUtils.unpack(pbuff, 4, desc.length + 2);
      p2 = new[desc.length];
      
      for (i=0;i<desc.length;i++)
	p2[i] = payload[i+2];
	
      pkt.deserialize(p2);
      
      pkt.error 	     = desc.error;

      rx_queue.push_back(pkt);
   endtask // automatic

   task spin_lock_init(inout spinlock_t lck);
      lck.locked  =0;
   endtask // spinlock_init

   task spin_lock(inout spinlock_t lck);
      while(lck.locked) #1ns;
      lck.locked  =1;
   endtask // spin_lock

   task spin_unlock(inout spinlock_t lck);
      lck.locked  =0;
   endtask // spin_unlock


   task automatic nic_hw_tx(int idx, EthPacket pkt);
      nic_tx_descriptor_t desc; 
      reg[31:0] tmp;
      u64_array_t pbuf;
      byte 	payload[];
      
      int i;

      pkt.serialize(payload);

      desc.offset  = 'h4000 + idx * 'h800;
      desc.length  = payload.size();
      desc.pad_e   = (desc.length < 60 ? 1 : 0);
      desc.ts_e    = (pkt.oob == TX_FID ? 1: 0);
      desc.dpm 	   = 32'hffffffff;
      desc.ts_id   = tx_oob_fid++;
      desc.ready   = 1;
      desc.error   = 0;
      
      
      pbuf = SimUtils.pack({0,0,payload}, 4, 1);
      for(i=0;i<pbuf.size(); i++)
        writel(`BASE_NIC_MEM + desc.offset + i * 4, swap_endian(pbuf[i]));
      
      write_tx_desc(idx, desc);

   endtask // automatic
   
   
   task automatic nic_start_xmit(EthPacket pkt, output ok);
      //FIXME: check if there are any free descriptors
      reg[31:0] rval;
      
      nic_tx_descriptor_t desc;

      spin_lock(tx_lock); // make sure the interrupt handler won't make a mess here
       
      read_tx_desc(tx_head_idx, desc);

      if(desc.ready) // the head descriptor still hasn't been transmitted? Perhaps the NIC is still transmitting it.
	begin
	   $display("nic_start_xmit: no free tx descriptors");
	   spin_unlock(tx_lock);
	   ok  = 0;
	   return;
	end

      nic_hw_tx(tx_head_idx, pkt);
   
      tx_head_idx++;
      if(tx_head_idx == `NUM_TX_DESC)
	tx_head_idx  = 0;

      spin_unlock(tx_lock);
      
      enable_tx();
      ok  =1;
   endtask // nic_start_xmit
   
   task automatic handle_rcomp_irq();
      nic_rx_descriptor_t desc;
      int n_read;
      
      n_read  = 0;

      forever begin
	 read_rx_desc(rx_head_idx, desc);
	 
	 if(desc.empty /* || n_read == `NUM_RX_DESC */)
	   break;
	 
	// $display("Offset: %x len: %d error: %d port_id %d ts_r %d ts_f %d got_ts %d",desc.offset, desc.length, desc.error, desc.port_id, desc.ts_r, desc.ts_f, desc.got_ts);

	 nic_hw_rx(desc);
	 
	 create_rx_desc(rx_head_idx, 'h800*rx_head_idx, 1600);
	 
	 rx_head_idx++;
	 if(rx_head_idx == `NUM_RX_DESC)
	   rx_head_idx  = 0;

	 n_read++;
      end
      writel(`ADDR_NIC_EIC_ISR, `NIC_EIC_ISR_RCOMP);

   endtask // automatic

   
   
   task automatic handle_tcomp_irq();
      nic_tx_descriptor_t desc;
      EthPacket pkt;
      
      spin_lock(tx_lock);

      
      if(!tx_queue.size())
	begin
	   disable_tx(); // disable TX irq
	   tx_head_idx 	= 0;
	   writel(`ADDR_NIC_EIC_ISR, `NIC_EIC_ISR_TCOMP);
	   spin_unlock(tx_lock);
	   return;
	end
  
      while(tx_queue.size() > 0)
      begin
	 read_tx_desc(tx_head_idx, desc);

	 if(desc.ready || desc.error) // the head descriptor still hasn't been transmitted? Perhaps the NIC is still transmitting it.
	   begin
	      $display("handle_tcomp_irq: no free TX descriptors at the moment");
	      break;
	   end

	 pkt = tx_queue.pop_front();
	 nic_hw_tx(tx_head_idx, pkt);
   
	 tx_head_idx++;
	 if(tx_head_idx == `NUM_TX_DESC)
	   tx_head_idx  = 0;
      end // while (tx_queue.get_count())
      
      
      writel(`ADDR_NIC_EIC_ISR, `NIC_EIC_ISR_TCOMP);
      spin_unlock(tx_lock);
   endtask // handle_tcomp_irq
   

   task automatic handle_txerr_irq();
      nic_tx_descriptor_t desc;
      int cur_tx_desc;
      reg[31:0] tmp;
      
      readl(`ADDR_NIC_SR, tmp);
      cur_tx_desc  = (tmp & `NIC_SR_CUR_TX_DESC) >> `NIC_SR_CUR_TX_DESC_OFFSET;

      read_tx_desc(cur_tx_desc, desc);
      
      $display("TXerror: faulty descriptor %d error %b ready %b offset %x len %d", cur_tx_desc,desc.error, desc.ready, desc.offset, desc.length);
      desc.error  = 0;
      desc.ready  = 1; // just clear the error and try to retransmit

      write_tx_desc(cur_tx_desc, desc);
      
      writel(`ADDR_NIC_EIC_ISR, `NIC_EIC_ISR_TXERR);
//      $stop;
      

   endtask // automatic
   
   
   task vlan_egress_untag(int vid, int untag);
     uint64_t wval=0;
     if(untag>0)
       untag_tab[(vid>>4)] = untag_tab[(vid>>4)] | (1<<('h000F & vid));
     else
       untag_tab[(vid>>4)] = untag_tab[(vid>>4)] & !  (1<<('h000F & vid));

     wval = (untag_tab[(vid>>4)] << 10) | ('h000003FF & (vid>>4));

     $display("[vlan_egress_untag], write offset: %d, data: 0x%x (val=0x%x)", 
         (vid>>4),untag_tab[(vid>>4)], wval);
         
     writel(`ADDR_NIC_VCR1, wval);
   endtask
       // vlan_egress_untag

   
   task automatic nic_irq_handler();
      
     reg[31:0] isr;
      readl(`ADDR_NIC_EIC_ISR, isr);
   //   $display("irq_handler: isr %x", isr[2:0]);
      
      
      if(isr & `NIC_EIC_ISR_RCOMP)
	handle_rcomp_irq();
     
      if(isr & `NIC_EIC_ISR_TXERR)
	handle_txerr_irq();
 
      if(isr & `NIC_EIC_ISR_TCOMP)
	handle_tcomp_irq();
   endtask // automatic
   
   
   task automatic init();
      int i;
           
      disable_rx();
      disable_tx();

      spin_lock_init(tx_lock);
      
      for(i=0; i<`NUM_RX_DESC * 4; i++)
	begin
	   writel(`BASE_NIC_DRX + i *4, 0); // clear the descriptor tables
	   writel(`BASE_NIC_DTX + i *4, 0); // clear the descriptor tables
	end
      
      
      for(i=0; i<`NUM_RX_DESC; i++)
	create_rx_desc(i, 'h800*i, 1600); // create NUM_RX_DESC empty RX descriptors

      rx_head_idx      = 0;
      tx_head_idx      = 0;
      tx_oob_fid       = 100;
      tx_queue_active  = 1;

      enable_rx();
      
      
   endtask

   task update(bit nic_irq);
      
      if(nic_irq) begin
	 nic_irq_handler();
	 #50ns;
      end

      
      if(tx_queue_active && tx_queue.size() > 0 && !tx_irq_enabled) begin
	 reg ok;
	 EthPacket pkt;

	 pkt = tx_queue.pop_front();
	 nic_start_xmit(pkt, ok);
      end
   endtask // update


    
   
endclass // CSimDrv_NIC



class NICPacketSource extends EthPacketSource;
   CSimDrv_NIC nic;
   
   function new (ref CSimDrv_NIC nic_);
      nic = nic_;
   endfunction // new
     
   task send(ref EthPacket pkt, ref int result = _null);
      nic.tx_queue.push_back(pkt);
   endtask // send

endclass


class NICPacketSink extends EthPacketSink;

   CSimDrv_NIC nic;
   
   function new (ref CSimDrv_NIC nic_);
      nic = nic_;
   endfunction // new

   function int poll();
      return (nic.rx_queue.size() > 0) ? 1 :0; 
   endfunction // poll

  //ML stuff
  function int permanent_stall_enable();
    //empty
    return 0;
  endfunction  
  //ML stuff
  function int permanent_stall_disable();
    // empty
    return 0;
  endfunction
  
   task recv(ref EthPacket pkt, ref int result = _null);
      while(!nic.rx_queue.size()) #1ns;
      pkt = nic.rx_queue.pop_front();
   endtask
	
endclass // NICPacketSink

`endif
