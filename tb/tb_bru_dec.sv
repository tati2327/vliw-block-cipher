`timescale 1ns/1ps

module tb_bru_dec;
    logic [4:0] funct;
    logic [2:0] br_op;
    logic we;
    logic [3:0] esperado;
    int casos = 0;
    int fallos = 0;
    bru_dec u_bru_dec (.funct, .br_op, .we);
    initial begin
        $dumpfile("build/tb_bru_dec.vcd");
        $dumpvars(0, tb_bru_dec);
        // Esperado = {br_op, we}, tabla oficial de §4.8, los 32 códigos.
        for (int code = 0; code < 32; code++) begin
            case (code)
                1: esperado = 4'b0010;
                2: esperado = 4'b0100;
                3: esperado = 4'b0110;
                4: esperado = 4'b1000;
                5: esperado = 4'b1111;
                16: esperado = 4'b1010;
                17: esperado = 4'b1101;
                default: esperado = 4'b0000;
            endcase
            funct = code[4:0]; #1;
            casos++;
            if ({br_op, we} === esperado)
                $display("PASS funct=%05b", funct);
            else begin
                fallos++;
                $display("FAIL funct=%05b obtenido=%04b esperado=%04b",
                    funct, {br_op, we}, esperado);
            end
        end
        funct = 5'b10001; #1;
        funct = 5'b00000; #1;
        casos++;
        if ({br_op, we} === 4'b0000) $display("PASS jas -> nopi");
        else begin fallos++; $display("FAIL jas -> nopi"); end
        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_bru_dec");
        $display("PASS tb_bru_dec");
        $finish;
    end
endmodule
