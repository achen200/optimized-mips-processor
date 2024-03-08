`include "mips_core.svh"

module value_prediction #(
    parameter INDEX_WIDTH = 6
) (
    input clk, rst_n, vp_en, recovery_done, recover_en,
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
	// $display("-------------------------- CLK --------------------------- recover %b", recover);

	if(recovery_done) begin 
		vp_lock <= 1'b0;
		// $display("VP: lock disabled next cycle");
	end
	else if(~vp_en) begin // | done
		out <= d_cache_data.data;
		out_valid <= d_cache_data.valid;
	end
	else if(vp_en) begin 
		if(~vp_lock) begin //First prediction: save address and "last_predicted"
			// $display("VP first prediction");
			vp_lock <= 1'b1; 
			done <= 1'b0;
			last_predicted <= predicted;
			last_predicted_pc <= addr;
			$display("ADDR: %h data %h", addr, predicted);
			out <= predicted;
			out_valid <= 1'b1; 	//Prediction only valid for first cycle
		end
		else
			out_valid <= 1'b0; 
	end			
end

logic ren_recover;	//Only run once per cache valid read

always_ff @(posedge clk) begin
	if(d_cache_data.valid & recover_en) begin	
		// $display("REQ valid changing: valid %b action %b", d_cache_req.valid, d_cache_req.mem_action);
		ren_recover <= 1'b0;
		if(ren_recover) begin
			if(d_cache_data.data != last_predicted) begin
				$display("VP: Incorrect prediction detected, recovery begins next cycle");
				recover <= 1'b1;
			end
			else begin
				$display("VP: Prediction correct detected, no need to recover, lock disabled next cycle | lock %b", vp_lock);
				vp_lock <= 1'b0;
				done <= 1'b1;
				out_valid <= 1'b0;
			end
		end //Assuming d_cache_data.valid only on for 1 cycle, if not, need an else for recover <= 1'b0;
		else begin
			recover <= 1'b0;
		end
	end
	else begin
		ren_recover <= 1'b1;
		recover <= 1'b0;
	end
end

    
endmodule