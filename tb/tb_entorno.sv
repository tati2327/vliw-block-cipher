`timescale 1ns/1ps

module tb_entorno;

    logic [7:0][3:0] datos;

    initial begin
        $dumpfile("build/tb_entorno.vcd");
        $dumpvars(0, tb_entorno);

        datos = 32'h06000043;
        #1;

        if (datos[0] === 4'd3 &&
            datos[1] === 4'd4 &&
            datos[6] === 4'd6) begin
            $display("PASS: arreglos empaquetados");
        end else begin
            $fatal(1, "FAIL: arreglos empaquetados");
        end

        $finish;
    end

endmodule