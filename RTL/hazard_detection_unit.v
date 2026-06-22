// ============================================================
// Hazard Detection Unit
//
// Detects two hazard types that require pipeline stalls:
//
// 1. Load-use hazard:
//    LW in EX (id_ex stage) and the following instruction in ID
//    reads the same register.  Insert 1 bubble.
//    (After the stall, HOLD->EX forwarding delivers the data.)
//
// 2. Branch data hazard:
//    A branch in ID whose source register is produced by the
//    instruction currently in EX (id_ex stage).
//    Insert 1 bubble so the result reaches EX/MEM where
//    EX/MEM->ID forwarding can deliver it to the branch comparator.
// ============================================================
module hazard_detection_unit (
    input  [4:0] id_rs1,
    input  [4:0] id_rs2,
    input  [4:0] ex_rd,          // rd of instruction in EX (ID/EX reg)
    input        ex_mem_read,    // EX instruction is a load
    input        id_branch,      // instruction in ID is a branch
    // Not used for stall decisions — kept for potential extension
    input  [4:0] ex_mem_rd,
    input        ex_mem_reg_write,
    output reg   stall,
    output reg   pc_write,       // 0 = freeze PC
    output reg   if_id_write     // 0 = freeze IF/ID register
);

    always @(*) begin
        stall       = 1'b0;
        pc_write    = 1'b1;
        if_id_write = 1'b1;

        // Load-use: EX stage is a load and its rd matches rs1 or rs2 in ID
        if (ex_mem_read && (ex_rd != 5'd0) &&
            ((ex_rd == id_rs1) || (ex_rd == id_rs2))) begin
            stall       = 1'b1;
            pc_write    = 1'b0;
            if_id_write = 1'b0;
        end

        // Branch data hazard: instruction in EX writes rs1 or rs2 of a branch in ID
        if (id_branch && (ex_rd != 5'd0) &&
            ((ex_rd == id_rs1) || (ex_rd == id_rs2))) begin
            stall       = 1'b1;
            pc_write    = 1'b0;
            if_id_write = 1'b0;
        end
    end

endmodule
