`timescale 1ns / 1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

// ----------------------------------------------------------------------------
// Systolic Array Interface
// ----------------------------------------------------------------------------
interface systolic_array_if (input logic clk);

logic reset;
logic [3:0] enable;
logic cfg_merge_horizontal_top;
logic cfg_merge_horizontal_bottom;
logic cfg_merge_vertical_left;
logic cfg_merge_vertical_right;

logic [7:0] activations_in [0:31];
logic [7:0] activations_out [0:31];

logic [31:0] partial_sums_in [0:31];
logic [31:0] partial_sums_out [0:31];

logic [7:0] weights [0:31];
logic [7:0] weights_out [0:31];

logic [3:0] weight_write;
logic [3:0] weight_swap;
logic [3:0] weight_write_out;
logic [3:0] weight_swap_out;

endinterface

// ----------------------------------------------------------------------------
// Sequence Item (Stimulus Transaction)
// ----------------------------------------------------------------------------
class systolic_array_seq_item extends uvm_sequence_item;

`uvm_object_utils(systolic_array_seq_item)

logic reset_val;
logic [3:0] enable;
logic [3:0] cfg;
logic [3:0] weight_write;
logic [3:0] weight_swap;
logic [7:0] weights [0:31];
logic [7:0] activations_in [0:31];
logic [31:0] partial_sums_in [0:31];

function new(string name = "systolic_array_seq_item");
super.new(name);
endfunction

endclass

// ----------------------------------------------------------------------------
// Monitor Output Item
// ----------------------------------------------------------------------------
class systolic_array_mon_item extends uvm_sequence_item;

`uvm_object_utils(systolic_array_mon_item)

int cycle;
logic [31:0] partial_sums_out [0:31];

function new(string name = "systolic_array_mon_item");
super.new(name);
endfunction

endclass

// ----------------------------------------------------------------------------
// Driver
// ----------------------------------------------------------------------------
class systolic_array_driver extends uvm_driver #(systolic_array_seq_item);

`uvm_component_utils(systolic_array_driver)

virtual systolic_array_if vif;

