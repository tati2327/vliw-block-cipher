`timescale 1ns/1ps

// microarchitecture.md §§1.5, 3.6 y 4.3; tarea 8.
// RAM de datos: dirección de byte, palabras de 32 bits, escritura por carril.
module memory #(parameter int DEPTH_WORDS = 16384, parameter INIT_FILE = "")
               (input  logic clk, input logic [31:0] addr, wdata, input logic we,
                input  logic [3:0] be, output logic [31:0] rdata);
    // microarchitecture.md §3.6 — arreglo de palabras (una por línea del .mem)
    localparam int AW = $clog2(DEPTH_WORDS);
    logic [31:0]   mem [0:DEPTH_WORDS-1];
    logic [AW-1:0] idx;

    // microarchitecture.md §3.6 — índice: se ignoran addr[1:0] y los bits altos
    assign idx = addr[AW+1:2];

    // microarchitecture.md §3.6 — lectura combinacional (no hay etapa MEM)
    assign rdata = mem[idx];

    // microarchitecture.md §3.6 — escritura por carril en el flanco de subida
    always_ff @(posedge clk)
        if (we)
            for (int i = 0; i < 4; i++)
                if (be[i]) mem[idx][8*i +: 8] <= wdata[8*i +: 8];

    // microarchitecture.md §3.6 — inicialización: todo en 0 y luego el .mem.
    // Sin reset: el contenido no se borra.
    initial begin
        for (int i = 0; i < DEPTH_WORDS; i++)
            mem[i] = '0;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end
endmodule
