`timescale 1ns/1ps
`include "lamport_config.svh"

// Comprueba el almacenamiento y la diferencia entre reset normal y arranque.
module tb_crypto_state;
    // Usa un patrón de prueba; no representa el ancla final de la cadena Lamport.
    localparam logic [31:0] TEST_ANCHOR = 32'hA1B2C3D4;
    logic clk = 1'b0;
    logic rst = 1'b0, init_anchor = 1'b0;
    logic auth_next = 1'b0, kvlock_next = 1'b0, exc_next = 1'b0;
    logic [31:0] ancla_next = TEST_ANCHOR;
    logic auth, kvlock, exc;
    logic [31:0] ancla_otp;
    logic [31:0] ancla_por_defecto;
    int comprobaciones = 0, fallos = 0;

    crypto_state #(.RESET_ANCHOR(TEST_ANCHOR)) u_crypto_state (
        .clk(clk), .rst(rst), .init_anchor(init_anchor),
        .auth_next(auth_next), .kvlock_next(kvlock_next), .exc_next(exc_next),
        .ancla_next(ancla_next), .auth(auth), .kvlock(kvlock), .exc(exc),
        .ancla_otp(ancla_otp)
    );

    // Comprueba también el ancla real de fábrica sin sobrescribir el parámetro.
    crypto_state u_estado_por_defecto (
        .clk(clk), .rst(rst), .init_anchor(init_anchor),
        .auth_next(auth_next), .kvlock_next(kvlock_next), .exc_next(exc_next),
        .ancla_next(ancla_next), .auth(), .kvlock(), .exc(),
        .ancla_otp(ancla_por_defecto)
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

    initial begin
        $dumpfile("build/tb_crypto_state.vcd");
        $dumpvars(0, tb_crypto_state);

        // El arranque protegido carga el parámetro con el procesador en reset.
        #2;
        rst = 1'b1;
        init_anchor = 1'b1;
        auth_next = 1'b1;
        kvlock_next = 1'b1;
        exc_next = 1'b1;
        #1;
        check("reset inicial limpia banderas sin esperar reloj", {auth, kvlock, exc} === 3'b000);
        tick();
        check("arranque carga RESET_ANCHOR", ancla_otp === TEST_ANCHOR);
        check("ancla por defecto coincide con la cadena Lamport generada",
              ancla_por_defecto === `LAMPORT_RESET_ANCHOR);
        check("reset domina entradas de banderas", {auth, kvlock, exc} === 3'b000);
        @(negedge clk);
        init_anchor = 1'b0;
        ancla_next = 32'hDEADBEEF;
        tick();
        check("reset sin init_anchor conserva ancla inicial", ancla_otp === TEST_ANCHOR);
        @(negedge clk);
        rst = 1'b0;

        // Recorre todas las combinaciones de banderas y cambia el ancla.
        for (int patron = 0; patron < 8; patron++) begin
            @(negedge clk);
            {auth_next, kvlock_next, exc_next} = 3'(patron);
            ancla_next = 32'h13572460 + 32'(patron);
            tick();
            check($sformatf("banderas cargan patrón %03b", 3'(patron)),
                  {auth, kvlock, exc} === 3'(patron));
            check("ancla carga entrada siguiente", ancla_otp === ancla_next);
        end

        // Los valores siguientes no llegan a las salidas antes del flanco.
        @(negedge clk);
        {auth_next, kvlock_next, exc_next} = 3'b000;
        ancla_next = 32'h89ABCDEF;
        #1;
        check("banderas conservan valor entre flancos", {auth, kvlock, exc} === 3'b111);
        check("ancla conserva valor entre flancos", ancla_otp === 32'h13572467);
        tick();
        check("flanco aplica banderas nuevas", {auth, kvlock, exc} === 3'b000);
        check("flanco aplica ancla nueva", ancla_otp === 32'h89ABCDEF);

        // El control conserva el estado cuando devuelve las salidas como entradas.
        @(negedge clk);
        auth_next = auth;
        kvlock_next = kvlock;
        exc_next = exc;
        ancla_next = ancla_otp;
        repeat (3) begin
            tick();
            check("realimentación conserva todo el estado",
                  {auth, kvlock, exc, ancla_otp} === {3'b000, 32'h89ABCDEF});
        end

        // Prepara una sesión y un ancla consumida antes del reset normal.
        @(negedge clk);
        {auth_next, kvlock_next, exc_next} = 3'b111;
        ancla_next = 32'h12345678;
        tick();
        @(negedge clk);
        ancla_next = 32'hFFFFFFFF;
        #2;
        rst = 1'b1;
        #1;
        check("reset limpia banderas de forma asíncrona", {auth, kvlock, exc} === 3'b000);
        check("reset no borra ancla consumida", ancla_otp === 32'h12345678);
        repeat (3) begin
            tick();
            check("reset sostenido bloquea cambios pendientes",
                  {auth, kvlock, exc, ancla_otp} === {3'b000, 32'h12345678});
        end
        @(negedge clk);
        ancla_next = ancla_otp;
        {auth_next, kvlock_next, exc_next} = 3'b000;
        rst = 1'b0;
        tick();
        check("salida de reset conserva el ancla realimentada", ancla_otp === 32'h12345678);

        // init_anchor aislado no restaura el ancla: necesita rst simultáneo.
        @(negedge clk);
        init_anchor = 1'b1;
        ancla_next = 32'h87654321;
        tick();
        check("init_anchor sin rst permite actualización normal", ancla_otp === 32'h87654321);

        // La carga protegida ocurre en subida, no al activar init_anchor.
        @(negedge clk);
        init_anchor = 1'b0;
        rst = 1'b1;
        #1;
        init_anchor = 1'b1;
        #1;
        check("init_anchor con rst espera al reloj", ancla_otp === 32'h87654321);
        tick();
        check("arranque protegido restaura el parámetro", ancla_otp === TEST_ANCHOR);
        check("arranque protegido restaura el ancla de fábrica real",
              ancla_por_defecto === `LAMPORT_RESET_ANCHOR);
        check("arranque mantiene las banderas limpias", {auth, kvlock, exc} === 3'b000);

        $display("Comprobaciones: %0d | Fallos: %0d", comprobaciones, fallos);
        if (fallos != 0) $fatal(1, "crypto_state no pasó las pruebas");
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "Tiempo máximo de simulación excedido");
    end
endmodule
