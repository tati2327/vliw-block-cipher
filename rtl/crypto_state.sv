`timescale 1ns/1ps

// Guarda las banderas de acceso y el ancla de autenticación.
// El control entrega los valores siguientes; entrega los actuales si no cambia nada.
// El ancla por defecto corresponde a x100 de la cadena con semilla CAFEDECE.
module crypto_state #(
    parameter logic [31:0] RESET_ANCHOR = 32'hFEFF95FF
) (
    input  logic        clk,        // Guarda las entradas en el flanco de subida.
    input  logic        rst,        // Limpia las banderas y bloquea cambios del ancla.
    input  logic        init_anchor,// Habilita la carga de fábrica mientras rst = 1.
    input  logic        auth_next,  // Contiene el valor siguiente de autenticación.
    input  logic        kvlock_next,// Contiene el valor siguiente del bloqueo de bóveda.
    input  logic        exc_next,   // Contiene el valor siguiente de excepción.
    input  logic [31:0] ancla_next, // Contiene el valor siguiente del ancla.
    output logic        auth,       // Indica si hay una sesión autenticada.
    output logic        kvlock,     // Indica si la bóveda está bloqueada para escritura.
    output logic        exc,        // Indica el estado de excepción de CRYPTO.
    output logic [31:0] ancla_otp   // Contiene el ancla que se compara con el hash.
);
    // Las tres banderas se limpian inmediatamente cuando se activa el reset.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            auth   <= 1'b0;
            kvlock <= 1'b0;
            exc    <= 1'b0;
        end else begin
            auth   <= auth_next;
            kvlock <= kvlock_next;
            exc    <= exc_next;
        end
    end

    // El ancla conserva los tokens consumidos durante un reset normal.
    // Tiene control síncrono: rst por sí solo no borra ni inicializa este registro.
    // El arranque mantiene rst e init_anchor en 1 durante una subida de clk.
    always_ff @(posedge clk) begin
        if (rst) begin
            if (init_anchor) begin
                ancla_otp <= RESET_ANCHOR;
            end
            // Con init_anchor = 0 conserva el ancla, incluso con ancla_next distinto.
        end else begin
            // Con rst = 0, init_anchor no restaura el valor de fábrica.
            ancla_otp <= ancla_next;
        end
    end
endmodule
