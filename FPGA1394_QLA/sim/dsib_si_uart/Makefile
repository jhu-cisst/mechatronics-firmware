VERILATOR ?= verilator
export CCACHE_DISABLE := 1

SRC_DIR := ../../Verilog
BUILD_DIR := obj_dir
UART_BUILD_DIR := $(BUILD_DIR)/uart
PARSER_BUILD_DIR := $(BUILD_DIR)/parser

.PHONY: sim uart parser clean

sim: uart parser

uart:
	@mkdir -p $(UART_BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-fatal \
		-Wno-BLKSEQ -Wno-DECLFILENAME -Wno-PROCASSINIT -Wno-UNUSEDSIGNAL \
		--top-module tb_dsib_si_uart \
		tb_dsib_si_uart.sv \
		$(SRC_DIR)/dsib_si_uart.v \
		-Mdir $(UART_BUILD_DIR)
	./$(UART_BUILD_DIR)/Vtb_dsib_si_uart

parser:
	@mkdir -p $(PARSER_BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-fatal \
		-Wno-BLKSEQ -Wno-DECLFILENAME -Wno-PROCASSINIT -Wno-UNUSEDSIGNAL \
		--top-module tb_dsib_si_parser \
		tb_dsib_si_parser.sv \
		$(SRC_DIR)/dsib_si_parser.v \
		$(SRC_DIR)/Crc16.v \
		-Mdir $(PARSER_BUILD_DIR)
	./$(PARSER_BUILD_DIR)/Vtb_dsib_si_parser

clean:
	rm -rf $(BUILD_DIR)
