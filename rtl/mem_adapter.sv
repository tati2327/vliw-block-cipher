`timescale 1ns/1ps

// Convierte un pedido de palabra en un único acceso de línea, sin guardar líneas.
module mem_adapter (
    input logic clk, rst,
    input logic req, we,
    input logic [31:0] addr, wdata,
    input logic [3:0] be,
    output logic [31:0] rdata,
    output logic listo,
    output logic line_req, line_we,
    output logic [10:0] line_addr,
    output logic [255:0] line_wdata,
    output logic [31:0] line_mask,
    input logic line_accepted, line_ready,
    input logic [255:0] line_rdata
);
    logic active, sent;
    logic saved_we;
    logic [31:0] saved_addr, saved_data;
    logic [3:0] saved_be;
    wire [31:0] selected_addr = active ? saved_addr : addr;
    wire [31:0] selected_data = active ? saved_data : wdata;
    wire [3:0] selected_be = active ? saved_be : be;
    wire [2:0] word_index = selected_addr[4:2];
    assign line_addr = selected_addr[15:5];
    assign line_we = active ? saved_we : we;
    // El primer pedido pasa directamente; después se sostiene hasta accepted.
    // accepted se observa también combinacionalmente para bajar req de inmediato.
    assign line_req = !rst && (active ? (!sent && !line_accepted) : req);
    always_comb begin
        line_wdata = 0;
        line_mask = 0;
        line_wdata[32*word_index +: 32] = selected_data;
        line_mask[4*word_index +: 4] = selected_be;
    end
    assign rdata = line_rdata[32*word_index +: 32];
    assign listo = active && line_ready;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            active <= 0; sent <= 0;
            saved_we <= 0; saved_addr <= 0; saved_data <= 0; saved_be <= 0;
        end else if (listo) begin
            active <= 0; sent <= 0;
        end else if (!active && req) begin
            active <= 1; sent <= 0;
            saved_we <= we; saved_addr <= addr; saved_data <= wdata; saved_be <= be;
        end else if (active && line_accepted) sent <= 1;
    end
endmodule