function new(string name = "systolic_array_driver", uvm_component parent = null);
super.new(name, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
if (!uvm_config_db#(virtual systolic_array_if)::get(this, "", "vif", vif)) begin
`uvm_fatal("DRV", "Virtual interface not found in uvm_config_db")
end
endfunction

virtual task run_phase(uvm_phase phase);
systolic_array_seq_item req;

vif.reset = 1'b1;
vif.enable = 4'b0000;
vif.cfg_merge_horizontal_top = 1'b0;
vif.cfg_merge_horizontal_bottom = 1'b0;
vif.cfg_merge_vertical_left = 1'b0;
vif.cfg_merge_vertical_right = 1'b0;
vif.weight_write = 4'b0000;
vif.weight_swap = 4'b0000;

for (int i = 0; i < 32; i++) begin
vif.activations_in[i] = 8'd0;
vif.partial_sums_in[i] = 32'd0;
vif.weights[i] = 8'd0;
end

forever begin
seq_item_port.get_next_item(req);
@(negedge vif.clk);

vif.reset = req.reset_val;
vif.enable = req.enable;

vif.cfg_merge_horizontal_top = req.cfg[3];
vif.cfg_merge_horizontal_bottom = req.cfg[2];
vif.cfg_merge_vertical_left = req.cfg[1];
vif.cfg_merge_vertical_right = req.cfg[0];

vif.weight_write = req.weight_write;
vif.weight_swap = req.weight_swap;

for (int i = 0; i < 32; i++) begin
vif.weights[i] = req.weights[i];
vif.activations_in[i] = req.activations_in[i];
vif.partial_sums_in[i] = req.partial_sums_in[i];
end

seq_item_port.item_done();
end
endtask

endclass

// ----------------------------------------------------------------------------
// Monitor
// ----------------------------------------------------------------------------
class systolic_array_monitor extends uvm_monitor;

`uvm_component_utils(systolic_array_monitor)

virtual systolic_array_if vif;
uvm_analysis_port #(systolic_array_mon_item) mon_ap;
int cycle_count;

function new(string name = "systolic_array_monitor", uvm_component parent = null);
super.new(name, parent);
mon_ap = new("mon_ap", this);
cycle_count = 0;
endfunction

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
if (!uvm_config_db#(virtual systolic_array_if)::get(this, "", "vif", vif)) begin
`uvm_fatal("MON", "Virtual interface not found in uvm_config_db")
end
endfunction

virtual task run_phase(uvm_phase phase);
systolic_array_mon_item item;

forever begin
@(negedge vif.clk);
item = systolic_array_mon_item::type_id::create("item");
item.cycle = cycle_count;

for (int i = 0; i < 32; i++) begin
item.partial_sums_out[i] = vif.partial_sums_out[i];
end

mon_ap.write(item);
cycle_count++;
end
endtask

endclass

// ----------------------------------------------------------------------------
// Scoreboard
// ----------------------------------------------------------------------------
class systolic_array_scoreboard extends uvm_scoreboard;

`uvm_component_utils(systolic_array_scoreboard)

uvm_analysis_imp #(systolic_array_mon_item, systolic_array_scoreboard) mon_export;

int exp_file;
int exp_status;
int exp_cycle;
int exp_port;
logic [31:0] exp_val;
int passes;
int mismatches;

function new(string name = "systolic_array_scoreboard", uvm_component parent = null);
super.new(name, parent);
mon_export = new("mon_export", this);
passes = 0;
mismatches = 0;
endfunction

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
exp_file = $fopen("tb/stimulus_expected.txt", "r");
if (exp_file == 0) begin
`uvm_fatal("SB", "Could not open tb/stimulus_expected.txt")
end
exp_status = $fscanf(exp_file, "%d %d %h\n", exp_cycle, exp_port, exp_val);
endfunction

virtual function void write(systolic_array_mon_item item);
if (item.cycle > 0) begin
while (exp_status == 3 && exp_cycle == item.cycle - 1) begin
if (item.partial_sums_out[exp_port] !== exp_val) begin
`uvm_error("SB", $sformatf("Cycle %0d, Port %0d: Expected %h, Got %h", exp_cycle, exp_port, exp_val, item.partial_sums_out[exp_port]))
mismatches++;
end else begin
passes++;
end
exp_status = $fscanf(exp_file, "%d %d %h\n", exp_cycle, exp_port, exp_val);
end
end
endfunction

virtual function void check_phase(uvm_phase phase);
super.check_phase(phase);
while (exp_status == 3) begin
`uvm_error("SB", $sformatf("Unchecked expected output: Cycle %0d, Port %0d, Expected %h", exp_cycle, exp_port, exp_val))
mismatches++;
exp_status = $fscanf(exp_file, "%d %d %h\n", exp_cycle, exp_port, exp_val);
end
$fclose(exp_file);
endfunction

virtual function void report_phase(uvm_phase phase);
super.report_phase(phase);
$display("Verification Complete: Passes = %0d, Mismatches = %0d", passes, mismatches);
if (mismatches == 0) begin
`uvm_info("SB", "ALL CHECKS PASSED PERFECTLY", UVM_LOW)
end else begin
`uvm_error("SB", $sformatf("Total mismatches found: %0d", mismatches))
end
endfunction

endclass

// ----------------------------------------------------------------------------
// Sequencer & Agent
// ----------------------------------------------------------------------------
typedef uvm_sequencer #(systolic_array_seq_item) systolic_array_sequencer;

class systolic_array_agent extends uvm_agent;

`uvm_component_utils(systolic_array_agent)

systolic_array_driver drv;
systolic_array_sequencer seqr;
systolic_array_monitor mon;

function new(string name = "systolic_array_agent", uvm_component parent = null);
super.new(name, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
drv = systolic_array_driver::type_id::create("drv", this);
seqr = systolic_array_sequencer::type_id::create("seqr", this);
mon = systolic_array_monitor::type_id::create("mon", this);
endfunction

virtual function void connect_phase(uvm_phase phase);
super.connect_phase(phase);
drv.seq_item_port.connect(seqr.seq_item_export);
endfunction

endclass

// ----------------------------------------------------------------------------
// Environment
// ----------------------------------------------------------------------------
class systolic_array_env extends uvm_env;

`uvm_component_utils(systolic_array_env)

systolic_array_agent agt;
systolic_array_scoreboard sb;

function new(string name = "systolic_array_env", uvm_component parent = null);
super.new(name, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
agt = systolic_array_agent::type_id::create("agt", this);
sb = systolic_array_scoreboard::type_id::create("sb", this);
endfunction

virtual function void connect_phase(uvm_phase phase);
super.connect_phase(phase);
agt.mon.mon_ap.connect(sb.mon_export);
endfunction

endclass

// ----------------------------------------------------------------------------
// Sequence (Stimulus File Reader)
// ----------------------------------------------------------------------------
class systolic_array_seq extends uvm_sequence #(systolic_array_seq_item);

`uvm_object_utils(systolic_array_seq)

function new(string name = "systolic_array_seq");
super.new(name);
endfunction

virtual task body();
int file;
int status;
logic r_reset;
logic [3:0] r_enable;
logic [3:0] r_cfg;
logic [3:0] r_weight_write;
logic [3:0] r_weight_swap;
logic [7:0] r_weights [0:31];
logic [7:0] r_activations_in [0:31];
logic [31:0] r_partial_sums_in [0:31];
systolic_array_seq_item req;

file = $fopen("tb/stimulus_inputs.txt", "r");
if (file == 0) begin
`uvm_fatal("SEQ", "Could not open tb/stimulus_inputs.txt")
end

while (!$feof(file)) begin
status = $fscanf(file, "%h %h %h %h %h", r_reset, r_enable, r_cfg, r_weight_write, r_weight_swap);
if (status == 5) begin
for (int i = 0; i < 32; i++) begin
status = $fscanf(file, "%h", r_weights[i]);
end
for (int i = 0; i < 32; i++) begin
status = $fscanf(file, "%h", r_activations_in[i]);
end
for (int i = 0; i < 32; i++) begin
status = $fscanf(file, "%h", r_partial_sums_in[i]);
end

req = systolic_array_seq_item::type_id::create("req");
start_item(req);
req.reset_val = r_reset;
req.enable = r_enable;
req.cfg = r_cfg;
req.weight_write = r_weight_write;
req.weight_swap = r_weight_swap;
for (int i = 0; i < 32; i++) begin
req.weights[i] = r_weights[i];
req.activations_in[i] = r_activations_in[i];
req.partial_sums_in[i] = r_partial_sums_in[i];
end
finish_item(req);
end
end

$fclose(file);
endtask

endclass

// ----------------------------------------------------------------------------
// Test
// ----------------------------------------------------------------------------
class systolic_array_test extends uvm_test;

`uvm_component_utils(systolic_array_test)

systolic_array_env env;

function new(string name = "systolic_array_test", uvm_component parent = null);
super.new(name, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
env = systolic_array_env::type_id::create("env", this);
endfunction

virtual task run_phase(uvm_phase phase);
systolic_array_seq seq;
phase.raise_objection(this);
seq = systolic_array_seq::type_id::create("seq");
seq.start(env.agt.seqr);
#100;
phase.drop_objection(this);
endtask

endclass

// ----------------------------------------------------------------------------
// Testbench Top Module
// ----------------------------------------------------------------------------
module systolic_array_tb;

logic clk;

localparam int ACTIVATION_WIDTH = 8;
localparam int WEIGHT_WIDTH = 8;
localparam int P_SUM_WIDTH = 32;
localparam int TILE_ROWS = 8;
localparam int TILE_COLS = 8;

systolic_array_if vif (clk);

logic [ACTIVATION_WIDTH-1:0] act_in [0:4*TILE_ROWS-1];
logic [ACTIVATION_WIDTH-1:0] act_out [0:4*TILE_ROWS-1];
logic [P_SUM_WIDTH-1:0] psum_in [0:4*TILE_COLS-1];
logic [P_SUM_WIDTH-1:0] psum_out [0:4*TILE_COLS-1];
logic [WEIGHT_WIDTH-1:0] w_in [0:4*TILE_COLS-1];
logic [WEIGHT_WIDTH-1:0] w_out [0:4*TILE_COLS-1];
logic enable_arr [0:3];
logic w_write_arr [0:3];
logic w_swap_arr [0:3];
logic w_write_out_arr [0:3];
logic w_swap_out_arr [0:3];

always_comb begin
for (int i = 0; i < 4; i++) begin
enable_arr[i] = vif.enable[i];
w_write_arr[i] = vif.weight_write[i];
w_swap_arr[i] = vif.weight_swap[i];
vif.weight_write_out[i] = w_write_out_arr[i];
vif.weight_swap_out[i] = w_swap_out_arr[i];
end

for (int i = 0; i < 32; i++) begin
act_in[i] = vif.activations_in[i];
psum_in[i] = vif.partial_sums_in[i];
w_in[i] = vif.weights[i];
vif.activations_out[i] = act_out[i];
vif.partial_sums_out[i] = psum_out[i];
vif.weights_out[i] = w_out[i];
end
end

systolic_array #(
.ACTIVATION_WIDTH(ACTIVATION_WIDTH),
.WEIGHT_WIDTH(WEIGHT_WIDTH),
.P_SUM_WIDTH(P_SUM_WIDTH),
.TILE_ROWS(TILE_ROWS),
.TILE_COLS(TILE_COLS)
) dut (
.clk(clk),
.reset(vif.reset),
.enable(enable_arr),
.cfg_merge_horizontal_top(vif.cfg_merge_horizontal_top),
.cfg_merge_horizontal_bottom(vif.cfg_merge_horizontal_bottom),
.cfg_merge_vertical_left(vif.cfg_merge_vertical_left),
.cfg_merge_vertical_right(vif.cfg_merge_vertical_right),
.activations_in(act_in),
.activations_out(act_out),
.partial_sums_in(psum_in),
.partial_sums_out(psum_out),
.weights(w_in),
.weights_out(w_out),
.weight_write(w_write_arr),
.weight_swap(w_swap_arr),
.weight_write_out(w_write_out_arr),
.weight_swap_out(w_swap_out_arr)
);

always begin
#5 clk = ~clk;
end

initial begin
clk = 0;
uvm_config_db#(virtual systolic_array_if)::set(null, "*", "vif", vif);
run_test("systolic_array_test");
end

endmodule
