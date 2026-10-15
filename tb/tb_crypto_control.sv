`timescale 1ns/1ps

// Aplica la tabla de permisos y cambios de estado a las entradas del control.
module tb_crypto_control;
    logic en, rst, ex_valid, ex_commit;
    logic [2:0] crypto_op;
    logic [31:0] a, ancla_otp;
    logic auth, kvlock, exc, auth_match, auth_busy, auth_done;
    logic allowed, read_en, write_en, do_feis;
    logic auth_start, auth_accept, crypto_stall;
    logic auth_next, kvlock_next, exc_next;
    logic [31:0] ancla_next;
    logic [7:0] permisos;
    logic [6:0] controles_esperados;
    logic [2:0] banderas_esperadas;
    logic [31:0] ancla_esperada;
    int comprobaciones = 0, fallos = 0;

    crypto_control u_crypto_control (
        .en(en), .rst(rst), .ex_valid(ex_valid), .ex_commit(ex_commit),
        .crypto_op(crypto_op), .a(a), .auth(auth), .kvlock(kvlock), .exc(exc),
        .ancla_otp(ancla_otp), .auth_match(auth_match), .auth_busy(auth_busy),
        .auth_done(auth_done), .allowed(allowed), .read_en(read_en),
        .write_en(write_en), .do_feis(do_feis), .auth_start(auth_start),
        .auth_accept(auth_accept), .crypto_stall(crypto_stall),
        .auth_next(auth_next), .kvlock_next(kvlock_next), .exc_next(exc_next),
        .ancla_next(ancla_next)
    );

    // Compara juntas todas las salidas e identifica el escenario si falla.
    task automatic comprobar(input string nombre);
        #1;
        comprobaciones++;
        if ({allowed, read_en, write_en, do_feis, auth_start, auth_accept,
             crypto_stall, auth_next, kvlock_next, exc_next, ancla_next} ===
            {controles_esperados, banderas_esperadas, ancla_esperada}) begin
            $display("PASS: %s", nombre);
        end else begin
            fallos++;
            $display("FAIL: %s", nombre);
            $display("  control obtenido=%07b esperado=%07b",
                     {allowed, read_en, write_en, do_feis, auth_start, auth_accept,
                      crypto_stall}, controles_esperados);
            $display("  banderas obtenidas=%03b esperadas=%03b, ancla=%08h esperada=%08h",
                     {auth_next, kvlock_next, exc_next}, banderas_esperadas,
                     ancla_next, ancla_esperada);
        end
    endtask

    initial begin
        $dumpfile("build/tb_crypto_control.vcd");
        $dumpvars(0, tb_crypto_control);
        en = 1'b1;
        rst = 1'b0;
        ex_valid = 1'b1;
        auth_busy = 1'b0;
        auth_done = 1'b0;
        auth_match = 1'b0;
        a = 32'h12345678;
        ancla_otp = 32'hA1B2C3D4;

        // Recorre las ocho combinaciones de banderas y las ocho operaciones.
        // Los bits de permisos se ordenan de operación 7 a operación 0.
        for (int estado = 0; estado < 8; estado++) begin
            {auth, kvlock, exc} = 3'(estado);
            case (estado)
                0, 1, 2, 3: permisos = 8'b00001100;
                4, 5:       permisos = 8'b01111110;
                6, 7:       permisos = 8'b01101110;
            endcase
            for (int op = 0; op < 8; op++) begin
                crypto_op = 3'(op);
                for (int commit = 0; commit < 2; commit++) begin
                    ex_commit = 1'(commit);
                    controles_esperados = {permisos[op], 6'b0};
                    banderas_esperadas = 3'(estado);
                    ancla_esperada = ancla_otp;
                    // Orden del control: allowed, read, write, feis, start, accept, stall.
                    case (op)
                        1: controles_esperados = auth ? 7'b1101000 : 7'b0000000;
                        2: controles_esperados = 7'b1000101;
                        4: controles_esperados[4] = permisos[4] && ex_commit;
                        default: begin end
                    endcase
                    if (commit) begin
                        case (op)
                            1, 4, 5, 6: begin
                                if (!permisos[op]) banderas_esperadas[0] = 1'b1;
                                else if (op == 5) banderas_esperadas[1] = 1'b1;
                                else if (op == 6) ancla_esperada = a;
                            end
                            3: banderas_esperadas[2] = 1'b0;
                            default: begin end
                        endcase
                    end
                    comprobar($sformatf("estado=%03b op=%0d commit=%0d", 3'(estado), op, commit));
                end
            end
        end

        // Recorre las fases del hash, la coincidencia y la autorización de commit.
        crypto_op = 3'b010;
        for (int estado = 0; estado < 8; estado++) begin
            {auth, kvlock, exc} = 3'(estado);
            for (int fase = 0; fase < 3; fase++) begin
                auth_busy = (fase == 1);
                auth_done = (fase == 2);
                for (int match = 0; match < 2; match++) begin
                    auth_match = 1'(match);
                    for (int commit = 0; commit < 2; commit++) begin
                        ex_commit = 1'(commit);
                        banderas_esperadas = 3'(estado);
                        ancla_esperada = ancla_otp;
                        case (fase)
                            0: controles_esperados = 7'b1000101;
                            1: controles_esperados = 7'b1000001;
                            2: begin
                                controles_esperados = commit ? 7'b1000010 : 7'b1000000;
                                if (commit) begin
                                    banderas_esperadas = {auth_match, kvlock, !auth_match};
                                    if (match) ancla_esperada = a;
                                end
                            end
                        endcase
                        comprobar($sformatf("auth estado=%03b fase=%0d match=%0d commit=%0d",
                                            3'(estado), fase, match, commit));
                    end
                end
            end
        end

        // Cada condición de inactividad bloquea efectos incluso con commit y done.
        auth = 1'b1;
        kvlock = 1'b0;
        exc = 1'b1;
        ex_commit = 1'b1;
        auth_busy = 1'b0;
        auth_done = 1'b1;
        auth_match = 1'b1;
        for (int bloqueo = 0; bloqueo < 3; bloqueo++) begin
            en = (bloqueo != 0);
            ex_valid = (bloqueo != 1);
            rst = (bloqueo == 2);
            for (int op = 0; op < 8; op++) begin
                crypto_op = 3'(op);
                controles_esperados = 7'b0;
                banderas_esperadas = {auth, kvlock, exc};
                ancla_esperada = ancla_otp;
                comprobar($sformatf("inactivo motivo=%0d op=%0d", bloqueo, op));
            end
        end

        $display("Comprobaciones: %0d | Fallos: %0d", comprobaciones, fallos);
        if (fallos != 0) $fatal(1, "crypto_control no pasó las pruebas");
        $finish;
    end
endmodule
