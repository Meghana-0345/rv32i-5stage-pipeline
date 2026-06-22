# 5-Stage Pipelined RV32I Processor

This repository contains the RTL design and verification of a 5-stage pipelined RISC-V RV32I processor written in Verilog. The design implements the classic IF → ID → EX → MEM → WB pipeline with full data forwarding, hazard detection, load-use stall handling, and branch resolution in the ID stage. An extra HOLD stage absorbs the one-cycle read latency of the M10K block RAM data memory.

The project was implemented and synthesized using Intel Quartus Prime and verified using a self-checking Verilog testbench with scoreboard-based checking across arithmetic, logical, memory, shift, branch, and jump instructions.

---

# Design Overview

The processor executes the RV32I base integer instruction set through a 5-stage pipeline with full forwarding and hazard resolution to maximize throughput while maintaining correct program execution.

## Supported Features

- 5-Stage Pipeline: IF → ID → EX → MEM → WB
- Full Data Forwarding (EX/MEM → HOLD → MEM/WB → EX)
- Load-Use Hazard Detection with 1-Cycle Stall
- Branch Data Hazard Detection with 1-Cycle Stall
- Branch Resolution in ID Stage (1-cycle penalty)
- JAL / JALR Jump Support
- M10K Block RAM Data Memory with HOLD Stage Latency Alignment
- LUT-Based Instruction ROM (no MIF file required)
- Flip-Flop Register File (32 × 32-bit, async read, sync write)
- Self-Checking Testbench with Scoreboard
- Debug Output Ports for Waveform Inspection

---

# Default Configuration

| Parameter         | Value                          |
|-------------------|--------------------------------|
| ISA               | RV32I Base Integer             |
| Pipeline Stages   | 5 (IF, ID, EX, MEM, WB)       |
| Data Width        | 32 bits                        |
| Register File     | 32 × 32-bit flip-flop array    |
| Instruction Mem   | 256 × 32-bit combinatorial ROM |
| Data Memory       | 1024 × 32-bit M10K block RAM   |
| Branch Resolution | ID Stage                       |
| Forwarding        | EX/MEM, HOLD, MEM/WB → EX     |

---

# Processor Architecture

The design consists of the following RTL modules:

---

## 1. Instruction Fetch (IF)

The IF stage drives the PC register and fetches the instruction for the current address from instruction memory.

### PC Update Logic

```
pc_next = branch/jump target   (if flush)
        = pc + 4               (otherwise)
```

The PC is frozen during a stall and overridden during a branch, JAL, or JALR.

### Instruction Memory

Implemented as a combinatorial case statement ROM — pure LUT logic with no block RAM inference and no external MIF file required.

---

## 2. Instruction Decode (ID)

The ID stage decodes the fetched instruction, reads the register file, generates the sign-extended immediate, evaluates branch conditions, and detects hazards.

### Modules in ID

| Module                | Function                               |
|-----------------------|----------------------------------------|
| Control Unit          | Decodes opcode, funct3, funct7         |
| Register File         | 32 × 32-bit async read, sync write     |
| Immediate Generator   | Sign-extends all RV32I immediate types |
| Branch Comparator     | Evaluates branch condition in ID       |
| Hazard Detection Unit | Detects load-use and branch hazards    |

### Supported Opcodes

| Type   | Instructions                                          |
|--------|-------------------------------------------------------|
| R-type | ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU     |
| I-type | ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI |
| Load   | LW                                                    |
| Store  | SW                                                    |
| Branch | BEQ, BNE, BLT, BGE, BLTU, BGEU                       |
| Jump   | JAL, JALR                                             |
| Upper  | LUI, AUIPC                                            |

### Branch Resolution

Branch comparison is performed in the ID stage using forwarded register values, reducing the branch penalty to 1 cycle. A flush is issued to the IF/ID register when a branch is taken or a jump is executed.

---

## 3. Execute (EX)

