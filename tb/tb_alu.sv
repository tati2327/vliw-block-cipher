`timescale 1ns/1ps

// Tarea 7 del plan: alu y alu_dec, cada uno por separado.
module tb_alu;
    localparam logic [3:0] ALU_ADD = 4'b0000, ALU_SUB = 4'b0001,
        ALU_AND = 4'b0010, ALU_OR = 4'b0011, ALU_XOR = 4'b0100,
        ALU_SLL = 4'b0101, ALU_SRL = 4'b0110, ALU_SRA = 4'b0111,
        ALU_SLT = 4'b1000, ALU_SLE = 4'b1001, ALU_SEQ = 4'b1010,
        ALU_SNE = 4'b1011, ALU_IFMOV = 4'b1100, ALU_PASS = 4'b1101;

    // Señales de alu.
    logic [31:0] a, b, imm, y;
    logic [3:0]  alu_op;
    logic        use_imm, cond_ok;
    // Señales de alu_dec, independientes de las de alu.
    logic [4:0]  funct;
    logic [3:0]  dec_alu_op;
    logic        dec_use_imm, dec_we;
    logic [5:0]  expected;
    int fallos = 0;
    int casos = 0;

    alu u_alu (.a, .b, .imm, .alu_op, .use_imm, .y, .cond_ok);
    alu_dec u_alu_dec (.funct, .alu_op(dec_alu_op), .use_imm(dec_use_imm), .we(dec_we));

    task automatic check(string nombre, logic [32:0] obtenido, logic [32:0] esperado);
        casos++;
        if (obtenido === esperado) $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: obtenido %h, esperado %h", nombre, obtenido, esperado);
        end
    endtask

    // Aplica un caso a la ALU y compara {cond_ok, y}.
    task automatic caso_alu(string nombre, logic [3:0] op, logic [31:0] va,
        logic [31:0] vb, logic [31:0] vimm, logic vuse_imm,
        logic [31:0] y_esp, logic cond_esp);
        alu_op = op; a = va; b = vb; imm = vimm; use_imm = vuse_imm;
        #1;
        check(nombre, {cond_ok, y}, {cond_esp, y_esp});
    endtask

    initial begin
        $dumpfile("build/tb_alu.vcd");
        $dumpvars(0, tb_alu);

        // Parte 1 — alu. Casos de plan_implementacion_modulos.md, Tarea 7.
        caso_alu("1 add desbordamiento", ALU_ADD, 32'h7FFFFFFF, 32'd1, 32'd0, 1'b0, 32'h80000000, 1'b1);
        caso_alu("2 sub negativa", ALU_SUB, 32'd0, 32'd1, 32'd0, 1'b0, 32'hFFFFFFFF, 1'b1);
        caso_alu("3 slt desbordamiento", ALU_SLT, 32'h7FFFFFFF, 32'h80000000, 32'd0, 1'b0, 32'd0, 1'b1);
        caso_alu("4 slt desbordamiento", ALU_SLT, 32'h80000000, 32'h7FFFFFFF, 32'd0, 1'b0, 32'd1, 1'b1);
        caso_alu("5 slt negativo", ALU_SLT, 32'hFFFFFFFF, 32'd0, 32'd0, 1'b0, 32'd1, 1'b1);
        caso_alu("6a slt iguales", ALU_SLT, 32'd5, 32'd5, 32'd0, 1'b0, 32'd0, 1'b1);
        caso_alu("6b sle iguales", ALU_SLE, 32'd5, 32'd5, 32'd0, 1'b0, 32'd1, 1'b1);
        caso_alu("7a seq", ALU_SEQ, 32'd7, 32'd7, 32'd0, 1'b0, 32'd1, 1'b1);
        caso_alu("7b sne", ALU_SNE, 32'd7, 32'd7, 32'd0, 1'b0, 32'd0, 1'b1);
        caso_alu("8a sra", ALU_SRA, 32'h80000000, 32'd4, 32'd0, 1'b0, 32'hF8000000, 1'b1);
        caso_alu("8b srl", ALU_SRL, 32'h80000000, 32'd4, 32'd0, 1'b0, 32'h08000000, 1'b1);
        caso_alu("9 sll solo 5 bits", ALU_SLL, 32'd1, 32'd33, 32'd0, 1'b0, 32'd2, 1'b1);
        caso_alu("10 and", ALU_AND, 32'hF0F0, 32'hFF00, 32'd0, 1'b0, 32'hF000, 1'b1);
        caso_alu("11 or", ALU_OR, 32'hF0, 32'h0F, 32'd0, 1'b0, 32'hFF, 1'b1);
        caso_alu("12 xor", ALU_XOR, 32'hFF, 32'h0F, 32'd0, 1'b0, 32'hF0, 1'b1);
        // En 13 y 14, b lleva otro valor: si la ALU usara b en lugar de imm, fallan.
        caso_alu("13 xori", ALU_XOR, 32'hFF, 32'h12345678, 32'h0F, 1'b1, 32'hF0, 1'b1);
        caso_alu("14 saddi", ALU_ADD, 32'd5, 32'h12345678, 32'hFFFFFFFF, 1'b1, 32'd4, 1'b1);
        caso_alu("15 mov", ALU_PASS, 32'd123, 32'd0, 32'hABC, 1'b1, 32'hABC, 1'b1);
        caso_alu("16 ifmov b=0", ALU_IFMOV, 32'hDEAD, 32'd0, 32'd0, 1'b0, 32'hDEAD, 1'b0);
        caso_alu("17 ifmov b=5", ALU_IFMOV, 32'hDEAD, 32'd5, 32'd0, 1'b0, 32'hDEAD, 1'b1);
        caso_alu("18 add b=0", ALU_ADD, 32'd3, 32'd0, 32'd0, 1'b0, 32'd3, 1'b1);
        caso_alu("19 alu_op 1110", 4'b1110, 32'h1234, 32'h5678, 32'd0, 1'b0, 32'd0, 1'b1);

        // Parte 2 — alu_dec. Tabla de microarchitecture.md §4.8: todas las
        // codificaciones. expected = {alu_op, use_imm, we}.
        for (int code = 0; code < 32; code++) begin
            case (code)
                1:  expected = {ALU_ADD,   1'b0, 1'b1};
                2:  expected = {ALU_SUB,   1'b0, 1'b1};
                3:  expected = {ALU_AND,   1'b0, 1'b1};
                4:  expected = {ALU_OR,    1'b0, 1'b1};
                5:  expected = {ALU_XOR,   1'b0, 1'b1};
                6:  expected = {ALU_SLL,   1'b0, 1'b1};
                7:  expected = {ALU_SRL,   1'b0, 1'b1};
                8:  expected = {ALU_SRA,   1'b0, 1'b1};
                9:  expected = {ALU_SLT,   1'b0, 1'b1};
                10: expected = {ALU_SLE,   1'b0, 1'b1};
                11: expected = {ALU_SEQ,   1'b0, 1'b1};
                12: expected = {ALU_SNE,   1'b0, 1'b1};
                13: expected = {ALU_IFMOV, 1'b0, 1'b1};
                16: expected = {ALU_ADD,   1'b1, 1'b1};
                17: expected = {ALU_XOR,   1'b1, 1'b1};
                18: expected = {ALU_PASS,  1'b1, 1'b1};
                0, 14, 15: expected = {ALU_ADD, 1'b0, 1'b0};   // nopi y libres 0xxxx
                default:   expected = {ALU_ADD, 1'b1, 1'b0};   // libres 10011-11111
            endcase
            funct = code[4:0];
            #1;
            check($sformatf("alu_dec funct=%05b", funct),
                {27'b0, dec_alu_op, dec_use_imm, dec_we}, {27'b0, expected});
        end

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_alu");
        $display("PASS tb_alu");
        $finish;
    end
endmodule
