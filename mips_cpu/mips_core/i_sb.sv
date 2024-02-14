`include "mips_core.svh"

module i_sb #(
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
    input ic_miss,

    // Response
	cache_output_ifc.out sb_out,

    // Memory interface
	axi_read_address.master mem_read_address,
	axi_read_data.master mem_read_data
);

    localparam LINE_SIZE = 1 << BLOCK_OFFSET_WIDTH;
	localparam TAG_WIDTH = `ADDR_WIDTH - INDEX_WIDTH - BLOCK_OFFSET_WIDTH - 2;
	localparam LRU_WIDTH = 3;
    localparam OFFSET_DEPTH = 4;

    logic [TAG_WIDTH-1:0] i_tag;
	logic [INDEX_WIDTH-1:0] i_index;
	logic [BLOCK_OFFSET_WIDTH-1:0] i_block_offset;

    logic [DATA_WIDTH-1:0] data_table [BUF_DEPTH-1:0][OFFSET_DEPTH];
    logic [`ADDR_WIDTH-1:0] pc_table [BUF_DEPTH-1:0];
    logic empty_table [BUF_DEPTH-1:0];

    logic [DATA_WIDTH-1:0] wdata;
	logic [LRU_WIDTH-1:0] waddr;
	logic [LRU_WIDTH-1:0] raddr;
	logic w_e;

    logic int_valid;
	logic [DATA_WIDTH-1:0] int_data;
	logic [LRU_WIDTH:0] lru;

    //refill
	logic [TAG_WIDTH-1:0] r_tag;
	logic [INDEX_WIDTH-1:0] r_index;
	logic [`ADDR_WIDTH-1:0] r_pc;

    enum logic[1:0] {
		STATE_READY,            // Ready for incoming requests
		STATE_REFILL_REQUEST,   // Sending out a memory read request
		STATE_REFILL_DATA       // Missing on a read
	} state, next_state;

    enum logic[1:0] {
		FETCH1,
		FETCH2,
		FETCH3,
        FETCH4
    } fetch_state;

    assign {i_tag, i_index, i_block_offset} = i_pc_current.pc[`ADDR_WIDTH - 1 : 2];
    assign raddr = (i_pc_current.pc>>4) % LRU_WIDTH;

    initial begin
        for (int i = 0; i < BUF_DEPTH; i++) begin
            pc_table[i] = '0;
            empty_table[i] = 1'b0;
            for (int j = 0; j < OFFSET_DEPTH; j++) begin
                data_table[i][j] = '0;
            end
        end
    end

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
						// $display("IC miss, pc %h", r_pc);
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
					if(mem_read_data.RVALID) begin
						pc_table[waddr] <= r_pc;
						empty_table[waddr] <= 1'b1;
                        $display("data: %h, addr: %h", wdata, waddr);
                        case (fetch_state)
                            FETCH1: begin
                                data_table[waddr][0] <= wdata;
                                fetch_state = FETCH2;
                            end
                            FETCH2: begin
                                data_table[waddr][1] <= wdata;
                                fetch_state = FETCH3;
                            end
                            FETCH3: begin
                                data_table[waddr][2] <= wdata;
                                fetch_state = FETCH4;
                            end
                            FETCH4: begin
                                data_table[waddr][3] <= wdata;
                                fetch_state = FETCH1;
                            end
                        endcase
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
				if (~ic_out.valid) //Check if ic_miss works
					next_state = STATE_REFILL_REQUEST;
			STATE_REFILL_REQUEST:
				if (mem_read_address.ARREADY)
					next_state = STATE_REFILL_DATA;
			STATE_REFILL_DATA:
				if (mem_read_data.RVALID) //Need last_refill_word here
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

    //Reading from buffer
	always_ff @(posedge clk) begin
		if(ic_out.valid) 
			int_valid <= 1'b0;
		else begin
			if(pc_table[raddr] == i_pc_current.pc && empty_table[raddr] != 0 && state == STATE_READY) begin
				// $display("table ind: %d, pc %h value %h", raddr, pc_table[raddr], data_table[raddr]);
				int_valid <= 1'b1;
				int_data <= data_table[raddr][i_block_offset];
			end
			else int_valid <= 0'b0;
		end
	end

    // output logic
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

endmodule