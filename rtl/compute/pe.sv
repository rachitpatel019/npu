// Processing Element (PE) for systolic array matrix multiplication.
// Implements double-buffered weights with pipelined swap control and shadow register shift chain.

module pe #(
    parameter int ACTIVATION_WIDTH,
    parameter int WEIGHT_WIDTH,
    parameter int P_SUM_WIDTH
) (
    input logic clk,
    input logic reset,
    input logic enable,

    input logic [ACTIVATION_WIDTH-1:0] activation_in,
    output logic [ACTIVATION_WIDTH-1:0] activation_out,

    input logic [P_SUM_WIDTH-1:0] partial_sum_in,
    output logic [P_SUM_WIDTH-1:0] partial_sum_out,

    input logic [WEIGHT_WIDTH-1:0] weight_in,
    input logic weight_write_in,
    input logic weight_swap_in,
    output logic [WEIGHT_WIDTH-1:0] weight_out,
    output logic weight_write_out,
    output logic weight_swap_out
);

// Registers to hold weight data for double buffering.
logic [WEIGHT_WIDTH-1:0] weight_active;
logic [WEIGHT_WIDTH-1:0] weight_shadow;

// Pipelined registers for control and data forwarding.
logic [ACTIVATION_WIDTH-1:0] activation_reg;
logic [P_SUM_WIDTH-1:0] partial_sum_reg;
logic weight_swap_reg;

// Drive combinational weight output from shadow register.
assign weight_out = weight_shadow;

// Connect registered internal signals to output ports.
assign activation_out = activation_reg;
assign partial_sum_out = partial_sum_reg;
assign weight_write_out = weight_write_in;
assign weight_swap_out = weight_swap_reg;

// Pipelined control and data updates.
always_ff @(posedge clk) begin
    if (reset) begin
        weight_active <= '0;
        weight_shadow <= '0;
        activation_reg <= '0;
        partial_sum_reg <= '0;
        weight_swap_reg <= 1'b0;
    end
    else if (enable) begin
        if (weight_write_in) begin
            weight_shadow <= weight_in;
        end
        if (weight_swap_in) begin
            weight_active <= weight_shadow;
        end
        activation_reg <= activation_in;
        partial_sum_reg <= $signed(partial_sum_in) + ($signed(activation_in) * $signed(weight_active));
        weight_swap_reg <= weight_swap_in;
    end
end

endmodule