// Unidad de simulación: 1 ns; precisión: 1 ps. No define la frecuencia de clk.
`timescale 1ns/1ps

//Modulo auth_hash32.sv
// Recibe un token de 32 bits y calcula los primeros cuatro bytes de su hash.
// start carga el token; los doce flancos siguientes ejecutan las rondas.
// Cuando termina, done permanece en 1 hasta que otro bloque confirma con accept.
// La comparación del hash con el ancla se realiza fuera de este módulo.
module auth_hash32 (
    input  logic        clk,    // Los registros avanzan en el flanco de subida.
    input  logic        rst,    // Reset asíncrono activo en 1; cancela el cálculo.
    input  logic        start,  // Solicita el inicio si busy = 0 y done = 0.
    input  logic        accept, // Confirma que se consumió el resultado pendiente.
    input  logic [31:0] token,  // Se incorpora al estado cuando se acepta start.
    output logic [31:0] hash32, // Resultado utilizable únicamente con done = 1.
    output logic        busy,   // En 1 mientras el motor ejecuta las rondas.
    output logic        done    // En 1 mientras hay un resultado pendiente.
);
    // constantes precalculadas después de la inicialización de Ascon.
    // localparam las mantiene fijas; cada nuevo cálculo parte de estos valores.
    localparam logic [63:0] S0_INIT = 64'h9B1E5494E934D681;
    localparam logic [63:0] S1_INIT = 64'h4BC3A01E333751D2;
    localparam logic [63:0] S2_INIT = 64'hAE65396C6B34B81A;
    localparam logic [63:0] S3_INIT = 64'h3C7FD4A4D56A4DB3;
    localparam logic [63:0] S4_INIT = 64'h1A5C464906C5976D;

    // cinco registros de 64 bits guardan el estado actual (320 bits).
    logic [63:0] s0, s1, s2, s3, s4;
    // La ronda calcula estos valores; se guardan en s0..s4 en el próximo flanco.
    logic [63:0] s0_next, s1_next, s2_next, s3_next, s4_next;
    logic [3:0]  round_idx; // Ronda actual: 0..11; se necesitan cuatro bits.
    logic [7:0]  rc;        // Contiene la constante de la ronda seleccionada.
    logic [63:0] message;   // Token de 32 bits seguido de su relleno en bits altos.
    logic        load_init, last_round; // Condiciones de inicio y última ronda.

    // pasos intermedios de la ronda, sin almacenamiento entre ciclos.
    // x prepara la entrada, t aplica la parte no lineal y y termina la sustitución.
    logic [63:0] x0, x1, x2, x3, x4;
    logic [63:0] t0, t1, t2, t3, t4;
    logic [63:0] y0, y1, y2, y3, y4;

    // concatena 32 bits de relleno con los 32 bits del token.
    // Ejemplo: token = 12345678 -> message = 0000000112345678 (hex).
    // El bit 32 vale 1; los bits 63..33 valen 0. Los bytes se interpretan
    // desde token[7:0] hasta token[31:24], en orden little-endian.
    assign message    = {32'h00000001, token};
    // Impide que un nuevo inicio sobrescriba el cálculo o el resultado pendiente.
    assign load_init  = start && !busy && !done;
    // Las doce rondas se numeran desde cero: la última es la 11.
    assign last_round = (round_idx == 4'd11);
    // Muestra los 32 bits bajos de s0. También cambian durante el cálculo;
    // el receptor los utiliza únicamente cuando done = 1.
    assign hash32     = s0[31:0];

    // rota a la derecha y recupera por la izquierda los bits que salen.
    // shift: >> mueve los bits a la derecha; << los devuelve por el extremo izquierdo.
    // | aplica OR bit a bit y combina ambas partes.
    // Las llamadas usan distancias fijas entre 1 y 63.
    function automatic logic [63:0] ror64 (
        input logic [63:0] value,
        input int unsigned distance
    );
        ror64 = (value >> distance) | (value << (64 - distance));
    endfunction

    // tabla combinacional de constantes de Ascon-p[12].
    // Se actualiza cuando cambia round_idx; no necesita un flanco de reloj.
    // El valor por defecto cubre los índices fuera de 0..11.
    always_comb begin
        rc = 8'h00;
        case (round_idx)
            4'd0:  rc = 8'hF0;
            4'd1:  rc = 8'hE1;
            4'd2:  rc = 8'hD2;
            4'd3:  rc = 8'hC3;
            4'd4:  rc = 8'hB4;
            4'd5:  rc = 8'hA5;
            4'd6:  rc = 8'h96;
            4'd7:  rc = 8'h87;
            4'd8:  rc = 8'h78;
            4'd9:  rc = 8'h69;
            4'd10: rc = 8'h5A;
            4'd11: rc = 8'h4B;
            default: rc = 8'h00;
        endcase
    end

    // circuito de una ronda, reutilizado doce veces con estados distintos.
    // Las asignaciones con = se evalúan en orden y preparan cada etapa.
    // Todas las salidas se calculan siempre; este bloque no guarda estado.
    always_comb begin
        // Copia el estado actual e incorpora rc mediante XOR en s2.
        // Los 56 ceros extienden rc a 64 bits: solo altera los ocho bits bajos.
        x0 = s0;
        x1 = s1;
        x2 = s2 ^ {56'b0, rc};
        x3 = s3;
        x4 = s4;

        // Mezcla las palabras antes de la parte no lineal.
        // El orden importa: x0 usa x4 antes de que la siguiente línea cambie x4.
        x0 = x0 ^ x4;
        x4 = x4 ^ x3;
        x2 = x2 ^ x1;

        // Parte no lineal: ~ invierte bits, & aplica AND y ^ aplica XOR.
        // Conserva los x intactos: los cinco t usan los mismos x preparados.
        t0 = x0 ^ ((~x1) & x2);
        t1 = x1 ^ ((~x2) & x3);
        t2 = x2 ^ ((~x3) & x4);
        t3 = x3 ^ ((~x4) & x0);
        t4 = x4 ^ ((~x0) & x1);

        // Completa la sustitución: mezcla los t e invierte t2.
        y0 = t0 ^ t4;
        y1 = t1 ^ t0;
        y2 = ~t2;
        y3 = t3 ^ t2;
        y4 = t4;

        // Difusión: mezcla cada palabra con dos versiones rotadas de sí misma.
        // Estas distancias son las definidas por Ascon para cada palabra.
        // Los resultados quedan en *_next; los registros los capturan en el flanco.
        s0_next = y0 ^ ror64(y0, 19) ^ ror64(y0, 28);
        s1_next = y1 ^ ror64(y1, 61) ^ ror64(y1, 39);
        s2_next = y2 ^ ror64(y2,  1) ^ ror64(y2,  6);
        s3_next = y3 ^ ror64(y3, 10) ^ ror64(y3, 17);
        s4_next = y4 ^ ror64(y4,  7) ^ ror64(y4, 41);
    end

    // almacenamiento y control. <= programa la actualización de registros
    // para que todas las palabras avancen juntas usando el estado anterior.
    // El reset actúa cuando sube rst; el resto actúa solo cuando sube clk.
    // Avanza durante la pausa del pipeline, sin depender de su habilitación.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Cancela cualquier cálculo o resultado pendiente y deja el motor libre.
            s0        <= 64'b0;
            s1        <= 64'b0;
            s2        <= 64'b0;
            s3        <= 64'b0;
            s4        <= 64'b0;
            round_idx <= 4'd0;
            busy      <= 1'b0;
            done      <= 1'b0;
        end else if (load_init) begin
            // Incorpora el token una sola vez. Cambios posteriores en token
            // no afectan este cálculo porque las rondas usan el estado guardado.
            s0        <= S0_INIT ^ message;
            s1        <= S1_INIT;
            s2        <= S2_INIT;
            s3        <= S3_INIT;
            s4        <= S4_INIT;
            round_idx <= 4'd0;
            busy      <= 1'b1;
            done      <= 1'b0;
        end else if (busy) begin
            // Guarda una ronda completa en este flanco.
            s0 <= s0_next;
            s1 <= s1_next;
            s2 <= s2_next;
            s3 <= s3_next;
            s4 <= s4_next;
            if (last_round) begin
                // Con la ronda 11, detiene el cálculo y señala que el resultado está listo.
                // El contador queda en 11; el hash queda guardado en s0.
                busy <= 1'b0;
                done <= 1'b1;
            end else begin
                // Prepara el índice de la ronda que se ejecutará después.
                round_idx <= round_idx + 4'd1;
            end
        end else if (done && accept) begin
            // Libera el resultado. El estado conserva sus bits, pero deja de
            // ser válido. Un nuevo start se acepta a partir del siguiente flanco.
            done <= 1'b0;
        end
        // Sin carga, cálculo ni aceptación, conserva todos los registros.
    end
endmodule
