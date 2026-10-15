`timescale 1ns/1ps

module tb_lsu_dec;
    logic [4:0] funct;
    logic is_load, is_store, is_byte;
    logic [2:0] expected;
    int fallos = 0;
    int casos = 0;
    lsu_dec u_lsu_dec (.funct, .is_load, .is_store, .is_byte);

    initial begin
        $dumpfile("build/tb_lsu_dec.vcd");
        $dumpvars(0, tb_lsu_dec);
        // Tabla de microarchitecture.md §4.8: todas las codificaciones.
        for (int code = 0; code < 32; code++) begin
            case (code)
                1: expected = 3'b100;
                2: expected = 3'b010;
                3: expected = 3'b101;
                4: expected = 3'b011;
                default: expected = 3'b000;
            endcase
            funct = code[4:0];
            #1;
            casos++;
            if ({is_load, is_store, is_byte} === expected)
                $display("PASS funct=%05b", funct);
            else begin
                fallos++;
                $display("FAIL funct=%05b: obtenido=%03b esperado=%03b",
                    funct, {is_load, is_store, is_byte}, expected);
            end
        end
        // Comprueba que los controles no se retienen al pasar de store a NOP.
        funct = 5'b00100; #1;
        funct = 5'b00000; #1;
        casos++;
        if ({is_load, is_store, is_byte} === 3'b000)
            $display("PASS sb -> nopi");
        else begin fallos++; $display("FAIL sb -> nopi"); end
        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_lsu_dec");
        $display("PASS tb_lsu_dec");
        $finish;
    end
endmodule
