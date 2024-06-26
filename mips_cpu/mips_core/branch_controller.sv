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


module branch_controller (
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low
	input vp_lock,

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

	// Change the following line to switch predictor
	perceptron PREDICTOR (
		.clk, .rst_n,
		.vp_lock,
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
		request_prediction = dec_branch_decoded.valid & ~dec_branch_decoded.is_jump;

		dec_branch_decoded.recovery_target =
			(dec_branch_decoded.prediction == TAKEN)
			? dec_pc.pc + `ADDR_WIDTH'd8
			: dec_branch_decoded.target;
		
	end

endmodule

module perceptron (
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low
	input vp_lock,

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
	parameter N = 7;										// Number of Bits for GHR
	parameter W_BITS = 6;									// Number of Bits for weight
	parameter P_BITS = 10;									// Number of bits for perceptron
	parameter P_NUM = 1024;									// Number of perceptrons

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

	// logic [`ADDR_WIDTH - 1 : 0] counter [P_NUM:0];
	logic [N-1:0] stored_x;

	assign r_hash = (i_req_pc[`ADDR_WIDTH - 1:2] ^ x) % P_NUM;
	assign fb_hash = (i_fb_pc[`ADDR_WIDTH - 1:2] ^ stored_x) % P_NUM;

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
		theta = 27;
		x = 1;
		for(int i = 0; i < P_NUM; i++) begin
			for(int j = 0; j < N; j++) begin
				w[i][j] = '0;
			end
		end
	end

	//Shift GHR
	always @(i_fb_valid) begin
		if(i_fb_valid) begin
			stored_x <= x;
			x <= {x[N-2:1], i_fb_outcome, 1'b1};
		end
	end

	//Train
	always_ff @(posedge clk) begin	
		if (i_fb_valid & ~vp_lock) begin
			if (i_fb_prediction != i_fb_outcome | y_abs <= theta) begin
				for (int i = 0; i < N; i++) begin
					w[fb_hash][i] <= w[fb_hash][i] + (2*i_fb_outcome-1) * (2*x[i]-1);
				end
			end
		end
	end

	//Predictions - updates value of y triggered by whenever r_hash changes
	always @(r_hash) begin
		if(i_req_valid) begin
			y = w[r_hash][0];
			for (int i = 1; i < N; i++) begin
				y = y + (2*x[i]-1) * w[r_hash][i];
			end
			stored_y[r_hash] = y;
		end	
	end
	
	always_comb begin
		o_req_prediction = stored_y[r_hash][N-1] ? NOT_TAKEN : TAKEN;		 
	end

endmodule