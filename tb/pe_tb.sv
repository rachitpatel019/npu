`timescale 1ns / 1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

// Interface for processing element unit
interface pe_if (input logic clk);

logic reset;
logic enable;

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

endinterface

// Stimulus sequence item for processing element
class pe_seq_item extends uvm_sequence_item;

`uvm_object_utils(pe_seq_item)

logic reset_val;
logic enable;
logic [7:0] activation_in;
logic [31:0] partial_sum_in;
logic [7:0] weight_in;
logic weight_write_in;
logic weight_swap_in;

function new(string name = "pe_seq_item");
super.new(name);
endfunction

endclass

// Monitor transaction item capturing DUT interface state
class pe_mon_item extends uvm_sequence_item;

`uvm_object_utils(pe_mon_item)

int cycle;
logic reset;
logic enable;
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

function new(string name = "pe_mon_item");
super.new(name);
endfunction

endclass

// Driver translating sequence items to interface signals
class pe_driver extends uvm_driver #(pe_seq_item);

`uvm_component_utils(pe_driver)

virtual pe_if vif;

function new(string name = "pe_driver", uvm_component parent = null);
super.new(name, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
if (!uvm_config_db#(virtual pe_if)::get(this, "", "vif", vif)) begin
`uvm_fatal("DRV", "Virtual interface not found in uvm_config_db")
end
endfunction

virtual task run_phase(uvm_phase phase);
pe_seq_item req;

vif.reset = 1'b1;
vif.enable = 1'b0;
vif.activation_in = 8'd0;
vif.partial_sum_in = 32'd0;
vif.weight_in = 8'd0;
vif.weight_write_in = 1'b0;
vif.weight_swap_in = 1'b0;

forever begin
seq_item_port.get_next_item(req);
@(negedge vif.clk);

vif.reset = req.reset_val;
vif.enable = req.enable;
vif.activation_in = req.activation_in;
vif.partial_sum_in = req.partial_sum_in;
vif.weight_in = req.weight_in;
vif.weight_write_in = req.weight_write_in;
vif.weight_swap_in = req.weight_swap_in;

seq_item_port.item_done();
end
endtask

endclass

// Monitor capturing pin activity at each clock edge
class pe_monitor extends uvm_monitor;

`uvm_component_utils(pe_monitor)

virtual pe_if vif;
uvm_analysis_port #(pe_mon_item) mon_ap;
int cycle_count;

function new(string name = "pe_monitor", uvm_component parent = null);
super.new(name, parent);
mon_ap = new("mon_ap", this);
cycle_count = 0;
endfunction

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
if (!uvm_config_db#(virtual pe_if)::get(this, "", "vif", vif)) begin
`uvm_fatal("MON", "Virtual interface not found in uvm_config_db")
end
endfunction

virtual task run_phase(uvm_phase phase);
pe_mon_item item;

forever begin
@(negedge vif.clk);
item = pe_mon_item::type_id::create("item");
item.cycle = cycle_count;
item.reset = vif.reset;
item.enable = vif.enable;
item.activation_in = vif.activation_in;
item.activation_out = vif.activation_out;
item.partial_sum_in = vif.partial_sum_in;
item.partial_sum_out = vif.partial_sum_out;
item.weight_in = vif.weight_in;
item.weight_write_in = vif.weight_write_in;
item.weight_swap_in = vif.weight_swap_in;
item.weight_out = vif.weight_out;
item.weight_write_out = vif.weight_write_out;
item.weight_swap_out = vif.weight_swap_out;

mon_ap.write(item);
cycle_count++;
end
endtask

endclass

// Scoreboard comparing DUT execution against golden reference model
class pe_scoreboard extends uvm_scoreboard;

`uvm_component_utils(pe_scoreboard)

uvm_analysis_imp #(pe_mon_item, pe_scoreboard) mon_export;

logic signed [7:0] exp_weight_active;
logic signed [7:0] exp_weight_shadow;
logic signed [7:0] exp_activation_reg;
logic signed [31:0] exp_partial_sum_reg;
logic exp_weight_swap_reg;

int passes;
int mismatches;

function new(string name = "pe_scoreboard", uvm_component parent = null);
super.new(name, parent);
mon_export = new("mon_export", this);
exp_weight_active = '0;
exp_weight_shadow = '0;
exp_activation_reg = '0;
exp_partial_sum_reg = '0;
exp_weight_swap_reg = 1'b0;
passes = 0;
mismatches = 0;
endfunction

virtual function void write(pe_mon_item item);
logic signed [7:0] exp_weight_out;
logic exp_weight_write_out;
logic exp_weight_swap_out;
logic signed [7:0] exp_act_out;
logic signed [31:0] exp_psum_out;

exp_weight_out = exp_weight_shadow;
exp_weight_write_out = item.weight_write_in;
exp_weight_swap_out = exp_weight_swap_reg;
exp_act_out = exp_activation_reg;
exp_psum_out = exp_partial_sum_reg;

if (item.cycle > 0) begin
if (item.weight_out !== exp_weight_out) begin
`uvm_error("SB", $sformatf("Cycle %0d: Weight out mismatch: Expected %0d, Got %0d", item.cycle, exp_weight_out, item.weight_out))
mismatches++;
end else begin
passes++;
end

if (item.weight_write_out !== exp_weight_write_out) begin
`uvm_error("SB", $sformatf("Cycle %0d: Weight write out mismatch: Expected %0d, Got %0d", item.cycle, exp_weight_write_out, item.weight_write_out))
mismatches++;
end else begin
passes++;
end

if (item.weight_swap_out !== exp_weight_swap_out) begin
`uvm_error("SB", $sformatf("Cycle %0d: Weight swap out mismatch: Expected %0d, Got %0d", item.cycle, exp_weight_swap_out, item.weight_swap_out))
mismatches++;
end else begin
passes++;
end

if (item.activation_out !== exp_act_out) begin
`uvm_error("SB", $sformatf("Cycle %0d: Activation out mismatch: Expected %0d, Got %0d", item.cycle, exp_act_out, item.activation_out))
mismatches++;
end else begin
passes++;
end

if ($signed(item.partial_sum_out) !== exp_psum_out) begin
`uvm_error("SB", $sformatf("Cycle %0d: Partial sum out mismatch: Expected %0d, Got %0d", item.cycle, exp_psum_out, $signed(item.partial_sum_out)))
mismatches++;
end else begin
passes++;
end
end

if (item.reset) begin
exp_weight_active = '0;
exp_weight_shadow = '0;
exp_activation_reg = '0;
exp_partial_sum_reg = '0;
exp_weight_swap_reg = 1'b0;
end else if (item.enable) begin
if (item.weight_write_in) begin
exp_weight_shadow = item.weight_in;
end
if (item.weight_swap_in) begin
exp_weight_active = exp_weight_shadow;
end
exp_activation_reg = item.activation_in;
exp_partial_sum_reg = $signed(item.partial_sum_in) + ($signed(item.activation_in) * exp_weight_active);
exp_weight_swap_reg = item.weight_swap_in;
end
endfunction

virtual function void report_phase(uvm_phase phase);
super.report_phase(phase);
$display("PE Verification Complete: Passes = %0d, Mismatches = %0d", passes, mismatches);
if (mismatches == 0) begin
`uvm_info("SB", "ALL PE CHECKS PASSED", UVM_LOW)
end else begin
`uvm_error("SB", $sformatf("Total PE mismatches found: %0d", mismatches))
end
endfunction

endclass

// Sequencer definition for sequence item dispatch
typedef uvm_sequencer #(pe_seq_item) pe_sequencer;

// Verification agent grouping driver, sequencer, and monitor
class pe_agent extends uvm_agent;

`uvm_component_utils(pe_agent)

pe_driver drv;
pe_sequencer seqr;
pe_monitor mon;

function new(string name = "pe_agent", uvm_component parent = null);
super.new(name, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
drv = pe_driver::type_id::create("drv", this);
seqr = pe_sequencer::type_id::create("seqr", this);
mon = pe_monitor::type_id::create("mon", this);
endfunction

virtual function void connect_phase(uvm_phase phase);
super.connect_phase(phase);
drv.seq_item_port.connect(seqr.seq_item_export);
endfunction

endclass

// Verification environment encapsulating agent and scoreboard
class pe_env extends uvm_env;

`uvm_component_utils(pe_env)

pe_agent agt;
pe_scoreboard sb;

function new(string name = "pe_env", uvm_component parent = null);
super.new(name, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
agt = pe_agent::type_id::create("agt", this);
sb = pe_scoreboard::type_id::create("sb", this);
endfunction

virtual function void connect_phase(uvm_phase phase);
super.connect_phase(phase);
agt.mon.mon_ap.connect(sb.mon_export);
endfunction

endclass

// Stimulus sequence exercising processing element operational modes
class pe_seq extends uvm_sequence #(pe_seq_item);

`uvm_object_utils(pe_seq)

function new(string name = "pe_seq");
super.new(name);
endfunction

task automatic send_item(
input logic rst,
input logic en,
input logic [7:0] act,
input logic [31:0] psum,
input logic [7:0] w,
input logic w_wr,
input logic w_sw
);
pe_seq_item req;
req = pe_seq_item::type_id::create("req");
start_item(req);
req.reset_val = rst;
req.enable = en;
req.activation_in = act;
req.partial_sum_in = psum;
req.weight_in = w;
req.weight_write_in = w_wr;
req.weight_swap_in = w_sw;
finish_item(req);
endtask

virtual task body();
send_item(1'b1, 1'b0, 8'd0, 32'd0, 8'd0, 1'b0, 1'b0);
send_item(1'b1, 1'b0, 8'd0, 32'd0, 8'd0, 1'b0, 1'b0);
send_item(1'b0, 1'b1, 8'd0, 32'd0, 8'd0, 1'b0, 1'b0);

send_item(1'b0, 1'b1, 8'd0, 32'd0, 8'd15, 1'b1, 1'b0);
send_item(1'b0, 1'b1, 8'd0, 32'd0, 8'd99, 1'b0, 1'b0);
send_item(1'b0, 1'b1, 8'd0, 32'd0, 8'd0, 1'b0, 1'b1);
send_item(1'b0, 1'b1, 8'd0, 32'd0, 8'd0, 1'b0, 1'b0);

send_item(1'b0, 1'b1, 8'd4, 32'd100, 8'd0, 1'b0, 1'b0);
send_item(1'b0, 1'b1, -8'd5, 32'd50, 8'd0, 1'b0, 1'b0);
send_item(1'b0, 1'b1, 8'd0, 32'd0, 8'd0, 1'b0, 1'b0);

send_item(1'b0, 1'b1, 8'd0, 32'd0, -8'd10, 1'b1, 1'b0);
send_item(1'b0, 1'b1, 8'd0, 32'd0, 8'd0, 1'b0, 1'b1);
send_item(1'b0, 1'b1, -8'd3, -32'd40, 8'd0, 1'b0, 1'b0);
send_item(1'b0, 1'b1, 8'd0, 32'd0, 8'd0, 1'b0, 1'b0);

send_item(1'b0, 1'b0, 8'd10, 32'd1000, 8'd0, 1'b0, 1'b0);
send_item(1'b0, 1'b0, 8'd20, 32'd2000, 8'd0, 1'b0, 1'b0);
send_item(1'b0, 1'b1, 8'd10, 32'd1000, 8'd0, 1'b0, 1'b0);
send_item(1'b0, 1'b1, 8'd0, 32'd0, 8'd0, 1'b0, 1'b0);

send_item(1'b0, 1'b1, 8'd0, 32'd0, 8'd127, 1'b1, 1'b0);
send_item(1'b0, 1'b1, 8'd0, 32'd0, 8'd0, 1'b0, 1'b1);
send_item(1'b0, 1'b1, 8'd127, 32'd10000, 8'd0, 1'b0, 1'b0);
send_item(1'b0, 1'b1, -8'd128, -32'd10000, 8'd0, 1'b0, 1'b0);
send_item(1'b0, 1'b1, 8'd0, 32'd0, 8'd0, 1'b0, 1'b0);
send_item(1'b0, 1'b1, 8'd0, 32'd0, 8'd0, 1'b0, 1'b0);
endtask

endclass

// Root UVM test configuring and executing sequence
class pe_test extends uvm_test;

`uvm_component_utils(pe_test)

pe_env env;

function new(string name = "pe_test", uvm_component parent = null);
super.new(name, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
env = pe_env::type_id::create("env", this);
endfunction

virtual task run_phase(uvm_phase phase);
pe_seq seq;
phase.raise_objection(this);
seq = pe_seq::type_id::create("seq");
seq.start(env.agt.seqr);
#100;
phase.drop_objection(this);
endtask

endclass

// Top testbench module instantiating processing element DUT and interface
module pe_tb;

logic clk;

localparam int ACTIVATION_WIDTH = 8;
localparam int WEIGHT_WIDTH = 8;
localparam int P_SUM_WIDTH = 32;

pe_if vif (clk);

pe #(
.ACTIVATION_WIDTH(ACTIVATION_WIDTH),
.WEIGHT_WIDTH(WEIGHT_WIDTH),
.P_SUM_WIDTH(P_SUM_WIDTH)
) dut (
.clk(clk),
.reset(vif.reset),
.enable(vif.enable),
.activation_in(vif.activation_in),
.activation_out(vif.activation_out),
.partial_sum_in(vif.partial_sum_in),
.partial_sum_out(vif.partial_sum_out),
.weight_in(vif.weight_in),
.weight_write_in(vif.weight_write_in),
.weight_swap_in(vif.weight_swap_in),
.weight_out(vif.weight_out),
.weight_write_out(vif.weight_write_out),
.weight_swap_out(vif.weight_swap_out)
);

always begin
#5 clk = ~clk;
end

initial begin
clk = 0;
uvm_config_db#(virtual pe_if)::set(null, "*", "vif", vif);
run_test("pe_test");
end

endmodule
