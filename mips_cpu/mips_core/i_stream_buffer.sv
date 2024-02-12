`include "mips_core.svh"

module i_stream_buffer #(
    parameter INDEX_WIDTH = 6, // 1 KB Cahe size 
	parameter BLOCK_OFFSET_WIDTH = 2,
    parameter BUF_DEPTH = 8,
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
	localparam LINE_SIZE = 1 << BLOCK_OFFSET_WIDTH;
	localparam TAG_WIDTH = `ADDR_WIDTH - INDEX_WIDTH - BLOCK_OFFSET_WIDTH - 2;
	localparam LRU_WIDTH = 3; //set to log_2(buf_depth)
	


	logic [TAG_WIDTH-1:0] i_tag;
	logic [INDEX_WIDTH-1:0] i_index;
	logic [BLOCK_OFFSET_WIDTH-1:0] i_block_offset;

    logic [DATA_WIDTH-1:0] data_table [BUF_DEPTH-1:0];
    logic [`ADDR_WIDTH-1:0] pc_table [BUF_DEPTH-1:0];

    // Output of SB 1
    logic intermediate1_valid;	// Output Valid
	logic [DATA_WIDTH-1:0] intermediate1_data;
	logic [LRU_WIDTH:0] lru;


    initial begin
		lru = '0;
        for (int i = 0; i < BUF_DEPTH; i++) begin
            pc_table[i] = '0;
            data_table[i] = '0;
        end
    end 

	
	//DONE: Properly set mem_read_addr and mem_read_data parameters in always_comb
		//DONT NEED? --- Have intermediate signal store output of mem_read_data
		//if mem_read_data is valid and we're at a cache miss, update table values
		
	assign {i_tag, i_index, i_block_offset} = i_pc_current.pc[`ADDR_WIDTH - 1 : 2];
	
	//Set parameters for memory access
	always_comb begin 
		mem_read_address.ARADDR = {i_tag, i_index, {BLOCK_OFFSET_WIDTH + 2{1'b0}}};
		mem_read_address.ARLEN = LINE_SIZE;
		mem_read_address.ARVALID = 1;
		mem_read_address.ARID = 4'd2;
		mem_read_data.RREADY = 1'b1;
	end

    always_ff @( i_cache_miss ) begin
		intermediate1_valid = 1'b0;
        if (i_cache_miss) begin
			//Find first empty entry in the table
			byte first_empty = -1;
			logic int_valid = 1'b0;

			for(int i = 0; i < BUF_DEPTH; i++) begin
				if (pc_table[i] == 0 && data_table[i] == 0 && first_empty == -1) begin
					first_empty = i;
				end

				//If we find PC that we're looking for (exception at pc_table[i] == 0)
				if (pc_table[i] != 0 && pc_table[i] == i_pc_current.pc) begin
					$display("Found cached miss");
					intermediate1_data = data_table[i];
                	intermediate1_valid = 1'b1;
					int_valid = 1'b1; 
				end
				else if(int_valid == 1) begin
					intermediate1_valid = 1'b1;
				end
				else begin
					intermediate1_valid = 1'b0;
				end
			end
			//If table not fully populated
			if(first_empty != -1 && int_valid == 0)begin
				$display("Populating Table");
				data_table[first_empty] = mem_read_data.RDATA;
				pc_table[first_empty] = i_pc_current.pc;
			end
			//Else overwrite LRU entry
			else if (first_empty == -1 && int_valid == 0)begin
				//$display("Overwriting LRU");
				data_table[lru] = mem_read_data.RDATA;
				pc_table[lru] = i_pc_current.pc;
				lru = (lru+1) % BUF_DEPTH;
			end

			//$display("pc: %b", i_pc_current.pc);
			//$display("addr: %d", mem_read_address.ARADDR);
			//$display("data: %d", mem_read_data.RDATA);
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