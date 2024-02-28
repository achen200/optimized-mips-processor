/*
 * reg_file.sv
 * Author: Zinsser Zhang
 * Last Revision: 04/09/2018
 *
 * A 32-bit wide, 32-word deep register file with two asynchronous read port
 * and one synchronous write port.
 *
 * Register file needs to output '0 if uses_r* signal is low. In this case,
 * either reg zero is requested for read or the register is unused.
 *
 * See wiki page "Branch and Jump" for details.
 */
`include "mips_core.svh"

interface reg_file_output_ifc ();
	logic [`DATA_WIDTH - 1 : 0] rs_data;
	logic [`DATA_WIDTH - 1 : 0] rt_data;

	modport in  (input rs_data, rt_data);
	modport out (output rs_data, rt_data);
endinterface

module reg_file (
	input clk,    // Clock

	// Input from decoder
	decoder_output_ifc.in i_decoded,

	// Input from write back stage
	write_back_ifc.in i_wb,

	// Output data
	reg_file_output_ifc.out out,
	input recover_snapshot, recovery_done_ack,
	input  [`DATA_WIDTH-1:0] regs_snapshot[32],
	output [`DATA_WIDTH-1:0] regs_out[32],
	output done
);

	logic [`DATA_WIDTH - 1 : 0] regs [32];
	logic d;

	assign out.rs_data = i_decoded.uses_rs ? regs[i_decoded.rs_addr] : '0;
	assign out.rt_data = i_decoded.uses_rt ? regs[i_decoded.rt_addr] : '0;
	assign regs_out = regs; //assuming this works
	//assign done = d;

	always_ff @(posedge clk) begin
		if(i_wb.uses_rw)
		begin
			regs[i_wb.rw_addr] = i_wb.rw_data;
		end
	end

	always_ff @(posedge clk) begin
		if(d) 
			done <= 1'b1;
		else if(recovery_done_ack) begin //if ~d and recovery_done_ack 
			done <= 1'b0;
			$display("Done toggling off next cycle")
		end
	end
	always @(recover_snapshot) begin
		if(recover_snapshot) begin
			regs = regs_snapshot;
			d = 1'b1;
			$display("=========== Recovered Snapshot ============");
			for(int i = 0; i < 32; i++)
				$display("=== R[%d]: %h", i, regs[i]);
			$display("==========================================");
		end
		else begin
			d = 1'b0;
		end
	end

endmodule
