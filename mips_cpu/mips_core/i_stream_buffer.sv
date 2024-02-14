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
	output sbuf_hit,

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

    logic [DATA_WIDTH-1:0] data_table [BUF_DEPTH-1:0][LINE_SIZE-1:0];
    logic [`ADDR_WIDTH-1:0] pc_table [BUF_DEPTH-1:0];
	logic [BUF_DEPTH-1:0] valid_bits;

	logic [DATA_WIDTH-1:0] wdata;
	logic [LRU_WIDTH-1:0] waddr;
	logic [LRU_WIDTH-1:0] raddr;

	logic [TAG_WIDTH-1:0] i_tag, n_tag;
	logic [INDEX_WIDTH-1:0] i_index, n_index;
	logic [BLOCK_OFFSET_WIDTH-1:0] i_block_offset;
	//refill
	logic [TAG_WIDTH-1:0] r_tag;
	logic [INDEX_WIDTH-1:0] r_index;
	logic [`ADDR_WIDTH-1:0] r_pc;

	// Output of SB 1
    logic int_valid;
	logic [DATA_WIDTH-1:0] int_data;
	//logic [LRU_WIDTH:0] lru;

	enum logic[1:0] {
		STATE_READY,            // Ready for incoming requests
		STATE_REFILL_REQUEST,   // Sending out a memory read request
		STATE_REFILL_DATA       // Missing on a read
	} state, next_state;

    initial begin
		//lru = '0;
        for (int i = 0; i < BUF_DEPTH; i++) begin
            pc_table[i] = '0;
			valid_bits[i] = 1'b0;
        end
    end 
	logic last_refill_word;
	logic [LINE_SIZE-1:0] ctr, next_ctr; //Counters to stall
	
	assign {i_tag, i_index, i_block_offset} = i_pc_current.pc[`ADDR_WIDTH - 1 : 2];				
	assign {i_tag_next, i_index_next, i_block_offset_next} = i_pc_next.pc[`ADDR_WIDTH - 1 : 2]; //Read information
	assign {n_tag, n_index} = {i_tag, i_index} + 1'b1; 		//Write information
	assign raddr = {i_tag, i_index} % BUF_DEPTH;
	assign raddr_n = {i_tag_next, i_index_next} % BUF_DEPTH;
	assign sbuf_hit = hit;


	logic hit, miss;
	always_comb begin
		hit = valid_bits[raddr] 
			& ({i_tag, i_index} == pc_table[raddr]) 
			& (state == STATE_READY);
		miss = ~hit;
		next_ctr = ctr + 1;
		last_refill_word = (ctr == LINE_SIZE-1) 
			& mem_read_data.RVALID;
	end
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
		if(~rst_n) begin
			state <= STATE_READY;
			valid_bits <= '0;
			ctr <= 0; 
		end
		else begin
			state <= next_state;
			case (state)
				STATE_READY:
				begin
					if(~ic_out.valid && miss) begin //~ic_out.valid
						$display("STREAM READY MISS: pc_top %h ", {i_tag, i_index});
						r_tag <= n_tag;
						r_index <= n_index;
					end
				end
				STATE_REFILL_REQUEST:
				begin
					ctr <= 0;
					$display("STREAM REFILL REQ:");
				end
				STATE_REFILL_DATA:
				begin
					if(mem_read_data.RVALID) begin
						$display("STREAM REFILL_DATA: pc %h stored_pc %h memaddr %h value %h last_word %h", {n_tag, n_index}, {r_tag, r_index}, mem_read_address.ARADDR, wdata, last_refill_word); // wrote to %h, waddr
						pc_table[waddr] <= {r_tag, r_index};
						data_table[waddr][ctr] <= wdata;
						valid_bits[waddr] <= last_refill_word;
						ctr <= next_ctr;
					end
				end
			endcase
		end
	end
	
	//next_state logic
	always_comb begin
		next_state = state;
		unique case(state)
			STATE_READY:
				if (~ic_out.valid && miss) //~ic_out.valid
				begin
					next_state = STATE_REFILL_REQUEST;
				end
			STATE_REFILL_REQUEST:
				if (mem_read_address.ARREADY)
					next_state = STATE_REFILL_DATA;
			STATE_REFILL_DATA:
				if (last_refill_word)
					next_state = STATE_READY;
		endcase
	end

	//Buffer pre-write logic
	always_comb begin
		wdata = mem_read_data.RDATA;
		waddr = ({r_tag, r_index})%BUF_DEPTH; //change waddr width to match modulus
	end

	//Reading from buffer
	// always_ff @(posedge clk) begin
	// 	if(ic_out.valid) 
	// 		int_valid <= 1'b0;
	// 	else begin
	// 		if(hit && ~ic_out.valid) begin //if in table and cache missed
	// 			$display("READ FROM TABLE: STATE %h curr_pc %h stored_pc %h data_table[%h][%h]: %h", state, i_pc_current.pc, pc_table[raddr], raddr, i_block_offset, data_table[raddr][i_block_offset]);
	// 			int_valid <= 1'b1;
	// 			int_data <= data_table[raddr][i_block_offset];
	// 		end
	// 		else int_valid <= 1'b0;
	// 	end
	// end
	always_comb begin
		if(ic_out.valid)
			int_valid = 1'b0;
		else begin
			if(hit && ~ic_out.valid) begin
				$display("READ FROM TABLE: STATE %h curr_pc %h stored_pc %h data_table[%h][%h]: %h", state, i_pc_current.pc, pc_table[raddr], raddr, i_block_offset, data_table[raddr][i_block_offset]);
				int_valid = 1'b1;
				int_data = data_table[raddr][i_block_offset];
			end
			else int_valid = 1'b0;
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