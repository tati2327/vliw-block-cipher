`timescale 1ns/1ps

// microarchitecture.md §§3.13, 4.3 y 4.5; tarea 4.
// Prioridad: reset asíncrono > flush síncrono > habilitación de carga.
module pipe_reg #(parameter int W = 1) (
    input  logic clk, rst, flush, en,
    input  logic [W-1:0] d,
    output logic [W-1:0] q
);
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            q <= '0;
        else if (flush)
            q <= '0;
        else if (en)
            q <= d;
        // Sin carga: el registro conserva q. No es lógica combinacional.
    end
endmodule
