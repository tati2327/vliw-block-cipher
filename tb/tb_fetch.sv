`timescale 1ns/1ps

// Esperados: microarchitecture.md §3.12 y plan de implementación, tarea 6.
module tb_fetch;
    localparam int PC_W = 22;
    logic clk = 0;
    logic rst = 0;
    logic stall = 0;
    logic branch_taken = 0;
    logic [PC_W-1:0] branch_target = '0;
    logic [PC_W-1:0] pc;
    int casos = 0;
    int fallos = 0;

    fetch u_fetch (.clk, .rst, .stall, .branch_taken, .branch_target, .pc);
    always #5 clk = ~clk;

    task automatic check(input string nombre, input logic [PC_W-1:0] esperado);
        casos++;
        if (pc === esperado) $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: pc=%h esperado=%h", nombre, pc, esperado);
        end
    endtask
    task automatic capturar;
        @(posedge clk); #1;
    endtask

    initial begin
        $dumpfile("build/tb_fetch.vcd");
        $dumpvars(0, tb_fetch);
        #2; rst = 1; #1;
        check("reset antes del primer flanco", 0);

        @(negedge clk); rst = 0;
        for (int i = 1; i <= 4; i++) begin
            capturar(); check($sformatf("avance secuencial %0d", i), i);
        end

        @(negedge clk); branch_taken = 1; branch_target = 8;
        #1; check("destino no cambia PC antes de subida", 4);
        capturar(); check("salto adelante a 8", 8);
        @(negedge clk); branch_target = 2;
        capturar(); check("salto atras a 2", 2);

        @(negedge clk); branch_target = 5;
        capturar(); check("preparacion PC 5", 5);
        #1; rst = 1; #1;
        check("reset asincrono desde PC 5", 0);

        @(negedge clk); rst = 0; branch_taken = 0;
        capturar(); check("avance despues del reset", 1);
        @(negedge clk); stall = 1;
        for (int i = 1; i <= 3; i++) begin
            capturar(); check($sformatf("pausa conserva PC, ciclo %0d", i), 1);
        end
        @(negedge clk); stall = 0;
        capturar(); check("reanuda avance despues de pausa", 2);

        @(negedge clk); stall = 1; branch_taken = 1; branch_target = 9;
        capturar(); check("stall prevalece sobre salto", 2);
        @(negedge clk); branch_target = 12;
        capturar(); check("destino cambia durante pausa sin alterar PC", 2);
        @(negedge clk); stall = 0; branch_target = 9;
        capturar(); check("salto se aplica al liberar pausa", 9);
        @(negedge clk); branch_taken = 0;
        capturar(); check("avance secuencial desde destino", 10);

        @(negedge clk); branch_target = 100;
        capturar(); check("destino ignorado con branch_taken cero", 11);

        @(negedge clk); branch_taken = 1; branch_target = {PC_W{1'b1}};
        capturar(); check("salto a PC maximo", 22'h3FFFFF);
        @(negedge clk); branch_taken = 0;
        capturar(); check("incremento modular del PC maximo", 0);

        @(negedge clk); branch_taken = 1; branch_target = 25;
        capturar(); check("preparacion PC no cero antes de reset y pausa", 25);
        #1; stall = 1; branch_target = 123; rst = 1; #1;
        check("reset prevalece sobre pausa y salto", 0);
        @(negedge clk); rst = 0;
        capturar(); check("pausa conserva cero tras liberar reset", 0);
        @(negedge clk); stall = 0; branch_taken = 0;
        capturar(); check("reanuda desde bundle cero", 1);

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_fetch");
        $display("PASS tb_fetch");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "FAIL tb_fetch: tiempo limite excedido");
    end
endmodule
