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

   task init(bit[2:0] inj_prio, bit[15:0] holdover_clk_class, bit ignore_rx_port_id,
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
      uint64_t i;
      uint64_t tmp;
      uint64_t dat;
      for(i=0;i<1024;i++)
      begin
        m_acc.write(m_base + `ADDR_PSU_PTD,
                                                            `PSU_PTD_TX_RAM_RD_ENA |
                     (i << `PSU_PTD_TX_RAM_RD_ADR_OFFSET) & `PSU_PTD_TX_RAM_RD_ADR);
        m_acc.read(m_base + `ADDR_PSU_PTD, tmp, 4);
        dat = (tmp & `PSU_PTD_TX_RAM_RD_DAT) >> `PSU_PTD_TX_RAM_RD_DAT_OFFSET;
        if((dat >> 17) & 'h1) $display("%2d: 0x4%x",i, dat);
      end
        m_acc.write(m_base + `ADDR_PSU_PTD, 'h0000);
   endtask;

endclass // CSimDrv_PSU

`endif //  `ifndef __SIMDRV_PSU_SVH
