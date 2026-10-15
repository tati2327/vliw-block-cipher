`timescale 1ns/1ps

// Comprueba toda la tabla de cinco bits, incluidos los 25 códigos libres.
module tb_crypto_dec;
    logic [4:0] funct;
    logic [2:0] crypto_op;
    logic we;
    logic [3:0] esperado;
    int comprobaciones = 0, fallos = 0;

    crypto_dec u_crypto_dec (.funct(funct), .crypto_op(crypto_op), .we(we));

    initial begin
        $dumpfile("build/tb_crypto_dec.vcd");
        $dumpvars(0, tb_crypto_dec);

        // Visita los 32 códigos en orden alternado entre rangos válidos y libres.
        // Multiplicar por siete módulo 32 recorre cada valor exactamente una vez.
        for (int caso = 0; caso < 32; caso++) begin
            funct = 5'((caso * 7) % 32);
            // El esperado concatena la operación de tres bits y we de un bit.
            case (funct)
                5'b00000: esperado = 4'b0000; // NOP.
                5'b00001: esperado = 4'b0011; // feis.
                5'b00010: esperado = 4'b0100; // auth.
                5'b00011: esperado = 4'b0110; // logout.
                5'b00100: esperado = 4'b1000; // kv_write.
                5'b00101: esperado = 4'b1010; // kv_lock.
                5'b00110: esperado = 4'b1100; // sanc.
                default:  esperado = 4'b0000; // Códigos libres.
            endcase
            #1;
            comprobaciones++;
            if ({crypto_op, we} === esperado) begin
                $display("PASS: funct=%05b crypto_op=%03b we=%b", funct, crypto_op, we);
            end else begin
                fallos++;
                $display("FAIL: funct=%05b obtenido=%04b esperado=%04b",
                         funct, {crypto_op, we}, esperado);
            end
        end

        $display("Comprobaciones: %0d | Fallos: %0d", comprobaciones, fallos);
        if (fallos != 0) $fatal(1, "crypto_dec no pasó las pruebas");
        $finish;
    end
endmodule
