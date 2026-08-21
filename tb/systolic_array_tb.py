"""
Systolic Array Verification Framework (RTL Simulation)
======================================================
This framework generates random matrices for all 6 configurations of the reconfigurable
systolic array across 6 distinct test batches (nominal, zeros, max, min, and gating) using NumPy.
It runs the cycle-accurate behavioral model in Python to generate cycle-by-cycle
test vectors (stimulus inputs and expected outputs), validates results against NumPy GEMM,
and executes the SystemVerilog UVM simulation using ModelSim/Questa.

It parses the simulation log to verify that the RTL implementation matches the
expected numerical results.
"""

import numpy as np
import subprocess
import re
import os
import shutil

# Helper functions for signed integer wrap-around
def to_signed_8(val):
    """Wrap integer to 8-bit signed range [-128, 127]"""
    return (int(val) + 128) % 256 - 128

def to_signed_32(val):
    """Wrap integer to 32-bit signed range [-2**31, 2**31 - 1]"""
    return (int(val) + 2**31) % 2**32 - 2**31


def compute_gemm_golden(A, B, D):
    """Compute golden GEMM C = A * B + D using NumPy with 64-bit precision to prevent overflow"""
    A_mat = np.array(A, dtype=np.int64)
    B_mat = np.array(B, dtype=np.int64)
    D_mat = np.array(D, dtype=np.int64)
    C_mat = np.matmul(A_mat, B_mat) + D_mat
    return C_mat


class SystolicArrayState:
    """Internal state registers of the 16x16 tiled systolic array"""
    def __init__(self):
        self.tile_weight_active = [[[0] * 8 for _ in range(8)] for _ in range(4)]
        self.tile_weight_shadow = [[[0] * 8 for _ in range(8)] for _ in range(4)]
        self.tile_weight_swap_out = [[[0] * 8 for _ in range(8)] for _ in range(4)]
        self.tile_activation_out = [[[0] * 8 for _ in range(8)] for _ in range(4)]
        self.tile_partial_sum_out = [[[0] * 8 for _ in range(8)] for _ in range(4)]
        self.tile_weight_swap_col0 = [[0] * 8 for _ in range(4)]
        self.tile_weight_swap_col0_out = [0] * 4


