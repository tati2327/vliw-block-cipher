`timescale 1ns/1ps

// ISA §6.2; microarchitecture.md §§3.8, 4.3, 4.8.
module bru_dec (
    input  logic [4:0] funct,
    output logic [2:0] br_op,
    output logic we
);
    // Codificación interna oficial, distinta del funct del ISA.
    localparam logic [2:0] BR_NONE = 3'b000, BR_BEQ = 3'b001,
        BR_BNE = 3'b010, BR_BLT = 3'b011, BR_BGE = 3'b100,
        BR_JEF = 3'b101, BR_JAS = 3'b110, BR_JEFR = 3'b111;

    always_comb begin
        br_op = BR_NONE;
        we = 1'b0;
        case (funct)
            5'b00001: br_op = BR_BEQ;
            5'b00010: br_op = BR_BNE;
            5'b00011: br_op = BR_BLT;
            5'b00100: br_op = BR_BGE;
            5'b00101: begin br_op = BR_JEFR; we = 1'b1; end
            5'b10000: br_op = BR_JEF;
            5'b10001: begin br_op = BR_JAS; we = 1'b1; end
            default: ; // nopi y códigos libres
        endcase
    end
endmodule
