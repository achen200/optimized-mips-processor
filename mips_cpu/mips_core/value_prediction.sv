`include "mips_core.svh"

module value_prediction #(
    parameter INDEX_WIDTH = 6
) (
    input clk, rst_n, vp_en, recovery_done,
    input [`ADDR_WIDTH - 1 : 0] addr,

    cache_output_ifc.in d_cache_data,

    //cache_output_ifc.out out,
    output [`DATA_WIDTH - 1 : 0] out,
    
    output en_recover, done, vp_lock_out, out_valid
);

// Last predicted
logic [`DATA_WIDTH - 1 : 0] last_predicted;
logic [`DATA_WIDTH - 1 : 0] predicted;
logic [`DATA_WIDTH - 1 : 0] last_predicted_pc;

// Make prediction
always_comb begin
    predicted = '0; // predict all zeros for now
end

always_ff @(posedge clk) begin
	if(done | recovery_done | ~vp_en) begin
		vp_lock_out <= 1'b0;
		out <= d_cache_data.data;
		out_valid <= d_cache_data.valid;	//should be valid right after recovery
	end
	else if(vp_en) begin 
		if(~vp_lock_out) begin //First prediction: save address and "last_predicted"
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

always @(d_cache_data.valid) begin
	en_recover = 1'b0;
	done = 1'b0;

	if(d_cache_data.valid) begin
		if(d_cache_data.data != last_predicted) begin
			$display("VP: Triggering Recovery");
			en_recover = 1'b1;
		end
		else begin
			$display("VP: Predicted Correct, no need for recovery");
			done = 1'b1;
		end
	end
end


// always_comb begin
// 	done = 1'b0;

// 	if(d_cache_data.valid && d_cache_data != last_predicted) begin
// 		$display("VP: Triggering Recovery");
// 		en_recover = 'b1;
// 	end
// 	else if (d_cache_data.valid && d_cache_data == last_predicted) begin
// 		$display("VP: Predicted Correct, no need for recovery");
// 		done = 1'b1;
// 		en_recover = 1'b0;
// 	end
// end

    
endmodule