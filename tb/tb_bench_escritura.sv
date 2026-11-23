`timescale 1ns/1ps

// Prepara accesos concretos para medir sus pausas sin incluir la preparación.
// Cada instancia usa los mismos módulos y conexiones de memoria de top.
// No ejecuta un programa ni agrega operaciones a los benchmarks de recorridos.
module benchmark_store_case #(
    parameter int CACHE = 1,
    parameter int MEM_DIV = 4
) (output logic finished = 0);
    logic clk = 0, rst = 1;
    always #5 clk = ~clk;
    logic dmem_req = 0, dmem_we = 0, dmem_listo;
    logic [31:0] dmem_addr = 0, dmem_wdata = 0, dmem_rdata;
    logic [3:0] dmem_be = 4'hf;
    localparam int TMEM = 25 + 7 * MEM_DIV;
    integer pause_cycles;
    logic [63:0] hits, misses;
    wire [31:0] buffer_occupancy;
    wire [63:0] forwarded;
    generate
        if (CACHE == 1) begin
            assign buffer_occupancy = g_cache.u_wbuf.occupancy;
            assign forwarded = g_cache.u_wbuf.forwarding_count;
            assign hits = g_cache.u_l1.write_hits;
            assign misses = g_cache.u_l1.write_misses;
        end else begin
            assign buffer_occupancy = 0;
            assign forwarded = 0;
            assign hits = 0;
            assign misses = 0;
        end
    endgenerate
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
            l1_cache u_l1 (
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
    main_memory #(.MEM_DIV(MEM_DIV), .INIT_FILE("")) u_memory (
        .clk(clk), .rst(rst), .req(line_req), .we(line_we), .line_addr(line_addr),
        .wdata(line_wdata), .wmask(line_mask), .accepted(line_accepted),
        .ready(line_ready), .ready_rdata(line_rdata), .rdata(), .done(), .busy(),
        .read_count(), .write_count(), .transfer_cycles(), .total_cycles(), .timeout_count()
    );

    task automatic check(input logic ok, input string message);
        if (ok !== 1'b1)
            $fatal(1, "FAIL costo de escritura CACHE=%0d MEM_DIV=%0d %s", CACHE, MEM_DIV, message);
    endtask

    // Presenta un pedido en el flanco descendente y cuenta solo los flancos
    // en que el procesador debe detenerse. El flanco con listo confirma el acceso.
    task automatic access(input logic writing, input logic [31:0] address, value);
        @(negedge clk);
        dmem_req = 1; dmem_we = writing;
        dmem_addr = address; dmem_wdata = value;
        pause_cycles = 0;
        begin : waiting
            forever begin
                @(posedge clk);
                if (dmem_listo) disable waiting;
                pause_cycles++;
                check(pause_cycles < 1000, "acceso termina dentro del limite");
            end
        end
        #1;
        if (!writing) check(dmem_rdata === value, "lectura conserva el valor escrito");
        @(negedge clk);
        dmem_req = 0;
    endtask

    // La clasificación se comprueba con diferencias de contadores de L1.
    // Un fallo inicial no se reclasifica como acierto después de llenar su línea.
    task automatic measure(input string name, input logic [31:0] address, value,
                           input integer expected_hit, expected_pause, expected_reads = -1);
        logic [63:0] before_hits, before_misses, before_reads, before_writes;
        before_hits = hits; before_misses = misses;
        before_reads = u_memory.read_count; before_writes = u_memory.write_count;
        access(1, address, value);
        if (expected_pause >= 0)
            check(pause_cycles == expected_pause, "pausa coincide con el caso preparado");
        if (CACHE == 1) begin
            check(hits-before_hits == (expected_hit == 1), "acierto de escritura comprobado");
            check(misses-before_misses == (expected_hit == 0), "fallo de escritura comprobado");
            check(u_memory.read_count-before_reads ==
                  (expected_reads < 0 ? (expected_hit == 0) : expected_reads),
                  "solo un fallo requiere traer una linea");
        end else begin
            check(u_memory.read_count == before_reads, "store directo no lee una linea");
            check(u_memory.write_count-before_writes == 1, "store directo escribe memoria");
        end
        $fdisplay(tb_bench_escritura.csv_fd, "%0d,%0d,%s,%0d,%0d,%0d",
                  CACHE, MEM_DIV, name, pause_cycles,
                  u_memory.read_count-before_reads, u_memory.write_count-before_writes);
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 0;
        if (CACHE == 0) begin
            measure("memoria_directa", 'h1000, 'h11223344, -1, TMEM);
            check(u_memory.mem['h400] === 32'h11223344, "store directo termina en memoria fisica");
            measure("memoria_directa_repetida", 'h1000, 'h55667788, -1, TMEM);
            check(u_memory.mem['h400] === 32'h55667788, "segunda escritura conserva el dato nuevo");
        end else begin
            measure("l1_miss_memoria_libre", 'h1000, 'h11223344, 0, TMEM);
            check(u_memory.write_count == 0 && u_memory.mem['h400] === 0,
                  "asignacion por escritura conserva el dato nuevo en L1");
            measure("l1_hit_misma_palabra", 'h1000, 'h55667788, 1, 0);
            measure("l1_hit_palabra_vecina", 'h1004, 'habcddcba, 1, 0);
            check(u_memory.write_count == 0, "los aciertos no escriben directamente memoria");
            access(0, 'h1000, 'h55667788);
            access(0, 'h1004, 'habcddcba);

            // Estas tres direcciones tienen el mismo índice de conjunto y etiquetas
            // distintos. La tercera línea obliga a expulsar la primera de dos vías.
            // La preparación de la segunda línea queda fuera de la muestra siguiente.
            access(1, 'h1800, 'h12345678);
            measure("l1_miss_victima_modificada", 'h2000, 'h87654321, 0, -1);
            // La víctima sigue disponible en el buffer mientras se drena.
            // Volver a su dirección provoca un fallo de L1 que recibe esa copia.
            check(buffer_occupancy > 0 && forwarded == 0, "victima pendiente antes del forwarding");
            // La copia recibida se modifica otra vez en L1. El drenaje previo
            // debe conservar la versión que había aceptado, sin tomar este cambio.
            measure("l1_miss_buffer", 'h1000, 'hcafebabe, 0, 0, 0);
            check(forwarded == 1, "el llenado vino del buffer y no de memoria");
            access(0, 'h1000, 'hcafebabe);
            access(0, 'h1004, 'habcddcba);
            begin : drain
                integer waited;
                waited = 0;
                while (buffer_occupancy != 0 || u_memory.busy) begin
                    @(negedge clk);
                    waited++;
                    check(waited < 1000, "el drenaje de la victima termina");
                end
            end
            check(u_memory.write_count == 2, "las dos victimas modificadas fueron drenadas");
            check(u_memory.mem['h600] === 32'h12345678, "la segunda victima conserva su dato");
            check(u_memory.mem['h400] === 32'h55667788 &&
                  u_memory.mem['h401] === 32'habcddcba,
                  "la victima llega a memoria con sus dos palabras actualizadas");
            for (integer word_idx = 2; word_idx < 8; word_idx++)
                check(u_memory.mem['h400+word_idx] === 0,
                      "el drenaje conserva las otras palabras de la linea");
        end
        finished = 1;
    end
endmodule

// Las seis configuraciones tienen relojes y memorias independientes.
// El archivo reúne solo accesos medidos y conserva la selección de cada caso.
module tb_bench_escritura;
    integer csv_fd;
    wire [5:0] finished;
    benchmark_store_case #(.CACHE(0), .MEM_DIV(2)) direct2(finished[0]);
    benchmark_store_case #(.CACHE(0), .MEM_DIV(4)) direct4(finished[1]);
    benchmark_store_case #(.CACHE(0), .MEM_DIV(5)) direct5(finished[2]);
    benchmark_store_case #(.CACHE(1), .MEM_DIV(2)) cache2(finished[3]);
    benchmark_store_case #(.CACHE(1), .MEM_DIV(4)) cache4(finished[4]);
    benchmark_store_case #(.CACHE(1), .MEM_DIV(5)) cache5(finished[5]);
    initial begin
        csv_fd = $fopen("build/costos_controlados.csv", "w");
        if (!csv_fd) $fatal(1, "No se pudo abrir el archivo de costos controlados");
        $fdisplay(csv_fd, "cache,mem_div,caso,pausa_cpu,lecturas_memoria,escrituras_memoria");
        wait (&finished);
        $fclose(csv_fd);
        $display("PASS tb_bench_escritura");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "FAIL los casos controlados no terminaron");
    end
endmodule
