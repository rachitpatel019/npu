// Top-level FPGA wrapper for systolic array synthesis and timing benchmarking.
// Unpacks a single serial input into input registers for all array ports,
// and XOR-reduces all registered outputs to a single serial output pin
// to prevent synthesis optimization while fitting within physical pin constraints.

module top (
    input  logic clk,
    input  logic reset,
    input  logic serial_in,
    output logic serial_out
);

    // Flattened input shift register to feed all systolic array ports
    // Size breakdown:
    // - activations_in: 32 ports * 8 bits = 256 bits
    // - partial_sums_in: 32 ports * 32 bits = 1024 bits
    // - weights: 32 ports * 8 bits = 256 bits
    // - enable: 4 bits
    // - cfg_merge_horizontal_top: 1 bit
    // - cfg_merge_horizontal_bottom: 1 bit
    // - cfg_merge_vertical_left: 1 bit
    // - cfg_merge_vertical_right: 1 bit
    // - weight_write: 4 bits
    // - weight_swap: 4 bits
    // Total bits = 256 + 1024 + 256 + 4 + 1 + 1 + 1 + 1 + 4 + 4 = 1552 bits

    localparam int NUM_INPUT_BITS = 1552;
    logic [NUM_INPUT_BITS-1:0] input_shifter;

    // Shift in input data
    always_ff @(posedge clk) begin
        if (reset) begin
            input_shifter <= '0;
        end else begin
            input_shifter <= {input_shifter[NUM_INPUT_BITS-2:0], serial_in};
        end
    end

    // Unpack input shift register
    logic [7:0] activations_in [0:31];
    logic [31:0] partial_sums_in [0:31];
    logic [7:0] weights [0:31];
    logic enable [0:3];
    logic cfg_merge_horizontal_top;
    logic cfg_merge_horizontal_bottom;
    logic cfg_merge_vertical_left;
    logic cfg_merge_vertical_right;
    logic weight_write [0:3];
    logic weight_swap [0:3];

    genvar i;
    generate
        // Unpacking activations_in (bits 0 to 255)
        for (i = 0; i < 32; i++) begin : gen_activations_in
            assign activations_in[i] = input_shifter[i*8 +: 8];
        end

        // Unpacking partial_sums_in (bits 256 to 1279)
        for (i = 0; i < 32; i++) begin : gen_partial_sums_in
            assign partial_sums_in[i] = input_shifter[256 + i*32 +: 32];
        end

        // Unpacking weights (bits 1280 to 1535)
        for (i = 0; i < 32; i++) begin : gen_weights
            assign weights[i] = input_shifter[1280 + i*8 +: 8];
        end

        // Unpacking enable (bits 1536 to 1539)
        for (i = 0; i < 4; i++) begin : gen_enable
            assign enable[i] = input_shifter[1536 + i];
        end
    endgenerate

    // Unpacking configuration signals (bits 1540 to 1543)
    assign cfg_merge_horizontal_top    = input_shifter[1540];
    assign cfg_merge_horizontal_bottom = input_shifter[1541];
    assign cfg_merge_vertical_left     = input_shifter[1542];
    assign cfg_merge_vertical_right    = input_shifter[1543];

    // Unpacking weight_write and weight_swap (bits 1544 to 1551)
    generate
        for (i = 0; i < 4; i++) begin : gen_weight_ctrl
            assign weight_write[i] = input_shifter[1544 + i];
            assign weight_swap[i]  = input_shifter[1548 + i];
        end
    endgenerate

    // Outputs from systolic array
    logic [7:0] activations_out [0:31];
    logic [31:0] partial_sums_out [0:31];
    logic [7:0] weights_out [0:31];
    logic weight_write_out [0:3];
    logic weight_swap_out [0:3];

    // Instantiate systolic array
    systolic_array u_systolic_array (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .cfg_merge_horizontal_top(cfg_merge_horizontal_top),
        .cfg_merge_horizontal_bottom(cfg_merge_horizontal_bottom),
        .cfg_merge_vertical_left(cfg_merge_vertical_left),
        .cfg_merge_vertical_right(cfg_merge_vertical_right),
        .activations_in(activations_in),
        .activations_out(activations_out),
        .partial_sums_in(partial_sums_in),
        .partial_sums_out(partial_sums_out),
        .weights(weights),
        .weights_out(weights_out),
        .weight_write(weight_write),
        .weight_swap(weight_swap),
        .weight_write_out(weight_write_out),
        .weight_swap_out(weight_swap_out)
    );

    // Register systolic array outputs to prevent I/O path timing constraints from limiting Fmax
    logic [7:0] activations_out_r [0:31];
    logic [31:0] partial_sums_out_r [0:31];
    logic [7:0] weights_out_r [0:31];
    logic weight_write_out_r [0:3];
    logic weight_swap_out_r [0:3];

    always_ff @(posedge clk) begin
        if (reset) begin
            for (int j = 0; j < 32; j++) begin
                activations_out_r[j]  <= '0;
                partial_sums_out_r[j] <= '0;
                weights_out_r[j]      <= '0;
            end
            for (int j = 0; j < 4; j++) begin
                weight_write_out_r[j] <= '0;
                weight_swap_out_r[j]  <= '0;
            end
        end else begin
            activations_out_r  <= activations_out;
            partial_sums_out_r <= partial_sums_out;
            weights_out_r      <= weights_out;
            weight_write_out_r <= weight_write_out;
            weight_swap_out_r  <= weight_swap_out;
        end
    end

    // XOR reduction of all registered outputs to generate serial_out
    logic [1543:0] flat_outputs;
    
    generate
        for (i = 0; i < 32; i++) begin : gen_flat_outputs
            assign flat_outputs[i*8 +: 8] = activations_out_r[i];
            assign flat_outputs[256 + i*32 +: 32] = partial_sums_out_r[i];
            assign flat_outputs[1280 + i*8 +: 8] = weights_out_r[i];
        end

        for (i = 0; i < 4; i++) begin : gen_flat_ctrl
            assign flat_outputs[1536 + i] = weight_write_out_r[i];
            assign flat_outputs[1540 + i] = weight_swap_out_r[i];
        end
    endgenerate

    // Drive serial_out using registered XOR reduction
    always_ff @(posedge clk) begin
        if (reset) begin
            serial_out <= 1'b0;
        end else begin
            serial_out <= ^flat_outputs;
        end
    end

endmodule
