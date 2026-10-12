`timescale 1ns/1ps

// plan_implementacion_modulos.md, tarea 4: casos y esperados explícitos.
module tb_pipe_reg;
    logic clk = 1'b0;
    logic rst = 1'b0;
    logic flush = 1'b0;
    logic en = 1'b0;
    logic [7:0] d = 8'b0;
    logic [7:0] q;
    logic q_valid;
    int casos = 0;
    int fallos = 0;

    pipe_reg #(.W(8)) u_pipe_reg (.clk, .rst, .flush, .en, .d, .q);
    // Ancho predeterminado: también usado por los bits de validez del pipeline.
    pipe_reg u_valid (.clk, .rst, .flush, .en, .d(d[0]), .q(q_valid));
    always #5 clk = ~clk;

    task automatic check(input string nombre, input logic [7:0] esperado);
        casos++;
        if (q === esperado && q_valid === esperado[0])
            $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: q=%h esperado=%h; valid=%b esperado_valid=%b",
                nombre, q, esperado, q_valid, esperado[0]);
        end
    endtask

    task automatic capturar;
        @(posedge clk);
        #1; // Permite completar las asignaciones no bloqueantes del DUT.
    endtask

    initial begin
        $dumpfile("build/tb_pipe_reg.vcd");
        $dumpvars(0, tb_pipe_reg);

        #2; rst = 1'b1; #1;
        check("reset inicial antes del primer flanco", 8'h00);

        @(negedge clk); rst = 0; en = 1; d = 8'h5A;
        capturar(); check("preparacion de dato no cero", 8'h5A);
        #1; rst = 1; #1;
        check("reset asincrono borra 5A entre flancos", 8'h00);

        @(negedge clk); rst = 0; d = 8'h11;
        capturar(); check("carga normal 11", 8'h11);
        @(negedge clk); d = 8'h22;
        capturar(); check("carga normal 22", 8'h22);

        @(negedge clk); d = 8'h33; flush = 1;
        capturar(); check("flush sustituye dato 33 por cero", 8'h00);

        @(negedge clk); flush = 0; d = 8'h44;
        capturar(); check("preparacion 44", 8'h44);
        #1; flush = 1; #1;
        check("flush entre flancos conserva 44 hasta subida", 8'h44);
        capturar(); check("flush se aplica en siguiente subida", 8'h00);

        #1; rst = 1; flush = 1; en = 1; d = 8'hFF; #1;
        check("reset y flush simultaneos", 8'h00);

        @(negedge clk); rst = 0; flush = 0; d = 8'h55;
        capturar(); check("preparacion 55", 8'h55);
        @(negedge clk); en = 0; d = 8'h66;
        for (int i = 1; i <= 3; i++) begin
            capturar(); check($sformatf("en cero conserva 55, ciclo %0d", i), 8'h55);
        end

        @(negedge clk); en = 1; d = 8'h77;
        capturar(); check("reanuda carga con en uno", 8'h77);
        @(negedge clk); en = 0; flush = 1; d = 8'h88;
        capturar(); check("flush tiene prioridad sobre en cero", 8'h00);

        @(negedge clk); flush = 0; en = 1; d = 8'hA5;
        capturar(); check("carga despues del vaciado", 8'hA5);
        #1; d = 8'h3C; #1;
        check("cambio de d entre flancos no altera q", 8'hA5);
        capturar(); check("captura 3C en siguiente subida", 8'h3C);
        #1; en = 0; rst = 1; #1;
        check("reset prevalece aun con en cero", 8'h00);

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_pipe_reg");
        $display("PASS tb_pipe_reg");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "FAIL tb_pipe_reg: tiempo limite excedido");
    end
endmodule
