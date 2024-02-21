/*
 * cache_bank.sv
 * Author: Zinsser Zhang
 * Last Revision: 03/13/2022
 *
 * TODO update doc
 *
 * cache_bank provides a storage with one synchronous read and one synchronous
 * write port. When reading and writing to the same address, new data is
 * presented at the read port.
 *
 * cache_bank_core is a hint to Quartus's compiler to synthesis it to block ram.
 * Block rams in FPGA only support synchronous read and write (old data is
 * presented at the read port). So we need extra logic in cache_bank to forward
 * the new data.
 *
 * See wiki page "Synchronous Caches" for details.
 */
module cache_bank_double_access #(parameter DATA_WIDTH = 32, parameter ADDR_WIDTH = 4)(
	input clk,	// Clock
	input i_we,	// Write enable
	input logic [DATA_WIDTH - 1 : 0] i_wdata,			// Write data
	input logic [ADDR_WIDTH - 1 : 0] i_waddr, i_raddr,	// Write/read address
	output logic [DATA_WIDTH - 1 : 0] o_rdata,			// Read data

    // Double access
    input i_we2,	// Write enable
	input logic [DATA_WIDTH - 1 : 0] i_wdata2,			// Write data
	input logic [ADDR_WIDTH - 1 : 0] i_waddr2, i_raddr2,	// Write/read address
	output logic [DATA_WIDTH - 1 : 0] o_rdata2			// Read data
);

	// A register to store new_data
	logic [DATA_WIDTH - 1 : 0] new_data;
    logic [DATA_WIDTH - 1 : 0] new_data2;

	// The registered output of cache_bank_core
	logic [DATA_WIDTH - 1 : 0] old_data;
    logic [DATA_WIDTH - 1 : 0] old_data2;

	// A flag to determine whether the last cycle write data (new_data) or
	// the read output (old_data) should be presented at the output port.
	logic new_data_flag;
    logic new_data_flag2;

	generate
		if (ADDR_WIDTH < 4) begin
			// OpenRAM requires at least 16 rows
			// Use register based structure for shallow RAMs
			cache_bank_core_double_access #(DATA_WIDTH, ADDR_WIDTH)
				BANK_CORE (
					.clk, .i_we, .i_waddr, .i_raddr, .i_wdata,
					.o_rdata(old_data),
                    .i_we2, .i_waddr2, .i_raddr2, .i_wdata2,
					.o_rdata2(old_data2)
			);
		end else begin
			sram_double_access #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) BANK_CORE (
				// Port 0: W
				.clk0(clk), .csb0(~i_we), .addr0(i_waddr), .din0(i_wdata),
				// Port 1: R
				.clk1(clk), .csb1('0), .addr1(i_raddr), .dout1(old_data),

                // Port 0: W
				.clk02(clk), .csb02(~i_we2), .addr02(i_waddr2), .din02(i_wdata2),
				// Port 1: R
				.clk12(clk), .csb12('0), .addr12(i_raddr2), .dout12(old_data2)
			);
		end
	endgenerate

	assign o_rdata = new_data_flag ? new_data : old_data;
    assign o_rdata2 = new_data_flag2 ? new_data2 : old_data2;

	always_ff @(posedge clk)
	begin
		new_data <= i_wdata;
		new_data_flag <= i_we & (i_raddr == i_waddr);

        new_data2 <= i_wdata2;
		new_data_flag2 <= i_we2 & (i_raddr2 == i_waddr2);
	end
endmodule

module cache_bank_core_double_access #(parameter DATA_WIDTH = 32, parameter ADDR_WIDTH = 4)(
	input clk,	// Clock
	input i_we,	// Write enable
	input logic [DATA_WIDTH - 1 : 0] i_wdata,			// Write data
	input logic [ADDR_WIDTH - 1 : 0] i_waddr, i_raddr,	// Write/read address
	output logic [DATA_WIDTH - 1 : 0] o_rdata,			// Read data

    input i_we2,	// Write enable
	input logic [DATA_WIDTH - 1 : 0] i_wdata2,			// Write data
	input logic [ADDR_WIDTH - 1 : 0] i_waddr2, i_raddr2,	// Write/read address
	output logic [DATA_WIDTH - 1 : 0] o_rdata2			// Read data
);
	localparam DEPTH = 1 << ADDR_WIDTH;

	logic [DATA_WIDTH - 1 : 0] data [DEPTH];
    logic [DATA_WIDTH - 1 : 0] data2 [DEPTH];

	always_ff @(posedge clk)
	begin
		o_rdata <= data[i_raddr];
        o_rdata2 <= data2[i_raddr2];
		if (i_we)
			data[i_waddr] <= i_wdata;
        if (i_we2)
			data[i_waddr2] <= i_wdata2;
	end