class SystolicArraySimulator:
    """Cycle-accurate simulator for the 16x16 Reconfigurable 2D Systolic Array"""
    def __init__(self):
        self.state = SystolicArrayState()
        self.cycle = 0

    def reset(self):
        """Reset all internal registers and cycle count"""
        self.state = SystolicArrayState()
        self.cycle = 0

    def step(self, reset_pin, enable, cfg, activations_in, partial_sums_in, weights, weight_write, weight_swap):
        """Perform a single clock cycle update of the systolic array"""
        if reset_pin:
            self.state = SystolicArrayState()
            self.cycle += 1
            return [0] * 32, [0] * 32, [0] * 32, [0] * 4, [0] * 4

        cfg_h_top = cfg['cfg_merge_horizontal_top']
        cfg_h_bottom = cfg['cfg_merge_horizontal_bottom']
        cfg_v_left = cfg['cfg_merge_vertical_left']
        cfg_v_right = cfg['cfg_merge_vertical_right']

        next_state = SystolicArrayState()

        prev_tile_act_out = [[self.state.tile_activation_out[t][r][7] for r in range(8)] for t in range(4)]
        prev_tile_psum_out = [[self.state.tile_partial_sum_out[t][7][c] for c in range(8)] for t in range(4)]
        prev_tile_w_out = [[self.state.tile_weight_shadow[t][7][c] for c in range(8)] for t in range(4)]
        prev_tile_swap_out = [self.state.tile_weight_swap_out[t][0][7] for t in range(4)]
        prev_tile_swap_col0_out = [self.state.tile_weight_swap_col0_out[t] for t in range(4)]

        tile_activations_in = [[0] * 8 for _ in range(4)]
        tile_partial_sums_in = [[0] * 8 for _ in range(4)]
        tile_weights = [[0] * 8 for _ in range(4)]
        tile_weight_write_in = [0] * 4
        tile_weight_swap_in = [0] * 4

        for i in range(8):
            # Tile 0 (TL) inputs
            tile_activations_in[0][i] = to_signed_8(activations_in[i])
            tile_partial_sums_in[0][i] = to_signed_32(partial_sums_in[i])
            tile_weights[0][i] = to_signed_8(weights[i])

            # Tile 1 (TR) inputs
            tile_activations_in[1][i] = prev_tile_act_out[0][i] if cfg_h_top else to_signed_8(activations_in[i + 8])
            tile_partial_sums_in[1][i] = to_signed_32(partial_sums_in[i + 8])
            tile_weights[1][i] = to_signed_8(weights[i + 8])

            # Tile 2 (BL) inputs
            tile_activations_in[2][i] = to_signed_8(activations_in[i + 16])
            tile_partial_sums_in[2][i] = prev_tile_psum_out[0][i] if cfg_v_left else to_signed_32(partial_sums_in[i + 16])
            tile_weights[2][i] = prev_tile_w_out[0][i] if cfg_v_left else to_signed_8(weights[i + 16])

            # Tile 3 (BR) inputs
            tile_activations_in[3][i] = prev_tile_act_out[2][i] if cfg_h_bottom else to_signed_8(activations_in[i + 24])
            tile_partial_sums_in[3][i] = prev_tile_psum_out[1][i] if cfg_v_right else to_signed_32(partial_sums_in[i + 24])
            tile_weights[3][i] = prev_tile_w_out[1][i] if cfg_v_right else to_signed_8(weights[i + 24])

        tile_weight_write_in[0] = weight_write[0]
        tile_weight_swap_in[0] = weight_swap[0]

        tile_weight_write_in[1] = weight_write[1]
        tile_weight_swap_in[1] = prev_tile_swap_out[0] if cfg_h_top else weight_swap[1]

        tile_weight_write_in[2] = tile_weight_write_in[0] if cfg_v_left else weight_write[2]
        tile_weight_swap_in[2] = prev_tile_swap_col0_out[0] if cfg_v_left else weight_swap[2]

        tile_weight_write_in[3] = tile_weight_write_in[1] if cfg_v_right else weight_write[3]
        tile_weight_swap_in[3] = prev_tile_swap_out[2] if cfg_h_bottom else (prev_tile_swap_col0_out[1] if cfg_v_right else weight_swap[3])

        # Update swap col0 delay chain
        for t in range(4):
            if enable[t]:
                next_state.tile_weight_swap_col0[t][1] = tile_weight_swap_in[t]
                for i in range(2, 8):
                    next_state.tile_weight_swap_col0[t][i] = self.state.tile_weight_swap_col0[t][i-1]
                next_state.tile_weight_swap_col0_out[t] = self.state.tile_weight_swap_col0[t][7]
            else:
                for i in range(1, 8):
                    next_state.tile_weight_swap_col0[t][i] = self.state.tile_weight_swap_col0[t][i]
                next_state.tile_weight_swap_col0_out[t] = self.state.tile_weight_swap_col0_out[t]

        # Update PE registers
        for t in range(4):
            if enable[t]:
                for lr in range(8):
                    for lc in range(8):
                        act_in = tile_activations_in[t][lr] if lc == 0 else self.state.tile_activation_out[t][lr][lc-1]
                        psum_in = tile_partial_sums_in[t][lc] if lr == 0 else self.state.tile_partial_sum_out[t][lr-1][lc]
                        w_in = tile_weights[t][lc] if lr == 0 else self.state.tile_weight_shadow[t][lr-1][lc]
                        w_write_in = tile_weight_write_in[t]
                        
                        if lc == 0:
                            w_swap_in = tile_weight_swap_in[t] if lr == 0 else self.state.tile_weight_swap_col0[t][lr]
                        else:
                            w_swap_in = self.state.tile_weight_swap_out[t][lr][lc-1]

                        if w_write_in:
                            next_state.tile_weight_shadow[t][lr][lc] = to_signed_8(w_in)
                        else:
                            next_state.tile_weight_shadow[t][lr][lc] = self.state.tile_weight_shadow[t][lr][lc]

                        if w_swap_in:
                            next_state.tile_weight_active[t][lr][lc] = self.state.tile_weight_shadow[t][lr][lc]
                        else:
                            next_state.tile_weight_active[t][lr][lc] = self.state.tile_weight_active[t][lr][lc]

                        next_state.tile_activation_out[t][lr][lc] = to_signed_8(act_in)
                        prod = to_signed_8(act_in) * to_signed_8(self.state.tile_weight_active[t][lr][lc])
                        next_state.tile_partial_sum_out[t][lr][lc] = to_signed_32(to_signed_32(psum_in) + prod)
                        next_state.tile_weight_swap_out[t][lr][lc] = w_swap_in
            else:
                for lr in range(8):
                    for lc in range(8):
                        next_state.tile_weight_shadow[t][lr][lc] = self.state.tile_weight_shadow[t][lr][lc]
                        next_state.tile_weight_active[t][lr][lc] = self.state.tile_weight_active[t][lr][lc]
                        next_state.tile_activation_out[t][lr][lc] = self.state.tile_activation_out[t][lr][lc]
                        next_state.tile_partial_sum_out[t][lr][lc] = self.state.tile_partial_sum_out[t][lr][lc]
                        next_state.tile_weight_swap_out[t][lr][lc] = self.state.tile_weight_swap_out[t][lr][lc]

        self.state = next_state
        self.cycle += 1

        activations_out = [0] * 32
        partial_sums_out = [0] * 32
        weights_out = [0] * 32
        
        for i in range(8):
            activations_out[i] = self.state.tile_activation_out[0][i][7]
            activations_out[i + 8] = self.state.tile_activation_out[1][i][7]
            activations_out[i + 16] = self.state.tile_activation_out[2][i][7]
            activations_out[i + 24] = self.state.tile_activation_out[3][i][7]

            partial_sums_out[i] = self.state.tile_partial_sum_out[0][7][i]
            partial_sums_out[i + 8] = self.state.tile_partial_sum_out[1][7][i]
            partial_sums_out[i + 16] = self.state.tile_partial_sum_out[2][7][i]
            partial_sums_out[i + 24] = self.state.tile_partial_sum_out[3][7][i]

            weights_out[i] = self.state.tile_weight_shadow[0][7][i]
            weights_out[i + 8] = self.state.tile_weight_shadow[1][7][i]
            weights_out[i + 16] = self.state.tile_weight_shadow[2][7][i]
            weights_out[i + 24] = self.state.tile_weight_shadow[3][7][i]

        weight_write_out = [
            tile_weight_write_in[0],
            tile_weight_write_in[1],
            tile_weight_write_in[2],
            tile_weight_write_in[3],
        ]
        
        weight_swap_out = [
            self.state.tile_weight_swap_out[0][0][7],
            self.state.tile_weight_swap_out[1][0][7],
            self.state.tile_weight_swap_out[2][0][7],
            self.state.tile_weight_swap_out[3][0][7],
        ]

        return activations_out, partial_sums_out, weights_out, weight_write_out, weight_swap_out


