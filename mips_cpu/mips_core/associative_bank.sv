module associative_bank #(parameter DATA_WIDTH = 32, parameter ADDR_WIDTH = 4)(
	input clk,	// Clock
	input i_we,	// Write enable
	input logic [DATA_WIDTH - 1 : 0] i_wdata,			// Write data
	input logic [ADDR_WIDTH - 1 : 0] i_waddr, i_raddr,	// Write/read address
	output logic [DATA_WIDTH - 1 : 0] o_rdata,			// Read data
	output logic hit;
);

	// A register to store new_data
	logic [DATA_WIDTH - 1 : 0] new_data;

	// The registered output of cache_bank_core
	logic [DATA_WIDTH - 1 : 0] old_data;

	// A flag to determine whether the last cycle write data (new_data) or
	// the read output (old_data) should be presented at the output port.
	logic new_data_flag;

	// Fully associattive cache table
    localparam TABLE_BITS = 4;
	localparam DEPTH = 1 << TABLE_BITS;					// Associative cache size of 4
	logic [ADDR_WIDTH - 1 : 0] addr_table [DEPTH : 0];
	logic [DATA_WIDTH - 1 : 0] data_table [DEPTH : 0];
    logic [TABLE_BITS - 1 : 0] lru = '0;

	always_ff @( posedge clk ) begin
        if (i_we) begin
            addr_table[lru] <= i_waddr;
            data_table[lru] <= i_wdata;
            old_data <= i_wdata;            // does not matter because we are writing to table and not reading
            lru <= (lru + 1) % DEPTH;
        end
        else begin
            for (int i = 0; i < DEPTH; i++) begin
                if (addr_table[i] == i_raddr) begin
                    old_data <= data_table[i];
					hit = '1;
                    break;
                end
				else begin
					hit = '0;
					old_data <= '0;
				end
            end
        end
	end

	assign o_rdata = new_data_flag ? new_data : old_data;

	always_ff @(posedge clk)
	begin
		new_data <= i_wdata;
		new_data_flag <= i_we & (i_raddr == i_waddr);
	end
endmodule