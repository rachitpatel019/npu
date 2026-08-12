`timescale 1ns / 1ps

// ============================================================================
// Unit Testbench: tile_tb
// ============================================================================
// DUT:         tile
// Description: Self-checking testbench for an 8x8 tile of PEs.
//              Verifies weight loading and matrix multiplication computation.
// ============================================================================

module tile_tb;

// ---- Scoreboard Counters ---------------------------------------------------
int tests_total;
int tests_passed;
int tests_failed;

// ---- Clock & Reset ---------------------------------------------------------
localparam CLK_PERIOD = 10;

logic clk;
logic reset;
logic enable;

always #(CLK_PERIOD / 2) clk = ~clk;

// ---- DUT Parameters --------------------------------------------------------
localparam int ACTIVATION_WIDTH = 8;
localparam int WEIGHT_WIDTH = 8;
localparam int P_SUM_WIDTH = 32;
localparam int TILE_ROWS = 8;
localparam int TILE_COLS = 8;

// ---- DUT Signals -----------------------------------------------------------
logic [ACTIVATION_WIDTH-1:0] activations_in [0:TILE_ROWS-1];
logic [ACTIVATION_WIDTH-1:0] activations_out [0:TILE_ROWS-1];

logic [WEIGHT_WIDTH-1:0] weights [0:TILE_COLS-1];
logic [WEIGHT_WIDTH-1:0] weights_out [0:TILE_COLS-1];
logic weight_write_in;
logic weight_swap_in;
logic weight_write_out;
logic weight_swap_out;

logic [P_SUM_WIDTH-1:0] partial_sums_in [0:TILE_COLS-1];
logic [P_SUM_WIDTH-1:0] partial_sums_out [0:TILE_COLS-1];

// ---- Captured Outputs -------------------------------------------------------
logic [P_SUM_WIDTH-1:0] captured_p_sums [0:TILE_COLS-1];

// ---- DUT Instantiation -----------------------------------------------------
tile #(
.ACTIVATION_WIDTH(ACTIVATION_WIDTH),
.WEIGHT_WIDTH(WEIGHT_WIDTH),
.P_SUM_WIDTH(P_SUM_WIDTH),
.TILE_ROWS(TILE_ROWS),
.TILE_COLS(TILE_COLS)
) dut (
.clk(clk),
.reset(reset),
.enable(enable),
.activations_in(activations_in),
.activations_out(activations_out),
.weights(weights),
.weights_out(weights_out),
.weight_write_in(weight_write_in),
.weight_swap_in(weight_swap_in),
.weight_write_out(weight_write_out),
.weight_swap_out(weight_swap_out),
.partial_sums_in(partial_sums_in),
.partial_sums_out(partial_sums_out)
);

// ---- UVM-Style Reporting ---------------------------------------------------
task automatic report_info(string id, string msg);
$display("[UVM_INFO]  %s @ %0t: %s", id, $time, msg);
endtask

task automatic report_error(string id, string msg);
$display("[UVM_ERROR] %s @ %0t: %s", id, $time, msg);
tests_failed++;
tests_total++;
endtask

task automatic report_fatal(string id, string msg);
$display("[UVM_FATAL] %s @ %0t: %s", id, $time, msg);
$finish;
endtask

// ---- Helper Tasks ----------------------------------------------------------
task automatic reset_dut();
reset = 1;
enable = 0;
weight_write_in = 1'b0;
weight_swap_in = 1'b0;
for (int i = 0; i < TILE_ROWS; i++) begin
    activations_in[i] = '0;
end
for (int i = 0; i < TILE_COLS; i++) begin
    weights[i] = '0;
    partial_sums_in[i] = '0;
    captured_p_sums[i] = '0;
end
@(posedge clk);
@(posedge clk);
reset = 0;
enable = 1;
@(posedge clk);
endtask

// ---- Timeout Watchdog ------------------------------------------------------
initial begin
#100_000;
report_fatal("WATCHDOG", "Simulation timed out.");
end

// ---- Test Sequence ---------------------------------------------------------
initial begin
clk = 0;
tests_total = 0;
tests_passed = 0;
tests_failed = 0;
report_info("TB", "Starting tile tests.");

// Phase 1: Reset Behavior
reset_dut();
for (int i = 0; i < TILE_ROWS; i++) begin
    if (activations_out[i] !== '0) begin
        report_error("RESET", $sformatf("Non-zero activation output after reset at index %d", i));
    end
end
for (int i = 0; i < TILE_COLS; i++) begin
    if (partial_sums_out[i] !== '0) begin
        report_error("RESET", $sformatf("Non-zero partial sum output after reset at index %d", i));
    end
end
tests_total++;

// Phase 2: Weight Loading (Assert write, shift weights over TILE_ROWS cycles)
@(negedge clk);
weight_write_in = 1'b1;
for (int c = 0; c < TILE_ROWS; c++) begin
    for (int col = 0; col < TILE_COLS; col++) begin
        weights[col] = (TILE_ROWS - c) * 10 + (col + 1);
    end
    @(negedge clk);
end
weight_write_in = 1'b0;

// Wait for weights to propagate completely (TILE_ROWS cycles total propagation)
for (int cycle = 0; cycle < TILE_ROWS; cycle++) begin
    @(negedge clk);
end

// Phase 3: Diagonal Weight Swap
weight_swap_in = 1'b1;
@(negedge clk);
weight_swap_in = 1'b0;

// Wait for swap wavefront to propagate through the tile (TILE_ROWS + TILE_COLS cycles max)
for (int cycle = 0; cycle < TILE_ROWS + TILE_COLS; cycle++) begin
    @(negedge clk);
end

// Phase 4: Stream Activations & Perform Multiplication
for (int cycle = 0; cycle < 30; cycle++) begin
    for (int r = 0; r < TILE_ROWS; r++) begin
        if (cycle >= r && cycle < r + TILE_COLS) begin
            activations_in[r] = 8'd1;
        end else begin
            activations_in[r] = 8'd0;
        end
    end
    
    // Capture output at the exact peak cycle for each column c:
    for (int c = 0; c < TILE_COLS; c++) begin
        if (cycle === TILE_ROWS + c) begin
            captured_p_sums[c] = partial_sums_out[c];
        end
    end
    
    @(negedge clk);
end

// Phase 5: Verification of results
tests_total++;
// Expected correct output (independent weights): Column c = 360 + 8 * (c+1).
if (captured_p_sums[0] === 32'd368) begin
    report_info("TEST", "PASSED: Tile verified with correct independent weights!");
    tests_passed++;
end else if (captured_p_sums[0] === 32'd88) begin
    report_error("TEST", $sformatf("FAILED: Weight loading synchronization bug detected! Row-level weight separation is lost. Column 0 got 88 (expected 368). All rows got weight = %0d.", 11));
    $display("       Detailed Captured Outputs (Buggy):");
    for (int i = 0; i < TILE_COLS; i++) begin
        $display("       Col %0d: Expected (Independent) = %0d, Actual = %0d", i, 360 + 8*(i+1), captured_p_sums[i]);
    end
end else begin
    report_error("TEST", $sformatf("FAILED: Unexpected calculation output: Col 0 = %0d (expected 368)", captured_p_sums[0]));
end

// Summary
report_info("TB", "All tests complete.");
$display("--- tile Test Summary ---");
$display("Total: %0d | Passed: %0d | Failed: %0d", tests_total, tests_passed, tests_failed);
if (tests_failed == 0) $display("RESULT: PASS");
else $display("RESULT: FAIL");
$finish;
end

endmodule