# Configuration Topology Database
CONFIGURATIONS = {
    'mode_1x16x16': {
        'name': "1x 16x16 Monolithic Array",
        'cfg_merge_horizontal_top': 1,
        'cfg_merge_horizontal_bottom': 1,
        'cfg_merge_vertical_left': 1,
        'cfg_merge_vertical_right': 1,
        'grids': [
            {
                'H': 16, 'W': 16,
                'row_inputs': list(range(8)) + list(range(16, 24)),
                'col_inputs': list(range(16)),
                'row_outputs': list(range(8, 16)) + list(range(24, 32)),
                'col_outputs': list(range(16, 32)),
                'write_pins': [0, 1],
                'swap_pins': [0, 1]
            }
        ]
    },
    'mode_4x8x8': {
        'name': "4x 8x8 Independent Arrays",
        'cfg_merge_horizontal_top': 0,
        'cfg_merge_horizontal_bottom': 0,
        'cfg_merge_vertical_left': 0,
        'cfg_merge_vertical_right': 0,
        'grids': [
            {
                'H': 8, 'W': 8,
                'row_inputs': list(range(8)),
                'col_inputs': list(range(8)),
                'row_outputs': list(range(8)),
                'col_outputs': list(range(8)),
                'write_pins': [0],
                'swap_pins': [0]
            },
            {
                'H': 8, 'W': 8,
                'row_inputs': list(range(8, 16)),
                'col_inputs': list(range(8, 16)),
                'row_outputs': list(range(8, 16)),
                'col_outputs': list(range(8, 16)),
                'write_pins': [1],
                'swap_pins': [1]
            },
            {
                'H': 8, 'W': 8,
                'row_inputs': list(range(16, 24)),
                'col_inputs': list(range(16, 24)),
                'row_outputs': list(range(16, 24)),
                'col_outputs': list(range(16, 24)),
                'write_pins': [2],
                'swap_pins': [2]
            },
            {
                'H': 8, 'W': 8,
                'row_inputs': list(range(24, 32)),
                'col_inputs': list(range(24, 32)),
                'row_outputs': list(range(24, 32)),
                'col_outputs': list(range(24, 32)),
                'write_pins': [3],
                'swap_pins': [3]
            }
        ]
    },
    'mode_2x8x16': {
        'name': "Two 8x16 Horizontal Arrays",
        'cfg_merge_horizontal_top': 1,
        'cfg_merge_horizontal_bottom': 1,
        'cfg_merge_vertical_left': 0,
        'cfg_merge_vertical_right': 0,
        'grids': [
            {
                'H': 8, 'W': 16,
                'row_inputs': list(range(8)),
                'col_inputs': list(range(16)),
                'row_outputs': list(range(8, 16)),
                'col_outputs': list(range(16)),
                'write_pins': [0, 1],
                'swap_pins': [0, 1]
            },
            {
                'H': 8, 'W': 16,
                'row_inputs': list(range(16, 24)),
                'col_inputs': list(range(16, 32)),
                'row_outputs': list(range(24, 32)),
                'col_outputs': list(range(16, 32)),
                'write_pins': [2, 3],
                'swap_pins': [2, 3]
            }
        ]
    },
    'mode_2x16x8': {
        'name': "Two 16x8 Vertical Arrays",
        'cfg_merge_horizontal_top': 0,
        'cfg_merge_horizontal_bottom': 0,
        'cfg_merge_vertical_left': 1,
        'cfg_merge_vertical_right': 1,
        'grids': [
            {
                'H': 16, 'W': 8,
                'row_inputs': list(range(8)) + list(range(16, 24)),
                'col_inputs': list(range(8)),
                'row_outputs': list(range(8)) + list(range(16, 24)),
                'col_outputs': list(range(16, 24)),
                'write_pins': [0],
                'swap_pins': [0]
            },
            {
                'H': 16, 'W': 8,
                'row_inputs': list(range(8, 16)) + list(range(24, 32)),
                'col_inputs': list(range(8, 16)),
                'row_outputs': list(range(8, 16)) + list(range(24, 32)),
                'col_outputs': list(range(24, 32)),
                'write_pins': [1],
                'swap_pins': [1]
            }
        ]
    },
    'mode_1x8x16_2x8x8': {
        'name': "One 8x16 & Two 8x8 Arrays",
        'cfg_merge_horizontal_top': 1,
        'cfg_merge_horizontal_bottom': 0,
        'cfg_merge_vertical_left': 0,
        'cfg_merge_vertical_right': 0,
        'grids': [
            {
                'H': 8, 'W': 16,
                'row_inputs': list(range(8)),
                'col_inputs': list(range(16)),
                'row_outputs': list(range(8, 16)),
                'col_outputs': list(range(16)),
                'write_pins': [0, 1],
                'swap_pins': [0, 1]
            },
            {
                'H': 8, 'W': 8,
                'row_inputs': list(range(16, 24)),
                'col_inputs': list(range(16, 24)),
                'row_outputs': list(range(16, 24)),
                'col_outputs': list(range(16, 24)),
                'write_pins': [2],
                'swap_pins': [2]
            },
            {
                'H': 8, 'W': 8,
                'row_inputs': list(range(24, 32)),
                'col_inputs': list(range(24, 32)),
                'row_outputs': list(range(24, 32)),
                'col_outputs': list(range(24, 32)),
                'write_pins': [3],
                'swap_pins': [3]
            }
        ]
    },
    'mode_1x16x8_2x8x8': {
        'name': "One 16x8 & Two 8x8 Arrays",
        'cfg_merge_horizontal_top': 0,
        'cfg_merge_horizontal_bottom': 0,
        'cfg_merge_vertical_left': 1,
        'cfg_merge_vertical_right': 0,
        'grids': [
            {
                'H': 16, 'W': 8,
                'row_inputs': list(range(8)) + list(range(16, 24)),
                'col_inputs': list(range(8)),
                'row_outputs': list(range(8)) + list(range(16, 24)),
                'col_outputs': list(range(16, 24)),
                'write_pins': [0],
                'swap_pins': [0]
            },
            {
                'H': 8, 'W': 8,
                'row_inputs': list(range(8, 16)),
                'col_inputs': list(range(8, 16)),
                'row_outputs': list(range(8, 16)),
                'col_outputs': list(range(8, 16)),
                'write_pins': [1],
                'swap_pins': [1]
            },
            {
                'H': 8, 'W': 8,
                'row_inputs': list(range(24, 32)),
                'col_inputs': list(range(24, 32)),
                'row_outputs': list(range(24, 32)),
                'col_outputs': list(range(24, 32)),
                'write_pins': [3],
                'swap_pins': [3]
            }
        ]
    }
}

