`timescale 1ns / 1ps

// ============================================================================
// Unit Testbench: pe_tb
// ============================================================================
// DUT:         pe
// Description: Self-checking testbench with UVM-inspired reporting.
// ============================================================================

module pe_tb;

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
logic [7:0] activation_in;
logic [7:0] activation_out;

logic [31:0] partial_sum_in;
logic [31:0] partial_sum_out;

logic [7:0] weight_in;
logic weight_write_in;
logic weight_swap_in;
logic [7:0] weight_out;
logic weight_write_out;
logic weight_swap_out;

// ---- DUT Instantiation -----------------------------------------------------
pe dut (
.clk(clk),
.reset(reset),
.enable(enable),
.activation_in(activation_in),
.activation_out(activation_out),
.partial_sum_in(partial_sum_in),
.partial_sum_out(partial_sum_out),
.weight_in(weight_in),
.weight_write_in(weight_write_in),
.weight_swap_in(weight_swap_in),
.weight_out(weight_out),
.weight_write_out(weight_write_out),
.weight_swap_out(weight_swap_out)
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
activation_in = 8'd0;
partial_sum_in = 32'd0;
weight_in = 8'd0;
weight_write_in = 1'b0;
weight_swap_in = 1'b0;
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
report_info("TB", "Starting pe tests.");

// Phase 1: Reset Behavior
reset_dut();
if (activation_out === 8'd0 && partial_sum_out === 32'd0 && weight_out === 8'd0 && 
    weight_write_out === 1'b0 && weight_swap_out === 1'b0) begin
    tests_passed++;
end else begin
    report_error("RESET", "DUT registers did not clear on reset.");
end
tests_total++;

// Phase 2: Shadow Weight Loading
// Load weight = 15
weight_in = 8'd15;
weight_write_in = 1'b1;
@(posedge clk);
#1; // Delay to sample outputs after clock edge
// Check that write and weight propagate
if (weight_out === 8'd15 && weight_write_out === 1'b1) begin
    tests_passed++;
end else begin
    report_error("LOAD_PROP", $sformatf("Mismatch in weight propagation: weight_out=%d, write_out=%d", weight_out, weight_write_out));
end
tests_total++;

// Deassert weight_write
weight_write_in = 1'b0;
weight_in = 8'd99; // Change weight_in to make sure it doesn't affect active/shadow immediately
@(posedge clk);
#1;

// Phase 3: Weight Swap
// Swap shadow weight (15) to active register
weight_swap_in = 1'b1;
@(posedge clk);
#1;
if (weight_swap_out === 1'b1) begin
    tests_passed++;
end else begin
    report_error("SWAP_PROP", "weight_swap_out did not propagate.");
end
tests_total++;

weight_swap_in = 1'b0;

// Phase 4: Signed Multiplication and Accumulation
// Active weight is 15. We feed activation = 4, partial_sum_in = 100.
// Expected partial_sum_out = 100 + 4 * 15 = 160
// Expected activation_out = 4
activation_in = 8'd4;
partial_sum_in = 32'd100;
@(posedge clk);
#1;
if (partial_sum_out === 32'd160 && activation_out === 8'd4) begin
    tests_passed++;
end else begin
    report_error("COMPUTE_POS", $sformatf("Positive compute mismatch: partial_sum_out=%d, activation_out=%d (expected 160, 4)", partial_sum_out, activation_out));
end
tests_total++;

// Test signed values: active weight = 15, activation = -5 (8'hFB), partial_sum_in = 50.
// Expected partial_sum_out = 50 + (-5) * 15 = 50 - 75 = -25
activation_in = -8'd5;
partial_sum_in = 32'd50;
@(posedge clk);
#1;
if ($signed(partial_sum_out) === -32'd25 && $signed(activation_out) === -8'd5) begin
    tests_passed++;
end else begin
    report_error("COMPUTE_NEG_ACT", $sformatf("Negative activation mismatch: partial_sum_out=%d, activation_out=%d (expected -25, -5)", $signed(partial_sum_out), $signed(activation_out)));
end
tests_total++;

// Test signed active weight: load negative weight.
// Shadow weight load = -10 (8'hF6)
weight_in = -8'd10;
weight_write_in = 1'b1;
@(posedge clk);
#1;
weight_write_in = 1'b0;
weight_swap_in = 1'b1;
@(posedge clk);
#1;
weight_swap_in = 1'b0;
// Weight is now active = -10. Feed activation = -3, partial_sum_in = -40.
// Expected partial_sum_out = -40 + (-3) * (-10) = -40 + 30 = -10.
activation_in = -8'd3;
partial_sum_in = -32'd40;
@(posedge clk);
#1;
if ($signed(partial_sum_out) === -32'd10 && $signed(activation_out) === -8'd3) begin
    tests_passed++;
end else begin
    report_error("COMPUTE_NEG_WEIGHT", $sformatf("Negative weight mismatch: partial_sum_out=%d, activation_out=%d (expected -10, -3)", $signed(partial_sum_out), $signed(activation_out)));
end
tests_total++;

// Phase 5: Enable Control
enable = 0;
activation_in = 8'd10; // Change inputs
partial_sum_in = 32'd1000;
@(posedge clk);
#1;
// Outputs should not change since enable is 0
if ($signed(partial_sum_out) === -32'd10 && $signed(activation_out) === -8'd3) begin
    tests_passed++;
end else begin
    report_error("ENABLE_GATE", $sformatf("DUT state updated while enable=0: partial_sum_out=%d, activation_out=%d", $signed(partial_sum_out), $signed(activation_out)));
end
tests_total++;

enable = 1;
@(posedge clk);
#1;
// Now it should update with the inputs from the previous cycle (which were active while enable was 0? Wait!)
// When enable is 0, registers do not capture. At the next clock cycle when enable is 1, they capture the current value of input pins.
// At this cycle, input pins are still activation_in = 10, partial_sum_in = 1000.
// So it computes: 1000 + 10 * (-10) = 900.
if (partial_sum_out === 32'd900 && activation_out === 8'd10) begin
    tests_passed++;
end else begin
    report_error("ENABLE_RESUME", $sformatf("DUT did not resume correctly: partial_sum_out=%d, activation_out=%d (expected 900, 10)", partial_sum_out, activation_out));
end
tests_total++;

// Summary
report_info("TB", "All tests complete.");
$display("--- pe Test Summary ---");
$display("Total: %0d | Passed: %0d | Failed: %0d", tests_total, tests_passed, tests_failed);
if (tests_failed == 0) $display("RESULT: PASS");
else $display("RESULT: FAIL");
$finish;
end

endmodule
