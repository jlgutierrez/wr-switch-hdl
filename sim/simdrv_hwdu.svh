`ifndef __SIMDRV_WR_HWDU
`define __SIMDRV_WR_HWDU 1
`timescale 1ns/1ps

`include "simdrv_defs.svh"
`include "regs/hwdu_regs.v"



class CSimDrv_HWDU;

   protected CBusAccessor m_acc;
   protected uint64_t m_base;
   
   function new(CBusAccessor acc, uint64_t base, bit dbg=0);     
      m_acc         = acc;
      m_base        = base;
   endfunction // new

   task set_tatsu(bit[15:0] addr);
      
      uint64_t tmp;
      m_acc.write(m_base + `ADDR_HWDU_CR, 
                           `HWDU_CR_RD_EN | (`HWDU_CR_ADR & (addr << `HWDU_CR_ADR_OFFSET)) );
      m_acc.read(m_base + `ADDR_HWDU_REG_VAL, tmp, 4);
      $display("HWDU: raw_val: 0x%x, addr: 0%d",tmp, addr);
      $display("HWDU: unused res: %d",'h3FF & tmp);
      $display("HWDU: hp     res: %d",'h3FF & (tmp >> 10));
      $display("HWDU: normal res: %d",'h3FF & (tmp >> 20));
      
   endtask;

endclass // CSimDrv_TATSU

`endif //  `ifndef __SIMDRV_TATSU_SVH