The EX stage selects ALU operands (with forwarding), applies the ALU operation, and computes the memory address for loads and stores.

### Forwarding MUX Select

| fwd signal | Source     | Cycles behind EX |
|------------|------------|------------------|
| 2'b01      | EX/MEM reg | 1                |
| 2'b10      | HOLD reg   | 2                |
| 2'b11      | MEM/WB reg | 3                |
| 2'b00      | ID/EX reg  | (no forward)     |

### ALU Operations

| Code | Operation              |
|------|------------------------|
| ADD  | a + b                  |
| SUB  | a − b                  |
| AND  | a & b                  |
| OR   | a \| b                 |
| XOR  | a ^ b                  |
| SLT  | signed less-than       |
| SLTU | unsigned less-than     |
| SLL  | logical shift left     |
| SRL  | logical shift right    |
| SRA  | arithmetic shift right |
| LUI  | pass b                 |

---

## 4. Memory / HOLD

The MEM stage drives the data memory address and write data. Because data memory is implemented as M10K block RAM with a synchronous (registered) read output, an extra HOLD pipeline register is inserted between EX/MEM and MEM/WB to absorb the one-cycle read latency.

### HOLD Stage Purpose

```
EX/MEM reg captures address at posedge N
Data mem   captures address at posedge N  →  rd valid at posedge N+1
HOLD reg   captures EX/MEM control at posedge N  →  valid at posedge N+1
MEM/WB reg captures both at posedge N+1  →  hold_* and mem_data_out aligned
```

For non-load instructions the HOLD stage is transparent — the ALU result passes through. The load-use stall count remains 1.

### Effective Pipeline

```
IF | ID | EX | MEM | HOLD | WB
```

---

## 5. Write Back (WB)

The WB stage selects the value to write back to the register file.

### WB MUX

| wb_sel | Source      | Used by        |
|--------|-------------|----------------|
| 2'd0   | ALU result  | R-type, I-type |
| 2'd1   | Memory data | LW             |
| 2'd2   | PC + 4      | JAL, JALR      |

---

## Hazard Detection Unit

Detects two hazard types requiring pipeline stalls:

### 1. Load-Use Hazard

```
LW in EX stage → instruction in ID reads the same register
Action: insert 1 bubble, freeze IF/ID and PC
```

After the stall, the HOLD → EX forwarding path delivers the loaded data.

### 2. Branch Data Hazard

```
Branch in ID → instruction in EX writes rs1 or rs2 of that branch
Action: insert 1 bubble so result reaches EX/MEM → ID forwarding
```

---

## Forwarding Unit

Resolves RAW data hazards by selecting the most recent write to a register from the three forwarding sources. Priority order: EX/MEM > HOLD > MEM/WB.

```
if   (EX/MEM writes rs)  → forward from EX/MEM
elif (HOLD   writes rs)  → forward from HOLD
elif (MEM/WB writes rs)  → forward from MEM/WB
else                     → use ID/EX register value
```

---

# Verification Environment

The processor was verified using a fully self-checking testbench written in Verilog.

The testbench automatically:

- Initializes and resets the pipeline
- Runs a fixed instruction program for 140 cycles
- Checks register file values after execution
- Checks data memory contents
- Tracks pass / fail statistics
- Reports performance metrics
- Produces a scoreboard summary

No manual waveform inspection is required to determine correctness.

---

# Verification Methodology

## Directed Testing

Specific instruction sequences were created to verify:

- Reset behavior
- Arithmetic operations with forwarding
- Logical operations
- Memory load / store with load-use stall
- Shift and comparison instructions
- Branch instructions (taken and not-taken paths)
- JAL jump with skipped instruction
- x0 hardwired-zero enforcement

## Scoreboard Checking

The testbench compares:

```
Expected register / memory value
            vs
Actual DUT state
```

Any mismatch is immediately reported with the register number, expected value, and actual value.

---

# Test Scenarios

## TC1 – Reset Verification

