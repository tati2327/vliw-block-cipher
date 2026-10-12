`timescale 1ns/1ps

// microarchitecture.md §§1.1, 1.3, 3.14 y 4.3; tarea 24.
// Instancia core, imem y memory; solo expone clk y rst.
module top #(
  parameter     IMEM_INIT  = "",
  parameter     DMEM_INIT  = "",
  parameter int PC_W       = 22,
  parameter int IMEM_DEPTH = 4096,
  parameter int DMEM_WORDS = 16384
)(
  input logic clk, rst
);
    logic [PC_W-1:0] imem_addr;
    logic [127:0]    imem_rdata;
    logic [31:0]     dmem_addr, dmem_wdata, dmem_rdata;
    logic            dmem_we;
    logic [3:0]      dmem_be;

    core #(.PC_W(PC_W)) u_core (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_we(dmem_we),
        .dmem_be(dmem_be), .dmem_rdata(dmem_rdata)
    );

    imem #(.DEPTH(IMEM_DEPTH), .PC_W(PC_W), .INIT_FILE(IMEM_INIT)) u_imem (
        .addr(imem_addr), .rdata(imem_rdata)
    );

    memory #(.DEPTH_WORDS(DMEM_WORDS), .INIT_FILE(DMEM_INIT)) u_memory (
        .clk(clk), .addr(dmem_addr), .wdata(dmem_wdata), .we(dmem_we),
        .be(dmem_be), .rdata(dmem_rdata)
    );
endmodule
