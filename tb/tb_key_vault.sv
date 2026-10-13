`timescale 1ns/1ps

// verifica almacenamiento, selección y habilitaciones.
module tb_key_vault;
    logic clk = 1'b0;
    logic rst = 1'b0;
    logic [1:0] k = 2'b0, i = 2'b0;
    logic read_en = 1'b0, write_en = 1'b0;
    logic [31:0] write_data = 32'b0;
    logic [31:0] subkey;
    logic [31:0] esperado [0:3][0:3];
    int comprobaciones = 0;
    int fallos = 0;

    key_vault u_key_vault (
        .clk(clk), .rst(rst), .k(k), .i(i), .read_en(read_en),
        .write_en(write_en), .write_data(write_data), .subkey(subkey)
    );

    always #5 clk = ~clk;

    task automatic check(input string nombre, input logic condicion);
        comprobaciones++;
        if (condicion === 1'b1) $display("PASS: %s", nombre);
        else begin
            fallos++;
            $display("FAIL: %s (t=%0t)", nombre, $time);
        end
    endtask

    // recorre todas las posiciones y verifica la lectura combinacional.
    task automatic revisar_matriz;
        for (int llave = 0; llave < 4; llave++) begin
            for (int palabra = 0; palabra < 4; palabra++) begin
                @(negedge clk);
                k = 2'(llave);
                i = 2'(palabra);
                read_en = 1'b1;
                #1;
                check($sformatf("lectura llave=%0d palabra=%0d", llave, palabra),
                      subkey === esperado[llave][palabra]);
                read_en = 1'b0;
                #1;
                check("read_en=0 entrega cero", subkey === 32'b0);
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_key_vault.vcd");
        $dumpvars(0, tb_key_vault);
        for (int llave = 0; llave < 4; llave++)
            for (int palabra = 0; palabra < 4; palabra++)
                esperado[llave][palabra] = 32'b0;

        // reset entre flancos, con una escritura simultáneamente habilitada.
        #2;
        write_en = 1'b1;
        write_data = 32'hFFFFFFFF;
        rst = 1'b1;
        #1;
        for (int llave = 0; llave < 4; llave++)
            for (int palabra = 0; palabra < 4; palabra++)
                check("reset asíncrono limpia cada palabra",
                      u_key_vault.llaves[llave][palabra] === 32'b0);
        @(posedge clk);
        #1;
        check("reset tiene prioridad sobre escritura", u_key_vault.llaves[0][0] === 32'b0);
        @(negedge clk);
        write_en = 1'b0;
        rst = 1'b0;
        revisar_matriz();

        // carga patrones distintos y revisa también las posiciones no escritas.
        for (int llave = 0; llave < 4; llave++) begin
            for (int palabra = 0; palabra < 4; palabra++) begin
                @(negedge clk);
                k = 2'(llave);
                i = 2'(palabra);
                read_en = 1'b1;
                write_en = 1'b1;
                write_data = 32'hA5000100 + 32'(4 * llave + palabra);
                #1;
                check("dato no cambia antes de subida", subkey === esperado[llave][palabra]);
                @(posedge clk);
                #1;
                esperado[llave][palabra] = write_data;
                check("escritura aparece después de subida", subkey === write_data);
                @(negedge clk);
                write_en = 1'b0;
                revisar_matriz();
            end
        end

        // la escritura deshabilitada conserva cada una de las 16 palabras.
        for (int llave = 0; llave < 4; llave++) begin
            for (int palabra = 0; palabra < 4; palabra++) begin
                @(negedge clk);
                k = 2'(llave);
                i = 2'(palabra);
                read_en = 1'b1;
                write_data = 32'hDEADBEEF;
                @(posedge clk);
                #1;
                check("write_en=0 conserva la palabra", subkey === esperado[llave][palabra]);
            end
        end

        // La habilitación de lectura no impide una escritura autorizada.
        @(negedge clk);
        k = 2'd2;
        i = 2'd1;
        read_en = 1'b0;
        write_en = 1'b1;
        write_data = 32'h12345678;
        @(posedge clk);
        #1;
        esperado[2][1] = write_data;
        check("escritura con lectura cerrada mantiene salida cero", subkey === 32'b0);
        @(negedge clk);
        write_en = 1'b0;
        revisar_matriz();

        // el reset borra la bóveda cargada antes del próximo flanco.
        @(negedge clk);
        #2;
        rst = 1'b1;
        #1;
        for (int llave = 0; llave < 4; llave++) begin
            for (int palabra = 0; palabra < 4; palabra++) begin
                esperado[llave][palabra] = 32'b0;
                check("reset borra la bóveda cargada",
                      u_key_vault.llaves[llave][palabra] === 32'b0);
            end
        end
        @(negedge clk);
        rst = 1'b0;
        revisar_matriz();

        $display("Comprobaciones: %0d | Fallos: %0d", comprobaciones, fallos);
        if (fallos != 0) $fatal(1, "key_vault no pasó las pruebas");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Tiempo máximo de simulación excedido");
    end
endmodule
