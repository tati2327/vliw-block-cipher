`timescale 1ns/1ps

// ISA §6.1; microarchitecture.md §§3.2, 4.3, 4.8.
// Decodificador combinacional de los slots 0 y 1. Códigos libres = nopi.
module alu_dec (input  logic [4:0] funct,
                output logic [3:0] alu_op, output logic use_imm, output logic we);
    // Codificación interna oficial (§4.8), distinta del funct del ISA.
    localparam logic [3:0] ALU_ADD = 4'b0000, ALU_SUB = 4'b0001,
        ALU_AND = 4'b0010, ALU_OR = 4'b0011, ALU_XOR = 4'b0100,
        ALU_SLL = 4'b0101, ALU_SRL = 4'b0110, ALU_SRA = 4'b0111,
        ALU_SLT = 4'b1000, ALU_SLE = 4'b1001, ALU_SEQ = 4'b1010,
        ALU_SNE = 4'b1011, ALU_IFMOV = 4'b1100, ALU_PASS = 4'b1101;

    // microarchitecture.md §3.2 — el bit alto separa formato R (0) de I (1).
    // Con assign: Icarus no admite selecciones constantes dentro de always_comb.
    assign use_imm = funct[4];

    // microarchitecture.md §3.2 y tabla alu_dec de §4.8.
    always_comb begin
        alu_op = ALU_ADD;
        we     = 1'b0;
        case (funct)
            5'b00001: begin alu_op = ALU_ADD;   we = 1'b1; end // add
            5'b00010: begin alu_op = ALU_SUB;   we = 1'b1; end // sub
            5'b00011: begin alu_op = ALU_AND;   we = 1'b1; end // and
            5'b00100: begin alu_op = ALU_OR;    we = 1'b1; end // or
            5'b00101: begin alu_op = ALU_XOR;   we = 1'b1; end // xor
            5'b00110: begin alu_op = ALU_SLL;   we = 1'b1; end // sll
            5'b00111: begin alu_op = ALU_SRL;   we = 1'b1; end // srl
            5'b01000: begin alu_op = ALU_SRA;   we = 1'b1; end // sra
            5'b01001: begin alu_op = ALU_SLT;   we = 1'b1; end // slt
            5'b01010: begin alu_op = ALU_SLE;   we = 1'b1; end // sle
            5'b01011: begin alu_op = ALU_SEQ;   we = 1'b1; end // seq
            5'b01100: begin alu_op = ALU_SNE;   we = 1'b1; end // sne
            5'b01101: begin alu_op = ALU_IFMOV; we = 1'b1; end // ifmov
            5'b10000: begin alu_op = ALU_ADD;   we = 1'b1; end // saddi
            5'b10001: begin alu_op = ALU_XOR;   we = 1'b1; end // xori
            5'b10010: begin alu_op = ALU_PASS;  we = 1'b1; end // mov
            default: ; // nopi y códigos libres
        endcase
    end
endmodule
