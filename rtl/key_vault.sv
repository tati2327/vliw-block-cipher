`timescale 1ns/1ps

// Guarda cuatro llaves, cada una formada por cuatro palabras de 32 bits.
// crypto_control calcula los permisos y entrega read_en y write_en.
module key_vault (
    input  logic        clk,        // Actualiza el almacenamiento en subida.
    input  logic        rst,        // Borra todas las palabras de forma asíncrona.
    input  logic [1:0]  k,          // Selecciona una de las cuatro llaves.
    input  logic [1:0]  i,          // Selecciona una de sus cuatro palabras.
    input  logic        read_en,    // Habilita la salida de la palabra seleccionada.
    input  logic        write_en,   // Habilita la escritura de una sola palabra.
    input  logic [31:0] write_data, // Contiene el dato que se guarda en llaves[k][i].
    output logic [31:0] subkey      // Entrega la palabra o cero si read_en = 0.
);
    // matriz de 16 palabras; contiene 512 bits de almacenamiento.
    logic [31:0] llaves [0:3][0:3];

    // la lectura cambia con los índices, sin esperar un flanco de reloj.
    // La salida se conecta al datapath CRYPTO y no al banco de registros.
    assign subkey = read_en ? llaves[k][i] : 32'b0;

    // el reset tiene prioridad sobre cualquier escritura.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Borra las cuatro palabras de cada una de las cuatro llaves.
            for (int llave = 0; llave < 4; llave++) begin
                for (int palabra = 0; palabra < 4; palabra++) begin
                    llaves[llave][palabra] <= 32'b0;
                end
            end
        end else if (write_en) begin
            // Modifica la posición seleccionada y conserva las otras quince.
            llaves[k][i] <= write_data;
        end
        // Con write_en = 0, todos los registros conservan sus valores.
    end
endmodule
