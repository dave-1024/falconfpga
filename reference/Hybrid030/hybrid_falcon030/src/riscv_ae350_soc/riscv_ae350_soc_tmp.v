//Copyright (C)2014-2026 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.12.03 (64-bit)
//IP Version: 1.2
//Part Number: GW5AST-LV138PG484AC1/I0
//Device: GW5AST-138
//Device Version: C
//Created Time: Tue Jul 14 20:46:30 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

	RiscV_AE350_SOC_Top your_instance_name(
		.FLASH_SPI_CSN(FLASH_SPI_CSN), //inout FLASH_SPI_CSN
		.FLASH_SPI_MISO(FLASH_SPI_MISO), //inout FLASH_SPI_MISO
		.FLASH_SPI_MOSI(FLASH_SPI_MOSI), //inout FLASH_SPI_MOSI
		.FLASH_SPI_CLK(FLASH_SPI_CLK), //inout FLASH_SPI_CLK
		.FLASH_SPI_HOLDN(FLASH_SPI_HOLDN), //inout FLASH_SPI_HOLDN
		.FLASH_SPI_WPN(FLASH_SPI_WPN), //inout FLASH_SPI_WPN
		.DDR3_MEMORY_CLK(DDR3_MEMORY_CLK), //input DDR3_MEMORY_CLK
		.DDR3_CLK_IN(DDR3_CLK_IN), //input DDR3_CLK_IN
		.DDR3_RSTN(DDR3_RSTN), //input DDR3_RSTN
		.DDR3_LOCK(DDR3_LOCK), //input DDR3_LOCK
		.DDR3_STOP(DDR3_STOP), //output DDR3_STOP
		.DDR3_INIT(DDR3_INIT), //output DDR3_INIT
		.DDR3_BANK(DDR3_BANK), //output [2:0] DDR3_BANK
		.DDR3_CS_N(DDR3_CS_N), //output DDR3_CS_N
		.DDR3_RAS_N(DDR3_RAS_N), //output DDR3_RAS_N
		.DDR3_CAS_N(DDR3_CAS_N), //output DDR3_CAS_N
		.DDR3_WE_N(DDR3_WE_N), //output DDR3_WE_N
		.DDR3_CK(DDR3_CK), //output DDR3_CK
		.DDR3_CK_N(DDR3_CK_N), //output DDR3_CK_N
		.DDR3_CKE(DDR3_CKE), //output DDR3_CKE
		.DDR3_RESET_N(DDR3_RESET_N), //output DDR3_RESET_N
		.DDR3_ODT(DDR3_ODT), //output DDR3_ODT
		.DDR3_ADDR(DDR3_ADDR), //output [13:0] DDR3_ADDR
		.DDR3_DM(DDR3_DM), //output [1:0] DDR3_DM
		.DDR3_DQ(DDR3_DQ), //inout [15:0] DDR3_DQ
		.DDR3_DQS(DDR3_DQS), //inout [1:0] DDR3_DQS
		.DDR3_DQS_N(DDR3_DQS_N), //inout [1:0] DDR3_DQS_N
		.clk_lane4(clk_lane4), //input clk_lane4
		.addr_lane4(addr_lane4), //input [31:0] addr_lane4
		.wr_mask_lane4(wr_mask_lane4), //input [3:0] wr_mask_lane4
		.wr_data_lane4(wr_data_lane4), //input [31:0] wr_data_lane4
		.wr_en_lane4(wr_en_lane4), //input wr_en_lane4
		.wr_go_lane4(wr_go_lane4), //input wr_go_lane4
		.burstcount_lane4(burstcount_lane4), //input [7:0] burstcount_lane4
		.wr_wait_lane4(wr_wait_lane4), //output wr_wait_lane4
		.wr_done_lane4(wr_done_lane4), //output wr_done_lane4
		.clk_lane5(clk_lane5), //input clk_lane5
		.addr_lane5(addr_lane5), //input [31:0] addr_lane5
		.rd_en_lane5(rd_en_lane5), //input rd_en_lane5
		.rd_go_lane5(rd_go_lane5), //input rd_go_lane5
		.burstcount_lane5(burstcount_lane5), //input [7:0] burstcount_lane5
		.rd_valid_lane5(rd_valid_lane5), //output rd_valid_lane5
		.rd_data_lane5(rd_data_lane5), //output [31:0] rd_data_lane5
		.rd_rdy_lane5(rd_rdy_lane5), //output rd_rdy_lane5
		.TCK_IN(TCK_IN), //input TCK_IN
		.TMS_IN(TMS_IN), //input TMS_IN
		.TRST_IN(TRST_IN), //input TRST_IN
		.TDI_IN(TDI_IN), //input TDI_IN
		.TDO_OUT(TDO_OUT), //output TDO_OUT
		.TDO_OE(TDO_OE), //output TDO_OE
		.EXTM_HADDR(EXTM_HADDR), //input [31:0] EXTM_HADDR
		.EXTM_HBURST(EXTM_HBURST), //input [2:0] EXTM_HBURST
		.EXTM_HPROT(EXTM_HPROT), //input [3:0] EXTM_HPROT
		.EXTM_HREADY(EXTM_HREADY), //input EXTM_HREADY
		.EXTM_HSEL(EXTM_HSEL), //input EXTM_HSEL
		.EXTM_HSIZE(EXTM_HSIZE), //input [2:0] EXTM_HSIZE
		.EXTM_HTRANS(EXTM_HTRANS), //input [1:0] EXTM_HTRANS
		.EXTM_HWDATA(EXTM_HWDATA), //input [63:0] EXTM_HWDATA
		.EXTM_HWRITE(EXTM_HWRITE), //input EXTM_HWRITE
		.EXTM_HRDATA(EXTM_HRDATA), //output [63:0] EXTM_HRDATA
		.EXTM_HREADYOUT(EXTM_HREADYOUT), //output EXTM_HREADYOUT
		.EXTM_HRESP(EXTM_HRESP), //output EXTM_HRESP
		.UART2_TXD(UART2_TXD), //output UART2_TXD
		.UART2_RTSN(UART2_RTSN), //output UART2_RTSN
		.UART2_RXD(UART2_RXD), //input UART2_RXD
		.UART2_CTSN(UART2_CTSN), //input UART2_CTSN
		.UART2_DCDN(UART2_DCDN), //input UART2_DCDN
		.UART2_DSRN(UART2_DSRN), //input UART2_DSRN
		.UART2_RIN(UART2_RIN), //input UART2_RIN
		.UART2_DTRN(UART2_DTRN), //output UART2_DTRN
		.UART2_OUT1N(UART2_OUT1N), //output UART2_OUT1N
		.UART2_OUT2N(UART2_OUT2N), //output UART2_OUT2N
		.GPIO(GPIO), //inout [31:0] GPIO
		.CORE_CLK(CORE_CLK), //input CORE_CLK
		.DDR_CLK(DDR_CLK), //input DDR_CLK
		.AHB_CLK(AHB_CLK), //input AHB_CLK
		.APB_CLK(APB_CLK), //input APB_CLK
		.RTC_CLK(RTC_CLK), //input RTC_CLK
		.POR_RSTN(POR_RSTN), //input POR_RSTN
		.HW_RSTN(HW_RSTN) //input HW_RSTN
	);

//--------Copy end-------------------
