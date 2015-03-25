`ifndef __SIMDRV_WR_PSU
`define __SIMDRV_WR_PSU 1
`timescale 1ns/1ps

`include "simdrv_defs.svh"
`include "regs/psu_regs.v"



class CSimDrv_PSU;

   protected CBusAccessor m_acc;
   protected uint64_t m_base;
   
   function new(CBusAccessor acc, uint64_t base, bit dbg=0);     
      m_acc         = acc;
      m_base        = base;
   endfunction // new

   task init(bit[2:0] inj_prio, bit[7:0] holdover_clk_class, bit ignore_rx_port_id,
                 bit[31:0] rx_mask, bit[31:0] tx_mask );

      m_acc.write(m_base + `ADDR_PSU_PCR,
                 (holdover_clk_class << `PSU_PCR_HOLDOVER_CLK_CLASS_OFFSET) & `PSU_PCR_HOLDOVER_CLK_CLASS |
                 (inj_prio           << `PSU_PCR_INJ_PRIO_OFFSET          ) & `PSU_PCR_INJ_PRIO);
      m_acc.write(m_base + `ADDR_PSU_RXPM, rx_mask);
      m_acc.write(m_base + `ADDR_PSU_TXPM, tx_mask);
   endtask;

   task enable(bit onoff);
      uint64_t tmp;
      m_acc.read(m_base + `ADDR_PSU_PCR, tmp, 4);
      if(onoff)
         tmp = tmp | `PSU_PCR_PSU_ENA;
      else
         tmp = tmp & ~`PSU_PCR_PSU_ENA;
      m_acc.write(m_base + `ADDR_PSU_PCR, tmp);
   endtask;
   
   task tx_port_enable(int port_id, bit onoff);
      uint64_t tmp;
      m_acc.read(m_base + `ADDR_PSU_TXPM, tmp, 4);
      if(onoff)
         tmp = tmp | (1 << port_id);
      else
         tmp = tmp & ~(1 << port_id);
      m_acc.write(m_base + `ADDR_PSU_TXPM, tmp);
   endtask;

   task rx_port_enable(int port_id, bit onoff);
      uint64_t tmp;
      m_acc.read(m_base + `ADDR_PSU_RXPM, tmp, 4);
      if(onoff)
         tmp = tmp | (1 << port_id);
      else
         tmp = tmp & ~(1 << port_id);
      m_acc.write(m_base + `ADDR_PSU_RXPM, tmp);
   endtask;

   task dbg_holdover(onoff);
      $display("PSU/DBG: holdover: %d", onoff);
      if(onoff)
        m_acc.write(m_base + `ADDR_PSU_PTD, `PSU_PTD_DBG_HOLDOVER_ON);
      else
        m_acc.write(m_base + `ADDR_PSU_PTD, 'h0000);
   endtask;

   task dbg_dump_tx_ram();
      int i=0;
      int word_addr=0;
      int bank=0;
      uint64_t tmp;
      uint64_t dat;
      while(i<550)
      begin

        m_acc.write(m_base + `ADDR_PSU_PTD,
                     (i << `PSU_PTD_TX_RAM_RD_ADR_OFFSET) & `PSU_PTD_TX_RAM_RD_ADR);
        m_acc.read(m_base + `ADDR_PSU_PTD, tmp, 4);
        if(tmp & `PSU_PTD_TX_RAM_DAT_VALID) //is the data valid, otherwise retry
        begin 
	    dat = (tmp & `PSU_PTD_TX_RAM_RD_DAT) >> `PSU_PTD_TX_RAM_RD_DAT_OFFSET;
           if(i==0)    $display("[PSU-dump] === Bank 1 === \n" );
           if(i==256)  $display("[PSU-dump] === Bank 2 === \n" );
           if(i==512)  $display("[PSU-dump] == perport === \n" );
           if(i <335)  $display("addr = %2d bank=%d word=%2d : 0x4%x",i, bank,word_addr, 'hFFFFF & dat);
           else        $display("addr = %2d port=%d word=%2d : 0x4%x",i, bank,word_addr, 'hFFFFF & dat);
           i++;
           if     (i== 80) bank++;
           else if(i==335) bank=0;
           else if(i >355 && i%word_addr==0) bank++; 
           if(i>335 && i%word_addr==0) word_addr=0;
           else                        word_addr++;

           if(i== 80) begin i = 256; word_addr=0; bank++; end
           if(i==335) begin i = 512; word_addr=0; bank=0; end 
        end
      end
   endtask;

endclass // CSimDrv_PSU

`endif //  `ifndef __SIMDRV_PSU_SVH
