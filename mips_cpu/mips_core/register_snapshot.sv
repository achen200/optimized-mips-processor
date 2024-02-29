`include "mips_core.svh"

module register_snapshot (
    input clk, 
	input rst_n,

	input [`DATA_WIDTH-1:0] regs_in[32], 		//Register inputs(from hazard control <-- reg file)
	input take_snapshot,						//Signal new prediction path (from hazard)
	input snapshot_ack,

	output [`DATA_WIDTH-1:0] regs_snapshot[32], //Register outputs (to hazard control --> reg file)
	output logic done									//Done taking snapshot
);
	logic [`DATA_WIDTH-1:0]	regs[32];			//Registers
	logic d;

	always_ff @(posedge clk) begin
		if(d) 
			done <= 1'b1;
		else if(snapshot_ack) begin //if ~d and recovery_done_ack 
			done <= 1'b0;
			// $display("Done toggling off next cycle");
		end
	end

	always @(take_snapshot) begin
		if(take_snapshot) begin
			regs = regs_in;
			d = 1'b1;
			$display("=========== Register Snapshot ============");
			// for(int i = 0; i < 32; i++)
			// 	$display("= S[%d]: %h", i, regs[i]);
			// $display("==========================================");
		end
		else begin
			d = 1'b0;
		end
	end

	assign regs_snapshot = regs;
    
endmodule