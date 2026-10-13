`timescale 1ns/1ps
`include "lamport_config.svh"

// Verifica los módulos conectados y simula la retención del bundle durante auth.
module tb_crypto_unit;
    logic clk = 1'b0, rst = 1'b0, init_anchor = 1'b0;
    logic en = 1'b1, ex_valid = 1'b1;
    logic commit_enable = 1'b1;
    logic ex_commit;
    logic [2:0] crypto_op = 3'b000;
    logic [1:0] k = 2'b0, i = 2'b0;
    logic [31:0] a = 32'b0, b = 32'b0, result;
    logic allowed, crypto_stall;
    logic [31:0] tokens [0:`LAMPORT_TOKEN_COUNT-1];
    logic [31:0] llaves_esperadas [0:3][0:3];
    int comprobaciones = 0, fallos = 0;

    // Emula el contrato del core. commit_enable permite probar una espera adicional.
    assign ex_commit = ex_valid && !crypto_stall && !rst && commit_enable;
    // Usa el ancla por defecto para comprobar también su coherencia con la cadena.
    crypto_unit dut (
        .clk(clk), .rst(rst), .init_anchor(init_anchor), .en(en),
        .ex_valid(ex_valid), .ex_commit(ex_commit), .crypto_op(crypto_op),
        .k(k), .i(i), .a(a), .b(b), .result(result),
        .allowed(allowed), .crypto_stall(crypto_stall)
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

    task automatic presentar(input logic [2:0] op, input logic [31:0] valor_a);
        @(negedge clk);
        crypto_op = op;
        a = valor_a;
        #1;
    endtask

    task automatic retirar;
        @(negedge clk);
        crypto_op = 3'b000;
        #1;
    endtask

    task automatic revisar_boveda;
        for (int llave = 0; llave < 4; llave++) begin
            for (int palabra = 0; palabra < 4; palabra++) begin
                check($sformatf("bóveda llave=%0d palabra=%0d", llave, palabra),
                      dut.u_key_vault.llaves[llave][palabra] === llaves_esperadas[llave][palabra]);
            end
        end
    endtask

    // El reset normal conserva el ancla; el arranque protegido carga el valor de fábrica.
    task automatic reset_unidad(input bit fabrica, input logic [31:0] ancla_esperada);
        @(negedge clk);
        crypto_op = 3'b000;
        init_anchor = fabrica;
        #2;
        rst = 1'b1;
        #1;
        check("reset asíncrono limpia banderas y hash",
              {dut.auth, dut.kvlock, dut.exc, dut.auth_busy, dut.auth_done} === 5'b0);
        check("reset bloquea permisos, resultado y espera",
              {allowed, result, crypto_stall} === 34'b0);
        for (int llave = 0; llave < 4; llave++)
            for (int palabra = 0; palabra < 4; palabra++)
                llaves_esperadas[llave][palabra] = 32'b0;
        revisar_boveda();
        tick();
        check("reset conserva o inicializa el ancla según init_anchor",
              dut.ancla_otp === ancla_esperada);
        @(negedge clk);
        init_anchor = 1'b0;
        rst = 1'b0;
    endtask

    // Mantiene a, op y validez estables desde la carga hasta la finalización.
    task automatic autenticar(
        input logic [31:0] token,
        input bit exito,
        input int espera_final
    );
        logic [34:0] estado_anterior;
        estado_anterior = {dut.auth, dut.kvlock, dut.exc, dut.ancla_otp};
        commit_enable = (espera_final == 0);
        presentar(3'b010, token);
        check("auth permite el intento y pide pausa antes de carga",
              {allowed, crypto_stall, ex_commit, result} === {3'b110, 32'b0});
        tick();
        check("ciclo 1 carga el token y retiene el estado",
              dut.auth_busy === 1'b1 &&
              {dut.auth, dut.kvlock, dut.exc, dut.ancla_otp} === estado_anterior);
        for (int ronda = 0; ronda < 12; ronda++) begin
            tick();
            check($sformatf("ronda %0d no aplica efectos ni expone el hash", ronda),
                  {dut.auth, dut.kvlock, dut.exc, dut.ancla_otp} === estado_anterior && result === 32'b0);
            if (ronda < 11)
                check("pausa impide commit y reinicio del hash",
                      {crypto_stall, ex_commit, dut.auth_start} === 3'b100);
        end
        check("ciclo 13 entrega el hash y libera la pausa",
              {dut.auth_busy, dut.auth_done, crypto_stall, dut.auth_match} === {3'b010, 1'(exito)});
        repeat (espera_final) begin
            tick();
            check("resultado terminado espera commit sin cambiar estado",
                  dut.auth_done === 1'b1 && dut.auth_accept === 1'b0 &&
                  {dut.auth, dut.kvlock, dut.exc, dut.ancla_otp} === estado_anterior);
        end
        if (espera_final > 0) begin
            @(negedge clk);
            commit_enable = 1'b1;
        end
        tick();
        check("finalización aplica autenticación y excepción",
              {dut.auth, dut.exc} === {1'(exito), !1'(exito)});
        check("finalización conserva el sello", dut.kvlock === estado_anterior[33]);
        check("finalización avanza ancla solo si token válido",
              dut.ancla_otp === (exito ? token : estado_anterior[31:0]));
        check("finalización acepta y libera el hash", {dut.auth_busy, dut.auth_done} === 2'b00);
        retirar();
        tick();
        check("bundle retirado no reinicia el hash", {dut.auth_busy, dut.auth_done} === 2'b00);
    endtask

    initial begin
        $dumpfile("build/tb_crypto_unit.vcd");
        $dumpvars(0, tb_crypto_unit);
        $readmemh("data/lamport_demo/tokens.mem", tokens);
        reset_unidad(1'b1, `LAMPORT_RESET_ANCHOR);

        // Rechaza feis, escritura, bloqueo y sanc sin una sesión autenticada.
        presentar(3'b001, 32'h12345678);
        check("feis sin sesión rechaza y entrega cero", {allowed, result} === 33'b0);
        tick();
        check("feis rechazada activa excepción", dut.exc === 1'b1);
        retirar();
        for (int op = 4; op <= 6; op++) begin
            presentar(3'(op), 32'hDEADBEEF);
            tick();
            check("operación privilegiada rechazada conserva sesión, sello y ancla",
                  allowed === 1'b0 && {dut.auth, dut.kvlock, dut.exc} === 3'b001 &&
                  dut.ancla_otp === `LAMPORT_RESET_ANCHOR && result === 32'b0);
            retirar();
        end
        revisar_boveda();

        autenticar(32'b0, 1'b0, 0);
        autenticar(tokens[0], 1'b1, 0);
        autenticar(tokens[1], 1'b1, 3);
        autenticar(tokens[0], 1'b0, 0);
        autenticar(tokens[2], 1'b1, 0);

        // Carga las 16 palabras y prueba que feis utiliza cada selección correcta.
        for (int llave = 0; llave < 4; llave++) begin
            for (int palabra = 0; palabra < 4; palabra++) begin
                @(negedge clk);
                k = 2'(llave);
                i = 2'(palabra);
                crypto_op = 3'b100;
                a = 32'h01020300 + 32'(4 * llave + palabra);
                #1;
                check("kv_write autorizada no entrega dato en result", allowed === 1'b1 && result === 32'b0);
                tick();
                llaves_esperadas[llave][palabra] = a;
                retirar();
                presentar(3'b001, 32'h12345678);
                b = 32'b0;
                #1;
                check("feis usa la subllave seleccionada",
                      allowed === 1'b1 && result === (32'h12345678 ^ llaves_esperadas[llave][palabra]));
                tick();
                retirar();
            end
        end
        revisar_boveda();

        // Comprueba un patrón Feistel mixto contra un resultado calculado previamente.
        k = 2'd2;
        i = 2'd1;
        presentar(3'b100, 32'h76543210);
        tick();
        llaves_esperadas[2][1] = 32'h76543210;
        retirar();
        presentar(3'b001, 32'h12345678);
        b = 32'h89ABCDEF;
        #1;
        check("ronda Feistel mixta coincide con referencia", result === 32'hC044574C);
        tick();
        retirar();

        // Sin commit, las operaciones no cambian llaves, sesión, sello ni ancla.
        commit_enable = 1'b0;
        for (int op = 3; op <= 6; op++) begin
            presentar(3'(op), 32'hDEADBEEF);
            repeat (2) tick();
            check("sin commit conserva el estado",
                  {dut.auth, dut.kvlock, dut.exc, dut.ancla_otp} === {3'b100, tokens[2]});
            check("sin commit conserva la palabra de bóveda",
                  dut.u_key_vault.llaves[2][1] === 32'h76543210 && result === 32'b0);
            retirar();
        end
        commit_enable = 1'b1;

        // en y ex_valid impiden operaciones y el arranque del hash.
        for (int bloqueo = 0; bloqueo < 2; bloqueo++) begin
            @(negedge clk);
            en = (bloqueo != 0);
            ex_valid = (bloqueo != 1);
            for (int op = 1; op <= 6; op++) begin
                presentar(3'(op), 32'hDEADBEEF);
                tick();
                check("unidad inactiva no aplica efectos",
                      {allowed, crypto_stall, result, dut.auth_busy} === 35'b0 &&
                      {dut.auth, dut.kvlock, dut.exc, dut.ancla_otp} === {3'b100, tokens[2]});
                retirar();
            end
        end
        @(negedge clk);
        en = 1'b1;
        ex_valid = 1'b1;

        presentar(3'b101, 32'b0);
        tick();
        check("kv_lock sella la bóveda", dut.kvlock === 1'b1);
        retirar();
        presentar(3'b100, 32'hDEADBEEF);
        tick();
        check("bóveda sellada rechaza escritura y activa excepción",
              allowed === 1'b0 && dut.exc === 1'b1 &&
              dut.u_key_vault.llaves[2][1] === 32'h76543210);
        retirar();
        autenticar(tokens[3], 1'b1, 0);
        check("auth válida limpia excepción pero no abre el sello", {dut.kvlock, dut.exc} === 2'b10);

        presentar(3'b110, tokens[1]);
        tick();
        check("sanc autorizada reemplaza el ancla", dut.ancla_otp === tokens[1] && result === 32'b0);
        retirar();
        reset_unidad(1'b0, tokens[1]);
        autenticar(tokens[1], 1'b0, 0);
        autenticar(tokens[2], 1'b1, 0);
        presentar(3'b011, 32'b0);
        tick();
        check("logout cierra sesión y conserva ancla", dut.auth === 1'b0 && dut.ancla_otp === tokens[2]);
        retirar();
        autenticar(tokens[3], 1'b1, 0);

        // El reset cancela una autenticación sin consumir su token.
        presentar(3'b010, tokens[4]);
        repeat (4) tick();
        check("hash está en marcha antes de cancelación", dut.auth_busy === 1'b1);
        reset_unidad(1'b0, tokens[3]);
        repeat (14) tick();
        check("reset no aplica un resultado tardío", {dut.auth, dut.auth_done} === 2'b00);
        autenticar(tokens[4], 1'b1, 0);
        reset_unidad(1'b0, tokens[4]);
        autenticar(tokens[4], 1'b0, 0);
        autenticar(tokens[5], 1'b1, 0);

        // El control convierte NOP y el código interno libre en ausencia de efectos.
        for (int op = 0; op < 2; op++) begin
            presentar(op == 0 ? 3'b000 : 3'b111, 32'hDEADBEEF);
            tick();
            check("NOP y 111 conservan estado y entregan cero",
                  {allowed, result, crypto_stall} === 34'b0 &&
                  {dut.auth, dut.kvlock, dut.exc, dut.ancla_otp} === {3'b100, tokens[5]});
            retirar();
        end

        $display("Comprobaciones: %0d | Fallos: %0d", comprobaciones, fallos);
        if (fallos != 0) $fatal(1, "crypto_unit no pasó las pruebas");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "Tiempo máximo de simulación excedido");
    end
endmodule