# Verification Test Batches designed using NumPy matrix generation
TEST_BATCHES = [
    {
        'name': "Nominal Random",
        'gen_A': lambda H, M: np.random.randint(-64, 64, size=(M, H), dtype=np.int32).tolist(),
        'gen_B': lambda H, W: np.random.randint(-64, 64, size=(H, W), dtype=np.int32).tolist(),
        'gen_D': lambda W, M: np.random.randint(-100, 101, size=(M, W), dtype=np.int32).tolist(),
        'enable': [1, 1, 1, 1]
    },
    {
        'name': "All Zeros",
        'gen_A': lambda H, M: np.zeros((M, H), dtype=np.int32).tolist(),
        'gen_B': lambda H, W: np.zeros((H, W), dtype=np.int32).tolist(),
        'gen_D': lambda W, M: np.zeros((M, W), dtype=np.int32).tolist(),
        'enable': [1, 1, 1, 1]
    },
    {
        'name': "Extreme Max (127)",
        'gen_A': lambda H, M: np.full((M, H), 127, dtype=np.int32).tolist(),
        'gen_B': lambda H, W: np.full((H, W), 127, dtype=np.int32).tolist(),
        'gen_D': lambda W, M: np.full((M, W), 500, dtype=np.int32).tolist(),
        'enable': [1, 1, 1, 1]
    },
    {
        'name': "Extreme Min (-128)",
        'gen_A': lambda H, M: np.full((M, H), -128, dtype=np.int32).tolist(),
        'gen_B': lambda H, W: np.full((H, W), -128, dtype=np.int32).tolist(),
        'gen_D': lambda W, M: np.full((M, W), -500, dtype=np.int32).tolist(),
        'enable': [1, 1, 1, 1]
    },
    {
        'name': "Gating (TL & BL enabled, TR & BR disabled)",
        'gen_A': lambda H, M: np.random.randint(-64, 64, size=(M, H), dtype=np.int32).tolist(),
        'gen_B': lambda H, W: np.random.randint(-64, 64, size=(H, W), dtype=np.int32).tolist(),
        'gen_D': lambda W, M: np.random.randint(-100, 101, size=(M, W), dtype=np.int32).tolist(),
        'enable': [1, 0, 1, 0]
    },
    {
        'name': "Gating (TL & TR enabled, BL & BR disabled)",
        'gen_A': lambda H, M: np.random.randint(-64, 64, size=(M, H), dtype=np.int32).tolist(),
        'gen_B': lambda H, W: np.random.randint(-64, 64, size=(H, W), dtype=np.int32).tolist(),
        'gen_D': lambda W, M: np.random.randint(-100, 101, size=(M, W), dtype=np.int32).tolist(),
        'enable': [1, 1, 0, 0]
    }
]


