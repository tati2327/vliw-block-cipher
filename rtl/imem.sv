`timescale 1ns/1ps

// ISA §§3 y 11; microarchitecture.md §§1.5, 3.7 y 4.3; tarea 9.
// Dirección en bundles; salida de un bundle completo por lectura.
// ROM SÍNCRONA (enunciado P2 §3.1.1 y §3.2.1; M-09): la lectura se registra en el flanco
// de subida de clk y ese registro de salida ES el registro IF/ID del bundle (M-09). Carga con
// en = ~stall y conserva el bundle mientras en = 0 (misma regla que pipe_reg). flush síncrono
// lo pone en cero (nopi): tras un salto tomado el bundle anulado es un nopi y además el bit
// ifid_valid = 0 lo marca como anulado (M-09). Prioridad: reset asíncrono > flush > en.
module imem #(
    parameter int DEPTH = 4096,
    parameter int PC_W = 22,
    parameter INIT_FILE = ""
) (
    input  logic clk, rst, flush, en,
    input  logic [PC_W-1:0] addr,
    output logic [127:0] rdata
);
    // Al menos un bit para permitir también una ROM de una sola posición.
    localparam int IW = (DEPTH > 1) ? $clog2(DEPTH) : 1;
    logic [127:0] rom [0:DEPTH-1];

    // Comparación con la dirección completa ANTES de consumir el índice local.
    // Fuera de rango no se vuelve al comienzo del programa.
    logic [127:0] rd_next;
    assign rd_next = (addr < DEPTH) ? rom[addr[IW-1:0]] : 128'b0;

    // Registro de salida: reset asíncrono > flush síncrono > carga con en (como pipe_reg). El bundle llega
    // un flanco después de presentar addr y no se pierde ni cambia si en = 0 (pausa, M-09).
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            rdata <= '0;
        else if (flush)
            rdata <= '0;
        else if (en)
            rdata <= rd_next;
    end

    // Inicialización de simulación: posiciones sin programa son nopi.
    initial begin
        for (int i = 0; i < DEPTH; i++)
            rom[i] = '0;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, rom);
    end
endmodule
