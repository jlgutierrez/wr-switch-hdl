`ifndef __SIMDRV_WR_TRU_SVH
`define __SIMDRV_WR_TRU_SVH 1
`timescale 1ns/1ps

`include "simdrv_defs.svh"
`include "tru_wb_regs.v"

class CSimDrv_WR_TRU;

   protected CBusAccessor m_acc;
   protected uint64_t m_base;
   
   function new(CBusAccessor acc, uint64_t base);     
      m_acc   = acc;
      m_base  = base;
   endfunction // new

   task write_tru_tab(int valid,      int fid,          int subfid, 
                      int patrn_mask, int patrn_match,  int patrn_mode,
                      int ports_mask, int ports_egress, int ports_ingress);
      
      m_acc.write(m_base + `ADDR_TRU_TTR1, ports_ingress);
      m_acc.write(m_base + `ADDR_TRU_TTR2, ports_egress);
      m_acc.write(m_base + `ADDR_TRU_TTR3, ports_mask);
      m_acc.write(m_base + `ADDR_TRU_TTR4, patrn_match);
      m_acc.write(m_base + `ADDR_TRU_TTR5, patrn_mask);
      // write
      m_acc.write(m_base + `ADDR_TRU_TTR0, fid        << `TRU_TTR0_FID_OFFSET        | 
                                           subfid     << `TRU_TTR0_SUB_FID_OFFSET    |
                                           valid      << `TRU_TTR0_MASK_VALID_OFFSET |
                                           patrn_mode << `TRU_TTR0_PATRN_MODE_OFFSET |
                                             1        << `TRU_TTR0_UPDATE_OFFSET     );
   endtask;

   task transition_config(int mode,      int rx_id,       int prio, int time_diff,
                     int port_a_id, int port_b_id);

      m_acc.write(m_base +`ADDR_TRU_TCGR,  mode       << `TRU_TCGR_TRANS_MODE_OFFSET  |
                                           rx_id      << `TRU_TCGR_TRANS_RX_ID_OFFSET |
                                           prio       << `TRU_TCGR_TRANS_PRIO_OFFSET  |
                                           time_diff  << `TRU_TCGR_TRANS_TIME_DIFF_OFFSET);
        
      m_acc.write(m_base +`ADDR_TRU_TCPR,  port_a_id  << `TRU_TCPR_TRANS_PORT_A_ID_OFFSET    |
                                           1          << `TRU_TCPR_TRANS_PORT_A_VALID_OFFSET |
                                           port_b_id  << `TRU_TCPR_TRANS_PORT_B_ID_OFFSET    |
                                           1          << `TRU_TCPR_TRANS_PORT_B_VALID_OFFSET);         
   endtask;

   task transition_enable();
      uint64_t tmp;
      m_acc.read(m_base + `ADDR_TRU_TCGR, tmp, 4);
      m_acc.write(m_base +`ADDR_TRU_TCGR, tmp | 1 << `TRU_TCGR_TRANS_ENA_OFFSET);      
   endtask;

   task transition_disable();
      uint64_t tmp;
      m_acc.read(m_base + `ADDR_TRU_TCGR, tmp, 4);
      m_acc.write(m_base +`ADDR_TRU_TCGR, tmp & ! (1 << `TRU_TCGR_TRANS_ENA_OFFSET));      
   endtask;

   task transition_clear();
      uint64_t tmp;
      m_acc.read(m_base + `ADDR_TRU_TCGR, tmp, 4);
      m_acc.write(m_base +`ADDR_TRU_TCGR, tmp & 1 << `TRU_TCGR_TRANS_CLEAR_OFFSET);      
   endtask;

   task pattern_config(int replacement,  int addition);
      m_acc.write(m_base +`ADDR_TRU_MCR,  replacement << `TRU_MCR_PATTERN_MODE_REP_OFFSET  |
                                          addition    << `TRU_MCR_PATTERN_MODE_ADD_OFFSET);    
   endtask;

   task tru_enable();
      m_acc.write(m_base + `ADDR_TRU_GCR,  1 << `TRU_GCR_G_ENA_OFFSET);    
   endtask;

   task tru_swap_bank();
      uint64_t tmp;
      m_acc.read(m_base + `ADDR_TRU_GCR, tmp, 4);
      m_acc.write(m_base +`ADDR_TRU_GCR, tmp |  1 << `TRU_GCR_TRU_BANK_OFFSET);    
   endtask;

   task tru_rx_frame_reset(int reset_rx);
      uint64_t tmp;
      m_acc.read(m_base + `ADDR_TRU_GCR, tmp, 4);
      m_acc.write(m_base +`ADDR_TRU_GCR, tmp |  reset_rx << `TRU_GCR_RX_FRAME_RESET_OFFSET);    
   endtask;

   task rt_reconf_config(int tx_frame_id, int rx_frame_id, int mode);
      uint64_t tmp;
      m_acc.read(m_base + `ADDR_TRU_RTRCR, tmp, 4);
      m_acc.write(m_base +`ADDR_TRU_RTRCR, tmp  & 'h000F                             |  
                                           mode        << `TRU_RTRCR_RTR_MODE_OFFSET |
                                           rx_frame_id << `TRU_RTRCR_RTR_RX_OFFSET   |
                                           tx_frame_id << `TRU_RTRCR_RTR_TX_OFFSET   );    
   endtask;

   task rt_reconf_enable();
      uint64_t tmp;
      m_acc.read(m_base + `ADDR_TRU_RTRCR, tmp, 4);
      m_acc.write(m_base +`ADDR_TRU_RTRCR, tmp |  1 << `TRU_RTRCR_RTR_ENA_OFFSET);    
   endtask;

   task rt_reconf_disable();
      uint64_t tmp;
      m_acc.read(m_base + `ADDR_TRU_RTRCR, tmp, 4);
      m_acc.write(m_base +`ADDR_TRU_RTRCR, tmp |  !(1 << `TRU_RTRCR_RTR_ENA_OFFSET));    
   endtask;

   task rt_reconf_reset();
      uint64_t tmp;
      m_acc.read(m_base + `ADDR_TRU_RTRCR, tmp, 4);
      m_acc.write(m_base +`ADDR_TRU_RTRCR, tmp |  1 << `TRU_RTRCR_RTR_RESET_OFFSET);    
   endtask;
   
   task read_status(output int bank, output int ports_up, output int ports_stb_up);
      uint64_t tmp;
      
      m_acc.read(m_base + `ADDR_TRU_GSR0, tmp, 4); 
      bank         = (tmp & `TRU_GSR0_STAT_BANK)   >> `TRU_GSR0_STAT_BANK_OFFSET;
      ports_stb_up = (tmp & `TRU_GSR0_STAT_STB_UP) >> `TRU_GSR0_STAT_STB_UP_OFFSET;
      
      m_acc.read(m_base + `ADDR_TRU_GSR1, tmp, 4);
      ports_up     = (tmp & `TRU_GSR1_STAT_UP) >> `TRU_GSR1_STAT_UP_OFFSET;
      
   endtask;

endclass // CSimDrv_WR_TRU

`endif //  `ifndef __SIMDRV_WR_TRU_SVH
