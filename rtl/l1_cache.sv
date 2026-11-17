`timescale 1ns/1ps

// Caché de datos de dos vías con escritura diferida y asignación en escritura.
module l1_cache (
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
    input logic [255:0] line_rdata,
    input logic [1:0] resp_src,
    output logic push,
    output logic [10:0] push_addr,
    output logic [255:0] push_data,
    input logic full,
    output logic [63:0] read_count, write_count,
    output logic [63:0] read_hits, read_misses, write_hits, write_misses,
    output logic [63:0] stall_buffer_cycles, stall_l2_cycles,
    output logic [63:0] stall_memory_cycles, stall_full_cycles
);
    logic [255:0] data [0:63][0:1];
    logic [4:0] tags [0:63][0:1];
    logic valid [0:63][0:1];
    logic dirty [0:63][0:1];
    // El bit indica cuál vía se reemplaza si ambas son válidas.
    logic lru [0:63];
    logic active, sent, evicted;
    logic saved_we, saved_way;
    logic [31:0] saved_addr, saved_data;
    logic [3:0] saved_be;
    logic [63:0] pending_stalls;

    wire [31:0] access_addr = active ? saved_addr : addr;
    wire access_we = active ? saved_we : we;
    wire [31:0] access_data = active ? saved_data : wdata;
    wire [3:0] access_be = active ? saved_be : be;
    wire [5:0] index = access_addr[10:5];
    wire [4:0] tag = access_addr[15:11];
    wire [2:0] word_index = access_addr[4:2];
    wire hit0 = valid[index][0] && tags[index][0] == tag;
    wire hit1 = valid[index][1] && tags[index][1] == tag;
    wire hit = hit0 || hit1;
    wire hit_way = !hit0;
    wire victim = !valid[index][0] ? 1'b0 :
                  !valid[index][1] ? 1'b1 : lru[index];
    wire way = active ? saved_way : victim;
    wire requested = !rst && (active || req);
    wire miss = requested && (active || !hit);
    wire needs_push = valid[index][way] && dirty[index][way] && !evicted;
    wire blocked = miss && needs_push && full;
    wire filling = miss && !blocked;
    wire complete_fill = filling && line_ready;

    function automatic [255:0] merge_store(
        input logic [255:0] original,
        input logic [2:0] word_number,
        input logic [31:0] value,
        input logic [3:0] mask
    );
        merge_store = original;
        for (int b = 0; b < 4; b++)
            if (mask[b]) merge_store[32*word_number+8*b +: 8] = value[8*b +: 8];
    endfunction

    assign push = filling && needs_push;
    assign push_addr = {tags[index][way], index};
    assign push_data = data[index][way];
    // El llenado sale en el mismo ciclo que el desalojo, sin etapa adicional.
    assign line_req = filling && !sent && !line_accepted;
    assign line_we = 1'b0;
    assign line_addr = access_addr[15:5];
    assign line_wdata = '0;
    assign line_mask = '0;
    assign listo = requested && ((!active && hit) || complete_fill);
    assign rdata = !active && hit ? data[index][hit_way][32*word_index +: 32] :
                                   line_rdata[32*word_index +: 32];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            active <= 0; sent <= 0; evicted <= 0;
            saved_we <= 0; saved_way <= 0;
            saved_addr <= 0; saved_data <= 0; saved_be <= 0;
            pending_stalls <= 0;
            read_count <= 0; write_count <= 0;
            read_hits <= 0; read_misses <= 0; write_hits <= 0; write_misses <= 0;
            stall_buffer_cycles <= 0; stall_l2_cycles <= 0;
            stall_memory_cycles <= 0; stall_full_cycles <= 0;
            for (int s = 0; s < 64; s++) begin
                lru[s] <= 0;
                for (int w = 0; w < 2; w++) begin
                    valid[s][w] <= 0; dirty[s][w] <= 0;
                    tags[s][w] <= 0; data[s][w] <= 0;
                end
            end
        end else begin
            // Cada pedido se cuenta al entrar, aunque tarde varios ciclos en terminar.
            if (!active && req) begin
                if (we) begin
                    write_count <= write_count + 1;
                    if (hit) write_hits <= write_hits + 1;
                    else write_misses <= write_misses + 1;
                end else begin
                    read_count <= read_count + 1;
                    if (hit) read_hits <= read_hits + 1;
                    else read_misses <= read_misses + 1;
                end
            end
            if (requested && !active && hit) begin
                lru[index] <= !hit_way;
                if (we) begin
                    data[index][hit_way] <= merge_store(data[index][hit_way], word_index, wdata, be);
                    dirty[index][hit_way] <= 1;
                end
            end
            if (miss) begin
                if (complete_fill) begin
                    data[index][way] <= access_we ?
                        merge_store(line_rdata, word_index, access_data, access_be) : line_rdata;
                    tags[index][way] <= tag;
                    valid[index][way] <= 1;
                    dirty[index][way] <= access_we;
                    lru[index] <= !way;
                    active <= 0; sent <= 0; evicted <= 0;
                    // El origen solo es válido con ready; las pausas se atribuyen al terminar.
                    case (resp_src)
                        2'd2: stall_buffer_cycles <= stall_buffer_cycles + pending_stalls;
                        2'd1: stall_l2_cycles <= stall_l2_cycles + pending_stalls;
                        default: stall_memory_cycles <= stall_memory_cycles + pending_stalls;
                    endcase
                    pending_stalls <= 0;
                end else begin
                    if (!active) begin
                        active <= 1;
                        saved_we <= we; saved_addr <= addr;
                        saved_data <= wdata; saved_be <= be; saved_way <= victim;
                    end
                    if (push) evicted <= 1;
                    if (filling && line_accepted) sent <= 1;
                    if (blocked) stall_full_cycles <= stall_full_cycles + 1;
                    else pending_stalls <= pending_stalls + 1;
                end
            end
        end
    end
endmodule