Verifies:

- PC = 0x00000000 after reset
- Pipeline registers cleared to NOP state

---

## TC2 – Arithmetic (Forwarding: EX→EX, MEM→EX)

Tests:

```
ADDI x1, x0, 10    →  x1 = 10
ADDI x2, x0, 20    →  x2 = 20
ADD  x3, x1, x2    →  x3 = 30
SUB  x4, x3, x1    →  x4 = 20
```

Checks:

- EX-to-EX and MEM-to-EX forwarding paths
- Correct ALU results

---

## TC3 – Logical Operations

Tests:

```
AND x5, x1, x2    →  x5 =  0  (10 & 20)
OR  x6, x1, x2    →  x6 = 30  (10 | 20)
XOR x7, x1, x2    →  x7 = 30  (10 ^ 20)
```

Checks correct bitwise operation results.

---

## TC4 – Memory (Load-Use Stall)

Tests:

```
ADDI x8, x0, 100    →  x8  = 100
SW   x8, 0(x0)      →  mem[0] = 100
LW   x9, 0(x0)      →  x9  = 100
ADD  x10, x9, x1    →  x10 = 110
```

Checks:

- Store to data memory
- Load with 1-cycle stall
- HOLD → EX forwarding for the ADD immediately after LW

---

## TC5 – Shift and Compare

Tests:

```
ADDI x11, x0,  5    →  x11 =   5
SLT  x12, x11, x1   →  x12 =   1  (5 < 10)
SLL  x13, x11, x11  →  x13 = 160  (5 << 5)
SRL  x14, x13, x11  →  x14 =   5  (160 >> 5)
```

Checks shift amounts and signed comparison.

---

## TC6 – Branch Instructions

Tests:

```
BEQ x15, x15, +8    →  branch taken, x16 skipped, x17 = 42
BNE x15, x2,  +8    →  branch taken, x18 skipped, x19 = 77
```

Checks:

- Correct branch target computation
- IF/ID flush on taken branch
- Skipped instruction produces no register write

---

## TC7 – JAL Jump

Tests:

```
JAL x20, +8    →  x20 = 92 (PC+4), jump to addr 96
               →  x21 skipped (addr 92 not executed)
               →  x22 = 33  (addr 96 executed)
```

Checks:

- Return address written to x20
- Skipped instruction produces no register write
- Correct jump target execution

---

## TC8 – x0 Hardwired Zero

Verifies:

- x0 always reads 0 regardless of any write attempt

---

# Simulation Results

The complete verification suite successfully passed all test cases.

## Scoreboard Summary

| Metric | Result |
|--------|--------|
| PASS   | 25     |
| FAIL   | 0      |
| TOTAL  | 25     |

## Performance Metrics

| Metric          | Value |
|-----------------|-------|
| Total Cycles    | 140   |
| WB Write Events | 19    |
| Effective CPI   | 7.37  |

> The CPI of 7.37 reflects the small 19-instruction program running through a pipeline that includes stall and flush cycles. It is not representative of steady-state throughput on a larger workload.

---

# FPGA Synthesis Results

The design was synthesized using Intel Quartus Prime Lite Edition targeting the Intel MAX 10 FPGA family.

## Device Information

| Parameter     | Value                     |
|---------------|---------------------------|
| Device Family | MAX 10                    |
| Device        | 10M08DAF484C8G            |
| Tool          | Quartus Prime Lite 20.1.1 |
| Timing Models | Final                     |

## Resource Utilization

| Resource                  | Usage                 |
|---------------------------|-----------------------|
| Total Logic Elements      | 3,136 / 8,064 (39%)   |
| Total Registers           | 1,528                 |
| Total Pins                | 169 / 250 (68%)       |
| Total Memory Bits         | 32,768 / 387,072 (8%) |
| Embedded Multiplier 9-bit | 0 / 48 (0%)           |
| PLLs                      | 0 / 2 (0%)            |

