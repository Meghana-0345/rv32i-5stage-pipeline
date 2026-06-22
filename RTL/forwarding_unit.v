// ============================================================
// Forwarding Unit
// Resolves RAW data hazards for ALU inputs in the EX stage.
//
// Three forwarding sources (most recent wins):
//   2'b01 = EX/MEM  stage  (1 cycle behind EX)
//   2'b10 = HOLD    stage  (2 cycles behind EX) [extra stage for sync data_mem]
//   2'b11 = MEM/WB  stage  (3 cycles behind EX)
//   2'b00 = no forwarding  (use value from ID/EX register)
// ============================================================
module forwarding_unit (
    input  [4:0] ex_rs1,
    input  [4:0] ex_rs2,
    // EX/MEM stage
    input  [4:0] mem_rd,
    input        mem_reg_write,
    // HOLD stage (between EX/MEM and MEM/WB)
    input  [4:0] hold_rd,
    input        hold_reg_write,
    // MEM/WB stage
    input  [4:0] wb_rd,
    input        wb_reg_write,
    output reg [1:0] fwd_a,
    output reg [1:0] fwd_b
);

    always @(*) begin
        // --- Forward A ---
        if (mem_reg_write  && (mem_rd  != 5'd0) && (mem_rd  == ex_rs1))
            fwd_a = 2'b01;   // EX/MEM
        else if (hold_reg_write && (hold_rd != 5'd0) && (hold_rd == ex_rs1))
            fwd_a = 2'b10;   // HOLD
        else if (wb_reg_write  && (wb_rd   != 5'd0) && (wb_rd   == ex_rs1))
            fwd_a = 2'b11;   // MEM/WB
        else
            fwd_a = 2'b00;

        // --- Forward B ---
        if (mem_reg_write  && (mem_rd  != 5'd0) && (mem_rd  == ex_rs2))
            fwd_b = 2'b01;
        else if (hold_reg_write && (hold_rd != 5'd0) && (hold_rd == ex_rs2))
            fwd_b = 2'b10;
        else if (wb_reg_write  && (wb_rd   != 5'd0) && (wb_rd   == ex_rs2))
            fwd_b = 2'b11;
        else
            fwd_b = 2'b00;
    end

endmodule
