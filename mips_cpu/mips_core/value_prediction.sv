`include "mips_core.svh"

module value_prediction #(
    parameter INDEX_WIDTH = 6
) (
    input clk, rst_n, vp_en, 
    input [`ADDR_WIDTH - 1 : 0] addr,

    cache_output_ifc.in d_cache_data,

    cache_output_ifc.out out,
    output en_recover, correct_prediction
);

// Last predicted
logic [`DATA_WIDTH - 1 : 0] last_predicted;
logic [`DATA_WIDTH - 1 : 0] predicted;

// Make prediction
always_comb begin
    //
end

always_ff @( posedge clk ) begin
    if (rst_n) begin
        out.valid <= 'b0;
        out.data <= 0;
        en_recover <= 'b0;
    end

    else if (vp_en) begin
        out.valid <= 'b1;
        out.data <= predicted;
        last_predicted <= predicted;
        en_recover <= 'b0;
    end

    else if (d_cache_data.data != last_predicted) begin
        // send signal to hazard controller
        out.valid <= d_cache_data.valid;
        out.data <= d_cache_data.data;
        en_recover <= 'b1;
        correct_prediction <= 'b0;
    end

    else if (d_cache_data.data == last_predicted) begin
        out.valid <= d_cache_data.valid;
        out.data <= d_cache_data.data;
        en_recover <= 'b0;
        correct_prediction <= 'b1;
    end

    else begin
        out.valid <= 'b0;
        out.data <= 0;
        en_recover <= 'b0;
    end
end
    
endmodule