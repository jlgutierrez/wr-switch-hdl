`ifndef __SIMDRV_WR_TXTSU_SVH
`define __SIMDRV_WR_TXTSU_SVH 1

`timescale 1ns/1ps

`include "simdrv_defs.svh"
`include "regs/txtsu_regs.vh"

class CSimDrv_TXTSU;

   CBusAccessor acc_regs;
   
   uint64_t base_addr;
   
   function new(CBusAccessor regs_, uint64_t base_addr_);
      base_addr      = base_addr_;
      acc_regs       = regs_;
  endfunction // new

   task init();
      writel(`ADDR_TXTSU_EIC_IER, 1);
   endtask // init
   
   
   task writel(uint32_t addr, uint32_t val);
      acc_regs.write(base_addr + addr, val, 4);
   endtask // writel

   task readl(uint32_t addr, output uint32_t val);
      uint64_t tmp;
      acc_regs.read(base_addr + addr, tmp, 4);
      val  = tmp;
   endtask // readl

   task update(bit txts_irq);
      uint32_t csr, r0, r1, r2;
      
      if(!txts_irq)
        return;

      while(1) begin
         readl(`ADDR_TXTSU_TSF_CSR, csr);

         if(csr & `TXTSU_TSF_CSR_EMPTY)
           break;

         
         readl(`ADDR_TXTSU_TSF_R0, r0);
         readl(`ADDR_TXTSU_TSF_R1, r1);
         readl(`ADDR_TXTSU_TSF_R2, r2);
         $display("txtsu: val %x pid %d fid %d incorrect %1b", r0, r1 & 'h1f, r1 >> 16, r2 & 1);
      end // while (1)
   endtask // update

endclass

`endif //  `ifndef __SIMDRV_WR_TXTSU_SVH

