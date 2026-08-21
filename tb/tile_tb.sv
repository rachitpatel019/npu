`timescale 1ns / 1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

// Interface for 8x8 processing element tile unit
interface tile_if (input logic clk);

logic reset;
logic enable;

logic [7:0] activations_in [0:7];
logic [7:0] activations_out [0:7];

logic [7:0] weights [0:7];
logic [7:0] weights_out [0:7];

logic weight_write_in;
logic weight_swap_in;
logic weight_write_out;
logic weight_swap_out;
logic weight_swap_col0_out;

logic [31:0] partial_sums_in [0:7];
logic [31:0] partial_sums_out [0:7];

endinterface

// Stimulus sequence item for 8x8 tile
class tile_seq_item extends uvm_sequence_item;

`uvm_object_utils(tile_seq_item)

logic reset_val;
logic enable;
logic weight_write_in;
logic weight_swap_in;
logic [7:0] activations_in [0:7];
logic [7:0] weights [0:7];
logic [31:0] partial_sums_in [0:7];

function new(string name = "tile_seq_item");
super.new(name);
endfunction

endclass

// Monitor transaction item capturing tile interface outputs
class tile_mon_item extends uvm_sequence_item;

`uvm_object_utils(tile_mon_item)

int cycle;
logic reset;
logic enable;
logic weight_write_in;
logic weight_swap_in;
logic weight_write_out;
logic weight_swap_out;
logic weight_swap_col0_out;
logic [7:0] activations_in [0:7];
logic [7:0] activations_out [0:7];
logic [7:0] weights [0:7];
logic [7:0] weights_out [0:7];
logic [31:0] partial_sums_in [0:7];
logic [31:0] partial_sums_out [0:7];

function new(string name = "tile_mon_item");
super.new(name);
endfunction

endclass

// Driver converting tile sequence transactions to interface pin signals
class tile_driver extends uvm_driver #(tile_seq_item);

`uvm_component_utils(tile_driver)

virtual tile_if vif;

