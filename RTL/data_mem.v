// ============================================================
// Data Memory  –  1024 x 32-bit words
//
// Written for Quartus Cyclone V M10K block RAM inference.
// Rules for clean single-port M10K inference:
//   1. Synchronous write
//   2. Synchronous read — NO conditional gating on the read
//      (gating prevents RAM inference; use the output instead)
//   3. Read and write in the same always block
//
// The output `rd` is the registered block-RAM output.
// The HOLD pipeline stage in riscv_pipeline.v absorbs the
// 1-cycle read latency.
// ============================================================
module data_mem (
    input             clk,
    input      [9:0]  addr,      // word address (bits [11:2] of byte addr)
    input      [31:0] wd,
    input             mem_write,
    output reg [31:0] rd
);

    reg [31:0] mem [0:1023];

    // Synchronous read + write in one always block
    // No conditional on read — this is the Quartus M10K pattern
    always @(posedge clk) begin
        if (mem_write)
            mem[addr] <= wd;
        rd <= mem[addr];
    end

endmodule
