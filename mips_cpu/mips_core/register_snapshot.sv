`include "mips_core.svh"

module register_snapshot (
    input clk, 
	input rst_n,

	input [`DATA_WIDTH-1:0] regs_in[32], 		//Register inputs(from reg file)
	input take_snapshot,						//Signal new prediction path (from hazard)

	output [`DATA_WIDTH-1:0] regs_snapshot[32] //Register outputs (to reg file)
);
	logic [`DATA_WIDTH-1:0]	regs[32];			//Registers

	always @(take_snapshot) begin
		if(take_snapshot) begin
			regs = regs_in;
		end
	end

	assign regs_snapshot = regs;
    
endmodule