function new(string name = "tile_driver", uvm_component parent = null);
super.new(name, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
if (!uvm_config_db#(virtual tile_if)::get(this, "", "vif", vif)) begin
`uvm_fatal("DRV", "Virtual interface not found in uvm_config_db")
end
endfunction

virtual task run_phase(uvm_phase phase);
tile_seq_item req;

vif.reset = 1'b1;
vif.enable = 1'b0;
vif.weight_write_in = 1'b0;
vif.weight_swap_in = 1'b0;

for (int i = 0; i < 8; i++) begin
vif.activations_in[i] = 8'd0;
vif.weights[i] = 8'd0;
vif.partial_sums_in[i] = 32'd0;
end

forever begin
seq_item_port.get_next_item(req);
@(negedge vif.clk);

vif.reset = req.reset_val;
vif.enable = req.enable;
vif.weight_write_in = req.weight_write_in;
vif.weight_swap_in = req.weight_swap_in;

for (int i = 0; i < 8; i++) begin
vif.activations_in[i] = req.activations_in[i];
vif.weights[i] = req.weights[i];
vif.partial_sums_in[i] = req.partial_sums_in[i];
end

seq_item_port.item_done();
end
endtask

endclass

// Monitor capturing tile pin activity at each clock cycle
class tile_monitor extends uvm_monitor;

`uvm_component_utils(tile_monitor)

virtual tile_if vif;
uvm_analysis_port #(tile_mon_item) mon_ap;
int cycle_count;

function new(string name = "tile_monitor", uvm_component parent = null);
super.new(name, parent);
mon_ap = new("mon_ap", this);
cycle_count = 0;
endfunction

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
if (!uvm_config_db#(virtual tile_if)::get(this, "", "vif", vif)) begin
`uvm_fatal("MON", "Virtual interface not found in uvm_config_db")
end
endfunction

virtual task run_phase(uvm_phase phase);
tile_mon_item item;

forever begin
@(negedge vif.clk);
item = tile_mon_item::type_id::create("item");
item.cycle = cycle_count;
item.reset = vif.reset;
item.enable = vif.enable;
item.weight_write_in = vif.weight_write_in;
item.weight_swap_in = vif.weight_swap_in;
item.weight_write_out = vif.weight_write_out;
item.weight_swap_out = vif.weight_swap_out;
item.weight_swap_col0_out = vif.weight_swap_col0_out;

for (int i = 0; i < 8; i++) begin
item.activations_in[i] = vif.activations_in[i];
item.activations_out[i] = vif.activations_out[i];
item.weights[i] = vif.weights[i];
item.weights_out[i] = vif.weights_out[i];
item.partial_sums_in[i] = vif.partial_sums_in[i];
item.partial_sums_out[i] = vif.partial_sums_out[i];
end

mon_ap.write(item);
cycle_count++;
end
endtask

endclass

// Scoreboard verifying tile computations against expected systolic results
class tile_scoreboard extends uvm_scoreboard;

`uvm_component_utils(tile_scoreboard)

uvm_analysis_imp #(tile_mon_item, tile_scoreboard) mon_export;

int passes;
int mismatches;

logic signed [7:0] pe_active_weight [0:7][0:7];
logic signed [7:0] pe_shadow_weight [0:7][0:7];
logic signed [7:0] pe_act_reg [0:7][0:7];
logic signed [31:0] pe_psum_reg [0:7][0:7];
logic pe_swap_reg [0:7][0:7];
logic swap_col0_reg [1:7];

function new(string name = "tile_scoreboard", uvm_component parent = null);
super.new(name, parent);
mon_export = new("mon_export", this);
passes = 0;
mismatches = 0;

for (int r = 0; r < 8; r++) begin
for (int c = 0; c < 8; c++) begin
pe_active_weight[r][c] = '0;
pe_shadow_weight[r][c] = '0;
pe_act_reg[r][c] = '0;
pe_psum_reg[r][c] = '0;
pe_swap_reg[r][c] = 1'b0;
end
end

for (int r = 1; r < 8; r++) begin
swap_col0_reg[r] = 1'b0;
end
endfunction

virtual function void write(tile_mon_item item);
logic [7:0] act_in_wire [0:7][0:8];
logic [31:0] psum_in_wire [0:8][0:7];
logic [7:0] w_in_wire [0:8][0:7];
logic swap_in_wire [0:7][0:8];

for (int r = 0; r < 8; r++) begin
act_in_wire[r][0] = item.activations_in[r];
for (int c = 0; c < 8; c++) begin
act_in_wire[r][c+1] = pe_act_reg[r][c];
end
end

for (int c = 0; c < 8; c++) begin
psum_in_wire[0][c] = item.partial_sums_in[c];
w_in_wire[0][c] = item.weights[c];
for (int r = 0; r < 8; r++) begin
psum_in_wire[r+1][c] = pe_psum_reg[r][c];
w_in_wire[r+1][c] = pe_shadow_weight[r][c];
end
end

swap_in_wire[0][0] = item.weight_swap_in;
for (int r = 1; r < 8; r++) begin
swap_in_wire[r][0] = swap_col0_reg[r];
end
for (int r = 0; r < 8; r++) begin
for (int c = 0; c < 8; c++) begin
swap_in_wire[r][c+1] = pe_swap_reg[r][c];
end
end

if (item.cycle > 0) begin
for (int r = 0; r < 8; r++) begin
if (item.activations_out[r] !== act_in_wire[r][8]) begin
`uvm_error("SB", $sformatf("Cycle %0d: Act out mismatch row %0d: Exp %0d, Got %0d", item.cycle, r, act_in_wire[r][8], item.activations_out[r]))
mismatches++;
end else begin
passes++;
end
end

for (int c = 0; c < 8; c++) begin
if (item.partial_sums_out[c] !== psum_in_wire[8][c]) begin
`uvm_error("SB", $sformatf("Cycle %0d: Partial sum out mismatch col %0d: Exp %0d, Got %0d", item.cycle, c, psum_in_wire[8][c], item.partial_sums_out[c]))
mismatches++;
end else begin
passes++;
end

if (item.weights_out[c] !== w_in_wire[8][c]) begin
`uvm_error("SB", $sformatf("Cycle %0d: Weight out mismatch col %0d: Exp %0d, Got %0d", item.cycle, c, w_in_wire[8][c], item.weights_out[c]))
mismatches++;
end else begin
passes++;
end
end
end

if (item.reset) begin
for (int r = 0; r < 8; r++) begin
for (int c = 0; c < 8; c++) begin
pe_active_weight[r][c] = '0;
pe_shadow_weight[r][c] = '0;
pe_act_reg[r][c] = '0;
pe_psum_reg[r][c] = '0;
pe_swap_reg[r][c] = 1'b0;
end
end
for (int r = 1; r < 8; r++) begin
swap_col0_reg[r] = 1'b0;
end
end else if (item.enable) begin
for (int r = 0; r < 8; r++) begin
for (int c = 0; c < 8; c++) begin
if (item.weight_write_in) begin
pe_shadow_weight[r][c] = w_in_wire[r][c];
end
if (swap_in_wire[r][c]) begin
pe_active_weight[r][c] = pe_shadow_weight[r][c];
end
pe_act_reg[r][c] = act_in_wire[r][c];
pe_psum_reg[r][c] = $signed(psum_in_wire[r][c]) + ($signed(act_in_wire[r][c]) * pe_active_weight[r][c]);
pe_swap_reg[r][c] = swap_in_wire[r][c];
end
end

swap_col0_reg[1] = item.weight_swap_in;
for (int r = 2; r < 8; r++) begin
swap_col0_reg[r] = swap_col0_reg[r-1];
end
end
endfunction

virtual function void report_phase(uvm_phase phase);
super.report_phase(phase);
$display("Tile Verification Complete: Passes = %0d, Mismatches = %0d", passes, mismatches);
if (mismatches == 0) begin
`uvm_info("SB", "ALL TILE CHECKS PASSED", UVM_LOW)
end else begin
`uvm_error("SB", $sformatf("Total tile mismatches found: %0d", mismatches))
end
endfunction

endclass

// Sequencer definition for tile transactions
typedef uvm_sequencer #(tile_seq_item) tile_sequencer;

// Agent grouping tile driver, sequencer, and monitor
class tile_agent extends uvm_agent;

`uvm_component_utils(tile_agent)

tile_driver drv;
tile_sequencer seqr;
tile_monitor mon;

function new(string name = "tile_agent", uvm_component parent = null);
super.new(name, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
drv = tile_driver::type_id::create("drv", this);
seqr = tile_sequencer::type_id::create("seqr", this);
mon = tile_monitor::type_id::create("mon", this);
endfunction

virtual function void connect_phase(uvm_phase phase);
super.connect_phase(phase);
drv.seq_item_port.connect(seqr.seq_item_export);
endfunction

endclass

// Environment wrapping tile agent and scoreboard
class tile_env extends uvm_env;

`uvm_component_utils(tile_env)

tile_agent agt;
tile_scoreboard sb;

function new(string name = "tile_env", uvm_component parent = null);
super.new(name, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
agt = tile_agent::type_id::create("agt", this);
sb = tile_scoreboard::type_id::create("sb", this);
endfunction

virtual function void connect_phase(uvm_phase phase);
super.connect_phase(phase);
agt.mon.mon_ap.connect(sb.mon_export);
endfunction

endclass

// Stimulus sequence driving tile reset, weight loading, and matrix streaming
class tile_seq extends uvm_sequence #(tile_seq_item);

`uvm_object_utils(tile_seq)

function new(string name = "tile_seq");
super.new(name);
endfunction

task automatic send_item(
input logic rst,
input logic en,
input logic w_wr,
input logic w_sw,
input logic [7:0] acts [0:7],
input logic [7:0] wts [0:7],
input logic [31:0] psums [0:7]
);
tile_seq_item req;
req = tile_seq_item::type_id::create("req");
start_item(req);
req.reset_val = rst;
req.enable = en;
req.weight_write_in = w_wr;
req.weight_swap_in = w_sw;
for (int i = 0; i < 8; i++) begin
req.activations_in[i] = acts[i];
req.weights[i] = wts[i];
req.partial_sums_in[i] = psums[i];
end
finish_item(req);
endtask

virtual task body();
logic [7:0] zero_acts [0:7];
logic [7:0] zero_wts [0:7];
logic [31:0] zero_psums [0:7];
logic [7:0] cur_acts [0:7];
logic [7:0] cur_wts [0:7];

for (int i = 0; i < 8; i++) begin
zero_acts[i] = 8'd0;
zero_wts[i] = 8'd0;
zero_psums[i] = 32'd0;
end

send_item(1'b1, 1'b0, 1'b0, 1'b0, zero_acts, zero_wts, zero_psums);
send_item(1'b1, 1'b0, 1'b0, 1'b0, zero_acts, zero_wts, zero_psums);
send_item(1'b0, 1'b1, 1'b0, 1'b0, zero_acts, zero_wts, zero_psums);

for (int c = 0; c < 8; c++) begin
for (int col = 0; col < 8; col++) begin
cur_wts[col] = (8 - c) * 10 + (col + 1);
end
send_item(1'b0, 1'b1, 1'b1, 1'b0, zero_acts, cur_wts, zero_psums);
end

for (int cycle = 0; cycle < 8; cycle++) begin
send_item(1'b0, 1'b1, 1'b0, 1'b0, zero_acts, zero_wts, zero_psums);
end

send_item(1'b0, 1'b1, 1'b0, 1'b1, zero_acts, zero_wts, zero_psums);

for (int cycle = 0; cycle < 16; cycle++) begin
send_item(1'b0, 1'b1, 1'b0, 1'b0, zero_acts, zero_wts, zero_psums);
end

for (int cycle = 0; cycle < 30; cycle++) begin
for (int r = 0; r < 8; r++) begin
if (cycle >= r && cycle < r + 8) begin
cur_acts[r] = 8'd1;
end else begin
cur_acts[r] = 8'd0;
end
end
send_item(1'b0, 1'b1, 1'b0, 1'b0, cur_acts, zero_wts, zero_psums);
end

for (int cycle = 0; cycle < 10; cycle++) begin
send_item(1'b0, 1'b1, 1'b0, 1'b0, zero_acts, zero_wts, zero_psums);
end
endtask

endclass

// Root UVM test configuring and executing tile testbench sequence
class tile_test extends uvm_test;

`uvm_component_utils(tile_test)

tile_env env;

function new(string name = "tile_test", uvm_component parent = null);
super.new(name, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
env = tile_env::type_id::create("env", this);
endfunction

virtual task run_phase(uvm_phase phase);
tile_seq seq;
phase.raise_objection(this);
seq = tile_seq::type_id::create("seq");
seq.start(env.agt.seqr);
#100;
phase.drop_objection(this);
endtask

endclass

// Top testbench module instantiating 8x8 tile DUT and interface
module tile_tb;

logic clk;

localparam int ACTIVATION_WIDTH = 8;
localparam int WEIGHT_WIDTH = 8;
localparam int P_SUM_WIDTH = 32;
localparam int TILE_ROWS = 8;
localparam int TILE_COLS = 8;

tile_if vif (clk);

tile #(
.ACTIVATION_WIDTH(ACTIVATION_WIDTH),
.WEIGHT_WIDTH(WEIGHT_WIDTH),
.P_SUM_WIDTH(P_SUM_WIDTH),
.TILE_ROWS(TILE_ROWS),
.TILE_COLS(TILE_COLS)
) dut (
.clk(clk),
.reset(vif.reset),
.enable(vif.enable),
.activations_in(vif.activations_in),
.activations_out(vif.activations_out),
.weights(vif.weights),
.weights_out(vif.weights_out),
.weight_write_in(vif.weight_write_in),
.weight_swap_in(vif.weight_swap_in),
.weight_write_out(vif.weight_write_out),
.weight_swap_out(vif.weight_swap_out),
.weight_swap_col0_out(vif.weight_swap_col0_out),
.partial_sums_in(vif.partial_sums_in),
.partial_sums_out(vif.partial_sums_out)
);

always begin
#5 clk = ~clk;
end

initial begin
clk = 0;
uvm_config_db#(virtual tile_if)::set(null, "*", "vif", vif);
run_test("tile_test");
end

endmodule