def format_stimulus_line(reset_val, enable_list, cfg_dict, write_list, swap_list, weights_list, activations_list, partial_sums_list):
    """Format single cycle stimulus into a space-separated hex string for Systolic Array Testbench"""
    enable_val = sum((1 << idx) if b else 0 for idx, b in enumerate(enable_list))
    
    cfg_val = 0
    if cfg_dict['cfg_merge_horizontal_top']:
        cfg_val |= 8
    if cfg_dict['cfg_merge_horizontal_bottom']:
        cfg_val |= 4
    if cfg_dict['cfg_merge_vertical_left']:
        cfg_val |= 2
    if cfg_dict['cfg_merge_vertical_right']:
        cfg_val |= 1
        
    write_val = sum((1 << idx) if b else 0 for idx, b in enumerate(write_list))
    swap_val = sum((1 << idx) if b else 0 for idx, b in enumerate(swap_list))
    
    weights_hex = " ".join(f"{w & 0xFF:02X}" for w in weights_list)
    activations_hex = " ".join(f"{a & 0xFF:02X}" for a in activations_list)
    partial_sums_hex = " ".join(f"{p & 0xFFFFFFFF:08X}" for p in partial_sums_list)
    
    return f"{int(reset_val):X} {enable_val:X} {cfg_val:X} {write_val:X} {swap_val:X} {weights_hex} {activations_hex} {partial_sums_hex}\n"


