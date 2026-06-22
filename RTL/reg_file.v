// ============================================================
// Register File  –  32 x 32-bit  (plain flip-flops)
//
// The (* ramstyle = "logic" *) attribute tells Quartus
// explicitly: do NOT use block RAM, use logic cells / FFs.
// This eliminates the "uninferred RAM / MIF" error entirely.
//
// Reads are combinatorial (async).  Writes are synchronous.
// x0 is hardwired to 0 at the read mux; regs[0] is never written.
// ============================================================
module reg_file (
    input         clk,
    input  [4:0]  rs1,
    input  [4:0]  rs2,
    input  [4:0]  rd,
    input  [31:0] wd,
    input         reg_write,
    output [31:0] rd1,
    output [31:0] rd2
);

    (* ramstyle = "logic" *)   // Quartus: force FF inference, no M10K
    reg [31:0] regs [0:31];

    // Simulation init (synthesis ignored)
    integer k;
    initial begin
        for (k = 0; k < 32; k = k + 1)
            regs[k] = 32'd0;
    end

    // Combinatorial read; x0 always 0
    assign rd1 = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
    assign rd2 = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

    // Synchronous write; never write x0
    always @(posedge clk) begin
        if (reg_write && (rd != 5'd0))
            regs[rd] <= wd;
    end

endmodule
