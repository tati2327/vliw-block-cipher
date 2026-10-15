`timescale 1ns/1ps

// ISA §§8 y 9.1; microarchitecture.md §§3.1, 4.1, 4.3 y 4.5.
module regfile #(
    parameter int NUM_SLOTS = 4,
    parameter int XLEN = 32,
    parameter int NUM_REGS = 16,
    parameter int AW = $clog2(NUM_REGS),
    parameter int NUM_RD = 2 * NUM_SLOTS
) (
    input  logic clk, rst,
    input  logic [NUM_RD-1:0][AW-1:0] raddr,
    output logic [NUM_RD-1:0][XLEN-1:0] rdata,
    input  logic [NUM_SLOTS-1:0][AW-1:0] waddr,
    input  logic [NUM_SLOTS-1:0][XLEN-1:0] wdata,
    input  logic [NUM_SLOTS-1:0] we
);
    logic [NUM_REGS-1:0][XLEN-1:0] regs;

    // Lecturas combinacionales independientes: dos puertos por slot.
    for (genvar p = 0; p < NUM_RD; p++) begin : g_read
        assign rdata[p] = regs[raddr[p]];
    end

    // Escritura en bajada: el dato llega a ID antes de la siguiente subida.
    // Un único proceso evita carreras entre escritores del banco.
    always_ff @(negedge clk or posedge rst) begin
        if (rst)
            regs <= '0;
        else begin
            // Las asignaciones al mismo destino se resuelven en este orden:
            // gana el último slot habilitado, es decir el de número mayor.
            for (int s = 0; s < NUM_SLOTS; s++) begin
                if (we[s] && waddr[s] != '0)
                    regs[waddr[s]] <= wdata[s];
            end
        end
    end
endmodule