endmodule

`ifdef SIMULATION
// OpenRAM SRAM model
module sram_double_access(
// Port 0: W
		clk0,csb0,addr0,din0,
// Port 1: R
		clk1,csb1,addr1,dout1,
// Port 0: W
		clk02,csb02,addr02,din02,
// Port 1: R
		clk12,csb12,addr12,dout12
	);

	parameter DATA_WIDTH = 32 ;
	parameter ADDR_WIDTH = 4 ;
	parameter RAM_DEPTH = 1 << ADDR_WIDTH;
	// FIXME: This delay is arbitrary.
	// parameter DELAY = 3 ;

	input  clk0; // clock
	input   csb0; // active low chip select
	input [ADDR_WIDTH-1:0]  addr0;
	input [DATA_WIDTH-1:0]  din0;
	input  clk1; // clock
	input   csb1; // active low chip select
	input [ADDR_WIDTH-1:0]  addr1;
	output [DATA_WIDTH-1:0] dout1;

    input  clk02; // clock
	input   csb02; // active low chip select
	input [ADDR_WIDTH-1:0]  addr02;
	input [DATA_WIDTH-1:0]  din02;
	input  clk12; // clock
	input   csb12; // active low chip select
	input [ADDR_WIDTH-1:0]  addr12;
	output [DATA_WIDTH-1:0] dout12;

	reg  csb0_reg;
	reg [ADDR_WIDTH-1:0]  addr0_reg;
	reg [DATA_WIDTH-1:0]  din0_reg;

    reg  csb0_reg2;
	reg [ADDR_WIDTH-1:0]  addr0_reg2;
	reg [DATA_WIDTH-1:0]  din0_reg2;

	// All inputs are registers
	always @(posedge clk0)
	begin
		csb0_reg = csb0;
		addr0_reg = addr0;
		din0_reg = din0;
		// if ( !csb0_reg )
		// 	$display($time," Writing %m addr0=%b din0=%b",addr0_reg,din0_reg);
	end

    always @(posedge clk02)
	begin
		csb0_reg2 = csb02;
		addr0_reg2 = addr02;
		din0_reg2 = din02;
		// if ( !csb0_reg )
		// 	$display($time," Writing %m addr0=%b din0=%b",addr0_reg,din0_reg);
	end

	reg  csb1_reg;
	reg [ADDR_WIDTH-1:0]  addr1_reg;
	reg [DATA_WIDTH-1:0]  dout1;

    reg  csb1_reg2;
	reg [ADDR_WIDTH-1:0]  addr1_reg2;
	reg [DATA_WIDTH-1:0]  dout12;

	// All inputs are registers
	always @(posedge clk1)
	begin
		csb1_reg = csb1;
		addr1_reg = addr1;
		// if (!csb0 && !csb1 && (addr0 == addr1))
		// 		 $display($time," WARNING: Writing and reading addr0=%b and addr1=%b simultaneously!",addr0,addr1);
		// dout1 = 32'bx;
		// if ( !csb1_reg )
		// 	$display($time," Reading %m addr1=%b dout1=%b",addr1_reg,mem[addr1_reg]);
	end

    always @(posedge clk12)
	begin
		csb1_reg2 = csb12;
		addr1_reg2 = addr12;
		// if (!csb0 && !csb1 && (addr0 == addr1))
		// 		 $display($time," WARNING: Writing and reading addr0=%b and addr1=%b simultaneously!",addr0,addr1);
		// dout1 = 32'bx;
		// if ( !csb1_reg )
		// 	$display($time," Reading %m addr1=%b dout1=%b",addr1_reg,mem[addr1_reg]);
	end

reg [DATA_WIDTH-1:0]    mem [0:RAM_DEPTH-1];

	// Memory Write Block Port 0
	// Write Operation : When web0 = 0, csb0 = 0
	always @ (negedge clk0)
	begin : MEM_WRITE0
		if (!csb0_reg)
				mem[addr0_reg] = din0_reg;
	end

    always @ (negedge clk02)
	begin : MEM_WRITE02
		if (!csb0_reg2)
				mem[addr0_reg2] = din0_reg2;
	end

	// Memory Read Block Port 1
	// Read Operation : When web1 = 1, csb1 = 0
	always @ (negedge clk1)
	begin : MEM_READ1
		if (!csb1_reg)
			 dout1 <= /* #(DELAY) */ mem[addr1_reg];
	end

    always @ (negedge clk12)
	begin : MEM_READ12
		if (!csb1_reg2)
			 dout12 <= /* #(DELAY) */ mem[addr1_reg2];
	end

endmodule
`endif
