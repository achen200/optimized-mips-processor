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

    // I cache Output
    cache_output_ifc.in ic_out,

    // From hazard controller
    input i_cache_miss,

    // Response
	cache_output_ifc.out sb_out,

    // Memory interface
	axi_read_address.master mem_read_address,
	axi_read_data.master mem_read_data
);

    logic [DATA_WIDTH-1 : 0] data_table [BUF_DEPTH-1 :  0];
    logic [`ADDR_WIDTH-1 : 0] pc_table [BUF_DEPTH-1 : 0];

    // Output of SB 1
    logic intermediate1_valid;	// Output Valid
	logic [DATA_WIDTH - 1 : 0] intermediate1_data;

    initial begin
        for (int i = 0; i < BUF_DEPTH; i++) begin
            pc_table[i] = '0;
            data_table[i] = '0;
        end
    end

    always_ff @( posedge clk ) begin
        for (int i = 0; i < BUF_DEPTH; i++) begin
            // TODO: Check if current or next
            if (i_pc_current.pc != 0 && i_pc_current.pc == pc_table[i]) begin
                intermediate1_data = data_table[i];
                intermediate1_valid = '1;
            end
            else begin
                intermediate1_valid = '0;
            end
        end
    end

    always_ff @( i_cache_miss ) begin
        if (i_cache_miss) begin
            data_table[0] = mem_read_data.RDATA;
            // $display("pc", i_pc_current.pc);
        end
    end

    always_comb begin
        if (ic_out.valid) begin
            sb_out.valid = ic_out.valid;
            sb_out.data  = ic_out.data;
        end
        else if (intermediate1_valid)begin
            sb_out.valid = intermediate1_valid;
            sb_out.data  = intermediate1_data;
        end
        else begin
            sb_out.valid = ic_out.valid;
            sb_out.data  = ic_out.data;
        end
    end

endmodule


// Plan
// Implement the fetchings
//      - Predictor logic
//      - update table data
// Data is being fetched 4 instructions in one memeory access
//      - Deal with this problem