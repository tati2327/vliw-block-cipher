`timescale 1ns/1ps

// Caché L2 de cuatro vías con reemplazo pseudoaleatorio y escritura diferida.
module l2_cache #(
    parameter int REPL = 0
) (
    input  logic clk, rst,
    input  logic req, we,
    input  logic [10:0] line_addr,
    input  logic [255:0] wdata,
    input  logic [31:0] wmask,
    output logic accepted, ready,
    output logic [255:0] ready_rdata,
    output logic [1:0] resp_src,
    output logic line_req, line_we,
    output logic [10:0] line_line_addr,
    output logic [255:0] line_wdata,
    output logic [31:0] line_wmask,
    input  logic line_accepted, line_ready,
    input  logic [255:0] line_rdata,
    input  logic [1:0] line_resp_src,
    output logic push,
    output logic [10:0] push_addr,
    output logic [255:0] push_data,
    input  logic full,
    output logic [63:0] read_count, write_count,
    output logic [63:0] read_hits, read_misses,
    output logic [63:0] write_hits, write_misses,
    output logic [63:0] stall_full_cycles
);
    logic [255:0] data [0:127][0:3];
    logic [3:0] tags [0:127][0:3];
    logic valid [0:127][0:3];
    logic dirty [0:127][0:3];
    logic [7:0] lfsr;

    typedef enum logic [1:0] { IDLE, LOOKUP, MISS, WAIT_LINE } state_t;
    state_t state;
    logic saved_we;
    logic [10:0] saved_addr;
    logic [255:0] saved_data;
    logic [31:0] saved_mask;
    logic [3:0] age;
    logic [1:0] victim_way;
    logic hit;
    logic [1:0] hit_way;
    logic victim_dirty, pushed, sent;
    logic [6:0] idx;
    logic [3:0] tag;
    logic [255:0] merged_data;

    assign idx = saved_addr[6:0];
    assign tag = saved_addr[10:7];

    always_comb begin
        hit = 0;
        hit_way = 0;
        for (int w = 0; w < 4; w++) begin
            if (valid[idx][w] && tags[idx][w] == tag) begin
                hit = 1;
                hit_way = 2'(w);
            end
        end
        victim_way = lfsr[1:0];
        // La primera vía inválida tiene prioridad sobre el reemplazo.
        for (int w = 3; w >= 0; w--)
            if (!valid[idx][w]) victim_way = 2'(w);
        victim_dirty = valid[idx][victim_way] && dirty[idx][victim_way];
        merged_data = data[idx][hit_way];
        for (int b = 0; b < 32; b++)
            if (saved_mask[b]) merged_data[8*b +: 8] = saved_data[8*b +: 8];
    end

    wire lookup_done = (state == LOOKUP && age == 4'd7);
    wire must_evict = victim_dirty && !pushed;
    wire eviction_blocked = (state == MISS || lookup_done) && !hit && must_evict && full;
    wire can_proceed = !must_evict || !full;
    wire read_miss_start = (state == MISS || lookup_done) && !hit && !saved_we && can_proceed;
    wire write_miss_finish = (state == MISS || lookup_done) && !hit && saved_we && can_proceed;
    wire hit_finish = lookup_done && hit;

    assign push = !rst && (state == MISS || lookup_done) && !hit && must_evict && !full;
    assign push_addr = {tags[idx][victim_way], idx};
    assign push_data = data[idx][victim_way];
    assign line_req = !rst && read_miss_start && !sent;
    assign line_we = 1'b0;
    assign line_line_addr = saved_addr;
    assign line_wdata = '0;
    assign line_wmask = '0;
    // La respuesta inmediata del nivel inferior se propaga sin etapa adicional.
    assign ready = !rst && (hit_finish || write_miss_finish ||
                    (read_miss_start && line_ready) ||
                    (state == WAIT_LINE && line_ready));
    assign ready_rdata = hit_finish ? data[idx][hit_way] :
                         write_miss_finish ? saved_data : line_rdata;
    assign resp_src = hit_finish ? 2'd1 :
                      write_miss_finish ? 2'd1 : line_resp_src;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            accepted <= 0;
            saved_we <= 0;
            saved_addr <= 0;
            saved_data <= 0;
            saved_mask <= 0;
            age <= 0;
            pushed <= 0;
            sent <= 0;
            lfsr <= 8'hA5;
            read_count <= 0; write_count <= 0;
            read_hits <= 0; read_misses <= 0;
            write_hits <= 0; write_misses <= 0;
            stall_full_cycles <= 0;
            for (int s = 0; s < 128; s++)
                for (int w = 0; w < 4; w++) begin
                    valid[s][w] <= 0;
                    dirty[s][w] <= 0;
                    tags[s][w] <= 0;
                    data[s][w] <= 0;
                end
        end else begin
            accepted <= 0;
            case (state)
                IDLE: if (req) begin
                    accepted <= 1;
                    saved_we <= we;
                    saved_addr <= line_addr;
                    saved_data <= wdata;
                    saved_mask <= wmask;
                    age <= 1;
                    pushed <= 0;
                    sent <= 0;
                    state <= LOOKUP;
                    if (we) write_count <= write_count + 1;
                    else read_count <= read_count + 1;
                end
                LOOKUP: begin
                    if (age != 7) age <= age + 1'b1;
                    else begin
                        if (saved_we) begin
                            if (hit) write_hits <= write_hits + 1;
                            else write_misses <= write_misses + 1;
                        end else begin
                            if (hit) read_hits <= read_hits + 1;
                            else read_misses <= read_misses + 1;
                        end
                        if (hit) begin
                            if (saved_we) begin
                                data[idx][hit_way] <= merged_data;
                                dirty[idx][hit_way] <= 1;
                            end
                            state <= IDLE;
                        end else if (!can_proceed) begin
                            stall_full_cycles <= stall_full_cycles + 1;
                            state <= MISS;
                        end else begin
                            if (push) pushed <= 1;
                            if (saved_we) begin
                                data[idx][victim_way] <= saved_data;
                                tags[idx][victim_way] <= tag;
                                valid[idx][victim_way] <= 1;
                                dirty[idx][victim_way] <= 1;
                                lfsr <= {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
                                state <= IDLE;
                            end else if (line_ready) begin
                                data[idx][victim_way] <= line_rdata;
                                tags[idx][victim_way] <= tag;
                                valid[idx][victim_way] <= 1;
                                dirty[idx][victim_way] <= 0;
                                lfsr <= {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
                                state <= IDLE;
                            end else begin
                                if (line_accepted) sent <= 1;
                                state <= WAIT_LINE;
                            end
                        end
                    end
                end
                MISS: begin
                    if (!can_proceed) stall_full_cycles <= stall_full_cycles + 1;
                    else begin
                        if (push) pushed <= 1;
                        if (saved_we) begin
                            data[idx][victim_way] <= saved_data;
                            tags[idx][victim_way] <= tag;
                            valid[idx][victim_way] <= 1;
                            dirty[idx][victim_way] <= 1;
                            lfsr <= {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
                            state <= IDLE;
                        end else if (line_ready) begin
                            data[idx][victim_way] <= line_rdata;
                            tags[idx][victim_way] <= tag;
                            valid[idx][victim_way] <= 1;
                            dirty[idx][victim_way] <= 0;
                            lfsr <= {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
                            state <= IDLE;
                        end else begin
                            if (line_accepted) sent <= 1;
                            state <= WAIT_LINE;
                        end
                    end
                end
                WAIT_LINE: begin
                    if (line_accepted) sent <= 1;
                    if (line_ready) begin
                        data[idx][victim_way] <= line_rdata;
                        tags[idx][victim_way] <= tag;
                        valid[idx][victim_way] <= 1;
                        dirty[idx][victim_way] <= 0;
                        lfsr <= {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
