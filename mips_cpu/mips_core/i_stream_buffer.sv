`include "mips_core.svh"

module i_stream_buffer #(
    parameter INDEX_WIDTH = 6, // 1 KB Cahe size 
	parameter BLOCK_OFFSET_WIDTH = 2,
    parameter BUF_DEPTH = 10,
    parameter DATA_WIDTH = 32
) (
    // General signals
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low

    // Request
	pc_ifc.in i_pc_current,
	pc_ifc.in i_pc_next,

    // From hazard controller
    input i_cache_miss,

    // Response
	cache_output_ifc.out out,

    // Memory interface
	axi_read_address.master mem_read_address,
	axi_read_data.master mem_read_data
);

    logic [DATA_WIDTH-1 :  0] data_table [BUF_DEPTH-1 :  0];

    initial begin
        for (int i = 0; i < BUF_DEPTH; i++) begin
            data_table[i] = '0;
        end
    end

    always_ff @( i_cache_miss ) begin
        if (i_cache_miss) begin
            data_table[0] = mem_read_data.RDATA;
            $display("pc", i_pc_current.pc);
        end
    end
endmodule


// Plan
// Connect the output correctly to decode
// Implement the fetchings
//      - Predictor logic
//      - update table data
// Multiple stream buffers