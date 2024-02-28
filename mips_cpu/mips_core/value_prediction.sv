`include "mips_core.svh"

module value_prediction #(
    parameter INDEX_WIDTH = 6
) (
    input clk, rst_n, vp_en, recovery_done,
    input [`ADDR_WIDTH - 1 : 0] addr,

    cache_output_ifc.in d_cache_data,
	d_cache_input_ifc.in d_cache_req,

    output [`DATA_WIDTH - 1 : 0] out,
    output en_recover, done, vp_lock_out, out_valid, recovery_done_ack
);

// Last predicted
logic [`DATA_WIDTH - 1 : 0] last_predicted;
logic [`DATA_WIDTH - 1 : 0] predicted;
logic [`DATA_WIDTH - 1 : 0] last_predicted_pc;
logic [`DATA_WIDTH - 1 : 0] next_pred; 
logic next_done, next_en_recover, next_valid;

// Make prediction
always_comb begin
    predicted = '0; // predict all zeros for now
end

always_ff @(posedge clk) begin
	done <= next_done;
	en_recover <= next_en_recover;

	if(recovery_done) begin
		// $display("VP: Finished recovery");
		recovery_done_ack <= 1'b1;
		vp_lock_out <= 1'b0;
		out <= next_pred;
		out_valid <= next_valid;
	end
	else if(~vp_en | done) begin
		recovery_done_ack <= 1'b0;
		if(done)
			vp_lock_out <= 1'b0;
		out <= d_cache_data.data;
		out_valid <= d_cache_data.valid;
	end
	else if(vp_en) begin 
		recovery_done_ack <= 1'b0;
		if(~vp_lock_out) begin //First prediction: save address and "last_predicted"
			// $display("VP first prediction");
			vp_lock_out <= 1'b1; 
			last_predicted <= predicted;
			last_predicted_pc <= addr;
			out <= predicted;
			out_valid <= 1'b1; 	//Prediction only valid for first cycle
		end
		else
			out_valid <= 1'b0; 
	end			
end

always @(next_en_recover) begin
	if(next_en_recover) begin
		next_pred = d_cache_data.data;
		next_valid = d_cache_data.valid;
	end
end

always @(d_cache_data.valid) begin
	next_en_recover = 1'b0;
	next_done = 1'b0;

	if(d_cache_data.valid && d_cache_req.mem_action == READ) begin
		if(d_cache_data.data != last_predicted) begin
			next_en_recover = 1'b1;
		end
		else begin
			next_done = 1'b1;
		end
	end
end

    
endmodule