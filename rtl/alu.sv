`timescale 1ns/1ps

// ISA §5.2; microarchitecture.md §§3.3, 4.3, 4.8.
// ALU combinacional de 32 bits. Dos instancias idénticas (slots 0 y 1).
module alu (input  logic [31:0] a, b, imm, input logic [3:0] alu_op, input logic use_imm,
            output logic [31:0] y, output logic cond_ok);
    // Codificación interna oficial (§4.8), la misma de alu_dec.
    localparam logic [3:0] ALU_ADD = 4'b0000, ALU_SUB = 4'b0001,
        ALU_AND = 4'b0010, ALU_OR = 4'b0011, ALU_XOR = 4'b0100,
        ALU_SLL = 4'b0101, ALU_SRL = 4'b0110, ALU_SRA = 4'b0111,
        ALU_SLT = 4'b1000, ALU_SLE = 4'b1001, ALU_SEQ = 4'b1010,
        ALU_SNE = 4'b1011, ALU_IFMOV = 4'b1100, ALU_PASS = 4'b1101;

    logic [31:0] op2, x, r;
    logic        resta;
    logic        n, z, v;
    logic        slt, sle, seq, sne;
    logic [31:0] y_and, y_or, y_xor;
    logic [4:0]  sh;
    logic [31:0] y_sll, y_srl, y_sra;

    // microarchitecture.md §3.3 — MUX de op2.
    always_comb begin
        op2 = b;
        if (use_imm) op2 = imm;
    end

    // microarchitecture.md §3.3 — sumador/restador.
    always_comb begin
        resta = 1'b0;
        case (alu_op)
            ALU_SUB, ALU_SLT, ALU_SLE, ALU_SEQ, ALU_SNE: resta = 1'b1;
            default: ;
        endcase
        x = op2;
        if (resta) x = ~op2;
        r = a + x + {31'b0, resta};
    end

    // microarchitecture.md §3.3 — banderas.
    // Con assign: Icarus no admite selecciones constantes dentro de always_comb.
    assign n = r[31];
    assign z = (r == 32'b0);
    assign v = (a[31] == x[31]) & (r[31] != a[31]);

    // microarchitecture.md §3.3 — comparador, con signo y corregido por desbordamiento.
    always_comb begin
        slt = n ^ v;
        sle = slt | z;
        seq = z;
        sne = ~z;
    end

    // microarchitecture.md §3.3 — bloque lógico.
    always_comb begin
        y_and = a & op2;
        y_or  = a | op2;
        y_xor = a ^ op2;
    end

    // microarchitecture.md §3.3 — desplazador de barril; solo los 5 bits bajos (C-03).
    assign sh = op2[4:0];

    always_comb begin
        y_sll = a << sh;
        y_srl = a >> sh;
        y_sra = $signed(a) >>> sh;
    end

    // microarchitecture.md §3.3 — MUX de resultado.
    always_comb begin
        y = 32'b0;
        case (alu_op)
            ALU_ADD, ALU_SUB: y = r;
            ALU_AND:          y = y_and;
            ALU_OR:           y = y_or;
            ALU_XOR:          y = y_xor;
            ALU_SLL:          y = y_sll;
            ALU_SRL:          y = y_srl;
            ALU_SRA:          y = y_sra;
            ALU_SLT:          y = {31'b0, slt};
            ALU_SLE:          y = {31'b0, sle};
            ALU_SEQ:          y = {31'b0, seq};
            ALU_SNE:          y = {31'b0, sne};
            ALU_IFMOV:        y = a;
            ALU_PASS:         y = op2;
            default:          y = 32'b0;   // 1110 y 1111 no se usan
        endcase
    end

    // microarchitecture.md §3.3 — cond_ok: usa b (rs2), nunca imm ni op2.
    always_comb begin
        cond_ok = 1'b1;
        if (alu_op == ALU_IFMOV) cond_ok = (b != 32'b0);
    end
endmodule
