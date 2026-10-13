`timescale 1ns/1ps

// Conecta control, estado, bóveda y datapath en una unidad de ejecución CRYPTO.
// crypto_dec permanece fuera de esta unidad, dentro de dispatch.
module crypto_unit #(
    // Usa x100 de la cadena con semilla CAFEDECE; admite otra cadena por parámetro.
    parameter logic [31:0] RESET_ANCHOR = 32'hFEFF95FF
) (
    input  logic        clk,
    input  logic        rst,         // Borra banderas, llaves y cálculo; conserva el ancla.
    input  logic        init_anchor, // Carga el ancla de fábrica en subida durante rst.
    input  logic        en,          // Habilita la rama CRYPTO del slot.
    input  logic        ex_valid,    // Indica que el bundle retenido en EX es válido.
    input  logic        ex_commit,   // Autoriza los efectos del bundle al finalizar.
    input  logic [2:0]  crypto_op,   // Recibe la operación interna desde ID/EX.
    input  logic [1:0]  k, i,        // Seleccionan llave y palabra de la bóveda.
    input  logic [31:0] a, b,        // Reciben los operandos desde ID/EX.
    output logic [31:0] result,      // Entrega una ronda feis autorizada; en otro caso, cero.
    output logic        allowed,     // Vale 1 si la operación activa cumple sus permisos.
    output logic        crypto_stall // Solicita la pausa de EX mientras termina auth.
);
    // El estado de acceso permanece interno; el programa no puede leerlo directamente.
    logic auth, kvlock, exc;
    logic [31:0] ancla_otp;
    logic auth_next, kvlock_next, exc_next;
    logic [31:0] ancla_next;

    // El control habilita la bóveda y selecciona el resultado del datapath.
    logic read_en, write_en, do_feis;
    logic [31:0] subkey;

    // El control solicita el hash; el datapath informa su avance y comparación.
    logic auth_start, auth_accept, auth_busy, auth_done, auth_match;

    crypto_control u_crypto_control (
        .en(en), .rst(rst), .ex_valid(ex_valid), .ex_commit(ex_commit),
        .crypto_op(crypto_op), .a(a),
        .auth(auth), .kvlock(kvlock), .exc(exc), .ancla_otp(ancla_otp),
        .auth_match(auth_match), .auth_busy(auth_busy), .auth_done(auth_done),
        .allowed(allowed), .read_en(read_en), .write_en(write_en), .do_feis(do_feis),
        .auth_start(auth_start), .auth_accept(auth_accept), .crypto_stall(crypto_stall),
        .auth_next(auth_next), .kvlock_next(kvlock_next), .exc_next(exc_next),
        .ancla_next(ancla_next)
    );

    // Propaga el parámetro de fábrica al registro que realmente guarda el ancla.
    crypto_state #(.RESET_ANCHOR(RESET_ANCHOR)) u_crypto_state (
        .clk(clk), .rst(rst), .init_anchor(init_anchor),
        .auth_next(auth_next), .kvlock_next(kvlock_next), .exc_next(exc_next),
        .ancla_next(ancla_next), .auth(auth), .kvlock(kvlock), .exc(exc),
        .ancla_otp(ancla_otp)
    );

    // Las escrituras toman a como dato; la lectura solo llega al datapath CRYPTO.
    key_vault u_key_vault (
        .clk(clk), .rst(rst), .k(k), .i(i), .read_en(read_en),
        .write_en(write_en), .write_data(a), .subkey(subkey)
    );

    crypto_datapath u_crypto_datapath (
        .clk(clk), .rst(rst), .a(a), .b(b), .subkey(subkey), .ancla_otp(ancla_otp),
        .auth_start(auth_start), .auth_accept(auth_accept), .do_feis(do_feis),
        .result(result), .auth_match(auth_match), .auth_busy(auth_busy), .auth_done(auth_done)
    );
endmodule
