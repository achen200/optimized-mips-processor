/*
 * branch_controller.sv
 * Author: Zinsser Zhang
 * Last Revision: 04/08/2018
 *
 * branch_controller is a bridge between branch predictor to hazard controller.
 * Two simple predictors are also provided as examples.
 *
 * See wiki page "Branch and Jump" for details.
 */
`include "mips_core.svh"
`ifdef SIMULATION
import "DPI-C" function void stats_event (input string e);
`endif


module branch_controller (
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low

	// Request
	pc_ifc.in dec_pc,
	branch_decoded_ifc.hazard dec_branch_decoded,

	// Feedback
	pc_ifc.in ex_pc,
	branch_result_ifc.in ex_branch_result
);
	logic request_prediction;
	logic prev_req;
	logic branch_count;
	logic branch_miss;

	// Change the following line to switch predictor
	perceptron PREDICTOR (
		.clk, .rst_n,

		.i_req_valid     (request_prediction),
		.i_req_pc        (dec_pc.pc),
		.i_req_target    (dec_branch_decoded.target),
		.o_req_prediction(dec_branch_decoded.prediction),

		.i_fb_valid      (ex_branch_result.valid),
		.i_fb_pc         (ex_pc.pc),
		.i_fb_prediction (ex_branch_result.prediction),
		.i_fb_outcome    (ex_branch_result.outcome)
	);

	always_comb
	begin
		prev_req = request_prediction;
		request_prediction = dec_branch_decoded.valid & ~dec_branch_decoded.is_jump;

		if(~prev_req & request_prediction) branch_count = 1'b1;
		if(ex_branch_result.valid & (ex_branch_result.prediction != ex_branch_result.outcome))
		begin
			branch_miss = 1'b1;
		end

		dec_branch_decoded.recovery_target =
			(dec_branch_decoded.prediction == TAKEN)
			? dec_pc.pc + `ADDR_WIDTH'd8
			: dec_branch_decoded.target;
		
	end
`ifdef SIMULATION
	always_ff @(posedge clk)
	begin
		if(branch_count) 
		begin
			stats_event("branch_pred");
			branch_count = 1'b0;
		end
		if(branch_miss)
		begin
			stats_event("branch_miss");
			branch_miss = 1'b0;
		end
	end
`endif

endmodule

module branch_predictor_always_not_taken (
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low

	// Request
	input logic i_req_valid,
	input logic [`ADDR_WIDTH - 1 : 0] i_req_pc,
	input logic [`ADDR_WIDTH - 1 : 0] i_req_target,
	output mips_core_pkg::BranchOutcome o_req_prediction,

	// Feedback
	input logic i_fb_valid,
	input logic [`ADDR_WIDTH - 1 : 0] i_fb_pc,
	input mips_core_pkg::BranchOutcome i_fb_prediction,
	input mips_core_pkg::BranchOutcome i_fb_outcome
);

	always_comb
	begin
		o_req_prediction = NOT_TAKEN;
	end
endmodule

module branch_predictor_always_taken(
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low

	// Request
	input logic i_req_valid,
	input logic [`ADDR_WIDTH - 1 : 0] i_req_pc,
	input logic [`ADDR_WIDTH - 1 : 0] i_req_target,
	output mips_core_pkg::BranchOutcome o_req_prediction,

	// Feedback
	input logic i_fb_valid,
	input logic [`ADDR_WIDTH - 1 : 0] i_fb_pc,
	input mips_core_pkg::BranchOutcome i_fb_prediction,
	input mips_core_pkg::BranchOutcome i_fb_outcome
);
	always_comb
	begin
		o_req_prediction = TAKEN;
	end
endmodule

