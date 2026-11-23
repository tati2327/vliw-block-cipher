`timescale 1ns/1ps

// Conecta el núcleo con la ROM y la jerarquía seleccionada de datos.
module top #(
  parameter     IMEM_INIT  = "",
  parameter     DMEM_INIT  = "",
  parameter int PC_W       = 22,
  parameter int IMEM_DEPTH = 4096,
  parameter int DMEM_WORDS = 16384,
  parameter int MEM_DIV = 4,
  parameter int CACHE = 2,
  // Política de reemplazo de L1. L2 conserva su selección independiente.
  // El valor 0 utiliza LRU y el valor 1 utiliza FIFO.
  parameter int L1_REPL = 0
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
    generate
        if (CACHE == 1) begin : g_cache
            logic req, we, accepted, ready, push, full;
            logic [10:0] addr, push_addr;
            logic [255:0] wdata, rdata, push_data;
            logic [31:0] mask;
            logic [1:0] resp_src;
            l1_cache #(.REPL(L1_REPL)) u_l1 (
                .clk(clk), .rst(rst), .req(dmem_req), .we(dmem_we),
                .addr(dmem_addr), .wdata(dmem_wdata), .be(dmem_be),
                .rdata(dmem_rdata), .listo(dmem_listo),
                .line_req(req), .line_we(we), .line_addr(addr),
                .line_wdata(wdata), .line_mask(mask),
                .line_accepted(accepted), .line_ready(ready), .line_rdata(rdata),
                .resp_src(resp_src), .push(push), .push_addr(push_addr),
                .push_data(push_data), .full(full),
                .read_count(), .write_count(), .read_hits(), .read_misses(),
                .write_hits(), .write_misses(), .stall_buffer_cycles(),
                .stall_l2_cycles(), .stall_memory_cycles(), .stall_full_cycles()
            );
            line_buffer #(.DEPTH(4)) u_wbuf (
                .clk(clk), .rst(rst), .req(req), .we(we), .line_addr(addr),
                .wdata(wdata), .wmask(mask), .accepted(accepted), .ready(ready),
                .ready_rdata(rdata), .resp_src(resp_src), .push(push),
                .push_addr(push_addr), .push_data(push_data), .full(full),
                .down_req(line_req), .down_we(line_we), .down_line_addr(line_addr),
                .down_wdata(line_wdata), .down_wmask(line_mask),
                .down_accepted(line_accepted), .down_ready(line_ready),
                .down_ready_rdata(line_rdata), .down_resp_src(2'd0),
                .received_count(), .forwarding_count(), .full_cycles(), .max_occupancy()
            );
        end else if (CACHE == 2) begin : g_cache2
            // L1 <-> Write Buffer
            logic l1_req, l1_we, l1_accepted, l1_ready;
            logic l1_push, wbuf_full;

            logic [10:0] l1_addr, l1_push_addr;
            logic [255:0] l1_wdata, l1_rdata, l1_push_data;
            logic [31:0] l1_mask;
            logic [1:0] l1_resp_src;

            // Write Buffer <-> L2
            logic wb_req, wb_we, wb_accepted, wb_ready;
            logic [10:0] wb_addr;
            logic [255:0] wb_wdata, wb_rdata;
            logic [31:0] wb_mask;
            logic [1:0] wb_resp_src;

            // L2 <-> Eviction Buffer
            logic l2_req, l2_we, l2_accepted, l2_ready;
            logic l2_push, ebuf_full;

            logic [10:0] l2_addr, l2_push_addr;
            logic [255:0] l2_wdata, l2_rdata, l2_push_data;
            logic [31:0] l2_mask;
            logic [1:0] l2_resp_src;

            // L1 Cache
            l1_cache #(.REPL(L1_REPL)) u_l1 (
                .clk(clk),
                .rst(rst),

                .req(dmem_req),
                .we(dmem_we),
                .addr(dmem_addr),
                .wdata(dmem_wdata),
                .be(dmem_be),
                .rdata(dmem_rdata),
                .listo(dmem_listo),

                .line_req(l1_req),
                .line_we(l1_we),
                .line_addr(l1_addr),
                .line_wdata(l1_wdata),
                .line_mask(l1_mask),

                .line_accepted(l1_accepted),
                .line_ready(l1_ready),
                .line_rdata(l1_rdata),
                .resp_src(l1_resp_src),

                .push(l1_push),
                .push_addr(l1_push_addr),
                .push_data(l1_push_data),
                .full(wbuf_full),

                .read_count(),
                .write_count(),
                .read_hits(),
                .read_misses(),
                .write_hits(),
                .write_misses(),
                .stall_buffer_cycles(),
                .stall_l2_cycles(),
                .stall_memory_cycles(),
                .stall_full_cycles()
            );

            // Write Buffer
            line_buffer #(
                .DEPTH(4)
            ) u_wbuf (
                .clk(clk),
                .rst(rst),

                .req(l1_req),
                .we(l1_we),
                .line_addr(l1_addr),
                .wdata(l1_wdata),
                .wmask(l1_mask),

                .accepted(l1_accepted),
                .ready(l1_ready),
                .ready_rdata(l1_rdata),
                .resp_src(l1_resp_src),

                .push(l1_push),
                .push_addr(l1_push_addr),
                .push_data(l1_push_data),
                .full(wbuf_full),

                .down_req(wb_req),
                .down_we(wb_we),
                .down_line_addr(wb_addr),
                .down_wdata(wb_wdata),
                .down_wmask(wb_mask),

                .down_accepted(wb_accepted),
                .down_ready(wb_ready),
                .down_ready_rdata(wb_rdata),
                .down_resp_src(wb_resp_src),

                .received_count(),
                .forwarding_count(),
                .full_cycles(),
                .max_occupancy()
            );

            // L2 Cache
            l2_cache u_l2 (
                .clk(clk),
                .rst(rst),

                .req(wb_req),
                .we(wb_we),
                .line_addr(wb_addr),
                .wdata(wb_wdata),
                .wmask(wb_mask),

                .accepted(wb_accepted),
                .ready(wb_ready),
                .ready_rdata(wb_rdata),
                .resp_src(wb_resp_src),

                .line_req(l2_req),
                .line_we(l2_we),
                .line_line_addr(l2_addr),
                .line_wdata(l2_wdata),
                .line_wmask(l2_mask),

                .line_accepted(l2_accepted),
                .line_ready(l2_ready),
                .line_rdata(l2_rdata),
                .line_resp_src(l2_resp_src),

                .push(l2_push),
                .push_addr(l2_push_addr),
                .push_data(l2_push_data),
                .full(ebuf_full),

                .read_count(),
                .write_count(),
                .read_hits(),
                .read_misses(),
                .write_hits(),
                .write_misses(),
                .stall_full_cycles()
            );

            // Eviction Buffer
            line_buffer #(
                .DEPTH(8)
            ) u_ebuf (
                .clk(clk),
                .rst(rst),

                .req(l2_req),
                .we(l2_we),
                .line_addr(l2_addr),
                .wdata(l2_wdata),
                .wmask(l2_mask),

                .accepted(l2_accepted),
                .ready(l2_ready),
                .ready_rdata(l2_rdata),
                .resp_src(l2_resp_src),

                .push(l2_push),
                .push_addr(l2_push_addr),
                .push_data(l2_push_data),
                .full(ebuf_full),

                .down_req(line_req),
                .down_we(line_we),
                .down_line_addr(line_addr),
                .down_wdata(line_wdata),
                .down_wmask(line_mask),

                .down_accepted(line_accepted),
                .down_ready(line_ready),
                .down_ready_rdata(line_rdata),
                .down_resp_src(2'd0),

                .received_count(),
                .forwarding_count(),
                .full_cycles(),
                .max_occupancy()
            );
        end else begin : g_direct
            mem_adapter u_mem_adapter (
                .clk(clk), .rst(rst), .req(dmem_req), .we(dmem_we),
                .addr(dmem_addr), .wdata(dmem_wdata), .be(dmem_be),
                .rdata(dmem_rdata), .listo(dmem_listo),
                .line_req(line_req), .line_we(line_we), .line_addr(line_addr),
                .line_wdata(line_wdata), .line_mask(line_mask),
                .line_accepted(line_accepted), .line_ready(line_ready), .line_rdata(line_rdata)
            );
        end
    endgenerate
    // Este canal permite insertar L2 y su buffer antes de la memoria principal.
    main_memory #(.MEM_DIV(MEM_DIV), .INIT_FILE(DMEM_INIT)) u_memory (
        .clk(clk), .rst(rst), .req(line_req), .we(line_we), .line_addr(line_addr),
        .wdata(line_wdata), .wmask(line_mask), .accepted(line_accepted),
        .ready(line_ready), .ready_rdata(line_rdata), .rdata(), .done(), .busy(),
        .read_count(), .write_count(), .transfer_cycles(), .total_cycles(), .timeout_count()
    );
endmodule
