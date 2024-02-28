/*
 * hazard_controller.sv
 * Author: Zinsser Zhang
 * Last Revision: 03/13/2022
 *
 * hazard_controller collects feedbacks from each stage and detect whether there
 * are hazards in the pipeline. If so, it generate control signals to stall or
 * flush each stage. It also contains a branch_controller, which talks to
 * a branch predictor to make a prediction when a branch instruction is decoded.
 *
 * It also contains simulation only logic to report hazard conditions to C++
 * code for execution statistics collection.
 *
 * See wiki page "Hazards" for details.
 * See wiki page "Branch and Jump" for details of branch and jump instructions.
 */
`include "mips_core.svh"

module hazard_controller (
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low

	// Feedback from IF
	cache_output_ifc.in if_i_cache_output,
	// Feedback from DEC
	pc_ifc.in dec_pc,
	branch_decoded_ifc.hazard dec_branch_decoded,
	// Feedback from EX
	pc_ifc.in ex_pc,
	input lw_hazard,
	branch_result_ifc.in ex_branch_result,
	// Feedback from MEM
	input mem_done,

	// Hazard control output
	hazard_control_ifc.out i2i_hc,
	hazard_control_ifc.out i2d_hc,
	hazard_control_ifc.out d2e_hc,
	hazard_control_ifc.out e2m_hc,
	hazard_control_ifc.out m2w_hc,

	// Load pc output
	load_pc_ifc.out load_pc,
	cache_output_ifc.in d_cache_output,
	cache_output_ifc.out predicted_value,

	input recovery_done,
	input [`DATA_WIDTH-1:0] r_to_s [32],
	output [`DATA_WIDTH-1:0] s_to_r [32],
	output recover_snapshot, recovery_done_ack,
	d_cache_input_ifc.in d_cache_req,
);

	branch_controller BRANCH_CONTROLLER (
		.clk, .rst_n,
		.dec_pc,
		.dec_branch_decoded,
		.ex_pc,
		.ex_branch_result
	);

	logic take_snapshot;
	logic vp_en, vp_done, vp_lock;
	logic rs_done;
	logic [`DATA_WIDTH-1:0] pred;
	logic pred_valid;

	register_snapshot REG_SNAPSHOT(
		.clk, .rst_n,
		.take_snapshot,
		.regs_in(r_to_s),
		.regs_snapshot(s_to_r),
		.done(rs_done)
	);

	value_prediction VALUE_PRED(
		.clk, .rst_n,
		.vp_en,
		.addr(load_pc.new_pc),
		.d_cache_data(d_cache_output),
		.d_cache_req,
		.en_recover(recover_snapshot),
		.out(pred),
		.out_valid(pred_valid),
		.done(vp_done),
		.recovery_done,
		.recovery_done_ack,
		.vp_lock_out(vp_lock)
	);

	// We have total 6 potential hazards
	logic ic_miss;			// I cache miss
	logic ds_miss;			// Delay slot miss
	logic dec_overload;		// Branch predict taken or Jump
	logic ex_overload;		// Branch prediction wrong
	//    lw_hazard;		// Load word hazard (input from forward unit)
	logic dc_miss;			// D cache miss
	logic inc_ic_amiss;
	logic branch_miss;
	logic branch_hit;

	// Control signals
	logic if_stall, if_flush;
	logic dec_stall, dec_flush;
	logic ex_stall, ex_flush;
	logic mem_stall, mem_flush;
	// wb doesn't need to be stalled or flushed
	// i.e. any data goes to wb is finalized and waiting to be commited

	//Stall overrides
	logic if_stall_ov, if_flush_ov; 
	logic dec_stall_ov, dec_flush_ov;
	logic ex_stall_ov, ex_flush_ov;
	logic mem_stall_ov, mem_flush_ov;
	logic ov_stall, ov_flush;
	logic output_vp;

	/*** Value Prediction ***/
	assign predicted_value.data = pred;
	assign predicted_value.valid = pred_valid;

	always_comb begin
		if(output_vp) begin
			predicted_value.data = pred;
			predicted_value.valid = pred_valid;
		end
		else begin
			predicted_value.data = d_cache_output.data;
			predicted_value.valid = d_cache_output.valid;
		end
	end

	always_comb begin
		if_stall_ov = ov_stall;
		dec_stall_ov = ov_stall;
		ex_stall_ov = ov_stall;
		//mem_stall_ov = ov_stall;

		if_flush_ov = ov_flush;
		dec_flush_ov = ov_flush;
		ex_flush_ov = ov_flush;
		//mem_flush_ov = ov_flush;
	end

	always @(d_cache_req.valid) begin
		take_snapshot = 1'b0;
		ov_stall  = 1'b0;
		ov_flush = 1'b0;
		vp_en = 1'b0;
		output_vp = 1'b1;
		
		//First Store
		if(d_cache_req.valid && d_cache_req.mem_action == WRITE && ~vp_lock) begin //Immediate execute
			output_vp = 1'b0;
		end
		//First Load
		else if(d_cache_req.valid && d_cache_req.mem_action == READ && ~vp_lock) begin
			vp_en = 1'b1;
			take_snapshot = 1'b1;
			$display("Begin VP");
		end
		else if(d_cache_req.valid && vp_lock) begin //second load/store request 
			$display("2nd L/S request, flushing and stalling...");
			ov_stall = 1'b1;
			ov_flush = 1'b1;
		end
	end

	// always @(predicted_value.valid) begin
	// 	$display("Changing pv.valid %h %h", predicted_value.valid, predicted_value.data);
	// end

	always @(vp_lock) begin
		ov_flush = 1'b0;
		if(vp_lock) begin			 //Beginning of VP (prediction already outputed)
			// $display("VP Locked"); 	//, and predicted value valid");
			vp_en = 1'b0;
		end
		else begin
			// $display("VP Unlocked"); 						
			if(recover_snapshot) begin
				$display("Flushing pipeline");
				ov_flush = 1'b1;				//TODO: Find out if this turns off properly
			end
			// $display("Stall overrides off");
			ov_stall = 1'b0;
		end
	end

	always_comb begin
		if(rs_done) begin
			take_snapshot = 1'b0;
		end
	end

	/*** Hazard Controls  ***/
	always_comb
	begin
		ic_miss = ~if_i_cache_output.valid;
		ds_miss = ic_miss & dec_branch_decoded.valid;
		dec_overload = dec_branch_decoded.valid
			& (dec_branch_decoded.is_jump
				| (dec_branch_decoded.prediction == TAKEN));
		ex_overload = ex_branch_result.valid
			& (ex_branch_result.prediction != ex_branch_result.outcome);

		// lw_hazard is determined by forward unit.
		dc_miss = ~mem_done;
	end

	/*
	 * Now let's go over the solution of all hazards
	 * ic_miss:
	 *     if_stall, if_flush
	 * ds_miss:
	 *     dec_stall, dec_flush (if_stall and if_flush handled by ic_miss)
	 * dec_overload:
	 *     load_pc
	 * ex_overload:
	 *     load_pc, ~if_stall, if_flush
	 * lw_hazard:
	 *     dec_stall, dec_flush
	 * dc_miss:
	 *     mem_stall, mem_flush
	 *
	 * The only conflict here is between ic_miss and ex_overload.
	 * ex_overload should have higher priority than ic_miss. Because i cache
	 * does not register missed request, it's totally fine to directly overload
	 * the pc value.
	 *
	 * In addition to above hazards, each stage should also stall if its
	 * downstream stage stalls (e.g., when mem stalls, if & dec & ex should all
	 * stall). This has the highest priority.
	 */

	always_comb
	begin : handle_if	
		if_stall = 1'b0;
		if_flush = 1'b0;

		if (ic_miss) begin
			if_stall = 1'b1;
			if_flush = 1'b1;
		end
		if (ex_overload) begin
			if_stall = 1'b0;
			if_flush = 1'b1;
		end
		if (dec_stall)
			if_stall = 1'b1;
		if(if_stall_ov)
			if_stall = 1'b1;
		if(if_flush_ov)
			if_flush = 1'b1;
	end

	always_comb
	begin : handle_dec
		dec_stall = 1'b0;
		dec_flush = 1'b0;
		if (ds_miss | lw_hazard) begin
			dec_stall = 1'b1;
			dec_flush = 1'b1;
		end
		if (ex_stall)
			dec_stall = 1'b1;

		if(dec_stall_ov)
			dec_stall = 1'b1;
		if(dec_flush_ov)
			dec_flush = 1'b1;
	end

	always_comb
	begin : handle_ex
		ex_stall = mem_stall;
		ex_flush = 1'b0;
		if(ex_stall_ov) 
			ex_stall = 1'b1;
		if(ex_flush_ov)
			ex_flush = 1'b1;
	end

	always_comb
	begin : handle_mem
		mem_stall = dc_miss;
		mem_flush = dc_miss;
		
		if(mem_stall_ov) 
			mem_stall = 1'b1;
		if(mem_flush_ov)
			mem_flush = 1'b1;
	end

	// Now distribute the control signals to each pipeline registers
	always_comb
	begin
		i2i_hc.flush = 1'b0;
		i2i_hc.stall = if_stall;
		i2d_hc.flush = if_flush;
		i2d_hc.stall = dec_stall;
		d2e_hc.flush = dec_flush;
		d2e_hc.stall = ex_stall;
		e2m_hc.flush = ex_flush;
		e2m_hc.stall = mem_stall;
		m2w_hc.flush = mem_flush;
		m2w_hc.stall = 1'b0;
	end

	// Derive the load_pc
	always_comb
	begin
		load_pc.we = dec_overload | ex_overload;
		if (dec_overload)
			load_pc.new_pc = dec_branch_decoded.target;
		else
			load_pc.new_pc = ex_branch_result.recovery_target;
	end

`ifdef SIMULATION
	always_ff @(ic_miss) begin
		if(ic_miss) begin 
			stats_event("ic_misses");
			inc_ic_amiss = 1'b1;
		end
	end
	always_ff @(dc_miss) begin
		if(dc_miss) stats_event("dc_misses");
	end
	always_ff @(posedge clk)
	begin
		if (inc_ic_amiss) inc_ic_amiss = 1'b0;
		if (ic_miss) stats_event("ic_miss_cycles");
		if (ds_miss) stats_event("ds_miss");
		if (dec_overload) stats_event("dec_overload");
		if (ex_overload) stats_event("ex_overload");
		if (lw_hazard) stats_event("lw_hazard");
		if (dc_miss) stats_event("dc_miss_cycles");
		if (if_stall) stats_event("if_stall");
		if (if_flush) stats_event("if_flush");
		if (dec_stall) stats_event("dec_stall");
		if (dec_flush) stats_event("dec_flush");
		if (ex_stall) stats_event("ex_stall");
		if (ex_flush) stats_event("ex_flush");
		if (mem_stall) stats_event("mem_stall");
		if (mem_flush) stats_event("mem_flush");
	end
`endif

endmodule
