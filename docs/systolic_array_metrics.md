# Systolic Array Performance & Utilization Metrics

This document specifies the peak performance, hardware utilization, and execution efficiency metrics for the NPU's reconfigurable 2D systolic array.

---

## 1. Architectural Overview & Configuration

The NPU features a **Reconfigurable 2D Weight-Stationary Systolic Array** composed of 256 Processing Elements (PEs) organized as four $8 \times 8$ tiles. 

### Key Hardware Specifications
* **PE Dimensions**: 256 PEs arranged in a configurable $16 \times 16$ grid.
* **Precision**: 8-bit signed activations, 8-bit signed weights, and 32-bit signed partial sum accumulators.
* **Double Buffering**: Each PE contains a shadow register allowing weight preloading during active execution, enabling zero-overhead weight swaps.
* **Pipelined Control**: Pipelined weight swap wave matching the wavefront of input activations to eliminate dynamic power spikes.

### Reconfigurable Layout Modes
The array can be dynamically partitioned into different topologies based on workload requirements:

| Configuration | Topology | Active PEs | Peak MACs / Cycle | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Monolithic** | $16 \times 16$ | 256 | 256 | Single large matrix multiplication. |
| **Dual Horizontal** | Two $8 \times 16$ | 256 | 256 | Two parallel wide-matrix multiplications. |
| **Dual Vertical** | Two $16 \times 8$ | 256 | 256 | Two parallel tall-matrix multiplications. |
| **Quad Tile** | Four $8 \times 8$ | 256 | 256 | Four independent smaller matrix multiplications. |

---

## 2. FPGA Synthesis & Hardware Utilization

The design has been synthesized and fit for the **Intel MAX 10 (10M50DAF484C7G)** FPGA device.

### Resource Utilization Summary
* **Logic Elements (LEs)**: $15,835 \text{ / } 49,760 \text{ (32\%)}$
* **Dedicated Logic Registers**: $15,439 \text{ / } 49,760 \text{ (31\%)}$
* **Embedded 9-bit Multipliers**: $256 \text{ / } 288 \text{ (89\%)}$ 
  * *Note: Exactly 1 multiplier block is mapped per PE, achieving maximum DSP efficiency.*
* **Pins (Wrapper)**: 4 pins ($1\text{ clk}$, $1\text{ reset}$, $1\text{ serial\_in}$, $1\text{ serial\_out}$)
  * *Note: A serializer/shifter chain is utilized in the benchmarking wrapper to fit within package constraints without sacrificing internal array scale.*

---

## 3. Clock Frequency & Timing Analysis

Under the worst-case operating conditions (**Slow 1200mV 85°C Model**):

* **Target Clock Constraint**: $9.5 \text{ ns}$ period ($105.26 \text{ MHz}$)
* **Worst-Case Slack**: $+0.160 \text{ ns}$ (Setup Timing Met)

---

## 4. Peak Compute Throughput

Each PE executes one Multiply-Accumulate (MAC) operation (1 multiplication + 1 addition = 2 operations) per clock cycle.

### Performance at Target Frequency ($105.26\text{ MHz}$)
* **Peak MAC Throughput**:
  $$\text{Throughput}_{\text{MAC}} = 256\text{ PEs} \times 105.26\text{ MHz} = \mathbf{26.95\text{ GMACs/s}}$$
* **Peak Operations Throughput**:
  $$\text{Throughput}_{\text{OPs}} = 512\text{ OPs/cycle} \times 105.26\text{ MHz} = \mathbf{53.89\text{ GOPs/s}}$$

---

## 5. Array Utilization & Execution Efficiency

In a practical workload, the actual compute utilization of the PEs is affected by the size of the matrices, the loading overhead of weights, and the array fills.

### Zero-Bubble Weight Updates
Due to the double-buffered shadow register design inside each PE, the next weight matrix can be loaded into the shadow buffers in parallel with the compute execution of the current matrix. 

When the current matrix multiplication completes, a pipelined `weight_swap` signal propagates through the array. This swaps the weights at the exact wavefront of the incoming activations, resulting in:
* **Zero bubble cycles** for weight loading between consecutive workloads.
* Continuous compute pipeline flow for back-to-back layers.

### Spatial-Temporal Array Utilization
For a matrix multiplication of size $(M \times K) \times (K \times N)$ mapped onto an active systolic array of size $R \times C$ (where $R \le 16$, $C \le 16$):

1. **Ramp-up Cycles**: The pipeline takes $R + C - 1$ cycles for the first output to exit the bottom of the array.
2. **Streaming Cycles**: It takes $M$ cycles to stream all activation rows of Matrix A.
3. **Ramp-down Cycles**: It takes $C$ cycles to drain the remaining partial sums.

The total clock cycles required for execution is:
$$\text{Cycles}_{\text{total}} = M + K + C - 1$$

The overall PE hardware utilization efficiency is:
$$\eta = \frac{M \times K \times N}{\text{Active PEs} \times (M + K + C - 1)}$$

For large workloads where $M, K \gg 16$, the utilization efficiency $\eta$ asymptotically approaches **100%**.
