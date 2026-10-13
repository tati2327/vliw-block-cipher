`timescale 1ns/1ps

// Calcula permisos y señales de control sin guardar estado ni recibir reloj.
// Los cambios de estado se aplican cuando ex_commit permite finalizar el bundle.
module crypto_control (
    input  logic        en,         // Habilita la unidad CRYPTO para este bundle.
    input  logic        rst,        // Deshabilita las operaciones durante el reset.
    input  logic        ex_valid,   // Indica que el bundle en EX es válido.
    input  logic        ex_commit,  // Permite aplicar los efectos del bundle.
    input  logic [2:0]  crypto_op,  // Identifica la operación que decodificó crypto_dec.
    input  logic [31:0] a,          // Contiene el token o el nuevo valor del ancla.
    input  logic        auth,       // Indica si existe una sesión autenticada.
    input  logic        kvlock,     // Indica si la bóveda está sellada.
    input  logic        exc,        // Contiene la bandera de excepción actual.
    input  logic [31:0] ancla_otp,  // Contiene el ancla actual.
    input  logic        auth_match, // Indica que el hash coincide con el ancla.
    input  logic        auth_busy,  // Indica que el motor de hash está calculando.
    input  logic        auth_done,  // Indica que el hash está disponible.
    output logic        allowed,    // Indica permiso; en auth no indica token válido.
    output logic        read_en,    // Habilita la lectura de una subllave para feis.
    output logic        write_en,   // Habilita una escritura autorizada en la bóveda.
    output logic        do_feis,    // Selecciona el resultado de una feis permitida.
    output logic        auth_start, // Solicita el cálculo de un hash al motor libre.
    output logic        auth_accept,// Confirma el consumo del hash al finalizar auth.
    output logic        crypto_stall,// Solicita la pausa del pipeline durante auth.
    output logic        auth_next,  // Entrega el valor siguiente de autenticación.
    output logic        kvlock_next,// Entrega el valor siguiente del sello de bóveda.
    output logic        exc_next,   // Entrega el valor siguiente de excepción.
    output logic [31:0] ancla_next  // Entrega el valor siguiente del ancla.
);
    localparam logic [2:0] OP_FEIS   = 3'b001;
    localparam logic [2:0] OP_AUTH   = 3'b010;
    localparam logic [2:0] OP_LOGOUT = 3'b011;
    localparam logic [2:0] OP_WRITE  = 3'b100;
    localparam logic [2:0] OP_LOCK   = 3'b101;
    localparam logic [2:0] OP_SANC   = 3'b110;

    logic activo;
    assign activo = en && ex_valid && !rst;

    always_comb begin
        // Deshabilita efectos y devuelve el estado actual por defecto.
        // Cada salida recibe un valor en todos los caminos; no genera latches.
        allowed      = 1'b0;
        read_en      = 1'b0;
        write_en     = 1'b0;
        do_feis      = 1'b0;
        auth_start   = 1'b0;
        auth_accept  = 1'b0;
        crypto_stall = 1'b0;
        auth_next    = auth;
        kvlock_next  = kvlock;
        exc_next     = exc;
        ancla_next   = ancla_otp;

        if (activo) begin
            case (crypto_op)
                OP_FEIS: begin
                    // Calcula el resultado cuando hay permiso, incluso sin commit.
                    // El pipeline controla cuándo se escribe el registro destino.
                    allowed = auth;
                    do_feis = auth;
                    read_en = auth;
                    if (ex_commit && !auth) exc_next = 1'b1;
                end
                OP_AUTH: begin
                    // Cualquier sesión puede intentar autenticarse.
                    // allowed no depende de que el token sea correcto.
                    allowed      = 1'b1;
                    crypto_stall = !auth_done;
                    auth_start   = !auth_busy && !auth_done;
                    auth_accept  = auth_done && ex_commit;
                    if (auth_done && ex_commit) begin
                        // Un token válido abre la sesión, limpia exc y avanza el ancla.
                        // Un token inválido cierra la sesión y conserva el ancla.
                        auth_next = auth_match;
                        exc_next  = !auth_match;
                        if (auth_match) ancla_next = a;
                    end
                end
                OP_LOGOUT: begin
                    // Cierra la sesión; conserva el sello, la excepción y el ancla.
                    allowed = 1'b1;
                    if (ex_commit) auth_next = 1'b0;
                end
                OP_WRITE: begin
                    // El sello bloquea la escritura incluso con una sesión válida.
                    allowed  = auth && !kvlock;
                    write_en = allowed && ex_commit;
                    if (ex_commit && !allowed) exc_next = 1'b1;
                end
                OP_LOCK: begin
                    // Sella la bóveda hasta el reset; no altera su contenido.
                    allowed = auth;
                    if (ex_commit) begin
                        if (auth) kvlock_next = 1'b1;
                        else exc_next = 1'b1;
                    end
                end
                OP_SANC: begin
                    // Reemplaza el ancla solo con una sesión autorizada.
                    allowed = auth;
                    if (ex_commit) begin
                        if (auth) ancla_next = a;
                        else exc_next = 1'b1;
                    end
                end
                default: begin
                    // NOP y 111 conservan el estado y las salidas deshabilitadas.
                end
            endcase
        end
        // El reset de los registros y de la bóveda ocurre en sus propios módulos.
    end
endmodule
