// ============================================================
// 5-Stage Pipelined RISC-V RV32I Processor
// Stages: IF -> ID -> EX -> MEM -> WB
//
// Memory implementation notes (Quartus Cyclone V compatible):
//  - instr_mem: combinatorial case-statement ROM (pure LUTs, no RAM)
//  - reg_file:  plain flip-flop array (combinatorial read, sync write)
//  - data_mem:  M10K block RAM with synchronous read
//
// Because data_mem has a 1-cycle registered read output, an extra
// pipeline hold register (HOLD) sits between EX/MEM and MEM/WB.
// All signals advance: EX/MEM -> HOLD -> MEM/WB in lock-step, so
// data_mem.rd and the control signals are always aligned.
//
// Effective pipeline: IF | ID | EX | MEM | HOLD | WB
// For non-load instructions HOLD is transparent (passes through).
// The load-use stall count remains 1.
// ============================================================
`timescale 1ns/1ps

module riscv_pipeline (
    input  clk,
    input  rst,
    // Debug/scoreboard ports
    output [31:0] dbg_pc,
    output [31:0] dbg_instr,
    output [4:0]  dbg_wb_rd,
    output [31:0] dbg_wb_data,
    output        dbg_wb_en,
    output [31:0] dbg_dmem_addr,
    output [31:0] dbg_dmem_wdata,
    output        dbg_dmem_we
);

// ============================================================
// SIGNAL DECLARATIONS
// ============================================================

// --- IF ---
reg  [31:0] pc;
wire [31:0] pc_plus4;
wire [31:0] instr_if;

// --- IF/ID pipeline register ---
reg [31:0] if_id_pc;
reg [31:0] if_id_instr;

// --- ID stage decode ---
wire [6:0] id_opcode  = if_id_instr[6:0];
wire [4:0] id_rd      = if_id_instr[11:7];
wire [2:0] id_funct3  = if_id_instr[14:12];
wire [4:0] id_rs1     = if_id_instr[19:15];
wire [4:0] id_rs2     = if_id_instr[24:20];
wire [6:0] id_funct7  = if_id_instr[31:25];

wire [31:0] id_rd1_raw, id_rd2_raw;
wire [31:0] id_imm;

wire        id_reg_write, id_mem_read, id_mem_write;
wire        id_branch, id_jump, id_jumpr;
wire [1:0]  id_alu_src, id_wb_sel;
wire [3:0]  id_alu_ctrl;
wire [2:0]  id_branch_type;

wire        branch_taken;
wire [31:0] id_rd1_fwd, id_rd2_fwd;

wire        stall, pc_write_en, if_id_write_en;

// --- ID/EX pipeline register ---
reg [31:0] id_ex_pc;
reg [31:0] id_ex_rd1, id_ex_rd2, id_ex_imm;
reg [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
reg        id_ex_reg_write, id_ex_mem_read, id_ex_mem_write;
reg [1:0]  id_ex_alu_src, id_ex_wb_sel;
reg [3:0]  id_ex_alu_ctrl;

// --- EX stage ---
wire [31:0] ex_alu_a, ex_alu_b_pre, ex_alu_b, ex_alu_result;
wire        ex_zero;
wire [1:0]  fwd_a, fwd_b;

// --- EX/MEM pipeline register ---
reg [31:0] ex_mem_pc4, ex_mem_alu_result, ex_mem_rd2;
reg [4:0]  ex_mem_rd;
reg        ex_mem_reg_write, ex_mem_mem_read, ex_mem_mem_write;
reg [1:0]  ex_mem_wb_sel;

// --- MEM stage ---
wire [31:0] mem_data_out;  // synchronous output of data_mem block RAM

// --- HOLD pipeline register (aligns control signals with block-RAM read output) ---
reg [31:0] hold_pc4, hold_alu_result;
reg [4:0]  hold_rd;
reg        hold_reg_write, hold_mem_read;
reg [1:0]  hold_wb_sel;

// --- MEM/WB pipeline register ---
reg [31:0] mem_wb_alu_result, mem_wb_mem_data, mem_wb_pc4;
reg [4:0]  mem_wb_rd;
reg        mem_wb_reg_write;
reg [1:0]  mem_wb_wb_sel;

// --- WB ---
wire [31:0] wb_data;

// ============================================================
// SUBMODULE INSTANTIATIONS
// ============================================================

instr_mem IMEM (
    .addr  (pc),
    .instr (instr_if)
);

// reg_file: async read, sync write — plain flip-flops
reg_file REGFILE (
    .clk       (clk),
    .rs1       (id_rs1),
    .rs2       (id_rs2),
    .rd        (mem_wb_rd),
    .wd        (wb_data),
    .reg_write (mem_wb_reg_write),
    .rd1       (id_rd1_raw),
    .rd2       (id_rd2_raw)
);

control_unit CU (
    .opcode      (id_opcode),
    .funct3      (id_funct3),
    .funct7      (id_funct7),
    .reg_write   (id_reg_write),
    .mem_read    (id_mem_read),
    .mem_write   (id_mem_write),
    .branch      (id_branch),
    .jump        (id_jump),
    .jumpr       (id_jumpr),
    .alu_src     (id_alu_src),
    .wb_sel      (id_wb_sel),
    .alu_ctrl    (id_alu_ctrl),
    .branch_type (id_branch_type)
);

imm_gen IMMGEN (
    .instr (if_id_instr),
    .imm   (id_imm)
);

hazard_detection_unit HDU (
    .id_rs1          (id_rs1),
    .id_rs2          (id_rs2),
    .ex_rd           (id_ex_rd),
    .ex_mem_read     (id_ex_mem_read),
    .id_branch       (id_branch),
    .ex_mem_rd       (ex_mem_rd),
    .ex_mem_reg_write(ex_mem_reg_write),
    .stall           (stall),
    .pc_write        (pc_write_en),
    .if_id_write     (if_id_write_en)
);

forwarding_unit FWD (
    .ex_rs1        (id_ex_rs1),
    .ex_rs2        (id_ex_rs2),
    .mem_rd        (ex_mem_rd),
    .mem_reg_write (ex_mem_reg_write),
    .hold_rd       (hold_rd),
    .hold_reg_write(hold_reg_write),
    .wb_rd         (mem_wb_rd),
    .wb_reg_write  (mem_wb_reg_write),
    .fwd_a         (fwd_a),
    .fwd_b         (fwd_b)
);

alu ALU (
    .a        (ex_alu_a),
    .b        (ex_alu_b),
    .alu_ctrl (id_ex_alu_ctrl),
    .result   (ex_alu_result),
    .zero     (ex_zero)
);

// data_mem: M10K block RAM, synchronous read (1-cycle latency)
// addr port takes word address directly (byte_addr[11:2])
data_mem DMEM (
    .clk       (clk),
    .addr      (ex_mem_alu_result[11:2]),
    .wd        (ex_mem_rd2),
    .mem_write (ex_mem_mem_write),
    .rd        (mem_data_out)
);

branch_comp BCOMP (
    .a           (id_rd1_fwd),
    .b           (id_rd2_fwd),
    .branch_type (id_branch_type),
    .taken       (branch_taken)
);

// ============================================================
// WB MUX  (defined early — used in forwarding below)
// ============================================================
assign wb_data = (mem_wb_wb_sel == 2'd1) ? mem_wb_mem_data :
                 (mem_wb_wb_sel == 2'd2) ? mem_wb_pc4      :
                 mem_wb_alu_result;

// HOLD stage forward value: if it was a load, the data is in block RAM
// output register (mem_data_out); otherwise use the ALU result.
wire [31:0] hold_fwd_val = hold_mem_read ? mem_data_out : hold_alu_result;

// ============================================================
// ID STAGE FORWARDING
// Branch comparator sits in ID. Forward from EX/MEM, HOLD, then WB.
// Same hold_fwd_val logic as EX stage (load vs ALU).
// ============================================================
assign id_rd1_fwd =
    (ex_mem_reg_write && ex_mem_rd  != 5'd0 && ex_mem_rd  == id_rs1) ? ex_mem_alu_result :
    (hold_reg_write   && hold_rd    != 5'd0 && hold_rd    == id_rs1) ? hold_fwd_val      :
    (mem_wb_reg_write && mem_wb_rd  != 5'd0 && mem_wb_rd  == id_rs1) ? wb_data           :
    id_rd1_raw;

assign id_rd2_fwd =
    (ex_mem_reg_write && ex_mem_rd  != 5'd0 && ex_mem_rd  == id_rs2) ? ex_mem_alu_result :
    (hold_reg_write   && hold_rd    != 5'd0 && hold_rd    == id_rs2) ? hold_fwd_val      :
    (mem_wb_reg_write && mem_wb_rd  != 5'd0 && mem_wb_rd  == id_rs2) ? wb_data           :
    id_rd2_raw;

// ============================================================
// IF STAGE
// ============================================================
assign pc_plus4       = pc + 32'd4;
wire [31:0] branch_target = if_id_pc + id_imm;
wire [31:0] jalr_target   = (id_rd1_fwd + id_imm) & ~32'd1;

wire flush_if_id = (id_branch && branch_taken) || id_jump || id_jumpr;
wire flush_id_ex = (id_branch && branch_taken);

wire [31:0] pc_next = flush_if_id ? (id_jumpr ? jalr_target : branch_target)
                                   : pc_plus4;

// flush overrides stall so branch/jump always redirects PC
always @(posedge clk or posedge rst) begin
    if (rst)
        pc <= 32'd0;
    else if (flush_if_id || pc_write_en)
        pc <= pc_next;
end

// ============================================================
// IF/ID PIPELINE REGISTER
// ============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        if_id_pc    <= 32'd0;
        if_id_instr <= 32'h0000_0013;
    end else if (flush_if_id) begin
        if_id_pc    <= 32'd0;
        if_id_instr <= 32'h0000_0013;
    end else if (if_id_write_en) begin
        if_id_pc    <= pc;
        if_id_instr <= instr_if;
    end
end

// ============================================================
// ID/EX PIPELINE REGISTER
// ============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        id_ex_pc        <= 32'd0;
        id_ex_rd1       <= 32'd0;
        id_ex_rd2       <= 32'd0;
        id_ex_imm       <= 32'd0;
        id_ex_rs1       <= 5'd0;
        id_ex_rs2       <= 5'd0;
        id_ex_rd        <= 5'd0;
        id_ex_reg_write <= 1'b0;
        id_ex_mem_read  <= 1'b0;
        id_ex_mem_write <= 1'b0;
        id_ex_alu_src   <= 2'd0;
        id_ex_wb_sel    <= 2'd0;
        id_ex_alu_ctrl  <= 4'd0;
    end else if (flush_id_ex || stall) begin
        id_ex_pc        <= 32'd0;
        id_ex_rd1       <= 32'd0;
        id_ex_rd2       <= 32'd0;
        id_ex_imm       <= 32'd0;
        id_ex_rs1       <= 5'd0;
        id_ex_rs2       <= 5'd0;
        id_ex_rd        <= 5'd0;
        id_ex_reg_write <= 1'b0;
        id_ex_mem_read  <= 1'b0;
        id_ex_mem_write <= 1'b0;
        id_ex_alu_src   <= 2'd0;
        id_ex_wb_sel    <= 2'd0;
        id_ex_alu_ctrl  <= 4'd0;
    end else begin
        id_ex_pc        <= if_id_pc;
        id_ex_rd1       <= id_rd1_fwd;
        id_ex_rd2       <= id_rd2_fwd;
        id_ex_imm       <= id_imm;
        id_ex_rs1       <= id_rs1;
        id_ex_rs2       <= id_rs2;
        id_ex_rd        <= id_rd;
        id_ex_reg_write <= id_reg_write;
        id_ex_mem_read  <= id_mem_read;
        id_ex_mem_write <= id_mem_write;
        id_ex_alu_src   <= id_alu_src;
        id_ex_wb_sel    <= id_wb_sel;
        id_ex_alu_ctrl  <= id_alu_ctrl;
    end
end

// ============================================================
// EX STAGE
// fwd_a/b: 00=reg, 01=EX/MEM, 10=HOLD, 11=MEM/WB
// hold_fwd_val is declared near the WB mux above.
// ============================================================
assign ex_alu_a     = (fwd_a == 2'b01) ? ex_mem_alu_result :
                      (fwd_a == 2'b10) ? hold_fwd_val      :
                      (fwd_a == 2'b11) ? wb_data           :
                      id_ex_rd1;

assign ex_alu_b_pre = (fwd_b == 2'b01) ? ex_mem_alu_result :
                      (fwd_b == 2'b10) ? hold_fwd_val      :
                      (fwd_b == 2'b11) ? wb_data           :
                      id_ex_rd2;

assign ex_alu_b     = (id_ex_alu_src == 2'd1) ? id_ex_imm : ex_alu_b_pre;

// ============================================================
// EX/MEM PIPELINE REGISTER
// ============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        ex_mem_pc4        <= 32'd0;
        ex_mem_alu_result <= 32'd0;
        ex_mem_rd2        <= 32'd0;
        ex_mem_rd         <= 5'd0;
        ex_mem_reg_write  <= 1'b0;
        ex_mem_mem_read   <= 1'b0;
        ex_mem_mem_write  <= 1'b0;
        ex_mem_wb_sel     <= 2'd0;
    end else begin
        ex_mem_pc4        <= id_ex_pc + 32'd4;
        ex_mem_alu_result <= ex_alu_result;
        ex_mem_rd2        <= ex_alu_b_pre;
        ex_mem_rd         <= id_ex_rd;
        ex_mem_reg_write  <= id_ex_reg_write;
        ex_mem_mem_read   <= id_ex_mem_read;
        ex_mem_mem_write  <= id_ex_mem_write;
        ex_mem_wb_sel     <= id_ex_wb_sel;
    end
end

// ============================================================
// MEM STAGE
// data_mem address/control driven by EX/MEM register outputs.
// data_mem registers its output at the NEXT posedge (block RAM).
// ============================================================

// ============================================================
// HOLD REGISTER
// Captures ex_mem_* control signals at the same posedge that
// data_mem captures its address.  One cycle later (MEM/WB
// posedge) hold_* and data_mem.rd are both valid together.
// ============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        hold_pc4        <= 32'd0;
        hold_alu_result <= 32'd0;
        hold_rd         <= 5'd0;
        hold_reg_write  <= 1'b0;
        hold_mem_read   <= 1'b0;
        hold_wb_sel     <= 2'd0;
    end else begin
        hold_pc4        <= ex_mem_pc4;
        hold_alu_result <= ex_mem_alu_result;
        hold_rd         <= ex_mem_rd;
        hold_reg_write  <= ex_mem_reg_write;
        hold_mem_read   <= ex_mem_mem_read;
        hold_wb_sel     <= ex_mem_wb_sel;
    end
end

// ============================================================
// MEM/WB PIPELINE REGISTER
// hold_* and data_mem.rd are both available here (aligned).
// ============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        mem_wb_alu_result <= 32'd0;
        mem_wb_mem_data   <= 32'd0;
        mem_wb_pc4        <= 32'd0;
        mem_wb_rd         <= 5'd0;
        mem_wb_reg_write  <= 1'b0;
        mem_wb_wb_sel     <= 2'd0;
    end else begin
        mem_wb_alu_result <= hold_alu_result;
        mem_wb_mem_data   <= mem_data_out;    // block RAM output reg, valid this cycle
        mem_wb_pc4        <= hold_pc4;
        mem_wb_rd         <= hold_rd;
        mem_wb_reg_write  <= hold_reg_write;
        mem_wb_wb_sel     <= hold_wb_sel;
    end
end

// ============================================================
// DEBUG OUTPUTS
// ============================================================
assign dbg_pc         = pc;
assign dbg_instr      = if_id_instr;
assign dbg_wb_rd      = mem_wb_rd;
assign dbg_wb_data    = wb_data;
assign dbg_wb_en      = mem_wb_reg_write;
assign dbg_dmem_addr  = ex_mem_alu_result;
assign dbg_dmem_wdata = ex_mem_rd2;
assign dbg_dmem_we    = ex_mem_mem_write;

endmodule
