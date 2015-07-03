`ifndef __SIMDRV_WR_ENDPOINT_SVH
`define __SIMDRV_WR_ENDPOINT_SVH 1
`timescale 1ns/1ps

`include "simdrv_defs.svh"
`include "endpoint_regs.v"

class CSimDrv_WR_Endpoint;

   protected CBusAccessor m_acc;
   protected uint64_t m_base;
   protected uint16_t untag_tab[256];
   
   function new(CBusAccessor acc, uint64_t base);     
      int i;
      m_acc   = acc;
      m_base  = base;
//       for(i=0;i<10;i++)
//         untag_tab[i]=0;
   endfunction // new

   task vlan_egress_untag(int vid, int untag);
      uint64_t wval=0;
      if(untag>0)
        untag_tab[(vid>>4)] = untag_tab[(vid>>4)] |  (1<<('h000F & vid));
      else
        untag_tab[(vid>>4)] = untag_tab[(vid>>4)] & ! (1<<('h000F & vid));
      
      wval = (untag_tab[(vid>>4)] << 10) | ('h000003FF & (vid>>4));
      
      $display("[vlan_egress_untag], write offset: %d, data: 0x%x (val=0x%x)", 
      (vid>>4),untag_tab[(vid>>4)], wval);      
      m_acc.write(m_base + `ADDR_EP_VCR1, wval);
      
   //   m_acc.write(m_base + `ADDR_EP_VCR1, vid | ((untag ? 1: 0) << 12));
   endtask // vlan_egress_untag

   task vlan_egress_untag_direct(uint16_t mask, uint16_t addr);
      uint64_t wval=0;
      wval = (mask << 10) | ('h000003FF & addr);
      $display("[vlan_egress_untag], write offset: %d, data: 0x%x ", addr,wval);      
      m_acc.write(m_base + `ADDR_EP_VCR1, wval);
   endtask // vlan_egress_untag

   task vcr1_buffer_write(int is_vlan, int addr, uint64_t data);
//       $display("addr=0x%x , data=0x%x",addr,data);
      m_acc.write(m_base + `ADDR_EP_VCR1, 
                 (((is_vlan ? 0 : 'h200) + addr) << `EP_VCR1_OFFSET_OFFSET)
                  | (data << `EP_VCR1_DATA_OFFSET));
   endtask // vlan_buffer_write

   task write_template(int slot, byte data[], int user_offset=-1);
      int i;

      if(data.size() & 1)
        $fatal("CSimDrv_WR_Endpoint::write_template(): data size must be even");
      
      if(user_offset >= data.size()-2)
        $fatal("CSimDrv_WR_Endpoint::write_template(): user_offset cannot be set to the last word of the template");

      if(user_offset & 1)
        $fatal("CSimDrv_WR_Endpoint::write_template(): user_offset must be even");

     
      $display("write_template: size %d", data.size());
      
      for(i=0;i<data.size();i+=2)
        begin
           uint64_t v = 0; 

           v = ((data[i] << 8) | data[i+1]) & 64'h0000FFFF;
           if(i == 0)
             v |= (1<<16); // start of template
           if(i == data.size() - 2)
             v |= (1<<16); // end of template

           if(i == user_offset)
             v |= (1<<17);

           vcr1_buffer_write(0, slot * 64 + i/2, v);
        end
   endtask // write_template

   task write_inj_gen_frame(byte header[], int frame_size);
      int i;
      int slot = 0;

      if(header.size() & 1)
        $fatal("CSimDrv_WR_Endpoint::write_inj_gen_frame(): header size must be even");
      if(frame_size < 64)
        $fatal("CSimDrv_WR_Endpoint::write_inj_gen_frame(): frame size needs to be greater than 64");
      if(frame_size > 1024)
        $fatal("CSimDrv_WR_Endpoint::write_inj_gen_frame(): frame size needs to be less than 1024 (to be modified)");

      $display("write_template: size %d",frame_size);
      
      frame_size = frame_size -4;//CRC which is automaticly suffixed
      for(i=0;i<frame_size;i+=2)
        begin
           uint64_t v = 0; 
           if(i < header.size())
             v = ((header[i] << 8) | header[i+1]) & 64'h0000FFFF;
           else
             v = 0;
           
           if(i == 0)
             v |= (1<<16); // start of template

           if((frame_size & 1) && (i == (frame_size - 1))) // end of template with odd size
             v |= (1<<16) | (1<<17);
           else if(i == (frame_size - 2)) // end of template with even size
             v |= (1<<16);
           
           if(i == header.size())
             v |= (1<<17); // place for frame ID

           vcr1_buffer_write(0, slot * 64 + i/2, v);
        end
   endtask // write_template

   task pfilter_load_microcode(uint64_t mcode[]);
      int i;

      for(i=0;i<mcode.size();i++)
        begin
           m_acc.write(m_base + `ADDR_EP_PFCR1, (mcode[i] & 'hfff) << `EP_PFCR1_MM_DATA_LSB_OFFSET);
           
           m_acc.write(m_base + `ADDR_EP_PFCR0, 
                       (i << `EP_PFCR0_MM_ADDR_OFFSET) | 
                       (((mcode[i] >> 12) & 'hffffff) << `EP_PFCR0_MM_DATA_MSB_OFFSET) |
                       `EP_PFCR0_MM_WRITE);
                       
           $display("code_pos=%2d : PFCR0=0x%4x PFCR1=0x%4x ",i, 
                    ((i << `EP_PFCR0_MM_ADDR_OFFSET) | 
                       (((mcode[i] >> 12) & 'hffffff) << `EP_PFCR0_MM_DATA_MSB_OFFSET) |
                       `EP_PFCR0_MM_WRITE ),
                       ((mcode[i] & 'hfff) << `EP_PFCR1_MM_DATA_LSB_OFFSET));
        end
           $display("pfilter: loaded code [size=%d] ",mcode.size());
   endtask // pfilter_load_microcde

   task pfilter_enable(int enable);
      m_acc.write(m_base + `ADDR_EP_PFCR0, enable ? `EP_PFCR0_ENABLE: 0);
   endtask // pfilter_enable

`define EP_QMODE_VLAN_DISABLED 2
   
   task init(int port_id);
      m_acc.write(m_base + `ADDR_EP_ECR, `EP_ECR_TX_EN | `EP_ECR_RX_EN | (port_id << `EP_ECR_PORTID_OFFSET)) ;
      m_acc.write(m_base + `ADDR_EP_RFCR, 1518 << `EP_RFCR_MRU_OFFSET);
      m_acc.write(m_base + `ADDR_EP_VCR0, `EP_QMODE_VLAN_DISABLED << `EP_VCR0_QMODE_OFFSET);
      m_acc.write(m_base + `ADDR_EP_TSCR, `EP_TSCR_EN_RXTS | `EP_TSCR_EN_TXTS);
   endtask // init

   task automatic mdio_read(int addr, output int val);
      uint64_t rval;

      m_acc.write(m_base + `ADDR_EP_MDIO_CR, (addr>>2) << 16, 4);
      while(1)begin
	 m_acc.read(m_base + `ADDR_EP_MDIO_ASR, rval, 4);
	 if(rval & 'h80000000) begin
	    val  = rval & 'hffff;
	    return;
	 end
	 
      end
   endtask // mdio_read

   task automatic mdio_write(int addr,int val);
      uint64_t rval;

      m_acc.write(m_base+`ADDR_EP_MDIO_CR, ((addr>>2) << 16) | `EP_MDIO_CR_RW | val);
      while(1)begin
	 #8ns;
	 m_acc.read(m_base+`ADDR_EP_MDIO_ASR, rval);
	 if(rval & 'h80000000)
	   return;
      end
   endtask // automatic

   task automatic check_link(ref int up);
      reg[31:0] rval;
      mdio_read(m_base + `ADDR_MDIO_MSR, rval);
      up= (rval & `MDIO_MSR_LSTATUS) ? 1 : 0;
   endtask // check_link
   
   task automatic vlan_config(int qmode,int fix_prio, int prio_val, int pvid, int prio_map[]);
      uint64_t wval;
      int i;
      wval = (qmode    << `EP_VCR0_QMODE_OFFSET    ) & `EP_VCR0_QMODE    |
             (fix_prio << `EP_VCR0_FIX_PRIO_OFFSET ) & `EP_VCR0_FIX_PRIO |
             (prio_val << `EP_VCR0_PRIO_VAL_OFFSET ) & `EP_VCR0_PRIO_VAL |
             (pvid     << `EP_VCR0_PVID_OFFSET     ) & `EP_VCR0_PVID;
      
      m_acc.write(m_base + `ADDR_EP_VCR0, wval);
      wval = 0;
      for(i=0;i<8;i++)
        wval = ('h7 & prio_map[i]) << (i*3) | wval;
      
      m_acc.write(m_base + `ADDR_EP_TCAR, `EP_TCAR_PCP_MAP & (wval << `EP_TCAR_PCP_MAP_OFFSET));
 
      $display("VLAN cofig: qmode=%1d, fix_prio=%1d, prio_val=%1d, pvid=%1d, prio_map=%1d-%1d-%1d-%1d-%1d-%1d-%1d-%1d",
                qmode,fix_prio, prio_val, pvid, prio_map[7],prio_map[6],prio_map[5],prio_map[4],
                prio_map[3],prio_map[2],prio_map[1],prio_map[0]);
   endtask // automatic

   task automatic pause_config(int txpause_802_3,int rxpause_802_3, int txpause_802_1q, int rxpause_802_1q);
     uint64_t wval;
     wval  = (txpause_802_1q << `EP_FCR_TXPAUSE_802_1Q_OFFSET) & `EP_FCR_TXPAUSE_802_1Q | // Tx
             (rxpause_802_1q << `EP_FCR_RXPAUSE_802_1Q_OFFSET) & `EP_FCR_RXPAUSE_802_1Q | // Rx
             (txpause_802_3  << `EP_FCR_TXPAUSE_OFFSET )       & `EP_FCR_TXPAUSE  | // Tx
             (rxpause_802_3  << `EP_FCR_RXPAUSE_OFFSET )       & `EP_FCR_RXPAUSE;             // Rx
     m_acc.write(m_base + `ADDR_EP_FCR, wval);
     $display("PAUSE cofig: tx_802.3 en=%1d, rx_802.3 en=%1d, tx_801.2Q (prio-based)=%1d, rx_802.1Q (prio-based)=%1d",
              txpause_802_3, rxpause_802_3, txpause_802_1q, rxpause_802_1q);     
   endtask // automatic

   task automatic inject_gen_ctrl_config(int interframe_gap, int sel_id, int mode);
     uint64_t wval = 0;
     wval  = (interframe_gap << `EP_INJ_CTRL_PIC_CONF_IFG_OFFSET) & `EP_INJ_CTRL_PIC_CONF_IFG | 
             (sel_id         << `EP_INJ_CTRL_PIC_CONF_SEL_OFFSET) & `EP_INJ_CTRL_PIC_CONF_SEL |
             (mode           << `EP_INJ_CTRL_PIC_MODE_ID_OFFSET ) & `EP_INJ_CTRL_PIC_MODE_ID_OFFSET  |
              `EP_INJ_CTRL_PIC_CONF_VALID | `EP_INJ_CTRL_PIC_MODE_VALID;
     m_acc.write(m_base + `ADDR_EP_INJ_CTRL, wval);
     $display("INJ ctrl cofig: interframe gap=%1d, pattern sel id=%1d, mode = %1d",interframe_gap,sel_id, mode);     
   endtask // automatic
   task automatic inject_gen_ctrl_enable();
     uint64_t wval = 0;
     wval  = `EP_INJ_CTRL_PIC_ENA;
     m_acc.write(m_base + `ADDR_EP_INJ_CTRL, wval);
     $display("INJ ctrl cofig: enabled");     
   endtask // automatic
   task automatic inject_gen_ctrl_disable();
     uint64_t wval = 0;
     m_acc.write(m_base + `ADDR_EP_INJ_CTRL, wval);
     $display("INJ ctrl cofig: disabled");     
   endtask // automatic

   task automatic inject_gen_ctrl_mode(int mode );
     uint64_t wval = 0;
     wval  = (mode           << `EP_INJ_CTRL_PIC_MODE_ID_OFFSET ) & `EP_INJ_CTRL_PIC_MODE_ID  |
              `EP_INJ_CTRL_PIC_MODE_VALID | `EP_INJ_CTRL_PIC_ENA;
     m_acc.write(m_base + `ADDR_EP_INJ_CTRL, wval);
     $display("INJ ctrl cofig: mode = %1d",mode);     
   endtask // automatic


endclass // CSimDrv_WR_Endpoint

`endif //  `ifndef __SIMDRV_WR_ENDPOINT_SVH
