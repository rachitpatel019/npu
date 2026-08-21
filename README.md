# RISC-V SoC Neural Processing Unit (NPU)

A high-throughput, reconfigurable **2D Weight-Stationary Systolic Array Accelerator** designed for deep learning inference acceleration in RISC-V SoC environments. Synthesized, verified, and benchmarked for FPGA deployment with zero-bubble double-buffered weight updates and low-power wavefront synchronization.

> [!NOTE]
> **Project Status & SoC Vision**:
> This repository is part of a larger initiative to build a full-featured **Neural Processing Unit (NPU)**. Currently, the core **Systolic Array Compute Engine** is implemented and verified. Future milestones will add memory buffers, DMA controllers, and instruction sequencers, culminating in full integration with our **[RISC-V CPU](https://github.com/rachitpatel019/riscv-cpu)** to form an end-to-end AI-accelerated RISC-V SoC.

---

## 📌 Architecture Highlights

* **256 Processing Elements (PEs)**: Arranged as four $8 \times 8$ compute tiles capable of forming a unified $16 \times 16$ grid or dynamically partitioned topologies.
* **INT8 / INT32 Precision**: 8-bit signed activations $\times$ 8-bit signed weights with 32-bit signed partial-sum accumulation to eliminate overflow.
* **Zero-Bubble Shadow Register Double-Buffering**: Asymmetric shadow registers in every PE allow weight matrices for the next layer to be preloaded in parallel with active compute execution.
* **Wavefront-Aligned Pipelined Weight Swaps**: Propagates the weight swap signal along the activation diagonal, mitigating $di/dt$ switching noise and current spikes across FPGA power rails.
* **Dynamic Topological Reconfiguration**: Run-time reconfigurable array partitioning across 4 distinct operational modes.

---

## 📐 Systolic Array Topologies

The compute engine consists of 4 independent $8 \times 8$ tiles ($T_0, T_1, T_2, T_3$) that can be dynamically stitched or decoupled via horizontal/vertical configuration switches:

```
          [Activations In]                      [Activations In]
                 │                                     │
                 ▼                                     ▼
        ┌─────────────────┐  cfg_merge_h_top  ┌─────────────────┐
        │  Tile 0 (8x8)   ├──────────────────►│  Tile 1 (8x8)   │
        └────────┬────────┘                   └────────┬────────┘
                 │                                     │
cfg_merge_v_left │                    cfg_merge_v_right│
                 ▼                                     ▼
        ┌─────────────────┐ cfg_merge_h_bottom┌─────────────────┐
        │  Tile 2 (8x8)   ├──────────────────►│  Tile 3 (8x8)   │
        └────────┬────────┘                   └────────┬────────┘
                 │                                     │
                 ▼                                     ▼
        [Partial Sums Out]                    [Partial Sums Out]
```

| Mode | Topology | Active PEs | Peak MACs / Cycle | Workload Optimization |
| :--- | :--- | :---: | :---: | :--- |
| **Monolithic** | Single $16 \times 16$ | 256 | 256 | Large GEMMs / dense convolution layers |
| **Dual Horizontal** | Two $8 \times 16$ | 256 | 256 | Wide-matrix batch processing |
| **Dual Vertical** | Two $16 \times 8$ | 256 | 256 | Tall-matrix / multi-channel reductions |
| **Quad Tile** | Four $8 \times 8$ | 256 | 256 | Independent multi-tenant sub-workloads |

---

## ⚡ FPGA Performance & Synthesis Metrics

The complete $16 \times 16$ systolic compute engine has been mapped and fully timing-closed for the **Intel MAX 10 FPGA (10M50DAF484C7G)**.

| Metric | Measured Value | Device Capacity / Limit | Utilization |
| :--- | :--- | :--- | :--- |
| **Logic Elements (LEs)** | **15,835** | 49,760 | **31.8%** |
| **Dedicated Logic Registers** | **15,439** | 49,760 | **31.0%** |
| **Embedded Multiplier 9-bit Elements** | **256** | 288 | **88.9%** (1 DSP / PE) |
| **Worst-Case Clock Frequency ($F_{\text{max}}$)** | **105.26 MHz** | Target: $9.5\text{ ns}$ period | **Setup Slack: $+0.160\text{ ns}$** |
| **Peak Compute Throughput (INT8)** | **26.95 GMAC/s** | *(53.89 GOP/s)* | @ 105.26 MHz |

*Timing model evaluated under worst-case industrial corner: **Slow 1200mV 85°C**.*

### ⏱️ Critical Path Analysis

Static Timing Analysis (STA) on the MAX 10 device identifies the limiting path as the single-cycle Multiply-Accumulate (MAC) cascade between adjacent Processing Elements:

$$\text{PE}_{(r, c-1)}\text{.activation\_reg} \xrightarrow{\text{Inter-PE Wire}} \text{PE}_{(r, c)}\text{.Multiplier (8}\times\text{8)} \xrightarrow{} \text{PE}_{(r, c)}\text{.Adder (32-bit Carry Chain)} \xrightarrow{} \text{PE}_{(r, c)}\text{.partial\_sum\_reg[31]}$$

* **Worst-Case Slack**: **$+0.160\text{ ns}$** at $9.500\text{ ns}$ clock period (Slow 1200mV 85°C).
* **Limiting Factors**: High DSP block density (88.9% utilization) spreads PEs across multiplier columns, while the combinational 8×8 multiply and 32-bit addition carry chain in [`pe.sv`](rtl/compute/pe.sv#L62) must complete within a single clock cycle.
* **Automated STA Reporting**: Run `quartus_sta -t fpga/report_critical_paths.tcl npu 20` to inspect the top 20 critical paths.

---

## 📂 Repository Structure

```
.
├── docs/                                  # Design documentation and interactive tools
│   ├── architectural_decisions/           # Architectural Decision Records (ADRs)
│   │   └── pe_double_buffer.md            # Shadow weight double-buffer design & di/dt mitigation
│   ├── systolic_array_metrics.md          # Comprehensive performance & timing benchmark report
│   └── systolic_array_visualizer.html     # Interactive web visualizer of systolic array dataflow
├── fpga/                                  # Quartus Prime project, constraints & top wrapper
│   ├── npu.qpf / npu.qsf                  # Quartus project definitions and pin assignments
│   ├── npu.sdc                            # Synopsys Design Constraints (timing clock setup)
│   ├── top.sv                             # Pin-constrained FPGA test wrapper with serial I/O
│   ├── report_critical_paths.tcl          # STA script to extract and report top critical paths
│   ├── report_critical_paths.sh           # Shell runner for timing analysis
│   ├── report_critical_paths.ps1          # PowerShell runner for timing analysis
│   └── output_files/                      # Synthesis, fitting, and TimeQuest STA reports
├── rtl/                                   # Synthesizable SystemVerilog RTL source files
│   ├── compute/
│   │   ├── pe.sv                          # Processing Element with shadow weight registers
│   │   ├── tile.sv                        # 8x8 PE tile with wavefront delay logic
│   │   └── systolic_array.sv              # 16x16 reconfigurable multi-tile systolic array
│   ├── control/                           # Execution state machines and sequencers (WIP)
│   ├── interface/                         # SoC / Memory bus interfaces (WIP)
│   ├── memory/                            # Activation / Weight buffers & scratchpads (WIP)
│   └── packages/                          # Shared data types, configurations, and constants
└── tb/                                    # Verification testbenches and co-simulation models
    ├── pe_tb.sv                           # Unit testbench for individual PE
    ├── tile_tb.sv                         # Testbench for 8x8 tile
    ├── systolic_array_tb.sv               # Top-level array SystemVerilog testbench
    └── systolic_array_tb.py               # Python cycle-accurate simulator and vector generator
```

---

## 🔬 Processing Element (PE) Microarchitecture

Each PE combines signed multiply-accumulate logic with asymmetric shadow registers:

```
                activation_in ───► [ Reg ] ───► activation_out
                                      │
                                      ▼
weight_in ──► [ weight_shadow ]    ( * )  (8-bit x 8-bit Signed)
                     │                │
          weight_swap│                ▼
                     ▼             ( + )  (32-bit Accumulate)
              [ weight_active ] ──────┤
                                      ▲
partial_sum_in ───────────────────────┴───────► [ Reg ] ───► partial_sum_out
```

* **Zero Multiplexer Overhead on Multiplier Path**: Active weights connect directly to the hardware multiplier without intermediate multiplexing, maximizing clock frequency ($F_{\text{max}}$).
* **Continuous Streaming**: While `weight_active` feeds the MAC pipeline, `weight_shadow` can receive new weights via vertical shift-chains with zero computation stall cycles.

---

## 🧪 Simulation & Verification

The verification suite combines standard SystemVerilog self-checking testbenches with a cycle-accurate Python golden reference model.

### 1. Cycle-Accurate Python Model & Co-Simulation
The Python framework ([`tb/systolic_array_tb.py`](tb/systolic_array_tb.py)) generates stimulus test vectors and validates ModelSim execution logs across all 6 configurations and corner cases (random matrices, zeros, min/max saturation, and tile enable gating):

```bash
# Run verification testbench generator and ModelSim co-simulation
python tb/systolic_array_tb.py
```

### 2. RTL Unit Testbenches
Individual RTL modules can be simulated with any standard SystemVerilog simulator (ModelSim, Questa, VCS, Verilator):

```bash
# Compile and run PE unit testbench
vlog -sv rtl/compute/pe.sv tb/pe_tb.sv
vsim -c -do "run -all; quit" pe_tb

# Compile and run Tile unit testbench
vlog -sv rtl/compute/pe.sv rtl/compute/tile.sv tb/tile_tb.sv
vsim -c -do "run -all; quit" tile_tb
```

---


## 🛠️ FPGA Synthesis Flow

The project is configured for synthesis via **Intel Quartus Prime**:

```bash
# Run full compilation (Map, Fit, ASM, STA)
quartus_sh --flow compile fpga/npu.qpf

# View TimeQuest Static Timing Analysis summary
cat fpga/output_files/npu.sta.summary
```

---

## 🗺️ System Roadmap & SoC Integration

This accelerator is designed to serve as the core matrix compute engine for a domain-specific **Neural Processing Unit (NPU)** within a larger RISC-V SoC:

- [x] **Phase 1 (Current)**: Parameterized, reconfigurable 2D systolic array core with double-buffering and FPGA timing closure.
- [ ] **Phase 2**: On-chip activation and weight SRAM scratchpad buffers with banking.
- [ ] **Phase 3**: DMA controller and custom NPU control sequencer / ISA decoding unit.
- [ ] **Phase 4**: Memory-mapped / coprocessor bus attachment and integration with the **[RISC-V CPU Core](https://github.com/rachitpatel019/riscv-cpu)**.

---

## 📜 Architectural Decisions & References

* [ADR: PE Weight Double Buffering & Swap Power Mitigation](docs/architectural_decisions/pe_double_buffer.md)
* [Performance & Utilization Specifications](docs/systolic_array_metrics.md)

