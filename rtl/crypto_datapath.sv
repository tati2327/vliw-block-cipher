`timescale 1ns/1ps

// Calcula una ronda Feistel y conecta el hash con el comparador del ancla.
// crypto_control decide los permisos y habilita cada operación.
module crypto_datapath (
    input  logic        clk,        // Hace avanzar los registros del motor de hash.
    input  logic        rst,        // Cancela el cálculo del hash y limpia su estado.
    input  logic [31:0] a,          // Contiene el operando de ronda o el token de auth.
    input  logic [31:0] b,          // Contiene el operando que entra a la función F.
    input  logic [31:0] subkey,     // Contiene la palabra seleccionada de la bóveda.
    input  logic [31:0] ancla_otp,  // Contiene el valor esperado del hash del token.
    input  logic        auth_start, // Solicita al motor el hash del token a.
    input  logic        auth_accept,// Confirma que el control consumió el hash.
    input  logic        do_feis,    // Habilita la salida de la ronda autorizada.
    output logic [31:0] result,     // Entrega la ronda si do_feis = 1; en otro caso, cero.
    output logic        auth_match, // Compara hash y ancla; se usa solo con auth_done = 1.
    output logic        auth_busy,  // Indica que el motor está calculando el hash.
    output logic        auth_done   // Indica que el hash está listo y pendiente de aceptación.
);
    logic [31:0] rol5, rol13; //rotaciones
    logic [31:0] sum32, f_out, ronda; //calculo feistel
    logic [31:0] hash32; //resultado de auntenticación

    // Rota b a la izquierda: los bits altos vuelven a entrar por el extremo bajo.
    // Las concatenaciones describen conexiones fijas, sin registros adicionales.
    assign rol5  = {b[26:0], b[31:27]};
    assign rol13 = {b[18:0], b[31:19]};

    // F(b, subkey) suma la llave a rol5 y aplica XOR con rol13.
    // sum32 conserva 32 bits: descarta el acarreo de la suma, según el diseño.
    assign sum32 = rol5 + subkey;
    assign f_out = sum32 ^ rol13;
    assign ronda = a ^ f_out;

    // El resultado no expone el hash ni copia directamente una subllave.
    // Fuera de una feis habilitada, la salida permanece en cero.
    assign result = do_feis ? ronda : 32'b0;

    // Usa a como token; la bóveda y b no intervienen en la autenticación.
    // La notación .puerto(señal) conecta cada puerto del motor con este módulo.
    auth_hash32 u_auth_hash32 (
        .clk(clk),
        .rst(rst),
        .start(auth_start),
        .accept(auth_accept),
        .token(a),
        .hash32(hash32),
        .busy(auth_busy),
        .done(auth_done)
    );

    // La igualdad se calcula continuamente, incluso mientras cambia el hash.
    // El control solo utiliza esta comparación cuando auth_done indica resultado válido.
    assign auth_match = (hash32 == ancla_otp);
endmodule
