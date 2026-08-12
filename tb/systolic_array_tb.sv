`timescale 1ns / 1ps

module systolic_array_tb;

logic clk;
logic reset;

logic enable [0:3];
logic cfg_merge_horizontal_top;
logic cfg_merge_horizontal_bottom;
logic cfg_merge_vertical_left;
logic cfg_merge_vertical_right;

// ---- DUT Parameters --------------------------------------------------------
localparam int ACTIVATION_WIDTH = 8;
localparam int WEIGHT_WIDTH = 8;
localparam int P_SUM_WIDTH = 32;
localparam int TILE_ROWS = 8;
localparam int TILE_COLS = 8;

// ---- DUT Signals -----------------------------------------------------------
logic [ACTIVATION_WIDTH-1:0] activations_in [0:4*TILE_ROWS-1];
logic [ACTIVATION_WIDTH-1:0] activations_out [0:4*TILE_ROWS-1];

logic [P_SUM_WIDTH-1:0] partial_sums_in [0:4*TILE_COLS-1];
logic [P_SUM_WIDTH-1:0] partial_sums_out [0:4*TILE_COLS-1];

logic [WEIGHT_WIDTH-1:0] weights [0:4*TILE_COLS-1];
logic [WEIGHT_WIDTH-1:0] weights_out [0:4*TILE_COLS-1];

logic weight_write [0:3];
logic weight_swap [0:3];
logic weight_write_out [0:3];
logic weight_swap_out [0:3];

integer file;
integer status;
integer exp_file;
integer exp_status;
integer exp_cycle;
integer exp_port;
integer current_cycle;
integer passes;
integer mismatches;

logic r_reset;
logic [3:0] r_enable;
logic [3:0] r_cfg;
logic [3:0] r_weight_write;
logic [3:0] r_weight_swap;
logic [WEIGHT_WIDTH-1:0] r_weights [0:4*TILE_COLS-1];
logic [ACTIVATION_WIDTH-1:0] r_activations_in [0:4*TILE_ROWS-1];
logic [P_SUM_WIDTH-1:0] r_partial_sums_in [0:4*TILE_COLS-1];
logic [P_SUM_WIDTH-1:0] exp_val;

// ---- DUT Instantiation -----------------------------------------------------
systolic_array #(
.ACTIVATION_WIDTH(ACTIVATION_WIDTH),
.WEIGHT_WIDTH(WEIGHT_WIDTH),
.P_SUM_WIDTH(P_SUM_WIDTH),
.TILE_ROWS(TILE_ROWS),
.TILE_COLS(TILE_COLS)
) dut (
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

always begin
#5 clk = ~clk;
end

initial begin
clk = 0;
end

initial begin
file = $fopen("tb/stimulus_inputs.txt", "r");
exp_file = $fopen("tb/stimulus_expected.txt", "r");
if (file == 0 || exp_file == 0) begin
$display("Error: Could not open tb/stimulus_inputs.txt or tb/stimulus_expected.txt");
$finish;
end

reset = 1;
enable[0] = 0;
enable[1] = 0;
enable[2] = 0;
enable[3] = 0;
cfg_merge_horizontal_top = 0;
cfg_merge_horizontal_bottom = 0;
cfg_merge_vertical_left = 0;
cfg_merge_vertical_right = 0;
weight_write[0] = 0;
weight_write[1] = 0;
weight_write[2] = 0;
weight_write[3] = 0;
weight_swap[0] = 0;
weight_swap[1] = 0;
weight_swap[2] = 0;
weight_swap[3] = 0;

for (int i = 0; i < 4*TILE_ROWS; i++) begin
    activations_in[i] = '0;
end
for (int i = 0; i < 4*TILE_COLS; i++) begin
    partial_sums_in[i] = '0;
    weights[i] = '0;
end

reset = 0;
exp_status = $fscanf(exp_file, "%d %d %h\n", exp_cycle, exp_port, exp_val);
current_cycle = 0;
passes = 0;
mismatches = 0;

while (!$feof(file)) begin
@(negedge clk);
if (current_cycle > 0) begin
while (exp_status == 3 && exp_cycle == current_cycle - 1) begin
if (partial_sums_out[exp_port] !== exp_val) begin
$display("[ERROR] Cycle %0d, Port %0d: Expected %h, Got %h", exp_cycle, exp_port, exp_val, partial_sums_out[exp_port]);
mismatches = mismatches + 1;
end
else begin
passes = passes + 1;
end
exp_status = $fscanf(exp_file, "%d %d %h\n", exp_cycle, exp_port, exp_val);
end
end

status = $fscanf(file, "%h %h %h %h %h", r_reset, r_enable, r_cfg, r_weight_write, r_weight_swap);
if (status == 5) begin
reset = r_reset;
enable[0] = r_enable[0];
enable[1] = r_enable[1];
enable[2] = r_enable[2];
enable[3] = r_enable[3];

cfg_merge_horizontal_top = r_cfg[3];
cfg_merge_horizontal_bottom = r_cfg[2];
cfg_merge_vertical_left = r_cfg[1];
cfg_merge_vertical_right = r_cfg[0];

weight_write[0] = r_weight_write[0];
weight_write[1] = r_weight_write[1];
weight_write[2] = r_weight_write[2];
weight_write[3] = r_weight_write[3];

weight_swap[0] = r_weight_swap[0];
weight_swap[1] = r_weight_swap[1];
weight_swap[2] = r_weight_swap[2];
weight_swap[3] = r_weight_swap[3];

for (int i = 0; i < 4*TILE_COLS; i++) begin
status = $fscanf(file, "%h", r_weights[i]);
weights[i] = r_weights[i];
end

for (int i = 0; i < 4*TILE_ROWS; i++) begin
status = $fscanf(file, "%h", r_activations_in[i]);
activations_in[i] = r_activations_in[i];
end

for (int i = 0; i < 4*TILE_COLS; i++) begin
status = $fscanf(file, "%h", r_partial_sums_in[i]);
partial_sums_in[i] = r_partial_sums_in[i];
end
end
current_cycle = current_cycle + 1;
end

@(negedge clk);
while (exp_status == 3 && exp_cycle == current_cycle - 1) begin
if (partial_sums_out[exp_port] !== exp_val) begin
$display("[ERROR] Cycle %0d, Port %0d: Expected %h, Got %h", exp_cycle, exp_port, exp_val, partial_sums_out[exp_port]);
mismatches = mismatches + 1;
end
else begin
passes = passes + 1;
end
exp_status = $fscanf(exp_file, "%d %d %h\n", exp_cycle, exp_port, exp_val);
end

$display("Verification Complete: Passes = %0d, Mismatches = %0d", passes, mismatches);
$fclose(file);
$fclose(exp_file);
$finish;
end

endmodule
