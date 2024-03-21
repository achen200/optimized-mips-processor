`include "mips_core.svh"

module value_prediction #(
    parameter INDEX_WIDTH = 6
) (
    input clk, rst_n,
	input vp_en, recovery_done, recover_en,
    input [`ADDR_WIDTH - 1 : 0] addr,

    cache_output_ifc.in d_cache_data,
	d_cache_input_ifc.in d_cache_req,

    output [`DATA_WIDTH - 1 : 0] out, 
	output [`ADDR_WIDTH - 1 : 0] last_predicted_pc,
    output recover, vp_lock, out_valid,
	output done 	//Only high when correct prediction
);

// Last predicted
logic [`ADDR_WIDTH - 1 : 0] last_predicted;
logic [`DATA_WIDTH - 1 : 0] predicted;

// Make prediction
always_comb begin
    predicted = '0; // predict all zeros for now
end

always_ff @(posedge clk) begin
	if(done) done <= 1'b0;
	if(recovery_done) begin 
		vp_lock <= 1'b0;
	end
	else if(~vp_en) begin
		out <= d_cache_data.data;
		out_valid <= d_cache_data.valid;
	end
	else if(vp_en) begin 
		if(~vp_lock) begin //First prediction: save address and "last_predicted"
			vp_lock <= 1'b1; 
			done <= 1'b0;
			last_predicted <= predicted;
			last_predicted_pc <= addr;
			// $display("VP: PC %h data %h", addr, predicted);
			out <= predicted;
			out_valid <= 1'b1; 	//Prediction only valid for first cycle
		end
		else
			out_valid <= 1'b0; 
	end			
end

logic first;	//Only run once per cache valid read

always_ff @(posedge clk) begin
	if(d_cache_data.valid & recover_en) begin	
		first <= 1'b0;
		if(first) begin
			if(d_cache_data.data != last_predicted) begin
				$display("VP: Incorrect prediction detected, recovery begins next cycle");
				recover <= 1'b1;
			end
			else begin
				$display("VP: Prediction correct detected, no need to recover");
				vp_lock <= 1'b0;
				done <= 1'b1;
				out_valid <= 1'b0;
			end
		end 
		else recover <= 1'b0;
	end
	else begin
		first <= 1'b1;
		recover <= 1'b0;
	end
end

    
endmodule