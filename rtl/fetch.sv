`timescale 1ns/1ps

// microarchitecture.md §§3.12, 4.3 y 4.5; tarea 6.
// PC de IF: cuenta bundles. Su incrementador es independiente del de BRU.
module fetch #(parameter int PC_W = 22) (
    input  logic clk, rst,
    input  logic stall,
    input  logic branch_taken,
    input  logic [PC_W-1:0] branch_target,
    output logic [PC_W-1:0] pc
);
    logic [PC_W-1:0] pc_plus_one, redirect_pc, next_pc;

    // Incrementador y dos multiplexores del diseño modular.
    assign pc_plus_one = pc + 1'b1;
    assign redirect_pc = branch_taken ? branch_target : pc_plus_one;
    assign next_pc = stall ? pc : redirect_pc;

    // Prioridad: reset asíncrono > stall > salto > avance secuencial.
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            pc <= '0;
        else
            pc <= next_pc;
    end
endmodule
