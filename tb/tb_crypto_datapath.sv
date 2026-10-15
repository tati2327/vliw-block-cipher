`timescale 1ns/1ps

// Comprueba la ronda Feistel y las conexiones del hash y su comparador.
module tb_crypto_datapath;
    logic clk = 1'b0;
    logic rst = 1'b0;
    logic [31:0] a = 32'b0, b = 32'b0, subkey = 32'b0, ancla_otp = 32'b0;
    logic auth_start = 1'b0, auth_accept = 1'b0, do_feis = 1'b0;
    logic [31:0] result;
    logic auth_match, auth_busy, auth_done;
    logic [31:0] esperado = 32'b0;
    int comprobaciones = 0, fallos = 0;

    crypto_datapath u_crypto_datapath (
        .clk(clk), .rst(rst), .a(a), .b(b), .subkey(subkey),
        .ancla_otp(ancla_otp), .auth_start(auth_start), .auth_accept(auth_accept),
        .do_feis(do_feis), .result(result), .auth_match(auth_match),
        .auth_busy(auth_busy), .auth_done(auth_done)
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

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    // El resultado combinacional aparece antes de la siguiente subida de reloj.
    task automatic probar_feis(
        input logic [31:0] valor_a,
        input logic [31:0] valor_b,
        input logic [31:0] llave,
        input logic [31:0] resultado_esperado
    );
        @(negedge clk);
        a = valor_a;
        b = valor_b;
        subkey = llave;
        esperado = resultado_esperado;
        do_feis = 1'b1;
        #1;
        check($sformatf("feis a=%08h b=%08h subkey=%08h: obtenido=%08h esperado=%08h",
                       a, b, subkey, result, esperado), result === esperado);
        do_feis = 1'b0;
        #1;
        check("do_feis=0 oculta la salida de ronda", result === 32'b0);
    endtask

    // Los hashes esperados vienen de la referencia externa usada en tb_auth_hash32.
    // Cambia b y subkey durante el cálculo: no deben afectar al hash del token a.
    task automatic probar_hash(
        input logic [31:0] token,
        input logic [31:0] hash_esperado,
        input bit ronda_simultanea
    );
        @(negedge clk);
        a = token;
        b = 32'd1;
        subkey = 32'b0;
        ancla_otp = hash_esperado;
        do_feis = ronda_simultanea;
        esperado = token ^ 32'h00002020;
        auth_start = 1'b1;
        tick();
        check("auth_start llega al motor", {auth_busy, auth_done} === 2'b10);
        @(negedge clk);
        auth_start = 1'b0;
        for (int ronda = 0; ronda < 12; ronda++) begin
            if (!ronda_simultanea) begin
                b = 32'(ronda);
                subkey = 32'hFFFFFFFF - 32'(ronda);
            end
            tick();
            check($sformatf("salida de resultado durante ronda hash %0d", ronda),
                  result === (ronda_simultanea ? esperado : 32'b0));
            check($sformatf("señales del motor después de ronda %0d", ronda),
                  {auth_busy, auth_done} === ((ronda == 11) ? 2'b01 : 2'b10));
            @(negedge clk);
        end
        do_feis = 1'b0;
        #1;
        check("hash coincide con el ancla correcta", auth_match === 1'b1);
        check("hash no aparece en result", result === 32'b0);

        // Cambia cada bit del ancla para comprobar que la igualdad usa los 32 bits.
        for (int bit_idx = 0; bit_idx < 32; bit_idx++) begin
            ancla_otp = hash_esperado ^ (32'h1 << bit_idx);
            #1;
            check($sformatf("comparador detecta diferencia en bit %0d", bit_idx),
                  auth_match === 1'b0);
        end
        ancla_otp = hash_esperado;
        a = ~token;
        repeat (2) begin
            tick();
            check("done conserva hash aunque cambie a",
                  {auth_busy, auth_done, auth_match, result} === {3'b011, 32'b0});
        end
        @(negedge clk);
        auth_accept = 1'b1;
        tick();
        check("auth_accept libera el motor", {auth_busy, auth_done} === 2'b00);
        @(negedge clk);
        auth_accept = 1'b0;
    endtask

    initial begin
        $dumpfile("build/tb_crypto_datapath.vcd");
        $dumpvars(0, tb_crypto_datapath);
        #2;
        rst = 1'b1;
        #1;
        check("reset limpia las señales del motor", {auth_busy, auth_done} === 2'b00);
        @(negedge clk);
        rst = 1'b0;

        // Incluye extremos, acarreo descartado y un patrón mixto calculado previamente.
        probar_feis(32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000);
        probar_feis(32'h12345678, 32'h00000000, 32'h00000000, 32'h12345678);
        probar_feis(32'h00000000, 32'h00000000, 32'hDEADBEEF, 32'hDEADBEEF);
        probar_feis(32'h00000000, 32'h00000001, 32'h00000000, 32'h00002020);
        probar_feis(32'h00000000, 32'h80000000, 32'h00000000, 32'h00001010);
        probar_feis(32'h00000000, 32'hFFFFFFFF, 32'h00000001, 32'hFFFFFFFF);
        probar_feis(32'h12345678, 32'h89ABCDEF, 32'h76543210, 32'hC044574C);
        probar_feis(32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFE);

        // Un bit activo recorre las 32 posiciones; el esperado indica su destino.
        for (int posicion = 0; posicion < 32; posicion++) begin
            probar_feis(32'b0, 32'h1 << posicion, 32'b0,
                        (32'h1 << ((posicion + 5) % 32)) ^
                        (32'h1 << ((posicion + 13) % 32)));
        end

        probar_hash(32'h12345678, 32'h88035407, 1'b0);
        probar_hash(32'h00000000, 32'h8F28B790, 1'b1);
        probar_hash(32'hFFFFFFFF, 32'h8A6AD37E, 1'b0);

        // Comprueba que el reset del datapath cancela también el motor instanciado.
        @(negedge clk);
        a = 32'h12345678;
        auth_start = 1'b1;
        tick();
        @(negedge clk);
        auth_start = 1'b0;
        repeat (3) tick();
        @(negedge clk);
        #2;
        rst = 1'b1;
        #1;
        check("reset cancela hash en marcha", {auth_busy, auth_done} === 2'b00);
        @(negedge clk);
        rst = 1'b0;
        repeat (13) tick();
        check("hash cancelado no entrega done después", auth_done === 1'b0);
        probar_hash(32'h12345678, 32'h88035407, 1'b0);

        $display("Comprobaciones: %0d | Fallos: %0d", comprobaciones, fallos);
        if (fallos != 0) $fatal(1, "crypto_datapath no pasó las pruebas");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Tiempo máximo de simulación excedido");
    end
endmodule
