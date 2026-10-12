`timescale 1ns/1ps

// Tarea 11: bru_dec + bru aislados. Los operandos y PC los proporciona el TB.
module tb_bru;
    logic [4:0] funct;
    logic [2:0] br_op;
    logic we, taken;
    logic [21:0] pc, instr_low, target;
    logic [31:0] a, b, link;
    int casos = 0;
    int fallos = 0;
    bru_dec u_bru_dec (.funct, .br_op, .we);
    bru u_bru (.pc, .a, .b, .instr_low, .br_op, .taken, .target, .link);

    task automatic comprobar (
        input string nombre,
        input logic [4:0] f,
        input logic [31:0] op_a, op_b,
        input logic [21:0] pc_in, campo,
        input logic taken_esperado,
        input logic [21:0] destino_esperado,
        input logic [31:0] enlace_esperado,
        input logic we_esperado
    );
        funct = f; a = op_a; b = op_b; pc = pc_in; instr_low = campo;
        #1;
        casos++;
        if ({taken, target, link, we} ===
            {taken_esperado, destino_esperado, enlace_esperado, we_esperado})
            $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s", nombre);
            $display("  obtenido: taken=%b target=%h link=%h we=%b", taken, target, link, we);
            $display("  esperado: taken=%b target=%h link=%h we=%b",
                taken_esperado, destino_esperado, enlace_esperado, we_esperado);
        end
    endtask

    initial begin
        $dumpfile("build/tb_bru.vcd");
        $dumpvars(0, tb_bru);
        // off de -2 = 18'h3FFFE; bits [21:18] no pertenecen a off.
        comprobar("blt negativo tomado", 3, 32'hFFFFFFFD, 5, 10, 22'h03FFFE, 1, 8, 11, 0);
        comprobar("bge negativo no tomado", 4, 32'hFFFFFFFF, 1, 10, 5, 0, 15, 11, 0);
        comprobar("beq iguales adelante", 1, 7, 7, 10, 5, 1, 15, 11, 0);
        comprobar("bne iguales no tomado", 2, 7, 7, 10, 5, 0, 15, 11, 0);
        comprobar("beq distintos no tomado", 1, 7, 8, 10, 5, 0, 15, 11, 0);
        comprobar("blt mayor no tomado", 3, 8, 7, 10, 5, 0, 15, 11, 0);
        comprobar("bge menor no tomado", 4, 7, 8, 10, 5, 0, 15, 11, 0);
        comprobar("bne distintos tomado", 2, 7, 8, 10, 5, 1, 15, 11, 0);
        comprobar("blt iguales no tomado", 3, 7, 7, 10, 5, 0, 15, 11, 0);
        comprobar("bge iguales tomado", 4, 7, 7, 10, 5, 1, 15, 11, 0);
        comprobar("bge mayor tomado", 4, 8, 7, 10, 5, 1, 15, 11, 0);
        // Formato J usa los 22 bits, no los 18 del formato B.
        comprobar("jef atras", 16, 0, 0, 100, 22'h3FFFD8, 1, 60, 101, 0);
        comprobar("jas adelante y enlace", 17, 0, 0, 100, 40, 1, 140, 101, 1);
        comprobar("jefR absoluto bits bajos", 5, 32'h00400065, 0, 100, 0, 1, 22'h65, 101, 1);
        comprobar("nopi sin salto", 0, 7, 7, 10, 5, 0, 15, 11, 0);
        comprobar("reservado 00110", 6, 7, 7, 10, 5, 0, 15, 11, 0);
        comprobar("reservado 11111", 31, 7, 7, 10, 5, 0, 15, 11, 0);
        comprobar("blt minimo vs maximo", 3, 32'h80000000, 32'h7FFFFFFF, 10, 1, 1, 11, 11, 0);
        comprobar("blt maximo vs minimo", 3, 32'h7FFFFFFF, 32'h80000000, 10, 1, 0, 11, 11, 0);
        comprobar("bge maximo vs minimo", 4, 32'h7FFFFFFF, 32'h80000000, 10, 1, 1, 11, 11, 0);
        comprobar("blt dos negativos", 3, 32'hFFFFFFFB, 32'hFFFFFFFE, 10, 1, 1, 11, 11, 0);
        comprobar("off minimo -131072", 1, 0, 0, 200000, 22'h020000, 1, 68928, 200001, 0);
        comprobar("off maximo 131071", 1, 0, 0, 200000, 22'h01FFFF, 1, 331071, 200001, 0);
        comprobar("B ignora bits 21 a 18", 1, 0, 0, 10, 22'h3C0005, 1, 15, 11, 0);
        comprobar("J conserva bits altos", 16, 0, 0, 100, 22'h040000, 1, 262244, 101, 0);
        comprobar("J minimo negativo", 16, 0, 0, 22'h200000, 22'h200000, 1, 0, 22'h200001, 0);
        comprobar("PC desborda a cero", 17, 0, 0, 22'h3FFFFF, 1, 1, 0, 0, 1);
        comprobar("PC resta modulo 22", 16, 0, 0, 0, 22'h3FFFFF, 1, 22'h3FFFFF, 1, 0);
        comprobar("jefR ignora instr_low", 5, 32'hFFFFFFFF, 0, 10, 123, 1, 22'h3FFFFF, 11, 1);
        comprobar("nopi despues de jefR", 0, 0, 0, 10, 0, 0, 10, 11, 0);

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_bru");
        $display("PASS tb_bru");
        $finish;
    end
endmodule