---

# How to Run

## Clone Repository

```bash
git clone https://github.com/<your-username>/rv32i-5stage-pipeline.git
cd rv32i-5stage-pipeline
```

## Compile RTL

Compile the following files:

```
rtl/alu.v
rtl/reg_file.v
rtl/imm_gen.v
rtl/control_unit.v
rtl/branch_comp.v
rtl/forwarding_unit.v
rtl/hazard_detection_unit.v
rtl/instr_mem.v
rtl/data_mem.v
rtl/riscv_pipeline.v
sim/tb_riscv_pipeline.v
```

## ModelSim

```bash
vlog rtl/alu.v
vlog rtl/reg_file.v
vlog rtl/imm_gen.v
vlog rtl/control_unit.v
vlog rtl/branch_comp.v
vlog rtl/forwarding_unit.v
vlog rtl/hazard_detection_unit.v
vlog rtl/instr_mem.v
vlog rtl/data_mem.v
vlog rtl/riscv_pipeline.v
vlog sim/tb_riscv_pipeline.v

vsim tb_riscv_pipeline

run -all
```

## Quartus

1. Create a new Quartus project
2. Add all RTL files from the `rtl/` folder
3. Set top-level entity:

```
riscv_pipeline
```

4. Select target device: `10M08DAF484C8G` (MAX 10)
5. Compile the design

---

# Directory Structure

```
rv32i-5stage-pipeline/
│
├── rtl/
│   ├── riscv_pipeline.v
│   ├── alu.v
│   ├── reg_file.v
│   ├── imm_gen.v
│   ├── control_unit.v
│   ├── branch_comp.v
│   ├── forwarding_unit.v
│   ├── hazard_detection_unit.v
│   ├── instr_mem.v
│   └── data_mem.v
│
├── sim/
│   └── tb_riscv_pipeline.v
│
├── docs/
│   ├── block_diagram.png
│   ├── simulation_results.png
│   ├── waveform.png
│   └── resource_utilization.png
│
└── README.md
```

---

# Features Summary

- RV32I Base Integer ISA
- 5-Stage Pipeline Architecture
- Full Data Forwarding (3 sources)
- Load-Use Hazard Detection and Stall
- Branch Hazard Detection and Stall
- Branch Resolution in ID Stage
- HOLD Stage for Block RAM Latency Alignment
- JAL and JALR Jump Support
- LUI and AUIPC Support
- Combinatorial Instruction ROM (no MIF file)
- M10K Block RAM Data Memory
- Flip-Flop Register File (force-inferred with ramstyle = "logic")
- Self-Checking Testbench with Scoreboard
- Debug Output Ports
- FPGA Synthesizable RTL
- Verified in ModelSim
- Synthesized on Intel MAX 10 FPGA

---

# Future Improvements

Potential enhancements include:

- Full RV32I Instruction Set (LH, LB, SH, SB)
- RV32M Multiply/Divide Extension
- 2-Bit Branch Predictor
- Instruction Cache
- Data Cache with Write-Back Policy
- Configurable Pipeline Depth
- UART Debug Interface
- AXI4-Lite Peripheral Bus
- SystemVerilog Assertions (SVA)
- UVM-Based Verification Environment
- FPGA Hardware Demonstration with GPIO or UART

---

# Project Outcome

This project demonstrates RTL design, pipelined processor architecture, data hazard resolution, control hazard handling, and FPGA synthesis — skills commonly required in FPGA design, Digital IC Design, Computer Architecture, and VLSI workflows.

It highlights:

- RTL design in Verilog
- Classic 5-stage RISC pipeline implementation
- Full forwarding and hazard detection logic
- Block RAM integration with pipeline timing alignment
- Self-checking verification methodology
- FPGA synthesis and resource analysis

making it a strong intermediate-to-advanced level digital design project suitable for Computer Architecture, FPGA, RTL Design, and VLSI-oriented portfolios.
