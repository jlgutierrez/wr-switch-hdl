`define ADDR_TRU_GCR                   6'h0
`define TRU_GCR_G_ENA_OFFSET 0
`define TRU_GCR_G_ENA 32'h00000001
`define TRU_GCR_TRU_BANK_OFFSET 1
`define TRU_GCR_TRU_BANK 32'h00000002
`define TRU_GCR_RX_FRAME_RESET_OFFSET 8
`define TRU_GCR_RX_FRAME_RESET 32'hffffff00
`define ADDR_TRU_GSR0                  6'h4
`define TRU_GSR0_STAT_BANK_OFFSET 0
`define TRU_GSR0_STAT_BANK 32'h00000001
`define TRU_GSR0_STAT_STB_UP_OFFSET 8
`define TRU_GSR0_STAT_STB_UP 32'hffffff00
`define ADDR_TRU_GSR1                  6'h8
`define TRU_GSR1_STAT_UP_OFFSET 0
`define TRU_GSR1_STAT_UP 32'hffffffff
`define ADDR_TRU_MCR                   6'hc
`define TRU_MCR_PATTERN_MODE_REP_OFFSET 0
`define TRU_MCR_PATTERN_MODE_REP 32'h0000000f
`define TRU_MCR_PATTERN_MODE_ADD_OFFSET 8
`define TRU_MCR_PATTERN_MODE_ADD 32'h00000f00
`define ADDR_TRU_LACR                  6'h10
`define TRU_LACR_AGG_GR_NUM_OFFSET 0
`define TRU_LACR_AGG_GR_NUM 32'h0000000f
`define TRU_LACR_AGG_DF_BR_ID_OFFSET 8
`define TRU_LACR_AGG_DF_BR_ID 32'h00000f00
`define TRU_LACR_AGG_DF_UN_ID_OFFSET 16
`define TRU_LACR_AGG_DF_UN_ID 32'h000f0000
`define ADDR_TRU_LAGT                  6'h14
`define TRU_LAGT_LAGT_GR_ID_MASK_0_OFFSET 0
`define TRU_LAGT_LAGT_GR_ID_MASK_0 32'h0000000f
`define TRU_LAGT_LAGT_GR_ID_MASK_1_OFFSET 4
`define TRU_LAGT_LAGT_GR_ID_MASK_1 32'h000000f0
`define TRU_LAGT_LAGT_GR_ID_MASK_2_OFFSET 8
`define TRU_LAGT_LAGT_GR_ID_MASK_2 32'h00000f00
`define TRU_LAGT_LAGT_GR_ID_MASK_3_OFFSET 12
`define TRU_LAGT_LAGT_GR_ID_MASK_3 32'h0000f000
`define TRU_LAGT_LAGT_GR_ID_MASK_4_OFFSET 16
`define TRU_LAGT_LAGT_GR_ID_MASK_4 32'h000f0000
`define TRU_LAGT_LAGT_GR_ID_MASK_5_OFFSET 20
`define TRU_LAGT_LAGT_GR_ID_MASK_5 32'h00f00000
`define TRU_LAGT_LAGT_GR_ID_MASK_6_OFFSET 24
`define TRU_LAGT_LAGT_GR_ID_MASK_6 32'h0f000000
`define TRU_LAGT_LAGT_GR_ID_MASK_7_OFFSET 28
`define TRU_LAGT_LAGT_GR_ID_MASK_7 32'hf0000000
`define ADDR_TRU_TCGR                  6'h18
`define TRU_TCGR_TRANS_ENA_OFFSET 0
`define TRU_TCGR_TRANS_ENA 32'h00000001
`define TRU_TCGR_TRANS_CLEAR_OFFSET 1
`define TRU_TCGR_TRANS_CLEAR 32'h00000002
`define TRU_TCGR_TRANS_MODE_OFFSET 4
`define TRU_TCGR_TRANS_MODE 32'h00000070
`define TRU_TCGR_TRANS_RX_ID_OFFSET 8
`define TRU_TCGR_TRANS_RX_ID 32'h00000700
`define TRU_TCGR_TRANS_PRIO_OFFSET 12
`define TRU_TCGR_TRANS_PRIO 32'h00007000
`define TRU_TCGR_TRANS_TIME_DIFF_OFFSET 16
`define TRU_TCGR_TRANS_TIME_DIFF 32'hffff0000
`define ADDR_TRU_TCPR                  6'h1c
`define TRU_TCPR_TRANS_PORT_A_ID_OFFSET 0
`define TRU_TCPR_TRANS_PORT_A_ID 32'h0000003f
`define TRU_TCPR_TRANS_PORT_A_VALID_OFFSET 8
`define TRU_TCPR_TRANS_PORT_A_VALID 32'h00000100
`define TRU_TCPR_TRANS_PORT_B_ID_OFFSET 16
`define TRU_TCPR_TRANS_PORT_B_ID 32'h003f0000
`define TRU_TCPR_TRANS_PORT_B_VALID_OFFSET 24
`define TRU_TCPR_TRANS_PORT_B_VALID 32'h01000000
`define ADDR_TRU_TSR                   6'h20
`define TRU_TSR_TRANS_STAT_ACTIVE_OFFSET 0
`define TRU_TSR_TRANS_STAT_ACTIVE 32'h00000001
`define TRU_TSR_TRANS_STAT_FINISHED_OFFSET 1
`define TRU_TSR_TRANS_STAT_FINISHED 32'h00000002
`define ADDR_TRU_RTRCR                 6'h24
`define TRU_RTRCR_RTR_ENA_OFFSET 0
`define TRU_RTRCR_RTR_ENA 32'h00000001
`define TRU_RTRCR_RTR_RESET_OFFSET 1
`define TRU_RTRCR_RTR_RESET 32'h00000002
`define TRU_RTRCR_RTR_MODE_OFFSET 8
`define TRU_RTRCR_RTR_MODE 32'h00000f00
`define TRU_RTRCR_RTR_RX_OFFSET 16
`define TRU_RTRCR_RTR_RX 32'h000f0000
`define TRU_RTRCR_RTR_TX_OFFSET 24
`define TRU_RTRCR_RTR_TX 32'h0f000000
`define ADDR_TRU_TTR0                  6'h28
`define TRU_TTR0_FID_OFFSET 0
`define TRU_TTR0_FID 32'h000000ff
`define TRU_TTR0_SUB_FID_OFFSET 8
`define TRU_TTR0_SUB_FID 32'h0000ff00
`define TRU_TTR0_UPDATE_OFFSET 16
`define TRU_TTR0_UPDATE 32'h00010000
`define TRU_TTR0_MASK_VALID_OFFSET 17
`define TRU_TTR0_MASK_VALID 32'h00020000
`define TRU_TTR0_PATRN_MODE_OFFSET 24
`define TRU_TTR0_PATRN_MODE 32'h0f000000
`define ADDR_TRU_TTR1                  6'h2c
`define TRU_TTR1_PORTS_INGRESS_OFFSET 0
`define TRU_TTR1_PORTS_INGRESS 32'hffffffff
`define ADDR_TRU_TTR2                  6'h30
`define TRU_TTR2_PORTS_EGRESS_OFFSET 0
`define TRU_TTR2_PORTS_EGRESS 32'hffffffff
`define ADDR_TRU_TTR3                  6'h34
`define TRU_TTR3_PORTS_MASK_OFFSET 0
`define TRU_TTR3_PORTS_MASK 32'hffffffff
`define ADDR_TRU_TTR4                  6'h38
`define TRU_TTR4_PATRN_MATCH_OFFSET 0
`define TRU_TTR4_PATRN_MATCH 32'hffffffff
`define ADDR_TRU_TTR5                  6'h3c
`define TRU_TTR5_PATRN_MASK_OFFSET 0
`define TRU_TTR5_PATRN_MASK 32'hffffffff
