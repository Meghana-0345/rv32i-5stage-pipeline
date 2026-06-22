// ============================================================
// Instruction Memory  –  256 x 32-bit ROM
//
// Implemented as a COMBINATORIAL CASE STATEMENT.
// There is NO reg/mem array here — Quartus synthesises this
// as pure LUT logic.  No RAM inference, no MIF file, no
// block-RAM limitations.
//
// Program is hardcoded in the case arms below.
// No external .hex file is required.
// ============================================================
module instr_mem (
    input      [31:0] addr,
    output reg [31:0] instr
);

    always @(*) begin
        case (addr[9:2])   // word index = byte_addr >> 2
            //----------------------------------------------------
            // Addr   0: ADDI x1,  x0, 10      x1  = 10
            8'd0  : instr = 32'h00a00093;
            // Addr   4: ADDI x2,  x0, 20      x2  = 20
            8'd1  : instr = 32'h01400113;
            // Addr   8: ADD  x3,  x1, x2      x3  = 30
            8'd2  : instr = 32'h002081b3;
            // Addr  12: SUB  x4,  x3, x1      x4  = 20
            8'd3  : instr = 32'h40118233;
            // Addr  16: AND  x5,  x1, x2      x5  =  0
            8'd4  : instr = 32'h0020f2b3;
            // Addr  20: OR   x6,  x1, x2      x6  = 30
            8'd5  : instr = 32'h0020e333;
            // Addr  24: XOR  x7,  x1, x2      x7  = 30
            8'd6  : instr = 32'h0020c3b3;
            // Addr  28: ADDI x8,  x0, 100     x8  = 100
            8'd7  : instr = 32'h06400413;
            // Addr  32: SW   x8,  0(x0)       mem[0] = 100
            8'd8  : instr = 32'h00802023;
            // Addr  36: LW   x9,  0(x0)       x9  = 100
            8'd9  : instr = 32'h00002483;
            // Addr  40: ADD  x10, x9,  x1     x10 = 110
            8'd10 : instr = 32'h00148533;
            // Addr  44: ADDI x11, x0,  5      x11 =   5
            8'd11 : instr = 32'h00500593;
            // Addr  48: SLT  x12, x11, x1     x12 =   1
            8'd12 : instr = 32'h0015a633;
            // Addr  52: SLL  x13, x11, x11    x13 = 160
            8'd13 : instr = 32'h00b596b3;
            // Addr  56: SRL  x14, x13, x11    x14 =   5
            8'd14 : instr = 32'h00b6d733;
            // Addr  60: ADDI x15, x0,  1      x15 =   1
            8'd15 : instr = 32'h00100793;
            // Addr  64: BEQ  x15, x15, +8     branch -> addr 72
            8'd16 : instr = 32'h00f78463;
            // Addr  68: ADDI x16, x0,  99     *** SKIPPED by BEQ ***
            8'd17 : instr = 32'h06300813;
            // Addr  72: ADDI x17, x0,  42     x17 =  42
            8'd18 : instr = 32'h02a00893;
            // Addr  76: BNE  x15, x2,  +8     branch -> addr 84
            8'd19 : instr = 32'h00279463;
            // Addr  80: ADDI x18, x0,  88     *** SKIPPED by BNE ***
            8'd20 : instr = 32'h05800913;
            // Addr  84: ADDI x19, x0,  77     x19 =  77
            8'd21 : instr = 32'h04d00993;
            // Addr  88: JAL  x20, +8          x20 =  92, jump -> addr 96
            8'd22 : instr = 32'h00800a6f;
            // Addr  92: ADDI x21, x0,  55     *** SKIPPED by JAL ***
            8'd23 : instr = 32'h03700a93;
            // Addr  96: ADDI x22, x0,  33     x22 =  33
            8'd24 : instr = 32'h02100b13;
            //----------------------------------------------------
            // All other addresses: NOP
            default: instr = 32'h00000013;
        endcase
    end

endmodule
