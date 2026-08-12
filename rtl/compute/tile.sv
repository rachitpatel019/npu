// 8x8 2D systolic array tile of processing elements (PEs).
// Manages activation, partial sum, and shift-chain weight dataflows.

module tile #(
    parameter int ACTIVATION_WIDTH,
    parameter int WEIGHT_WIDTH,
    parameter int P_SUM_WIDTH,
    parameter int TILE_ROWS,
    parameter int TILE_COLS
) (
    input logic clk,
    input logic reset,
    input logic enable,

    input logic [ACTIVATION_WIDTH-1:0] activations_in [0:TILE_ROWS-1],
    output logic [ACTIVATION_WIDTH-1:0] activations_out [0:TILE_ROWS-1],

    input logic [WEIGHT_WIDTH-1:0] weights [0:TILE_COLS-1],
    output logic [WEIGHT_WIDTH-1:0] weights_out [0:TILE_COLS-1],
    input logic weight_write_in,
    input logic weight_swap_in,
    output logic weight_write_out,
    output logic weight_swap_out,
    output logic weight_swap_col0_out,

    input logic [P_SUM_WIDTH-1:0] partial_sums_in [0:TILE_COLS-1],
    output logic [P_SUM_WIDTH-1:0] partial_sums_out [0:TILE_COLS-1]
);

// Interconnect wires for array ports.
logic [ACTIVATION_WIDTH-1:0] activation_wire [0:TILE_ROWS-1][0:TILE_COLS];

logic [P_SUM_WIDTH-1:0] partial_sum_wire [0:TILE_ROWS][0:TILE_COLS-1];

logic [WEIGHT_WIDTH-1:0] weight_data_wire [0:TILE_ROWS][0:TILE_COLS-1];

logic weight_swap_wire [0:TILE_ROWS-1][0:TILE_COLS];

// Drive boundary conditions and map array outputs.
genvar i;
generate
    for (i = 0; i < TILE_ROWS; i++) begin : boundary_act
        assign activation_wire[i][0] = activations_in[i];
        assign activations_out[i] = activation_wire[i][TILE_COLS];
    end

    for (i = 0; i < TILE_COLS; i++) begin : boundary_col
        assign partial_sum_wire[0][i] = partial_sums_in[i];
        assign weight_data_wire[0][i] = weights[i];
        assign partial_sums_out[i] = partial_sum_wire[TILE_ROWS][i];
        assign weights_out[i] = weight_data_wire[TILE_ROWS][i];
    end
endgenerate

// Delays the weight swap input by one cycle per row to form a diagonal wavefront.
generate
    if (TILE_ROWS > 1) begin : gen_swap_delay
        logic weight_swap_col0 [1:TILE_ROWS-1];

        always_ff @(posedge clk) begin
            if (reset) begin
                for (int r = 1; r < TILE_ROWS; r++) begin
                    weight_swap_col0[r] <= 1'b0;
                end
                weight_swap_col0_out <= 1'b0;
            end
            else if (enable) begin
                weight_swap_col0[1] <= weight_swap_in;
                for (int r = 2; r < TILE_ROWS; r++) begin
                    weight_swap_col0[r] <= weight_swap_col0[r-1];
                end
                weight_swap_col0_out <= weight_swap_col0[TILE_ROWS-1];
            end
        end

        genvar r;
        for (r = 0; r < TILE_ROWS; r++) begin : swap_in_conn
            assign weight_swap_wire[r][0] = (r == 0) ? weight_swap_in : weight_swap_col0[r];
        end
    end
    else begin : gen_no_swap_delay
        assign weight_swap_col0_out = weight_swap_in;
        assign weight_swap_wire[0][0] = weight_swap_in;
    end
endgenerate

// Instantiates the 2D array of processing elements and chains their connections.
genvar row;
genvar col;
generate
    for (row = 0; row < TILE_ROWS; row++) begin : tile_row
        for (col = 0; col < TILE_COLS; col++) begin : tile_col
            pe #(
                .ACTIVATION_WIDTH(ACTIVATION_WIDTH),
                .WEIGHT_WIDTH(WEIGHT_WIDTH),
                .P_SUM_WIDTH(P_SUM_WIDTH)
            ) pe_inst (
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
assign weight_swap_out = weight_swap_wire[0][TILE_COLS];

endmodule