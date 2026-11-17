`timescale 1ns/1ps

// Comprueba las palabras observadas y conserva los stores confirmados por la interfaz.
module mem_monitor #(
    parameter INIT_FILE = "",
    parameter LOG_FILE = "build/transacciones.txt"
)(
    input logic clk, rst, req, we, listo,
    input logic [31:0] addr, wdata, rdata,
    input logic [3:0] be,
    output logic [63:0] loads_checked = 0, stores_applied = 0, discrepancies = 0
);
    logic [31:0] mem [0:16383];
    longint unsigned cycle = 0, wait_cycles = 0;
    integer log_fd = 0;
    initial begin
        for (int i = 0; i < 16384; i++) mem[i] = 0;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
        if ($test$plusargs("LOG_MEM")) begin
            log_fd = $fopen(LOG_FILE, "w");
            if (!log_fd) $fatal(1, "No se pudo abrir LOG_FILE: %s", LOG_FILE);
            $fdisplay(log_fd, "ciclo tipo direccion dato espera");
        end
    end
    always @(posedge clk) begin
        if (rst) begin
            cycle = 0; wait_cycles = 0;
            loads_checked = 0; stores_applied = 0; discrepancies = 0;
        end else begin
            cycle++;
            if (req && listo) begin
                if (we) begin
                    for (int b = 0; b < 4; b++)
                        if (be[b]) mem[addr[15:2]][8*b +: 8] = wdata[8*b +: 8];
                    stores_applied++;
                end else begin
                    loads_checked++;
                    if (rdata !== mem[addr[15:2]]) begin
                        discrepancies++;
                        $display("FAIL monitor direccion=%h esperado=%h obtenido=%h ciclo=%0d",
                                 addr, mem[addr[15:2]], rdata, cycle);
                    end
                end
                if (log_fd) $fdisplay(log_fd, "%0d %s %08h %08h %0d", cycle,
                                     we ? "store" : "load ", addr, we ? wdata : rdata, wait_cycles);
                wait_cycles = 0;
            end else if (req) wait_cycles++;
            else wait_cycles = 0;
        end
    end
    final if (log_fd) $fclose(log_fd);
endmodule
