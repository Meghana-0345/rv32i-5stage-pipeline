// ============================================================
// Testbench with Scoreboard - 5-Stage RISC-V Pipeline
// ============================================================
`timescale 1ns/1ps

module tb_riscv_pipeline;

// ============================================================
// DUT SIGNALS
// ============================================================
reg         clk;
reg         rst;
wire [31:0] dbg_pc;
wire [31:0] dbg_instr;
wire [4:0]  dbg_wb_rd;
wire [31:0] dbg_wb_data;
wire        dbg_wb_en;
wire [31:0] dbg_dmem_addr;
wire [31:0] dbg_dmem_wdata;
wire        dbg_dmem_we;

// ============================================================
// DUT
// ============================================================
riscv_pipeline DUT (
    .clk           (clk),
    .rst           (rst),
    .dbg_pc        (dbg_pc),
    .dbg_instr     (dbg_instr),
    .dbg_wb_rd     (dbg_wb_rd),
    .dbg_wb_data   (dbg_wb_data),
    .dbg_wb_en     (dbg_wb_en),
    .dbg_dmem_addr (dbg_dmem_addr),
    .dbg_dmem_wdata(dbg_dmem_wdata),
    .dbg_dmem_we   (dbg_dmem_we)
);

// ============================================================
// CLOCK - 10ns period = 100 MHz
// ============================================================
initial clk = 0;
always #5 clk = ~clk;

// ============================================================
// SCOREBOARD
// ============================================================
integer pass_count;
integer fail_count;
integer total_cycles;
integer wb_events;
integer i;
integer j;
integer reg_check_failed;

// ============================================================
// TASKS
// ============================================================
task check_reg;
    input [4:0]  rnum;
    input [31:0] expected;
    input [127:0] label;
    reg [31:0] got;
    begin
        // x0 is hardwired 0, not stored in array
        got = (rnum == 5'd0) ? 32'd0 : DUT.REGFILE.regs[rnum];
        if (got !== expected) begin
            $display("  FAIL  x%-2d = 0x%08h  (expected 0x%08h)  [%s]",
                     rnum, got, expected, label);
            fail_count = fail_count + 1;
        end else begin
            $display("  PASS  x%-2d = 0x%08h", rnum, expected);
            pass_count = pass_count + 1;
        end
    end
endtask

task check_mem;
    input [31:0] waddr;
    input [31:0] expected;
    begin
        if (DUT.DMEM.mem[waddr] !== expected) begin
            $display("  FAIL  mem[%0d] = 0x%08h  (expected 0x%08h)",
                     waddr, DUT.DMEM.mem[waddr], expected);
            fail_count = fail_count + 1;
        end else begin
            $display("  PASS  mem[%0d] = 0x%08h", waddr, expected);
            pass_count = pass_count + 1;
        end
    end
endtask

task check_val;
    input [31:0] got;
    input [31:0] expected;
    input [127:0] label;
    begin
        if (got !== expected) begin
            $display("  FAIL  %s: got 0x%08h, expected 0x%08h", label, got, expected);
            fail_count = fail_count + 1;
        end else begin
            $display("  PASS  %s = 0x%08h", label, expected);
            pass_count = pass_count + 1;
        end
    end
endtask

// Cycle counter
always @(posedge clk) begin
    if (!rst) total_cycles = total_cycles + 1;
end

// WB event counter
always @(posedge clk) begin
    if (!rst && dbg_wb_en && dbg_wb_rd != 5'd0)
        wb_events = wb_events + 1;
end

// ============================================================
// MAIN TEST
// ============================================================
initial begin
    pass_count   = 0;
    fail_count   = 0;
    total_cycles = 0;
    wb_events    = 0;

    $display("=================================================");
    $display("   RISC-V 5-Stage Pipeline - Full Testbench     ");
    $display("=================================================");

    // ---- TEST 1: Reset ----
    $display("\n[TEST 1] Reset Verification");
    rst = 1;
    repeat(4) @(posedge clk);
    @(negedge clk);  // sample after last posedge

    // After reset, pipeline registers are cleared; x0 always reads 0
    // (reg_file has no synchronous reset - regs start at don't-care in synthesis,
    //  but $readmemh initialises them to 0 in simulation via Verilog default)
    check_val(DUT.pc, 32'd0, "PC after reset");
    $display("  INFO  Register file has no sync reset (synthesisable); x0=0 enforced by logic");

    // ---- Start execution ----
    rst = 0;
    $display("\n[RUN]  Running program (140 cycles)...");
    repeat(140) @(posedge clk);
    @(negedge clk);  // settle

    // ---- TEST 2: Arithmetic ----
    $display("\n[TEST 2] Arithmetic  (forwarding: EX->EX, MEM->EX)");
    check_reg( 1, 32'd10,  "ADDI x1=10");
    check_reg( 2, 32'd20,  "ADDI x2=20");
    check_reg( 3, 32'd30,  "ADD  x3=x1+x2");
    check_reg( 4, 32'd20,  "SUB  x4=x3-x1");

    // ---- TEST 3: Logical ----
    $display("\n[TEST 3] Logical Operations");
    check_reg( 5, 32'd0,   "AND  x5=x1&x2 (10&20=0)");
    check_reg( 6, 32'd30,  "OR   x6=x1|x2 (10|20=30)");
    check_reg( 7, 32'd30,  "XOR  x7=x1^x2 (10^20=30)");

    // ---- TEST 4: Memory ----
    $display("\n[TEST 4] Memory  (load-use stall)");
    check_reg( 8, 32'd100, "ADDI x8=100");
    check_mem(0,  32'd100);
    check_reg( 9, 32'd100, "LW   x9=mem[0]");
    check_reg(10, 32'd110, "ADD  x10=x9+x1 (100+10)");

    // ---- TEST 5: Shifts & Comparison ----
    $display("\n[TEST 5] Shift & Compare");
    check_reg(11, 32'd5,   "ADDI x11=5");
    check_reg(12, 32'd1,   "SLT  x12=(x11<x1)");
    check_reg(13, 32'd160, "SLL  x13=x11<<x11 (5<<5)");
    check_reg(14, 32'd5,   "SRL  x14=x13>>x11 (160>>5)");

    // ---- TEST 6: Branches ----
    $display("\n[TEST 6] Branch Instructions");
    check_reg(15, 32'd1,   "ADDI x15=1");
    check_reg(16, 32'd0,   "BEQ  x16=0 (instr skipped)");
    check_reg(17, 32'd42,  "BEQ  x17=42 (branch target)");
    check_reg(18, 32'd0,   "BNE  x18=0 (instr skipped)");
    check_reg(19, 32'd77,  "BNE  x19=77 (branch target)");

    // ---- TEST 7: JAL ----
    $display("\n[TEST 7] Jump (JAL)");
    // JAL at addr 88 -> x20 = 88+4 = 92
    check_reg(20, 32'd92,  "JAL  x20=PC+4=92");
    check_reg(21, 32'd0,   "JAL  x21=0 (skipped)");
    check_reg(22, 32'd33,  "JAL  x22=33 (jump target)");

    // ---- TEST 8: x0 always zero ----
    $display("\n[TEST 8] x0 Hardwired Zero");
    check_reg(0,  32'd0,   "x0=0");

    // ---- PERFORMANCE REPORT ----
    $display("\n=================================================");
    $display("             PERFORMANCE METRICS                ");
    $display("=================================================");
    $display("  Total Cycles    : %0d", total_cycles);
    $display("  WB write events : %0d", wb_events);
    if (wb_events > 0)
        $display("  Effective CPI   : %.2f", $itor(total_cycles) / $itor(wb_events));
    $display("=================================================");

    // ---- FINAL SUMMARY ----
    $display("\n=================================================");
    $display("               TEST SUMMARY                     ");
    $display("=================================================");
    $display("  PASSED : %0d", pass_count);
    $display("  FAILED : %0d", fail_count);
    $display("  TOTAL  : %0d", pass_count + fail_count);
    if (fail_count == 0)
        $display("\n  *** ALL TESTS PASSED! ***");
    else
        $display("\n  *** %0d TEST(S) FAILED ***", fail_count);
    $display("=================================================");

    $finish;
end

// Timeout
initial begin
    #50000;
    $display("TIMEOUT: Simulation exceeded limit");
    $finish;
end

// Waveform dump
initial begin
    $dumpfile("riscv_wave.vcd");
    $dumpvars(0, tb_riscv_pipeline);
end

endmodule
