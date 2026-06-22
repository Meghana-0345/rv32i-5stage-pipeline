// ============================================================
// Control Unit - Decodes opcode and funct fields
// ============================================================
module control_unit (
    input  [6:0] opcode,
    input  [2:0] funct3,
    input  [6:0] funct7,
    output reg       reg_write,
    output reg       mem_read,
    output reg       mem_write,
    output reg       branch,
    output reg       jump,       // JAL
    output reg       jumpr,      // JALR
    output reg [1:0] alu_src,    // 0=reg, 1=imm, 2=PC+4(JAL)
    output reg [1:0] wb_sel,     // 0=alu, 1=mem, 2=pc+4
    output reg [3:0] alu_ctrl,
    output reg [2:0] branch_type // 000=BEQ,001=BNE,100=BLT,101=BGE
);

    // Opcodes
    localparam OP_R      = 7'b0110011;
    localparam OP_I      = 7'b0010011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;

    // ALU ctrl codes (match alu.v)
    localparam ALU_ADD  = 4'd0;
    localparam ALU_SUB  = 4'd1;
    localparam ALU_AND  = 4'd2;
    localparam ALU_OR   = 4'd3;
    localparam ALU_XOR  = 4'd4;
    localparam ALU_SLT  = 4'd5;
    localparam ALU_SLTU = 4'd6;
    localparam ALU_SLL  = 4'd7;
    localparam ALU_SRL  = 4'd8;
    localparam ALU_SRA  = 4'd9;
    localparam ALU_LUI  = 4'd10;

    always @(*) begin
        // Safe defaults
        reg_write   = 0;
        mem_read    = 0;
        mem_write   = 0;
        branch      = 0;
        jump        = 0;
        jumpr       = 0;
        alu_src     = 2'd0;
        wb_sel      = 2'd0;
        alu_ctrl    = ALU_ADD;
        branch_type = funct3;

        case (opcode)
            // R-type
            OP_R: begin
                reg_write = 1;
                alu_src   = 2'd0;
                wb_sel    = 2'd0;
                case ({funct7[5], funct3})
                    4'b0000: alu_ctrl = ALU_ADD;
                    4'b1000: alu_ctrl = ALU_SUB;
                    4'b0001: alu_ctrl = ALU_SLL;
                    4'b0010: alu_ctrl = ALU_SLT;
                    4'b0011: alu_ctrl = ALU_SLTU;
                    4'b0100: alu_ctrl = ALU_XOR;
                    4'b0101: alu_ctrl = ALU_SRL;
                    4'b1101: alu_ctrl = ALU_SRA;
                    4'b0110: alu_ctrl = ALU_OR;
                    4'b0111: alu_ctrl = ALU_AND;
                    default: alu_ctrl = ALU_ADD;
                endcase
            end

            // I-type ALU
            OP_I: begin
                reg_write = 1;
                alu_src   = 2'd1;
                wb_sel    = 2'd0;
                case (funct3)
                    3'b000: alu_ctrl = ALU_ADD;  // ADDI
                    3'b010: alu_ctrl = ALU_SLT;  // SLTI
                    3'b011: alu_ctrl = ALU_SLTU; // SLTIU
                    3'b100: alu_ctrl = ALU_XOR;  // XORI
                    3'b110: alu_ctrl = ALU_OR;   // ORI
                    3'b111: alu_ctrl = ALU_AND;  // ANDI
                    3'b001: alu_ctrl = ALU_SLL;  // SLLI
                    3'b101: alu_ctrl = (funct7[5]) ? ALU_SRA : ALU_SRL;
                    default: alu_ctrl = ALU_ADD;
                endcase
            end

            // Load
            OP_LOAD: begin
                reg_write = 1;
                mem_read  = 1;
                alu_src   = 2'd1;
                wb_sel    = 2'd1;
                alu_ctrl  = ALU_ADD;
            end

            // Store
            OP_STORE: begin
                mem_write = 1;
                alu_src   = 2'd1;
                alu_ctrl  = ALU_ADD;
            end

            // Branch
            OP_BRANCH: begin
                branch      = 1;
                alu_src     = 2'd0;
                alu_ctrl    = ALU_SUB;
                branch_type = funct3;
            end

            // JAL
            OP_JAL: begin
                reg_write = 1;
                jump      = 1;
                wb_sel    = 2'd2;  // write PC+4
                alu_ctrl  = ALU_ADD;
            end

            // JALR
            OP_JALR: begin
                reg_write = 1;
                jumpr     = 1;
                alu_src   = 2'd1;
                wb_sel    = 2'd2;  // write PC+4
                alu_ctrl  = ALU_ADD;
            end

            // LUI
            OP_LUI: begin
                reg_write = 1;
                alu_src   = 2'd1;
                wb_sel    = 2'd0;
                alu_ctrl  = ALU_LUI;
            end

            // AUIPC
            OP_AUIPC: begin
                reg_write = 1;
                alu_src   = 2'd1;
                wb_sel    = 2'd0;
                alu_ctrl  = ALU_ADD;
            end

            default: begin
                // NOP / unknown
            end
        endcase
    end

endmodule
