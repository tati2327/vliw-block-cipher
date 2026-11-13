`timescale 1ns/1ps

// Memoria por líneas con burst en el dominio lento y entrega temporizada al procesador.
module main_memory #(
    parameter int MEM_DIV = 4,
    parameter INIT_FILE = ""
) (
    input  logic clk, rst,
    input  logic req, we,
    input  logic [10:0] line_addr,
    input  logic [255:0] wdata,
    input  logic [31:0] wmask,
    output logic [255:0] rdata,
    output logic accepted, done, busy,
    output logic ready,
    output logic [255:0] ready_rdata,
    output logic [63:0] read_count, write_count,
    output logic [63:0] transfer_cycles, total_cycles, timeout_count
);
    localparam int TMEM = 25 + 7 * MEM_DIV;
    // Arreglo indexado por palabra; el reset conserva su contenido.
    logic [31:0] mem [0:16383];
    initial begin
        if (MEM_DIV != 2 && MEM_DIV != 4 && MEM_DIV != 5)
            $fatal(1, "main_memory: MEM_DIV debe ser 2, 4 o 5");
        // El dominio lento necesita estado definido incluso si rst arranca alto
        // y el divisor permanece detenido durante todo ese reset inicial.
        req_meta = 0; req_sync = 0; ack_mem = 0; response = 0;
        completion_mem = 0; mem_active = 0; next_word = 0;
        for (int i = 0; i < 16384; i++) mem[i] = '0;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    // Divisor real: período MEM_DIV * Tclk; en divisores impares el duty no es 50%.
    integer div_phase;
    logic mem_clk;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            div_phase <= 0;
            mem_clk <= 0;
        end else begin
            if (div_phase == MEM_DIV-1) div_phase <= 0;
            else div_phase <= div_phase + 1;
            mem_clk <= (div_phase < (MEM_DIV/2));
        end
    end

    // Cruce de dominios con handshake de cuatro fases: req↑ ack↑ req↓ ack↓.
    // Los buses registrados permanecen quietos durante TODO el handshake.
    logic req_mem, ack_mem;
    (* ASYNC_REG = "TRUE" *) logic req_meta, req_sync;
    (* ASYNC_REG = "TRUE" *) logic ack_meta, ack_sync;
    // ack confirma recepción, no fin del burst: permite recuperar req/ack
    // mientras las ocho palabras se transfieren. Un toggle independiente
    // confirma que response completo ya está estable (también con dos FF).
    logic completion_mem;
    (* ASYNC_REG = "TRUE" *) logic completion_meta, completion_sync;
    logic mem_active;
    logic [2:0] next_word;
    wire word_transfer = mem_active || (req_sync && !ack_mem);
    wire [2:0] word_index = mem_active ? next_word : 3'd0;
    logic saved_we;
    logic [10:0] saved_addr;
    logic [255:0] saved_data, response;
    logic [31:0] saved_mask;
    always_ff @(posedge mem_clk or posedge rst) begin
        if (rst) begin
            req_meta <= 0;
            req_sync <= 0;
            ack_mem <= 0;
            response <= '0;
            completion_mem <= 0;
            mem_active <= 0;
            next_word <= 0;
        end else begin
            req_meta <= req_mem;
            req_sync <= req_meta;
            if (!req_sync) ack_mem <= 0;
            // Transfiere una palabra por subida lenta, en ocho flancos consecutivos.
            if (word_transfer) begin
                if (!mem_active) ack_mem <= 1;
                if (saved_we) begin
                    for (int b = 0; b < 4; b++)
                        if (saved_mask[4*word_index+b])
                            mem[{saved_addr, 3'b000} + {29'b0, word_index}][8*b +: 8]
                                <= saved_data[32*word_index+8*b +: 8];
                end else
                    response[32*word_index +: 32]
                        <= mem[{saved_addr, 3'b000} + {29'b0, word_index}];
                if (word_index == 7) begin
                    mem_active <= 0;
                    next_word <= 0;
                    completion_mem <= ~completion_mem;
                end else begin
                    mem_active <= 1;
                    next_word <= word_index + 1'b1;
                end
            end
        end
    end
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ack_meta <= 0; ack_sync <= 0;
            completion_meta <= 0; completion_sync <= 0;
        end else begin
            ack_meta <= ack_mem; ack_sync <= ack_meta;
            completion_meta <= completion_mem; completion_sync <= completion_meta;
        end
    end

    logic active, timeout_reported;
    logic expected_completion;
    wire access_complete = (completion_sync == expected_completion) &&
                           !req_mem && !ack_sync;
    integer age;
    // La respuesta ya está estable antes del flanco que registra done.
    // Este aviso permite confirmar en ese flanco sin un ciclo de retorno extra.
    assign ready = !rst && active && age+1 >= TMEM && access_complete;
    assign ready_rdata = response;
    // Atiende un solo pedido a la vez, sin cola interna. El emisor
    // conserva req y su bus hasta accepted si llega mientras busy=1.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            req_mem <= 0;
            saved_we <= 0; saved_addr <= 0; saved_data <= 0; saved_mask <= 0;
            rdata <= 0; expected_completion <= 1;
            accepted <= 0; done <= 0; busy <= 0; active <= 0;
            age <= 0; timeout_reported <= 0;
            read_count <= 0; write_count <= 0;
            transfer_cycles <= 0; total_cycles <= 0; timeout_count <= 0;
        end else begin
            accepted <= 0;
            done <= 0;
            // Cuenta lecturas y escrituras aceptadas; su suma es el total de pedidos.
            total_cycles <= total_cycles + 1;
            if (!busy && req) begin
                saved_we <= we; saved_addr <= line_addr;
                saved_data <= wdata; saved_mask <= wmask;
                req_mem <= 1; busy <= 1; active <= 1; accepted <= 1;
                age <= 0; expected_completion <= ~completion_sync; timeout_reported <= 0;
                if (we) write_count <= write_count + 1;
                else read_count <= read_count + 1;
            end else if (active) begin
                age <= age + 1;
                // Cuenta la ventana nominal, que incluye la recuperación del cruce de dominios.
                if (age < TMEM) transfer_cycles <= transfer_cycles + 1;
                // Retirar el pedido al recibir ack, sin esperar el fin del burst.
                if (ack_sync) req_mem <= 0;
                if (age+1 >= TMEM && access_complete) begin
                    if (!saved_we) rdata <= response;
                    done <= 1; busy <= 0; active <= 0;
                end
                // Registra una sola vez el acceso que no termina al alcanzar 2*Tmem.
                if (age+1 >= 2*TMEM && !access_complete && !timeout_reported) begin
                    timeout_reported <= 1;
                    timeout_count <= timeout_count + 1;

                end
            end
        end
    end
    // Diagnóstico de simulación fuera del proceso secuencial sintetizable.
    // synthesis translate_off
    always @(posedge timeout_reported)
        if (!rst)
            $error("main_memory: timeout tras %0d ciclos (MEM_DIV=%0d)", age, MEM_DIV);
    // synthesis translate_on
endmodule
