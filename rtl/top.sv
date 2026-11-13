`timescale 1ns/1ps

// Conecta el núcleo con la ROM y la memoria principal mediante un adaptador de palabra.
module top #(
  parameter     IMEM_INIT  = "",
  parameter     DMEM_INIT  = "",
  parameter int PC_W       = 22,
  parameter int IMEM_DEPTH = 4096,
  parameter int DMEM_WORDS = 16384,
  parameter int MEM_DIV = 4
)(
  input logic clk, rst
);
    // La memoria principal dispone de un espacio fijo de 64 KiB.
    initial if (DMEM_WORDS != 16384) $fatal(1, "DMEM_WORDS debe ser 16384");
    logic [PC_W-1:0] imem_addr;
    logic            imem_en, imem_flush;
    logic [127:0]    imem_rdata;
    logic [31:0]     dmem_addr, dmem_wdata, dmem_rdata;
    logic            dmem_req, dmem_we, dmem_listo;
    logic [3:0]      dmem_be;

    // Carga el ancla de fábrica solamente durante el primer reset.
    logic por_done = 1'b0;                     // valor al encender o configurar
    logic init_anchor;
    always_ff @(posedge clk) if (rst) por_done <= 1'b1;
    assign init_anchor = rst & ~por_done;

    core #(.PC_W(PC_W)) u_core (
        .clk(clk), .rst(rst), .init_anchor(init_anchor),
        .imem_addr(imem_addr), .imem_en(imem_en), .imem_flush(imem_flush), .imem_rdata(imem_rdata),
        .dmem_req(dmem_req), .dmem_listo(dmem_listo),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_we(dmem_we),
        .dmem_be(dmem_be), .dmem_rdata(dmem_rdata)
    );

    imem #(.DEPTH(IMEM_DEPTH), .PC_W(PC_W), .INIT_FILE(IMEM_INIT)) u_imem (
        .clk(clk), .rst(rst), .flush(imem_flush), .en(imem_en), .addr(imem_addr), .rdata(imem_rdata)
    );

    logic line_req, line_we, line_accepted, line_ready;
    logic [10:0] line_addr;
    logic [255:0] line_wdata, line_rdata;
    logic [31:0] line_mask;
    mem_adapter u_mem_adapter (
        .clk(clk), .rst(rst), .req(dmem_req), .we(dmem_we),
        .addr(dmem_addr), .wdata(dmem_wdata), .be(dmem_be),
        .rdata(dmem_rdata), .listo(dmem_listo),
        .line_req(line_req), .line_we(line_we), .line_addr(line_addr),
        .line_wdata(line_wdata), .line_mask(line_mask),
        .line_accepted(line_accepted), .line_ready(line_ready), .line_rdata(line_rdata)
    );
    // Conserva el nombre de instancia para inicialización y volcado por palabra.
    main_memory #(.MEM_DIV(MEM_DIV), .INIT_FILE(DMEM_INIT)) u_memory (
        .clk(clk), .rst(rst), .req(line_req), .we(line_we), .line_addr(line_addr),
        .wdata(line_wdata), .wmask(line_mask), .accepted(line_accepted),
        .ready(line_ready), .ready_rdata(line_rdata), .rdata(), .done(), .busy(),
        .read_count(), .write_count(), .transfer_cycles(), .total_cycles(), .timeout_count()
    );
endmodule
