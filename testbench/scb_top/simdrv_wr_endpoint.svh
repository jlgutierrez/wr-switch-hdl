`ifndef __SIMDRV_WR_ENDPOINT_SVH
`define __SIMDRV_WR_ENDPOINT_SVH 1
`timescale 1ns/1ps

`include "simdrv_defs.svh"
`include "endpoint_regs.v"

class CSimDrv_WR_Endpoint;

   protected CBusAccessor m_acc;
   protected uint64_t m_base;
   
   function new(CBusAccessor acc, uint64_t base);     
      m_acc   = acc;
      m_base  = base;
   endfunction // new

   task vlan_egress_untag(int vid, int untag);
      m_acc.write(m_base + `ADDR_EP_VCR1, vid | ((untag ? 1: 0) << 12));
   endtask // vlan_egress_untag

   task pfilter_load_microcode(uint64_t mcode[]);
      int i;

      for(i=0;i<mcode.size();i++)
        begin
           m_acc.write(m_base + `ADDR_EP_PFCR1, (mcode[i] & 'hfff) << `EP_PFCR1_MM_DATA_LSB_OFFSET);
           
           m_acc.write(m_base + `ADDR_EP_PFCR0, 
                       (i << `EP_PFCR0_MM_ADDR_OFFSET) | 
                       (((mcode[i] >> 12) & 'hffffff) << `EP_PFCR0_MM_DATA_MSB_OFFSET) |
                       `EP_PFCR0_MM_WRITE);
        end
   endtask // pfilter_load_microcde

   task pfilter_enable(int enable);
      m_acc.write(m_base + `ADDR_EP_PFCR0, enable ? `EP_PFCR0_ENABLE: 0);
   endtask // pfilter_enable

`define EP_QMODE_VLAN_DISABLED 3
   
   task init();
      m_acc.write(m_base + `ADDR_EP_ECR, `EP_ECR_TX_EN | `EP_ECR_RX_EN);
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
   

endclass // CSimDrv_WR_Endpoint

`endif //  `ifndef __SIMDRV_WR_ENDPOINT_SVH
