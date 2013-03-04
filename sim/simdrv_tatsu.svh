`ifndef __SIMDRV_WR_TATSU
`define __SIMDRV_WR_TATSU 1
`timescale 1ns/1ps

`include "simdrv_defs.svh"
`include "regs/tatsu_regs.v"



class CSimDrv_TATSU;

   protected CBusAccessor m_acc;
   protected uint64_t m_base;
   
   function new(CBusAccessor acc, uint64_t base, bit dbg=0);     
      m_acc         = acc;
      m_base        = base;
   endfunction // new

   task set_tatsu(bit[15:0] quanta,    bit[39:0] tm_tai, bit[27:0] tm_cycles, 
                  bit[ 7:0] prio_mask, bit[31:0] port_mask, bit[27:0] repeat_cycles);
      
      m_acc.write(m_base + `ADDR_TATSU_TSR0, 
                         (tm_tai[39:32] << `TATSU_TSR0_HTAI_OFFSET)   & `TATSU_TSR0_HTAI |
                         (prio_mask     << `TATSU_TSR0_PRIO_OFFSET)   & `TATSU_TSR0_PRIO |
                         (quanta        << `TATSU_TSR0_QNT_OFFSET)    & `TATSU_TSR0_QNT );
      m_acc.write(m_base + `ADDR_TATSU_TSR1, tm_tai[31:0]);
      m_acc.write(m_base + `ADDR_TATSU_TSR2, tm_cycles);
      m_acc.write(m_base + `ADDR_TATSU_TSR3, repeat_cycles & `TATSU_TSR3_CYC    );
      m_acc.write(m_base + `ADDR_TATSU_TSR4, port_mask);
      
      m_acc.write(m_base + `ADDR_TATSU_TCR, `TATSU_TCR_VALIDATE);
      
   endtask;

   task drop_at_HP_enable();
     uint64_t tmp;
     m_acc.read(m_base + `ADDR_TATSU_TCR, tmp, 4);
     m_acc.write(m_base + `ADDR_TATSU_TSR0, tmp |  `TATSU_TCR_DROP_ENA);
     $display("TATSU: enable drop at HP"); 
   endtask;

   task drop_at_HP_disable();
     uint64_t tmp;
     m_acc.read(m_base + `ADDR_TATSU_TCR, tmp, 4);
     m_acc.write(m_base + `ADDR_TATSU_TSR0, tmp &  ~(`TATSU_TCR_DROP_ENA));
     $display("TATSU: disable drop at HP"); 
   endtask;


//    task get_status(output int OK, output int error);
//      uint64_t tmp;
//      
//      m_acc.read(m_base + `ADDR_TATSU_TCR, tmp, 4);
//      OK    = (tmp & `TATSU_TCR_OK) >> `TATSU_TCR_OK_OFFSET;
//      error = (tmp & `TATSU_TCR_ERROR) >> `TATSU_TCR_ERROR_OFFSET;
//      $display("TATSU status: OK=%1d  Error=%1d", OK, error);
//    
//    endtask;

   task print_status();
     uint64_t tmp;
     int OK, error;
     m_acc.read(m_base + `ADDR_TATSU_TCR, tmp, 4);
     $display("TATSU status: [raw=x%x]",tmp);
     if(tmp & `TATSU_TCR_STARTED)      $display("\t TATSU started");
     if(tmp & `TATSU_TCR_DELAYED)      $display("\t TATSU starte delayed");
     if(tmp & `TATSU_TCR_STG_ERR)      $display("\t ERROR");
     if(tmp & `TATSU_TCR_STG_OK)       $display("\t Settings OK");
     if(tmp & `TATSU_TCR_STG_ERR_TAI)  $display("\t Settings ERROR: TAI value");
     if(tmp & `TATSU_TCR_STG_ERR_CYC)  $display("\t Settings ERROR: cycle value");
     if(tmp & `TATSU_TCR_STG_ERR_RPT)  $display("\t Settings ERROR: repeat value");
     if(tmp & `TATSU_TCR_STG_ERR_SNC)  $display("\t Sync ERROR");
   endtask;

endclass // CSimDrv_TATSU

`endif //  `ifndef __SIMDRV_TATSU_SVH
