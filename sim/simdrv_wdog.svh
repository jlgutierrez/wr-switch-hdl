`ifndef __SIMDRV_WR_WDOG_SVH
`define __SIMDRV_WR_WDOG_SVH 1

`include "simdrv_defs.svh"
`include "regs/wdog_regs.vh"

class CSimDrv_WDOG;

  protected CBusAccessor m_acc;
  protected uint32_t m_base;

  const string alloc_FSM[0:5] = '{"S_IDLE",
                            "S_PCKSTART_SET_USECNT",
                            "S_PCKSTART_PAGE_REQ",
                            "S_PCKINTER_PAGE_REQ",
                            "S_PCKSTART_SET_AND_REQ",
                            "Unknown"};

  const string trans_FSM[0:10] = '{"S_IDLE",
                            "S_READY",
                            "S_WAIT_RTU_VALID",
                            "S_WAIT_SOF",
                            "S_SET_USECNT",
                            "S_WAIT_WITH_TRANSFER",
                            "S_TOO_LONG_TRANSFER",
                            "S_TRANSFER",
                            "S_TRANSFERRED",
                            "S_DROP",
                            "Unknown"};

  const string rcv_FSM[0:7] = '{"S_IDLE",
                            "S_READY",
                            "S_PAUSE",
                            "S_RCV_DATA",
                            "S_DROP",
                            "S_WAIT_FORCE_FREE",
                            "S_INPUT_STUCK",
                            "Unknown"};

  const string ll_FSM[0:6] = '{"S_IDLE",
                            "S_READY_FOR_PGR_AND_DLAST",
                            "S_READY_FOR_DLAST_ONLY",
                            "S_WRITE",
                            "S_EOF_ON_WR",
                            "S_SOF_ON_WR",
                            "Unknown"};

  const string prep_FSM[0:7] = '{"S_RETRY_READY",
                            "S_NEWPCK_PAGE_READY",
                            "S_NEWPCK_PAGE_SET_IN_ADV",
                            "S_NEWPCK_PAGE_USED",
                            "S_RETRY_PREPARE",
                            "S_IDLE",
                            "Unknown",
                            "Frozen"};

  const string send_FSM[0:7] = '{"S_IDLE",
                            "S_DATA",
                            "S_FLUSH_STALL",
                            "S_FINISH_CYCLE",
                            "S_EOF",
                            "S_RETRY",
                            "S_WAIT_FREE_PCK",
                            "Unknown"};

  const string free_FSM[0:7] = '{"S_IDLE",
                            "S_REQ_READ_FIFO",
                            "S_READ_FIFO",
                            "S_READ_NEXT_PAGE_ADDR",
                            "S_FREE_CURRENT_PAGE_ADDR",
                            "S_FORCE_FREE_CURRENT_PAGE_ADDR",
                            "S_",
                            "Unknown"};

  function new(CBusAccessor acc, uint64_t base);
    m_acc   = acc;
    m_base  = base;
  endfunction;

  task print_fsms(int port);
    uint64_t fsms;
    uint64_t act;
    int act_tab[0:6];

    m_acc.write(m_base + `ADDR_WDOG_CR, (port << `WDOG_CR_PORT_OFFSET));
    m_acc.read(m_base + `ADDR_WDOG_FSM, fsms, 4);
    m_acc.read(m_base + `ADDR_WDOG_ACT, act, 4);
    for(int i=0; i<=6; i++) begin
      act_tab[i] = (act & (1<<i)) >> i;
    end

    $display("Alloc ", act_tab[0], ": ",alloc_FSM[(fsms & `WDOG_FSM_IB_ALLOC)>>`WDOG_FSM_IB_ALLOC_OFFSET]);
    $display("Trans ", act_tab[1], ": ",trans_FSM[(fsms & `WDOG_FSM_IB_TRANS)>>`WDOG_FSM_IB_TRANS_OFFSET]);
    $display("Rcv   ", act_tab[2], ": ",rcv_FSM[(fsms & `WDOG_FSM_IB_RCV)>>`WDOG_FSM_IB_RCV_OFFSET]);
    $display("LL    ", act_tab[3], ": ",ll_FSM[(fsms & `WDOG_FSM_IB_LL)>>`WDOG_FSM_IB_LL_OFFSET]);
    $display("Prep  ", act_tab[4], ": ",prep_FSM[(fsms & `WDOG_FSM_OB_PREP)>>`WDOG_FSM_OB_PREP_OFFSET]);
    $display("Send  ", act_tab[5], ": ",send_FSM[(fsms & `WDOG_FSM_OB_SEND)>>`WDOG_FSM_OB_SEND_OFFSET]);
    $display("Free  ", act_tab[6], ": ",free_FSM[(fsms & `WDOG_FSM_FREE)>>`WDOG_FSM_FREE_OFFSET]);

  endtask;

  task force_reset();
    m_acc.write(m_base + `ADDR_WDOG_CR, `WDOG_CR_RST);
  endtask;

endclass

`endif
