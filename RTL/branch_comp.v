// ============================================================
// Branch Comparator - Evaluates branch condition in ID stage
// ============================================================
module branch_comp (
    input  [31:0] a,
    input  [31:0] b,
    input  [2:0]  branch_type,
    output reg    taken
);

    always @(*) begin
        case (branch_type)
            3'b000: taken = (a == b);                         // BEQ
            3'b001: taken = (a != b);                         // BNE
            3'b100: taken = ($signed(a) < $signed(b));        // BLT
            3'b101: taken = ($signed(a) >= $signed(b));       // BGE
            3'b110: taken = (a < b);                          // BLTU
            3'b111: taken = (a >= b);                         // BGEU
            default: taken = 0;
        endcase
    end

endmodule
