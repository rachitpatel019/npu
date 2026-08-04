// Processing Element (PE) for systolic array matrix multiplication.
// Implements double-buffered weights with pipelined swap control.

module pe (
    input logic clk,
    input logic reset,

    input logic [7:0] activation_in,
    input logic [31:0] partial_sum_in,

    input logic [7:0] weight_in,
    input logic weight_write,
    input logic weight_swap_in,

    output logic [7:0] activation_out,
    output logic [31:0] partial_sum_out,
    output logic weight_swap_out
);

// Internal state for double-buffered weight registers.
logic [7:0] weight_active;
logic [7:0] weight_shadow;

// Synchronous pipeline logic, double-buffer updates, and MAC execution.
always_ff @(posedge clk) begin
    if (reset) begin
        activation_out <= 8'd0;
        weight_active <= 8'd0;
        weight_shadow <= 8'd0;
        weight_swap_out <= 1'b0;
        partial_sum_out <= 32'd0;
    end
    else begin
        if (weight_write) begin
            weight_shadow <= weight_in;
        end
        if (weight_swap_in) begin
            weight_active <= weight_shadow;
        end
        activation_out <= activation_in;
        partial_sum_out <= partial_sum_in + (activation_in * weight_active);
        weight_swap_out <= weight_swap_in;
    end
end

endmodule