def generate_stimulus_data():
    """Simulate all 6 configurations across 6 batches to generate test vectors verified with NumPy GEMM"""
    inputs_f = open("tb/stimulus_inputs.txt", "w")
    expected_f = open("tb/stimulus_expected.txt", "w")

    global_cycle = 0
    sim = SystolicArraySimulator()

    for config_key, config in CONFIGURATIONS.items():
        print(f"Generating vectors for: {config['name']}...")
        
        cfg = {
            'cfg_merge_horizontal_top': config['cfg_merge_horizontal_top'],
            'cfg_merge_horizontal_bottom': config['cfg_merge_horizontal_bottom'],
            'cfg_merge_vertical_left': config['cfg_merge_vertical_left'],
            'cfg_merge_vertical_right': config['cfg_merge_vertical_right']
        }

        for batch in TEST_BATCHES:
            print(f"  - Batch: {batch['name']}")
            sim.reset()
            enable = batch['enable']

            grids_data = []
            h_max = 0
            w_max = 0
            m_val = 8
            
            for grid in config['grids']:
                H = grid['H']
                W = grid['W']
                h_max = max(h_max, H)
                w_max = max(w_max, W)
                
                B = batch['gen_B'](H, W)
                A = batch['gen_A'](H, m_val)
                D = batch['gen_D'](W, m_val)
                
                # Verify mathematical consistency using NumPy GEMM
                C_golden = compute_gemm_golden(A, B, D)
                
                grids_data.append({
                    'grid': grid,
                    'A': A,
                    'B': B,
                    'D': D,
                    'C_golden': C_golden
                })

            # 1. Reset Phase (5 cycles)
            for _ in range(5):
                line = format_stimulus_line(
                    reset_val=1, enable_list=[0]*4, cfg_dict=cfg, write_list=[0]*4, swap_list=[0]*4,
                    weights_list=[0]*32, activations_list=[0]*32, partial_sums_list=[0]*32
                )
                inputs_f.write(line)
                sim.step(1, enable, cfg, [0]*32, [0]*32, [0]*32, [0]*4, [0]*4)
                global_cycle += 1

            # 2. Weight Loading Phase (h_max cycles)
            for t in range(h_max):
                weights_in = [0] * 32
                weight_write = [0] * 4
                weight_swap = [0] * 4
                activations_in = [0] * 32
                partial_sums_in = [0] * 32

                for data in grids_data:
                    grid = data['grid']
                    B = data['B']
                    H = grid['H']
                    W = grid['W']
                    
                    if t < H:
                        for pin in grid['write_pins']:
                            weight_write[pin] = 1
                        for c in range(W):
                            weights_in[grid['col_inputs'][c]] = B[H - 1 - t][c]

                line = format_stimulus_line(
                    reset_val=0, enable_list=enable, cfg_dict=cfg, write_list=weight_write, swap_list=weight_swap,
                    weights_list=weights_in, activations_list=activations_in, partial_sums_list=partial_sums_in
                )
                inputs_f.write(line)
                sim.step(0, enable, cfg, activations_in, partial_sums_in, weights_in, weight_write, weight_swap)
                global_cycle += 1

            # 3. Swap Wavefront Phase (1 swap cycle + wavefront wait cycles)
            weights_in = [0] * 32
            weight_write = [0] * 4
            weight_swap = [0] * 4
            activations_in = [0] * 32
            partial_sums_in = [0] * 32
            
            for data in grids_data:
                grid = data['grid']
                for pin in grid['swap_pins']:
                    weight_swap[pin] = 1

            line = format_stimulus_line(
                reset_val=0, enable_list=enable, cfg_dict=cfg, write_list=weight_write, swap_list=weight_swap,
                weights_list=weights_in, activations_list=activations_in, partial_sums_list=partial_sums_in
            )
            inputs_f.write(line)
            sim.step(0, enable, cfg, activations_in, partial_sums_in, weights_in, weight_write, weight_swap)
            global_cycle += 1

            # Wait cycles for swap to settle
            weight_swap = [0] * 4
            for _ in range(h_max + w_max):
                line = format_stimulus_line(
                    reset_val=0, enable_list=enable, cfg_dict=cfg, write_list=weight_write, swap_list=weight_swap,
                    weights_list=weights_in, activations_list=activations_in, partial_sums_list=partial_sums_in
                )
                inputs_f.write(line)
                sim.step(0, enable, cfg, activations_in, partial_sums_in, weights_in, weight_write, weight_swap)
                global_cycle += 1

            # 4. Activation and Partial Sum Streaming Phase
            total_stream_cycles = m_val + h_max + w_max
            for cycle_idx in range(total_stream_cycles):
                weights_in = [0] * 32
                weight_write = [0] * 4
                weight_swap = [0] * 4
                activations_in = [0] * 32
                partial_sums_in = [0] * 32

                for data in grids_data:
                    grid = data['grid']
                    A = data['A']
                    D = data['D']
                    H = grid['H']
                    W = grid['W']

                    for r in range(H):
                        idx = grid['row_inputs'][r]
                        t_idx = cycle_idx - r
                        if 0 <= t_idx < m_val:
                            activations_in[idx] = A[t_idx][r]

                    for c in range(W):
                        idx = grid['col_inputs'][c]
                        t_idx = cycle_idx - c
                        if 0 <= t_idx < m_val:
                            partial_sums_in[idx] = D[t_idx][c]

                line = format_stimulus_line(
                    reset_val=0, enable_list=enable, cfg_dict=cfg, write_list=weight_write, swap_list=weight_swap,
                    weights_list=weights_in, activations_list=activations_in, partial_sums_list=partial_sums_in
                )
                inputs_f.write(line)
                _, psum_out, _, _, _ = sim.step(0, enable, cfg, activations_in, partial_sums_in, weights_in, weight_write, weight_swap)

                # Record expected checks using the Python simulator's cycle-accurate output
                for data in grids_data:
                    grid = data['grid']
                    H = grid['H']
                    W = grid['W']
                    C_golden = data['C_golden']

                    for i in range(m_val):
                        for c in range(W):
                            expected_cycle = i + H + c - 1
                            if cycle_idx == expected_cycle:
                                port_idx = grid['col_outputs'][c]
                                val = psum_out[port_idx]
                                
                                # Validate against NumPy GEMM if all relevant tiles are enabled
                                if all(enable):
                                    gold_val = to_signed_32(int(C_golden[i, c]))
                                    assert val == gold_val, f"Mismatch with NumPy GEMM at row {i}, col {c}: sim={val}, numpy={gold_val}"
                                
                                expected_f.write(f"{global_cycle} {port_idx} {val & 0xFFFFFFFF:08X}\n")

                global_cycle += 1

    inputs_f.close()
    expected_f.close()
    print("Test vectors successfully generated and verified against NumPy GEMM.")


