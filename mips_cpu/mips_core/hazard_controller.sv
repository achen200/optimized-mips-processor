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
	d_cache_pass_through_ifc.in dc_pass,
	// Feedback from EX
	pc_ifc.in ex_pc,
	input lw_hazard,
	branch_result_ifc.in ex_branch_result,
	alu_pass_through_ifc.in ex_ctl,
	// Feedback from MEM
	input mem_done,
	pc_ifc.in mem_pc,

	//D-Cache Signals
	d_cache_input_ifc.in ex_req_in,
	d_cache_input_ifc.out dc_req_out,

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
	output recover_snapshot, recovery_done_ack
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
	logic recover_en;
	logic rs_done;
	logic [`DATA_WIDTH-1:0] vp_pc, pred;
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
		.vp_en, .recover_en,
		.addr(vp_pc),
		.d_cache_data(d_cache_output),
		.d_cache_req(ex_req_in),
		.recover(recover_snapshot),
		.out(pred), 
		.out_valid(pred_valid),
		.done(vp_done),
		.recovery_done,
		.vp_lock,
		.last_predicted_pc(pc_out)
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
	logic if_stall_ov, if_flush_ov, if_stall_ov_off, dec_stall_ov_off, ex_stall_ov_off, mem_stall_ov_off; 
	logic dec_stall_ov, dec_flush_ov;
	logic ex_stall_ov, ex_flush_ov;
	logic mem_stall_ov, mem_flush_ov, wb_stall_ov;
	logic ov_stall, ov_flush;
	logic output_vp;
	logic save_pc;

	logic pc_out;

	/*** Value Prediction ***/
	assign predicted_value.data = pred;
	assign predicted_value.valid = pred_valid;

	always_comb begin
		if(output_vp) begin
			predicted_value.data = pred;
			predicted_value.valid = pred_valid;
			// $display("Using predicted values %h valid %b", pred, pred_valid);
		end
		else begin
			predicted_value.data = d_cache_output.data;
			predicted_value.valid = d_cache_output.valid;
			// $display("Using d_cache values %h valid %b", d_cache_output.data, d_cache_output.valid);
		end
	end

	always_comb begin
		if_stall_ov = ov_stall;
		dec_stall_ov = ov_stall;
		ex_stall_ov = ov_stall;
		mem_stall_ov = ov_stall;
		//wb_stall_ov = ov_stall;

		if_flush_ov = ov_flush;
		dec_flush_ov = ov_flush;
		ex_flush_ov = ov_flush;
		mem_flush_ov = ov_flush;	
	end

	//Handle stores - immediate execute
	always_comb begin
		if(ex_req_in.valid & (vp_lock | (ex_req_in.mem_action == READ & ~d_cache_output.valid)))
			output_vp = 1'b1;
		else
			output_vp = 1'b0;
	end

	d_cache_input_ifc imm_dc_req();

	//Handle when cache_request is stored
	always_comb begin
		if(vp_lock | vp_en) begin
			dc_req_out.valid = imm_dc_req.valid;
			dc_req_out.mem_action = imm_dc_req.mem_action;
			dc_req_out.addr = imm_dc_req.addr;
			dc_req_out.addr_next = imm_dc_req.addr_next;
			dc_req_out.data = imm_dc_req.data;
			$display("dc_req_out1: valid %b addr %h", dc_req_out.valid, dc_req_out.addr);
		end
		else begin
			dc_req_out.valid = ex_req_in.valid;
			dc_req_out.mem_action = ex_req_in.mem_action;
			dc_req_out.addr = ex_req_in.addr;
			dc_req_out.addr_next = ex_req_in.addr_next;
			dc_req_out.data = ex_req_in.data;
			$display("dc_req_out2: valid %b addr %h", ex_req_in.valid, dc_req_out.addr);
		end
	end

	always_ff @(posedge clk) begin
		if(first_lmiss) begin
			// $display("Immediate assigned");
			imm_dc_req.valid = ex_req_in.valid;
			imm_dc_req.mem_action = ex_req_in.mem_action;
			imm_dc_req.addr = ex_req_in.addr;
			imm_dc_req.addr_next = ex_req_in.addr_next;
			imm_dc_req.data = ex_req_in.data;
			$display("immediate: valid %b mem_action %b addr %h", imm_dc_req.valid, imm_dc_req.mem_action, imm_dc_req.addr);
		end
	end


	logic next;
	logic first_lmiss;
	assign first_lmiss = ex_req_in.valid && ex_req_in.mem_action == READ && ~vp_lock && ~d_cache_output.valid & ~next;
	// logic n_off;
	always_ff @(posedge clk) begin
		$display("if_stall %b dec_stall %b == i2d_stall %b ex_stall %b mem_stall %b", if_stall, dec_stall, i2d_hc.stall, ex_stall, mem_stall);
			
		if(~vp_lock & vp_done & ov_stall) begin	// 
			$display("VP1 resolved correct, continuing at checkpoint");
			ov_stall <= 1'b0;
		end
		if(recover_snapshot) begin //If predicted incorrect --FLUSH
			recover_en <= 1'b0; 
			$display("Recover_en disabled next cycle");
		end
		// if(d_cache_output.valid & ov_stall) begin
		// 	$display("Stalling done next cycle");
		// 	ov_stall <= 1'b0;
		// end
		// if(n_off) begin
		// 	if(~d_cache_output.valid)	
		// 		ov_stall <= 1'b1; 
		// 	if_stall_ov_off <= 1'b0;
		// 	dec_stall_ov_off <= 1'b0;
		// 	ex_stall_ov_off <= 1'b0;
		// 	mem_stall_ov_off <= 1'b0;
		// 	ov_flush <= 1'b0;
		// 	n_off <= 1'b0;
		// end

		if(next) begin
			vp_en <= 1'b0;
			take_snapshot <= 1'b0;
			next <= 1'b0;
		end
 
		//Handle load miss  
		if(first_lmiss) begin	 
			$display("VP begin next cycle %b", ex_req_in.valid);
			$display("VP_PC %h", mem_pc.pc);
			vp_pc <= mem_pc.pc;
			vp_en <= 1'b1;
			take_snapshot <= 1'b1; 
			recover_en <= 1'b1;
			next <= 1'b1;
		end
		if (dc_pass.is_mem_access & vp_lock) begin // && vp_lock // Works if i_decoded changes by the time vp_lock turn on for VP1
			$display("Additional L/S detected");
			$display("2nd VP on %h", ex_pc.pc);
			// if_stall_ov_off <= 1'b1;
			// dec_stall_ov_off <= 1'b1;
			// ex_stall_ov_off <= 1'b1;
			// mem_stall_ov_off <= 1'b1;
			// ov_flush <= 1'b1;
			// n_off <= 1'b1; //Next flush off
			ov_stall <= 1'b1;
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
		
		if(~if_stall_ov_off) begin
			if (ic_miss) begin
				if_stall = 1'b1;
				if_flush = 1'b1;
				// $display("ic_miss");
			end
			if (ex_overload) begin
				if_stall = 1'b0;
				if_flush = 1'b1;
			end
			if (dec_stall | mem_stall | if_stall_ov)
				if_stall = 1'b1;
		end
		else begin
			if_stall = 1'b0;
			if_flush = 1'b0;

			if(if_flush_ov)
				if_flush = 1'b1;
		end
	end

	always_comb
	begin : handle_dec
		dec_stall = 1'b0;
		dec_flush = 1'b0;
		if(~dec_stall_ov_off) begin
			if (ds_miss | lw_hazard) begin
				dec_stall = 1'b1;
				dec_flush = 1'b1;
			end
			if (ex_stall | mem_stall | dec_stall_ov)
				dec_stall = 1'b1;
		end
		else begin
			dec_stall = 1'b0;
			dec_flush = 1'b0;

			if(dec_flush_ov)
				dec_flush = 1'b1;
		end
	end

	always_comb
	begin : handle_ex
		if(~ex_stall_ov_off) begin
			ex_stall = mem_stall;
			ex_flush = 1'b0;
			if(ex_stall_ov) 
				ex_stall = 1'b1;
		end
		else begin
			ex_stall = 1'b0;
			ex_flush = 1'b0;
			if(ex_flush_ov)
				ex_flush = 1'b1;
		end
	end

	always_comb
	begin : handle_mem
		if(~mem_stall_ov_off) begin
			mem_stall = dc_miss;
			mem_flush = dc_miss;
			
			if(mem_stall_ov) 
				mem_stall = 1'b1;
		end
		else begin
			mem_stall = 1'b0;
			mem_flush = 1'b0;
			if(mem_flush_ov)
				mem_flush = 1'b1;
		end
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
		m2w_hc.stall = 1'b0; //wb_stall_ov;
	end
	

	// Derive the load_pc	
	always_comb
	begin
		if(recover_snapshot) begin
			load_pc.new_pc = pc_out;
			load_pc.we = 1'b1;
			// if_stall_ov_off = 1'b1;
			//ov_flush = 1'b1;
			$display("Resetting PC to %h", load_pc.new_pc); //Stall %b Flush %b", load_pc.new_pc, if_stall, if_flush);
		end
		else begin
			//ov_flush = 1'b1;
			// if_stall_ov_off = 1'b0;
			load_pc.we = dec_overload | ex_overload;
			if (dec_overload)
				load_pc.new_pc = dec_branch_decoded.target;
			else
				load_pc.new_pc = ex_branch_result.recovery_target;
		end
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
