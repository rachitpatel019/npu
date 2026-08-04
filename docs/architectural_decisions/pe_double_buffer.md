# Architectural Decision Record: PE Weight Double Buffering & Swap Power Mitigation

**Affected Modules**: [`pe.sv`](../rtl/pe.sv), `systolic_array.sv` (array wrapper)

---

## 1. Context & Problem Statement

To maximize the compute throughput of the NPU systolic array, we must overlap the loading of the next tile's weights with the execution of the current tile. This requires a double-buffered weight system inside each processing element (PE). 

However, updating the active weights of all PEs in a large systolic array (e.g., $16 \times 16$ or $32 \times 32$) simultaneously on a single clock edge creates a substantial dynamic current draw. This simultaneous switching noise can lead to a severe voltage drop on the power rails, risking timing violations and data corruption.

---

## 2. Decision: Shadow Register with Pipelined Swap Control

We have adopted **Approach 2 (Asymmetric Shadow Buffering)** to keep the compute path timing-clean, coupled with a **Pipelined Swap Control** scheme to mitigate the transient power spike.

```
                  +-------------------+
                  |   weight_in       |
                  +---------+---------+
                            |
                            | weight_write
                            v
                  +---------+---------+
                  |   weight_shadow   |  (Double Buffer Load)
                  +---------+---------+
                            |
                            | weight_swap (Pipelined)
                            v
                  +---------+---------+
                  |   weight_active   |  (Compute-path Registered)
                  +---------+---------+
                            |
                            v
                    (Multiplier Input)
```

### Key Advantages:
1. **Critical Path Optimization**: The output of the active register is routed directly into the multiplier with zero multiplexer stages. This prevents any reduction in $F_{\text{max}}$.
2. **Current Spike Mitigation**: Instead of broadcasting the `weight_swap` signal globally to all PEs, the signal is pipelined across the array structure.

### Impacts:
* **Dynamic Current Reduction**: Peak $di/dt$ switching current is reduced by a factor of $N$ (number of rows), as only one row of PEs swaps its weights on any single clock edge.
* **Wavefront Alignment**: The weight swap timing matches the propagation delay of the input activations, maintaining a seamless, zero-bubble pipeline execution.

---

## 4. Implementation Details

### PE-Level Interface (pe.sv)
A new 1-bit input control signal is added to [`pe.sv`](../rtl/pe.sv):
* `weight_swap`: High for 1 cycle to copy `weight_shadow` to `weight_active`.

### Array-Level Wrapping (systolic_array.sv)
* Instantiates pipeline registers between rows/columns for the `weight_swap` signal.
* Coordinates the timing between the end-of-frame execution and the swap wave.
