`timescale 1ns/1ps

// Observa los eventos del pipeline sin intervenir en su avance.
module perf_counters (
    input logic clk, rst,
    input logic ex_commit,
    input logic [2:0] ops_count,
    input logic id_redirect, crypto_stall, mem_stall, stall,
    output logic [63:0] ciclos, bundles, instrucciones, saltos,
    output logic [63:0] pausa_crypto, pausa_memoria, pausa_total
);
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ciclos <= 0; bundles <= 0; instrucciones <= 0; saltos <= 0;
            pausa_crypto <= 0; pausa_memoria <= 0; pausa_total <= 0;
        end else begin
            ciclos <= ciclos + 1;
            // La confirmación cuenta una sola vez el bundle que estuvo detenido.
            if (ex_commit) begin
                bundles <= bundles + 1;
                instrucciones <= instrucciones + {61'b0, ops_count};
            end
            if (id_redirect) saltos <= saltos + 1;
            if (crypto_stall) pausa_crypto <= pausa_crypto + 1;
            if (mem_stall) pausa_memoria <= pausa_memoria + 1;
            // stall ya combina ambas causas y evita contar dos veces su coincidencia.
            if (stall) pausa_total <= pausa_total + 1;
        end
    end
endmodule
