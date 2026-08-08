// Processing Element (PE) for systolic array matrix multiplication.
// Implements double-buffered weights with pipelined swap control and fully systolic weight propagation.

// * Could split multiply and accumulate operations across 2 clock cycles to improve Fmax.

module pe (
    input logic clk,
    input logic reset,
    input logic enable,

    input logic [7:0] activation_in,
    output logic [7:0] activation_out,

    input logic [31:0] partial_sum_in,
    output logic [31:0] partial_sum_out,

    input logic [7:0] weight_in,
    input logic weight_write_in,
    input logic weight_swap_in,
    output logic [7:0] weight_out,
    output logic weight_write_out,
    output logic weight_swap_out
);

// Registers to hold weight data for double buffering and pipelined write enable state.
logic [7:0] weight_active;
logic [7:0] weight_shadow;
logic weight_write_reg;

// Pipelined logic for activation forwarding, partial sum accumulation, and double-buffered weight updates.
always_ff @(posedge clk) begin
    if (reset) begin
        activation_out <= 8'd0;
        partial_sum_out <= 32'd0;
        weight_out <= 8'd0;
        weight_active <= 8'd0;
        weight_shadow <= 8'd0;
        weight_write_reg <= 1'b0;
        weight_write_out <= 1'b0;
        weight_swap_out <= 1'b0;
    end
    else if (enable) begin
        if (weight_write_in) begin
            weight_shadow <= weight_in;
        end
        if (weight_swap_in) begin
            weight_active <= weight_shadow;
        end
        activation_out <= activation_in;
        partial_sum_out <= partial_sum_in + (activation_in * weight_active);
        weight_out <= weight_in;
        weight_write_reg <= weight_write_in;
        weight_write_out <= weight_write_reg;
        weight_swap_out <= weight_swap_in;
    end
end

endmodule