def run_modelsim_simulation():
    """Compile and run the SystemVerilog UVM simulation in ModelSim/Questa"""
    print("\n--------------------------------------------------")
    print("LAUNCHING MODELSIM UVM SIMULATION")
    print("--------------------------------------------------")

    # 1. Create work library in tb/
    print("Creating work library in tb/...")
    res = subprocess.run(["vlib", "tb/work"], capture_output=True, text=True)
    if res.returncode != 0 and "already exists" not in res.stderr:
        print("Error executing vlib tb/work:")
        print(res.stderr)
        return False

    # Find UVM src directory in ModelSim installation
    uvm_inc_dir = "C:/intelFPGA/20.1/modelsim_ase/verilog_src/uvm-1.2/src"
    uvm_pkg_file = "C:/intelFPGA/20.1/modelsim_ase/verilog_src/uvm-1.2/src/uvm_pkg.sv"
    
    try:
        vlog_loc = subprocess.run(
            ["powershell", "-Command", "Get-Command vlog | Select-Object -ExpandProperty Source"],
            capture_output=True,
            text=True
        ).stdout.strip()
        if vlog_loc and os.path.exists(vlog_loc):
            base_dir = os.path.dirname(os.path.dirname(vlog_loc))
            cand_inc = os.path.join(base_dir, "verilog_src", "uvm-1.2", "src")
            cand_pkg = os.path.join(cand_inc, "uvm_pkg.sv")
            if os.path.exists(cand_pkg):
                uvm_inc_dir = cand_inc.replace("\\", "/")
                uvm_pkg_file = cand_pkg.replace("\\", "/")
    except Exception:
        pass

    # 2. Compile SystemVerilog RTL and UVM testbench into tb/work
    print("Compiling RTL & UVM Testbench files...")
    compile_cmd = [
        "vlog", "-sv", "-work", "tb/work",
        "+define+UVM_NO_DPI",
        f"+incdir+{uvm_inc_dir}",
        uvm_pkg_file,
        "rtl/compute/pe.sv",
        "rtl/compute/tile.sv",
        "rtl/compute/systolic_array.sv",
        "tb/systolic_array_tb.sv"
    ]
    res = subprocess.run(compile_cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print("ModelSim Compilation FAILED:")
        print(res.stdout)
        print(res.stderr)
        return False
    print("Compilation successful.")

    # 3. Execute vsim with log file set to tb/transcript
    print("Running UVM simulation...")
    sim_cmd = [
        "vsim", "-c", "-l", "tb/transcript", "-do", "run -all; quit -f", "tb/work.systolic_array_tb"
    ]
    res = subprocess.run(sim_cmd, capture_output=True, text=True)
    
    log = res.stdout
    print("\n--- ModelSim Simulator Log ---")
    print(log)
    print("------------------------------\n")

    # Scan log for verification results
    if "Verification Complete:" in log or "UVM_ERROR :    0" in log:
        match = re.search(r"Passes = (\d+), Mismatches = (\d+)", log)
        if match:
            passes = int(match.group(1))
            mismatches = int(match.group(2))
            print(f"ModelSim UVM Verification Summary:")
            print(f"  - Total output values checked: {passes + mismatches}")
            print(f"  - Passed checks: {passes}")
            print(f"  - Mismatched checks: {mismatches}")
            if mismatches == 0:
                print("RESULT: ALL TEST CASES IN RTL SIMULATION PASSED!")
                return True
            else:
                print("RESULT: RTL SIMULATION ENCOUNTERED MISMATCHES.")
                return False

    print("RESULT: SIMULATION FAILED TO RUN OR REPORT STATUS.")
    return False


def cleanup_files():
    """Deletes intermediate stimulus files and ModelSim output folders if verification succeeds"""
    print("\nCleaning up generated simulation files and folders...")
    files_to_delete = [
        "tb/stimulus_inputs.txt",
        "tb/stimulus_expected.txt",
        "tb/transcript"
    ]
    folders_to_delete = [
        "tb/work"
    ]
    
    for f in files_to_delete:
        if os.path.exists(f):
            try:
                os.remove(f)
                print(f"  - Deleted file: {f}")
            except Exception as e:
                print(f"  - Error deleting file {f}: {e}")
                
    for folder in folders_to_delete:
        if os.path.exists(folder):
            try:
                shutil.rmtree(folder)
                print(f"  - Deleted directory: {folder}")
            except Exception as e:
                print(f"  - Error deleting directory {folder}: {e}")


if __name__ == "__main__":
    np.random.seed(42)
    generate_stimulus_data()
    success = run_modelsim_simulation()
    if success:
        cleanup_files()
        exit(0)
    else:
        exit(1)
