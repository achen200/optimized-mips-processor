`include "mips_core.svh"

module value_prediction #(
    parameter INDEX_WIDTH = 6
) (
    input clk, rst_n, vp_en, 
    input [`ADDR_WIDTH - 1 : 0] addr,

    cache_output_ifc.in d_cache_data,

    //cache_output_ifc.out out,
    output [`DATA_WIDTH - 1 : 0] out,
    
    output en_recover, correct_prediction, done
);

// Last predicted
logic [`DATA_WIDTH - 1 : 0] last_predicted;
logic [`DATA_WIDTH - 1 : 0] predicted;

// Make prediction
always_comb begin
    // predict all zeros for now
    predicted = '0;
end

// always_ff @( posedge clk ) begin
always_comb begin
    done = 1'b0;
    if (rst_n) begin
        out = '0;
        en_recover= 'b0;
    end
    else if (vp_en) begin
        out = predicted;
        last_predicted = predicted;
        en_recover = 'b0;
    end

    else if (d_cache_data.valid && d_cache_data.data != last_predicted) begin
        out = d_cache_data.data;
        en_recover = 'b1;
        correct_prediction = 'b0;
    end

    else if (d_cache_data.valid && d_cache_data.data == last_predicted) begin
        out = d_cache_data.data;
        en_recover = 'b0;
        correct_prediction = 'b1;
        done = 'b1;
    end

    else begin
        out = '0;
        en_recover = 'b0;
        correct_prediction = 'b0;
    end
end
    
endmodule