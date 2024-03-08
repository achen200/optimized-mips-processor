`include "mips_core.svh"

module register_snapshot (
    input clk, 
	input rst_n,

	input [`DATA_WIDTH-1:0] regs_in[32], 		//Register inputs(from hazard control <-- reg file)
	input take_snapshot,						//Signal new prediction path (from hazard)

	output [`DATA_WIDTH-1:0] regs_snapshot[32], //Register outputs (to hazard control --> reg file)
	output logic done									//Done taking snapshot
);
	logic [`DATA_WIDTH-1:0]	regs[32];			//Registers
	logic ts;

	always_ff @(posedge clk) begin
		ts <= take_snapshot; 	//Takes another cycle to wait for current WB to commit
		if(ts && ~done) begin 
			regs <= regs_in;
			done <= 1'b1;
			// $display("=========== Register Snapshot ============");
		end
		else begin 
			done <= 1'b0;
		end
	end

	assign regs_snapshot = regs;
    
endmodule