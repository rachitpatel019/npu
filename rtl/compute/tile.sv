// 8x8 2D systolic array tile of processing elements (PEs).
// Manages activation, partial sum, and shift-chain weight dataflows.

module tile (
input logic clk,
input logic reset,
input logic enable,

input logic [7:0] activations_in [0:7],
output logic [7:0] activations_out [0:7],

input logic [7:0] weights [0:7],
output logic [7:0] weights_out [0:7],
input logic weight_write_in,
input logic weight_swap_in,
output logic weight_write_out,
output logic weight_swap_out,
output logic weight_swap_col0_out,

input logic [31:0] partial_sums_in [0:7],
output logic [31:0] partial_sums_out [0:7]
);

// Interconnect wires for array ports.
logic [7:0] activation_wire [0:7][0:8];
logic [31:0] partial_sum_wire [0:8][0:7];
logic [7:0] weight_data_wire [0:8][0:7];
logic weight_swap_wire [0:7][0:8];
logic weight_swap_col0 [1:7];

// Drive boundary conditions and map array outputs.
generate
    for (genvar i = 0; i < 8; i++) begin : boundary_connections
        assign activation_wire[i][0] = activations_in[i];
        assign partial_sum_wire[0][i] = partial_sums_in[i];
        assign weight_data_wire[0][i] = weights[i];
        
        assign activations_out[i] = activation_wire[i][8];
        assign partial_sums_out[i] = partial_sum_wire[8][i];
        assign weights_out[i] = weight_data_wire[8][i];

        if (i == 0) begin
            assign weight_swap_wire[0][0] = weight_swap_in;
        end
        else begin
            assign weight_swap_wire[i][0] = weight_swap_col0[i];
        end
    end
endgenerate

// Delays the weight swap input by one cycle per row to form a diagonal wavefront.
always_ff @(posedge clk) begin
    if (reset) begin
        for (int i = 1; i < 8; i++) begin
            weight_swap_col0[i] <= 1'b0;
        end
        weight_swap_col0_out <= 1'b0;
    end
    else if (enable) begin
        weight_swap_col0[1] <= weight_swap_in;
        for (int i = 2; i < 8; i++) begin
            weight_swap_col0[i] <= weight_swap_col0[i-1];
        end
        weight_swap_col0_out <= weight_swap_col0[7];
    end
end

// Instantiates the 2D array of processing elements and chains their connections.
generate
    for (genvar row = 0; row < 8; row++) begin : tile_row
        for (genvar col = 0; col < 8; col++) begin : tile_col
            pe pe_inst (
                .clk(clk),
                .reset(reset),
                .enable(enable),
                .activation_in(activation_wire[row][col]),
                .activation_out(activation_wire[row][col+1]),
                .partial_sum_in(partial_sum_wire[row][col]),
                .partial_sum_out(partial_sum_wire[row+1][col]),
                .weight_in(weight_data_wire[row][col]),
                .weight_out(weight_data_wire[row+1][col]),
                .weight_write_in(weight_write_in),
                .weight_write_out(),
                .weight_swap_in(weight_swap_wire[row][col]),
                .weight_swap_out(weight_swap_wire[row][col+1])
            );
        end
    end
endgenerate

// Connects final boundary control signals to module outputs.
assign weight_write_out = weight_write_in;
assign weight_swap_out = weight_swap_wire[0][8];

endmodule