`timescale 1ns/1ps

// ISA §§3 y 11; microarchitecture.md §§1.5, 3.7 y 4.3; tarea 9.
// Dirección en bundles; salida de un bundle completo por lectura.
module imem #(
    parameter int DEPTH = 4096,
    parameter int PC_W = 22,
    parameter INIT_FILE = ""
) (
    input  logic [PC_W-1:0] addr,
    output logic [127:0] rdata
);
    // Al menos un bit para permitir también una ROM de una sola posición.
    localparam int IW = (DEPTH > 1) ? $clog2(DEPTH) : 1;
    logic [127:0] rom [0:DEPTH-1];

    // Comparación con la dirección completa ANTES de consumir el índice local.
    // Fuera de rango no se vuelve al comienzo del programa.
    assign rdata = (addr < DEPTH) ? rom[addr[IW-1:0]] : 128'b0;

    // Inicialización de simulación: posiciones sin programa son nopi.
    initial begin
        for (int i = 0; i < DEPTH; i++)
            rom[i] = '0;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, rom);
    end
endmodule