module branch_predictor_backward_taken(
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low

	// Request
	input logic i_req_valid,
	input logic [`ADDR_WIDTH - 1 : 0] i_req_pc,
	input logic [`ADDR_WIDTH - 1 : 0] i_req_target,
	output mips_core_pkg::BranchOutcome o_req_prediction,

	// Feedback
	input logic i_fb_valid,
	input logic [`ADDR_WIDTH - 1 : 0] i_fb_pc,
	input mips_core_pkg::BranchOutcome i_fb_prediction,
	input mips_core_pkg::BranchOutcome i_fb_outcome
);
	always_comb
	begin
		if(i_req_target <= i_req_pc)
			o_req_prediction = TAKEN;
		else
			o_req_prediction = NOT_TAKEN;
	end
endmodule

module branch_predictor_2bit (
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low

	// Request
	input logic i_req_valid,
	input logic [`ADDR_WIDTH - 1 : 0] i_req_pc,
	input logic [`ADDR_WIDTH - 1 : 0] i_req_target,
	output mips_core_pkg::BranchOutcome o_req_prediction,

	// Feedback
	input logic i_fb_valid,
	input logic [`ADDR_WIDTH - 1 : 0] i_fb_pc,
	input mips_core_pkg::BranchOutcome i_fb_prediction,
	input mips_core_pkg::BranchOutcome i_fb_outcome
);

	logic [1:0] counter;

	task incr;
		begin
			if (counter != 2'b11)
				counter <= counter + 2'b01;
		end
	endtask

	task decr;
		begin
			if (counter != 2'b00)
				counter <= counter - 2'b01;
		end
	endtask

	always_ff @(posedge clk)
	begin
		if(~rst_n)
		begin
			counter <= 2'b01;	// Weakly not taken
		end
		else
		begin
			if (i_fb_valid)
			begin
				case (i_fb_outcome)
					NOT_TAKEN: decr();
					TAKEN:     incr();
				endcase
			end
		end
	end

	always_comb
	begin
		o_req_prediction = counter[1] ? TAKEN : NOT_TAKEN;
	end

endmodule

module perceptron (
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low

	// Request
	input logic i_req_valid,
	input logic [`ADDR_WIDTH - 1 : 0] i_req_pc,
	input logic [`ADDR_WIDTH - 1 : 0] i_req_target,
	output mips_core_pkg::BranchOutcome o_req_prediction,

	// Feedback
	input logic i_fb_valid,
	input logic [`ADDR_WIDTH - 1 : 0] i_fb_pc,
	input mips_core_pkg::BranchOutcome i_fb_prediction,
	input mips_core_pkg::BranchOutcome i_fb_outcome
);
	parameter N = 32;										// Number of Bits for GHR
	parameter W_BITS = 7;									// Number of Bits for weight
	parameter P_BITS = 8;									// Number of bits for perceptron
	parameter P_NUM = 128;									// Number of perceptrons

	logic [W_BITS+N-1:0] theta;								// Threshold for training
	logic [N-1:0] x;										// Global History Register  
	logic signed [W_BITS-1:0] w [P_NUM-1:0][N-1:0];		// PxN array of weights		(Changed to signed)
	logic signed [N + W_BITS - 1:0] stored_y [P_NUM-1:0]; 	// Stored Y values
	/*For prediction */
	logic [P_BITS-1:0] r_hash;								// Req PC hashed				
	logic signed [W_BITS + N - 1:0] y;						// Calculated Y based on Req PC
	logic signed [W_BITS + N - 1:0] y_abs;
	/*For training*/
	logic [P_BITS-1:0] fb_hash;								// FB PC hashed

	assign r_hash = i_req_pc[`ADDR_WIDTH - 1:2] % P_NUM;
	assign fb_hash = i_fb_pc[`ADDR_WIDTH - 1:2] % P_NUM;

	always_comb begin
		if (stored_y[fb_hash] < 0) begin
			y_abs = -1*stored_y[fb_hash];
		end
		else begin
			y_abs = stored_y[fb_hash];
		end
	end


	//Initial values for simulation
	initial begin
		theta = 75;
		x = 1;										// change2: Last bit of perceptron should always be 1
		for(int i = 0; i < P_NUM; i++) begin
			for(int j = 0; j < N; j++) begin
				w[i][j] <= '0;
				// w[i][j] <= {$random} % 128;
			end
		end
	end

	//Shift GHR
	always @(i_fb_valid) begin					// same miss rate as: always @(i_fb_valid) begin
		if(i_fb_valid) begin
			x <= {x[N-2:1], i_fb_outcome, 1'b1};		// change2: Last bit of perceptron should always be 1
		end
	end

	//Train
	always_ff @(posedge clk) begin	
		if (i_fb_valid) begin
			// $display("i_fb_pc[`ADDR_WIDTH - 1:2]: %b",i_fb_pc[`ADDR_WIDTH - 1:2]);
			// $display("y_abs: ", y_abs, " fb_hash: ", fb_hash);
			if (i_fb_prediction != i_fb_outcome | y_abs <= theta) begin			// @unsigned(stored_y[fb_hash]) gave incorrect values
				// $display("w[fb_hash][0]:", w[fb_hash][0], " fb: : ", (2*i_fb_outcome-1), " x[0]: ", (2*x[0]-1));
				for (int i = 0; i < N; i++) begin
					w[fb_hash][i] = w[fb_hash][i] + (2*i_fb_outcome-1) * (2*x[i]-1);
				end
				// $display("w[fb_hash][0]:", w[fb_hash][0], "outcome: ", (2*i_fb_outcome-1) * (2*x[0]-1));
				// $display("train");
			end
			// else $display("untrain");
		end
	end

	//Predictions - updates value of y triggered by whenever r_hash changes
	always @(r_hash) begin
	// always_ff @(posedge clk) begin		// this has higher miss for some reason?
		if(i_req_valid) begin
			y = w[r_hash][0];
			for (int i = 1; i < N; i++) begin
				y = y + (2*x[i]-1) * w[r_hash][i];
			end
			stored_y[r_hash] = y;
		end	
	end
	
	always_comb begin //Changed from y to stored_y
		o_req_prediction = stored_y[r_hash][N-1] ? NOT_TAKEN : TAKEN;		 
	end

endmodule

// TODO:
// - Negative numbers are actually negative
// - Training is completed? 
// - Check if values are getting updated correctly
// - Multiple perceptrons are owrking right (hash)
// use most sig bit for hash