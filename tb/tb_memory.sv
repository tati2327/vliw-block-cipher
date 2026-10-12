`timescale 1ns/1ps

// Plan de implementación, tarea 8: casos de microarchitecture.md §3.6.
module tb_memory;
    logic clk = 1'b0;
    logic [31:0] addr = '0, wdata = '0, rdata;
    logic we = 1'b0;
    logic [3:0] be = '0;
    // Caso 10: volcado completo, releído posición por posición.
    logic [31:0] volcado [0:16383];
    int casos = 0;
    int fallos = 0;

    memory #(.INIT_FILE("data/hola.mem"))
        u_mem (.clk, .addr, .wdata, .we, .be, .rdata);

    always #5 clk = ~clk;

    task automatic check(input string nombre,
        input logic [31:0] obtenido, esperado);
        casos++;
        if (obtenido === esperado) $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: obtenido=%08h esperado=%08h", nombre, obtenido, esperado);
        end
    endtask

    // Lectura combinacional; las entradas cambian lejos del flanco de subida.
    task automatic leer(input string nombre,
        input logic [31:0] direccion, esperado);
        addr = direccion;
        we = 1'b0;
        #1;
        check(nombre, rdata, esperado);
    endtask

    // Estímulo en el flanco de bajada, un flanco de subida, y de vuelta a we = 0.
    task automatic ciclo(input logic [31:0] direccion, dato,
        input logic habilita, input logic [3:0] carriles);
        @(negedge clk);
        addr = direccion;
        wdata = dato;
        we = habilita;
        be = carriles;
        @(posedge clk);
        @(negedge clk);
        we = 1'b0;
        be = 4'b0000;
    endtask

    initial begin
        $dumpfile("build/tb_memory.vcd");
        $dumpvars(0, tb_memory);

        // §1.5 — carga del .mem: "Hola" en 0x1000, little endian.
        leer("1 carga del .mem", 32'h0000_1000, 32'h616C_6F48);
        leer("2 posicion sin cargar", 32'h0000_0000, 32'h0000_0000);

        // §3.6 — escritura por carril.
        ciclo(32'h0000_2000, 32'h1234_5678, 1'b1, 4'b1111);
        leer("3 sw", 32'h0000_2000, 32'h1234_5678);
        ciclo(32'h0000_2000, 32'h00AA_0000, 1'b1, 4'b0100);
        leer("4 sb carril 2", 32'h0000_2000, 32'h12AA_5678);
        ciclo(32'h0000_2000, 32'hFFFF_FFFF, 1'b0, 4'b1111);
        leer("5 we=0", 32'h0000_2000, 32'h12AA_5678);
        ciclo(32'h0000_2000, 32'hFFFF_FFFF, 1'b1, 4'b0000);
        leer("6 be=0000", 32'h0000_2000, 32'h12AA_5678);

        // §3.6 — índice: se ignoran addr[1:0] y los bits altos.
        leer("7 no alineada", 32'h0000_2002, 32'h12AA_5678);
        leer("8 reflejo", 32'h0001_2000, 32'h12AA_5678);

        // §3.6 — escritura y lectura en el mismo ciclo.
        @(negedge clk);
        addr = 32'h0000_3000;
        wdata = 32'hCAFE_BABE;
        we = 1'b1;
        be = 4'b1111;
        #1;
        check("9a mismo ciclo, antes del flanco", rdata, 32'h0000_0000);
        @(posedge clk);
        #1;
        check("9b mismo ciclo, despues del flanco", rdata, 32'hCAFE_BABE);
        @(negedge clk);
        we = 1'b0;
        be = 4'b0000;

        // §1.5 — volcado: se vuelve a leer con $readmemh.
        $writememh("build/tb_memory_dump.mem", u_mem.mem);
        $readmemh("build/tb_memory_dump.mem", volcado);
        check("10a volcado, carga del .mem", volcado['h400], 32'h616C_6F48);
        check("10b volcado, palabra escrita", volcado['h800], 32'h12AA_5678);

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_memory");
        $display("PASS tb_memory");
        $finish;
    end
endmodule
