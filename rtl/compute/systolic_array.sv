// 16x16 Reconfigurable 2D Systolic Array module.
// Integrates four 8x8 tiles to support monolithic 16x16, individual 8x8,
// or combined horizontal/vertical configurations.

module systolic_array (
    input logic clk,
    input logic reset,
    input logic enable [0:3],

    input logic cfg_merge_horizontal_top,
    input logic cfg_merge_horizontal_bottom,
    input logic cfg_merge_vertical_left,
    input logic cfg_merge_vertical_right,

    input logic [7:0] activations_in [0:31],
    output logic [7:0] activations_out [0:31],

    input logic [31:0] partial_sums_in [0:31],
    output logic [31:0] partial_sums_out [0:31],

    input logic [7:0] weights [0:31],
    output logic [7:0] weights_out [0:31],

    input logic weight_write [0:3],
    input logic weight_swap [0:3],
    output logic weight_write_out [0:3],
    output logic weight_swap_out [0:3]
);

// Intermediate signals for tile inputs.
logic [7:0] tile_activations_in [0:3][0:7];
logic [31:0] tile_partial_sums_in [0:3][0:7];
logic [7:0] tile_weights [0:3][0:7];
logic tile_weight_write_in [0:3];
logic tile_weight_swap_in [0:3];

// Intermediate signals for tile outputs.
logic [7:0] tile_activations_out [0:3][0:7];
logic [31:0] tile_partial_sums_out [0:3][0:7];
logic [7:0] tile_weights_out [0:3][0:7];
logic tile_weight_write_out [0:3];
logic tile_weight_swap_out [0:3];
logic tile_weight_swap_col0_out [0:3];

// Multiplexing and routing logic for tile inputs and top-level outputs.
generate
    for (genvar i = 0; i < 8; i++) begin : routing_gen
        // Tile 0 (TL) inputs
        assign tile_activations_in[0][i] = activations_in[i];
        assign tile_partial_sums_in[0][i] = partial_sums_in[i];
        assign tile_weights[0][i] = weights[i];

        // Tile 1 (TR) inputs
        assign tile_activations_in[1][i] = cfg_merge_horizontal_top ? tile_activations_out[0][i] : activations_in[i + 8];
        assign tile_partial_sums_in[1][i] = partial_sums_in[i + 8];
        assign tile_weights[1][i] = weights[i + 8];

        // Tile 2 (BL) inputs
        assign tile_activations_in[2][i] = activations_in[i + 16];
        assign tile_partial_sums_in[2][i] = cfg_merge_vertical_left ? tile_partial_sums_out[0][i] : partial_sums_in[i + 16];
        assign tile_weights[2][i] = cfg_merge_vertical_left ? tile_weights_out[0][i] : weights[i + 16];

        // Tile 3 (BR) inputs
        assign tile_activations_in[3][i] = cfg_merge_horizontal_bottom ? tile_activations_out[2][i] : activations_in[i + 24];
        assign tile_partial_sums_in[3][i] = cfg_merge_vertical_right ? tile_partial_sums_out[1][i] : partial_sums_in[i + 24];
        assign tile_weights[3][i] = cfg_merge_vertical_right ? tile_weights_out[1][i] : weights[i + 24];

        // Top-level outputs
        assign activations_out[i] = tile_activations_out[0][i];
        assign activations_out[i + 8] = tile_activations_out[1][i];
        assign activations_out[i + 16] = tile_activations_out[2][i];
        assign activations_out[i + 24] = tile_activations_out[3][i];

        assign partial_sums_out[i] = tile_partial_sums_out[0][i];
        assign partial_sums_out[i + 8] = tile_partial_sums_out[1][i];
        assign partial_sums_out[i + 16] = tile_partial_sums_out[2][i];
        assign partial_sums_out[i + 24] = tile_partial_sums_out[3][i];

        assign weights_out[i] = tile_weights_out[0][i];
        assign weights_out[i + 8] = tile_weights_out[1][i];
        assign weights_out[i + 16] = tile_weights_out[2][i];
        assign weights_out[i + 24] = tile_weights_out[3][i];
    end
endgenerate

// Control signal routing for all tile slices.
assign tile_weight_write_in[0] = weight_write[0];
assign tile_weight_swap_in[0] = weight_swap[0];

assign tile_weight_write_in[1] = weight_write[1];
assign tile_weight_swap_in[1] = cfg_merge_horizontal_top ? tile_weight_swap_out[0] : weight_swap[1];

assign tile_weight_write_in[2] = cfg_merge_vertical_left ? tile_weight_write_out[0] : weight_write[2];
assign tile_weight_swap_in[2] = cfg_merge_vertical_left ? tile_weight_swap_col0_out[0] : weight_swap[2];

assign tile_weight_write_in[3] = cfg_merge_vertical_right ? tile_weight_write_out[1] : weight_write[3];
assign tile_weight_swap_in[3] = cfg_merge_horizontal_bottom ? tile_weight_swap_out[2] : (cfg_merge_vertical_right ? tile_weight_swap_col0_out[1] : weight_swap[3]);

assign weight_write_out[0] = tile_weight_write_out[0];
assign weight_write_out[1] = tile_weight_write_out[1];
assign weight_write_out[2] = tile_weight_write_out[2];
assign weight_write_out[3] = tile_weight_write_out[3];

assign weight_swap_out[0] = tile_weight_swap_out[0];
assign weight_swap_out[1] = tile_weight_swap_out[1];
assign weight_swap_out[2] = tile_weight_swap_out[2];
assign weight_swap_out[3] = tile_weight_swap_out[3];

// Instantiation of the four 8x8 tiles.
generate
    for (genvar t = 0; t < 4; t++) begin : tile_inst_gen
        tile tile_inst (
            .clk(clk),
            .reset(reset),
            .enable(enable[t]),
            .activations_in(tile_activations_in[t]),
            .activations_out(tile_activations_out[t]),
            .weights(tile_weights[t]),
            .weights_out(tile_weights_out[t]),
            .weight_write_in(tile_weight_write_in[t]),
            .weight_swap_in(tile_weight_swap_in[t]),
            .weight_write_out(tile_weight_write_out[t]),
            .weight_swap_out(tile_weight_swap_out[t]),
            .weight_swap_col0_out(tile_weight_swap_col0_out[t]),
            .partial_sums_in(tile_partial_sums_in[t]),
            .partial_sums_out(tile_partial_sums_out[t])
        );
    end
endgenerate

endmodule