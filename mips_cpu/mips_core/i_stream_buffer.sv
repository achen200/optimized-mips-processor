`include "mips_core.svh"

module i_stream_buffer #(
    parameter INDEX_WIDTH = 6, // 1 KB Cahe size 
	parameter BLOCK_OFFSET_WIDTH = 2,
    parameter BUF_DEPTH = 8,
    parameter DATA_WIDTH = 32
	)(
    // General signals
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low

    // Request
	pc_ifc.in i_pc_current,
	pc_ifc.in i_pc_next,

    // I cache Output
    cache_output_ifc.in ic_out,

    // From hazard controller
    input ic_miss,

    // Response
	cache_output_ifc.out sb_out,

    // Memory interface
	axi_read_address.master mem_read_address,
	axi_read_data.master mem_read_data
);	
	localparam LINE_SIZE = 1 << BLOCK_OFFSET_WIDTH;
	localparam TAG_WIDTH = `ADDR_WIDTH - INDEX_WIDTH - BLOCK_OFFSET_WIDTH - 2;
	localparam LRU_WIDTH = 3; 	//set to log_2(buf_depth)

    logic [DATA_WIDTH-1:0] data_table [BUF_DEPTH-1:0];
    logic [`ADDR_WIDTH-1:0] pc_table [BUF_DEPTH-1:0];
	logic empty_table [BUF_DEPTH-1:0];

	logic [DATA_WIDTH-1:0] wdata;
	logic [LRU_WIDTH-1:0] waddr;
	logic [LRU_WIDTH-1:0] raddr;
	logic w_e;

	logic [TAG_WIDTH-1:0] i_tag;
	logic [INDEX_WIDTH-1:0] i_index;
	logic [BLOCK_OFFSET_WIDTH-1:0] i_block_offset;
	//refill
	logic [TAG_WIDTH-1:0] r_tag;
	logic [INDEX_WIDTH-1:0] r_index;
	logic [`ADDR_WIDTH-1:0] r_pc;

	// Output of SB 1
    logic int_valid;
	logic [DATA_WIDTH-1:0] int_data;
	logic [LRU_WIDTH:0] lru;

	enum logic[1:0] {
		STATE_READY,            // Ready for incoming requests
		STATE_REFILL_REQUEST,   // Sending out a memory read request
		STATE_REFILL_DATA       // Missing on a read
	} state, next_state;

    initial begin
		lru = '0;
        for (int i = 0; i < BUF_DEPTH; i++) begin
            pc_table[i] = '0;
            data_table[i] = '0;
			empty_table[i] = 1'b0;
        end
    end 
		
	assign {i_tag, i_index, i_block_offset} = i_pc_current.pc[`ADDR_WIDTH - 1 : 2];
	assign raddr = (i_pc_current.pc>>4) % LRU_WIDTH; 
	
	//Set parameters for memory access
	always_comb begin 
		mem_read_address.ARADDR = {r_tag, r_index, {BLOCK_OFFSET_WIDTH + 2{1'b0}}};
		mem_read_address.ARLEN = LINE_SIZE;
		mem_read_address.ARVALID = state == STATE_REFILL_REQUEST;
		mem_read_address.ARID = 4'd2;
		mem_read_data.RREADY = 1'b1;
	end

	//current state logic
	always_ff @(posedge clk) begin
		if(~rst_n) state <= STATE_READY;
		else begin
			state <= next_state;
			case (state)
				STATE_READY:
				begin
					if(~ic_out.valid) begin //Check if using ic_miss works
						$display("IC miss, pc %h", r_pc);
						r_tag <= i_tag;
						r_index <= i_index;
						r_pc <= i_pc_current.pc;
					end
				end
				STATE_REFILL_REQUEST:
				begin
				end
				STATE_REFILL_DATA:
				begin
				end
			endcase
		end
	end
	
	//next_state logic
	always_comb begin
		next_state = state;
		unique case(state)
			STATE_READY:
				if (~ic_out.valid) //Check if ic_miss works
					next_state = STATE_REFILL_REQUEST;
			STATE_REFILL_REQUEST:
				if (mem_read_address.ARREADY)
					next_state = STATE_REFILL_DATA;
			STATE_REFILL_DATA:
				if (mem_read_data.RVALID)
					next_state = STATE_READY;
		endcase
	end

	//Buffer pre-write logic
	always_comb begin
		if(mem_read_data.RVALID) begin
			w_e = 1'b1;
		end
		else 
			w_e = 1'b0;
		wdata = mem_read_data.RDATA;
		waddr = (r_pc>>4)%LRU_WIDTH; //change waddr width to match modulus
	end

	//Writing to buffer
	always_ff @(posedge clk) begin
		if(w_e) begin
			$display("state %d, wrote to %h pc %h value %h", state, waddr, r_pc, wdata);
			pc_table[waddr] <= r_pc;
			data_table[waddr] <= wdata;
			empty_table[waddr] <= 1'b1;
		end
		// else begin
		// 	$display("state: %d, icache valid?%d pc %h value %h", state, ic_out.valid, i_pc_current.pc, ic_out.data);
		// end
	end

	//Reading from buffer
	always_ff @(posedge clk) begin
		if(ic_out.valid) 
			int_valid <= 1'b0;
		else begin
			if(pc_table[raddr] == i_pc_current.pc && empty_table[raddr] != 0 && state == STATE_READY) begin
				$display("table ind: %d, pc %h value %h", raddr, pc_table[raddr], data_table[raddr]);
				int_valid <= 1'b1;
				int_data <= data_table[raddr];
			end
			else int_valid <= 0'b0;
		end
	end

	//Output logic
	always_comb begin
        if(int_valid) begin
            sb_out.valid = int_valid;
            sb_out.data  = int_data;
			//$display("sb_out: %h", sb_out.data);
        end
        else begin
            sb_out.valid = ic_out.valid;
            sb_out.data  = ic_out.data;
        end
    end

    // always_ff @(ic_miss) begin

	// 	int_valid = 1'b0;
    //     if (ic_miss) begin
	// 		//Find first empty entry in the table
	// 		byte first_empty = -1;
	// 		logic int_valid = 1'b0;

	// 		for(int i = 0; i < BUF_DEPTH; i++) begin
	// 			if (empty_table[i] == 0 && first_empty == -1) begin
	// 				first_empty = i;
	// 			end
	// 			//If we find PC that we're looking for (exception at pc_table[i] == 0)
	// 			if (empty_table[i] != 0 && pc_table[i] == i_pc_current.pc) begin
	// 				// $display("Found cached miss");
	// 				// $display("pc: %d", i_pc_current.pc);
	// 				int_data = data_table[i];
    //             	int_valid = 1'b1;
	// 				int_valid = 1'b1; 
	// 			end
	// 			else if(int_valid == 1) begin
	// 				int_valid = 1'b1;
	// 			end
	// 			else begin
	// 				int_valid = 1'b0;
	// 			end
	// 		end
	// 		//If table not fully populated
	// 		if(first_empty != -1 && int_valid == 0 && mem_read_data.RVALID)begin
	// 			data_table[first_empty] = mem_read_data.RDATA;
	// 			pc_table[first_empty] = i_pc_current.pc;
	// 			empty_table[first_empty] = 1'b1;
	// 		end
	// 		// Else overwrite LRU entry
	// 		else if (first_empty == -1 && int_valid == 0 && mem_read_data.RVALID)begin
	// 			// $display("-------------Overwriting LRU at spot %d ---------------", lru);
	// 			// $display("current pc: %d", i_pc_current.pc);
	// 			// $display("-----Table:-----");
	// 			// for(int j =0; j < BUF_DEPTH; j++)
	// 			// 	$display("%d | %d", j, pc_table[j]);
	// 			// $display("-----Table:-----");
	// 			data_table[lru] = mem_read_data.RDATA;
	// 			pc_table[lru] = i_pc_current.pc;
	// 			lru = (lru+1) % BUF_DEPTH;
	// 		end

	// 		//$display("pc: %b", i_pc_current.pc);
	// 		//$display("addr: %d", mem_read_address.ARADDR);
	// 		//$display("data: %d", mem_read_data.RDATA);
    //     end
    // end

    

endmodule


// Plan
// Implement the fetchings
//      - Predictor logic
//      - update table data
// Data is being fetched 4 instructions in one memeory access
//      - Deal with this problem