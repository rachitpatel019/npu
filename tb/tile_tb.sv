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

// ---- DUT Signals -----------------------------------------------------------
logic [7:0] activations_in [0:7];
logic [7:0] activations_out [0:7];

logic [7:0] weights [0:7];
logic [7:0] weights_out [0:7];
logic weight_write_in;
logic weight_swap_in;
logic weight_write_out;
logic weight_swap_out;

logic [31:0] partial_sums_in [0:7];
logic [31:0] partial_sums_out [0:7];

// ---- Captured Outputs -------------------------------------------------------
logic [31:0] captured_p_sums [0:7];

// ---- DUT Instantiation -----------------------------------------------------
tile dut (
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
for (int i = 0; i < 8; i++) begin
    activations_in[i] = 8'd0;
    weights[i] = 8'd0;
    partial_sums_in[i] = 32'd0;
    captured_p_sums[i] = 32'd0;
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
for (int i = 0; i < 8; i++) begin
    if (activations_out[i] !== 8'd0 || partial_sums_out[i] !== 32'd0) begin
        report_error("RESET", $sformatf("Non-zero output after reset at index %d", i));
    end
end
tests_total++;

// Phase 2: Weight Loading (Assert write, shift weights over 8 cycles)
@(negedge clk);
weight_write_in = 1'b1;
for (int c = 0; c < 8; c++) begin
    for (int col = 0; col < 8; col++) begin
        weights[col] = (8 - c) * 10 + (col + 1);
    end
    @(negedge clk);
end
weight_write_in = 1'b0;

// Wait for weights to propagate completely (8 cycles total propagation)
for (int cycle = 0; cycle < 8; cycle++) begin
    @(negedge clk);
end

// Phase 3: Diagonal Weight Swap
weight_swap_in = 1'b1;
@(negedge clk);
weight_swap_in = 1'b0;

// Wait for swap wavefront to propagate through the tile (15 cycles max for 8x8)
for (int cycle = 0; cycle < 16; cycle++) begin
    @(negedge clk);
end

// Phase 4: Stream Activations & Perform Multiplication
// Input activations matrix A (8x8) has A[r][k] = 1 for all r, k.
// We skew A: activations_in[r] is 1 for cycles r to r+7.
for (int cycle = 0; cycle < 30; cycle++) begin
    for (int r = 0; r < 8; r++) begin
        if (cycle >= r && cycle < r + 8) begin
            activations_in[r] = 8'd1;
        end else begin
            activations_in[r] = 8'd0;
        end
    end
    
    // Capture output at the exact peak cycle for each column c:
    // Output for Column c is valid at cycle: 8 (tile latency) + 8 (input feed cycles) + c - 1?
    // Wait, let's see. Column c output peaks when all 8 elements have finished accumulating.
    // The last activation element for Row 7 is fed at cycle 14 (r=7, k=7).
    // It propagates to Col c at cycle 14 + c.
    // The computation completes and is registered at PE(7, c) at cycle 14 + c.
    // It is visible at partial_sums_out[c] at cycle 15 + c.
    // Let's verify cycle indices from the logs:
    // Column 0 output was 88 at Cycle 44 (which is cycle index 44 in the previous TB? 
    // Wait, why was it cycle 44? 
    // Ah, because in the previous TB, we did reset_dut() (3 cycles), loading (8 cycles),
    // wait for weights (8 cycles), swap (1 cycle), wait for swap (16 cycles) -> total 36 cycles before computation started!
    // So computation started at cycle 36.
    // Column 0 output peaked at cycle 36 + 8 = 44!
    // Column c output peaks at cycle 36 + 8 + c = 44 + c!
    // Let's capture at cycle 44 + c.
    // Since cycle in this loop starts at 0 (which corresponds to cycle 36 in the global simulation timeline):
    // Column c peaks at loop cycle 8 + c!
    if (cycle === 8) captured_p_sums[0] = partial_sums_out[0];
    if (cycle === 9) captured_p_sums[1] = partial_sums_out[1];
    if (cycle === 10) captured_p_sums[2] = partial_sums_out[2];
    if (cycle === 11) captured_p_sums[3] = partial_sums_out[3];
    if (cycle === 12) captured_p_sums[4] = partial_sums_out[4];
    if (cycle === 13) captured_p_sums[5] = partial_sums_out[5];
    if (cycle === 14) captured_p_sums[6] = partial_sums_out[6];
    if (cycle === 15) captured_p_sums[7] = partial_sums_out[7];
    
    @(negedge clk);
end

// Phase 5: Verification of results
tests_total++;
// Expected correct output (independent weights): Column c = 360 + 8 * (c+1).
// Expected buggy output (same weight across rows): Column c = 80 + 8 * (c+1).
if (captured_p_sums[0] === 32'd368) begin
    report_info("TEST", "PASSED: Tile verified with correct independent weights!");
    tests_passed++;
end else if (captured_p_sums[0] === 32'd88) begin
    report_error("TEST", $sformatf("FAILED: Weight loading synchronization bug detected! Row-level weight separation is lost. Column 0 got 88 (expected 368). All rows got weight = %0d.", 11));
    $display("       Detailed Captured Outputs (Buggy):");
    for (int i = 0; i < 8; i++) begin
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
