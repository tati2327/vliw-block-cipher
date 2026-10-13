`timescale 1ns/1ps

// comprueba el hash y el protocolo del motor.
// Los valores esperados vienen de ascon/ascon-c, no de una copia del RTL.
module tb_auth_hash32;
    logic clk = 1'b0;
    logic rst = 1'b0;
    logic start = 1'b0;
    logic accept = 1'b0;
    logic [31:0] token = 32'b0;
    logic [31:0] hash32;
    logic busy, done;
    int comprobaciones = 0;
    int fallos = 0;

    // Estas señales facilitan la comparación visual en GTKWave.
    logic [31:0] token_cargado;
    logic [31:0] esperado;
    logic [319:0] estado_guardado;

    auth_hash32 u_auth_hash32 (
        .clk(clk), .rst(rst), .start(start), .accept(accept),
        .token(token), .hash32(hash32), .busy(busy), .done(done)
    );

    // Genera un reloj con periodo de 10 ns: cinco en bajo y cinco en alto.
    always #5 clk = ~clk;

    // cuenta los errores; una condición X o Z también produce FAIL.
    task automatic check(input string nombre, input logic condicion);
        comprobaciones++;
        if (condicion === 1'b1) begin
            $display("PASS: %s", nombre);
        end else begin
            fallos++;
            $display("FAIL: %s (t=%0t)", nombre, $time);
        end
    endtask

    // Espera un flanco y deja que se apliquen las asignaciones <= del módulo.
    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    // activa rst entre flancos y comprueba que el borrado es inmediato.
    task automatic reset_motor;
        @(negedge clk);
        start = 1'b0;
        accept = 1'b0;
        #2;
        rst = 1'b1;
        #1;
        check("reset asíncrono limpia busy y done", {busy, done} === 2'b00);
        check("reset limpia las cinco palabras",
              {u_auth_hash32.s4, u_auth_hash32.s3, u_auth_hash32.s2,
               u_auth_hash32.s1, u_auth_hash32.s0} === 320'b0);
        check("reset limpia el contador", u_auth_hash32.round_idx === 4'd0);
        @(negedge clk);
        rst = 1'b0;
    endtask

    // presenta las entradas en bajada y comprueba la carga en subida.
    task automatic iniciar(input logic [31:0] valor);
        @(negedge clk);
        token = valor;
        token_cargado = valor;
        start = 1'b1;
        accept = 1'b0;
        tick();
        check("start carga y activa busy sin done", {busy, done} === 2'b10);
        check("carga empieza en ronda cero", u_auth_hash32.round_idx === 4'd0);
        @(negedge clk);
        start = 1'b0;
    endtask

    // comprueba cada ciclo; no espera indefinidamente a que aparezca done.
    // Con interferencia, cambia token y mantiene start/accept durante el cálculo.
    task automatic calcular(
        input logic [31:0] hash_esperado,
        input bit interferencia
    );
        esperado = hash_esperado;
        if (interferencia) begin
            token = ~token_cargado;
            start = 1'b1;
            accept = 1'b1;
        end
        for (int ronda = 0; ronda < 12; ronda++) begin
            tick();
            if (ronda < 11) begin
                check($sformatf("ronda %0d mantiene busy y no termina antes", ronda),
                      {busy, done} === 2'b10);
                check($sformatf("contador después de ronda %0d", ronda),
                      u_auth_hash32.round_idx === 4'(ronda + 1));
            end else begin
                check("ronda 11 termina: busy=0, done=1", {busy, done} === 2'b01);
                check("contador conserva 11", u_auth_hash32.round_idx === 4'd11);
            end
            @(negedge clk);
        end
        start = 1'b0;
        accept = 1'b0;
        check($sformatf("hash token=%08h: obtenido=%08h, esperado=%08h",
                       token_cargado, hash32, esperado), hash32 === esperado);
    endtask

    // confirma el resultado y verifica que el motor queda libre.
    task automatic consumir;
        @(negedge clk);
        accept = 1'b1;
        tick();
        check("accept libera el resultado", {busy, done} === 2'b00);
        @(negedge clk);
        accept = 1'b0;
        tick();
        check("motor libre no inicia por sí solo", {busy, done} === 2'b00);
    endtask

    task automatic probar_vector(
        input logic [31:0] valor,
        input logic [31:0] hash_esperado
    );
        iniciar(valor);
        calcular(hash_esperado, 1'b0);
        consumir();
    endtask

    initial begin
        $dumpfile("build/tb_auth_hash32.vcd");
        $dumpvars(0, tb_auth_hash32);
        token_cargado = 32'b0;
        esperado = 32'b0;
        estado_guardado = 320'b0;

        reset_motor();
        repeat (2) tick();
        check("sin start conserva el reposo", {busy, done, hash32} === 34'b0);

        // Msg=00010203 del KAT corresponde al token little-endian 03020100.
        // MD empieza por D7 E4 C7 ED; como entero little-endian es EDC7E4D7.
        probar_vector(32'h03020100, 32'hEDC7E4D7);
        probar_vector(32'h00000000, 32'h8F28B790);
        probar_vector(32'h00000001, 32'hEC267D58);
        probar_vector(32'h80000000, 32'hF5C202DC);
        probar_vector(32'h80000001, 32'hFEFEC6C6);
        probar_vector(32'h12345678, 32'h88035407);
        probar_vector(32'hFFFFFFFF, 32'h8A6AD37E);
        probar_vector(32'hA5A55A5A, 32'hD020C92A);
        // Repite el primero sin reset: detecta estado residual entre cálculos.
        probar_vector(32'h03020100, 32'hEDC7E4D7);

        // start, accept y cambios de token no alteran un cálculo en marcha.
        iniciar(32'h12345678);
        calcular(32'h88035407, 1'b1);
        estado_guardado = {u_auth_hash32.s4, u_auth_hash32.s3,
                           u_auth_hash32.s2, u_auth_hash32.s1, u_auth_hash32.s0};
        // Intenta otro inicio mientras el resultado sigue pendiente.
        start = 1'b1;
        token = 32'hFFFFFFFF;
        repeat (3) begin
            tick();
            check("done retiene el resultado y rechaza start", {busy, done} === 2'b01);
            check("resultado pendiente conserva todo el estado",
                  {u_auth_hash32.s4, u_auth_hash32.s3, u_auth_hash32.s2,
                   u_auth_hash32.s1, u_auth_hash32.s0} === estado_guardado);
            check("resultado pendiente conserva contador", u_auth_hash32.round_idx === 4'd11);
            @(negedge clk);
        end

        // start simultáneo con accept no carga un token en ese mismo flanco.
        accept = 1'b1;
        tick();
        check("accept con start libera sin iniciar", {busy, done} === 2'b00);
        check("aceptación conserva el estado",
              {u_auth_hash32.s4, u_auth_hash32.s3, u_auth_hash32.s2,
               u_auth_hash32.s1, u_auth_hash32.s0} === estado_guardado);
        @(negedge clk);
        accept = 1'b0;
        token_cargado = token;
        tick();
        check("start sostenido inicia en el siguiente flanco", {busy, done} === 2'b10);
        @(negedge clk);
        start = 1'b0;
        calcular(32'h8A6AD37E, 1'b0);
        consumir();

        // cancela antes de cada una de las doce rondas posibles.
        for (int rondas_hechas = 0; rondas_hechas < 12; rondas_hechas++) begin
            iniciar(32'h12345678);
            repeat (rondas_hechas) tick();
            $display("Caso reset después de %0d rondas", rondas_hechas);
            reset_motor();
            repeat (2) tick();
            check("reset cancela sin generar un done tardío", {busy, done} === 2'b00);
        end

        // El motor vuelve a calcular correctamente después de las cancelaciones.
        iniciar(32'h80000001);
        calcular(32'hFEFEC6C6, 1'b0);
        reset_motor();
        check("reset también cancela un resultado pendiente", hash32 === 32'b0);
        probar_vector(32'h03020100, 32'hEDC7E4D7);

        $display("Comprobaciones: %0d | Fallos: %0d", comprobaciones, fallos);
        if (fallos != 0) $fatal(1, "auth_hash32 no pasó las pruebas");
        $finish;
    end

    // Limita la simulación si un cambio futuro deja alguna tarea bloqueada.
    initial begin
        #10000;
        $fatal(1, "Tiempo máximo de simulación excedido");
    end
endmodule
