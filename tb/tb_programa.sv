`timescale 1ns/1ps

`ifndef SIM_MAX_CYCLES
  `define SIM_MAX_CYCLES 2000000
`endif
`ifndef BENCH_START_PC
  `define BENCH_START_PC -1
`endif
`ifndef BENCH_END_PC
  `define BENCH_END_PC -1
`endif
`ifndef WAVE_FILE
  `define WAVE_FILE "build/tb_programa.vcd"
`endif
`ifndef WAVES
  `define WAVES 1
`endif
`ifndef CACHE
  `define CACHE 2
`endif
`ifndef OUT_DIR
  `define OUT_DIR "build"
`endif
`ifndef MEM_DIV
  `define MEM_DIV 4
`endif
`ifndef PROG_HEX
  `define PROG_HEX "programs/ejercicio1.hex"
`endif
`ifndef PROG_MEM
  `define PROG_MEM ""
`endif
`ifndef MEM_DESDE
  `define MEM_DESDE 0
`endif
`ifndef MEM_HASTA
  `define MEM_HASTA 4095
`endif
`ifndef EXP_MEM
  `define EXP_MEM "programs/ejercicio1.exp.mem"
`endif

// Programa, datos y resultados se seleccionan al compilar, sin valores del programa.
module tb_programa;
    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    top #(.IMEM_INIT(`PROG_HEX), .DMEM_INIT(`PROG_MEM), .MEM_DIV(`MEM_DIV), .CACHE(`CACHE)) dut (.clk, .rst);

    mem_monitor #(.INIT_FILE(`PROG_MEM), .LOG_FILE({`OUT_DIR, "/transacciones.txt"})) u_monitor (
        .clk(clk), .rst(rst), .req(dut.dmem_req), .we(dut.dmem_we),
        .listo(dut.dmem_listo), .addr(dut.dmem_addr), .wdata(dut.dmem_wdata),
        .rdata(dut.dmem_rdata), .be(dut.dmem_be),
        .loads_checked(), .stores_applied(), .discrepancies()
    );

    // El observador solo se activa cuando el ensamblador identifica las etiquetas
    // de vuelta. Los programas habituales conservan su ejecución sin mediciones.
    wire [63:0] bench_counts [0:36];
    wire [31:0] bench_occupancy, bench_dirty, bench_ebuf_occupancy;
    wire bench_hit;
    wire [1:0] bench_src;
    wire [31:0] bench_errors;
    wire [255:0] bench_memory_snapshot;
    // La dirección registrada permanece estable hasta completar la transferencia.
    // Cada palabra observada pertenece a la memoria física y no al monitor de CPU.
    for (genvar word_idx = 0; word_idx < 8; word_idx++)
        assign bench_memory_snapshot[32*word_idx +: 32] =
            dut.u_memory.mem[{dut.u_memory.saved_addr, 3'b000} + word_idx];
    // Los primeros contadores describen el procesador, la memoria física y
    // las operaciones de palabra comprobadas por el monitor de referencia.
    assign bench_counts[0] = dut.u_core.u_perf_counters.ciclos;
    assign bench_counts[1] = dut.u_core.u_perf_counters.bundles;
    assign bench_counts[2] = dut.u_core.u_perf_counters.instrucciones;
    assign bench_counts[3] = dut.u_core.u_perf_counters.saltos;
    assign bench_counts[4] = dut.u_core.u_perf_counters.pausa_crypto;
    assign bench_counts[5] = dut.u_core.u_perf_counters.pausa_memoria;
    assign bench_counts[6] = dut.u_core.u_perf_counters.pausa_total;
    assign bench_counts[7] = dut.u_memory.read_count;
    assign bench_counts[8] = dut.u_memory.write_count;
    assign bench_counts[9] = dut.u_memory.transfer_cycles;
    assign bench_counts[10] = dut.u_memory.total_cycles;
    assign bench_counts[11] = u_monitor.loads_checked;
    assign bench_counts[12] = u_monitor.stores_applied;
    assign bench_counts[13] = u_monitor.discrepancies;
    generate
        if (`CACHE == 1) begin : benchmark_cache
            // Se usan los eventos originales de L1 y del buffer de escritura.
            // La selección sin caché deja estas columnas en cero.
            assign bench_counts[14] = dut.g_cache.u_l1.read_count;
            assign bench_counts[15] = dut.g_cache.u_l1.write_count;
            assign bench_counts[16] = dut.g_cache.u_l1.read_hits;
            assign bench_counts[17] = dut.g_cache.u_l1.read_misses;
            assign bench_counts[18] = dut.g_cache.u_l1.write_hits;
            assign bench_counts[19] = dut.g_cache.u_l1.write_misses;
            assign bench_counts[20] = dut.g_cache.u_l1.stall_buffer_cycles;
            assign bench_counts[21] = dut.g_cache.u_l1.stall_l2_cycles;
            assign bench_counts[22] = dut.g_cache.u_l1.stall_memory_cycles;
            assign bench_counts[23] = dut.g_cache.u_l1.stall_full_cycles;
            assign bench_counts[24] = dut.g_cache.u_wbuf.received_count;
            assign bench_counts[25] = dut.g_cache.u_wbuf.forwarding_count;
            assign bench_counts[26] = dut.g_cache.u_wbuf.full_cycles;
            assign bench_occupancy = dut.g_cache.u_wbuf.occupancy;
            assign bench_hit = dut.g_cache.u_l1.hit && !dut.g_cache.u_l1.active;
            assign bench_src = dut.g_cache.resp_src;
            // Solo cuentan las líneas válidas cuya copia de L1 fue modificada.
            wire [127:0] dirty_bits;
            for (genvar set_idx = 0; set_idx < 64; set_idx++)
                for (genvar way = 0; way < 2; way++)
                    assign dirty_bits[2*set_idx+way] = dut.g_cache.u_l1.valid[set_idx][way] &&
                                                      dut.g_cache.u_l1.dirty[set_idx][way];
            assign bench_dirty = $countones(dirty_bits);
            for (genvar k = 27; k < 37; k++) assign bench_counts[k] = 0;
            assign bench_ebuf_occupancy = 0;
        end else if (`CACHE == 2) begin : benchmark_full
            // Se usan los eventos originales de L1 y del buffer de escritura.
            // La selección sin caché deja estas columnas en cero.
            assign bench_counts[14] = dut.g_cache2.u_l1.read_count;
            assign bench_counts[15] = dut.g_cache2.u_l1.write_count;
            assign bench_counts[16] = dut.g_cache2.u_l1.read_hits;
            assign bench_counts[17] = dut.g_cache2.u_l1.read_misses;
            assign bench_counts[18] = dut.g_cache2.u_l1.write_hits;
            assign bench_counts[19] = dut.g_cache2.u_l1.write_misses;
            assign bench_counts[20] = dut.g_cache2.u_l1.stall_buffer_cycles;
            assign bench_counts[21] = dut.g_cache2.u_l1.stall_l2_cycles;
            assign bench_counts[22] = dut.g_cache2.u_l1.stall_memory_cycles;
            assign bench_counts[23] = dut.g_cache2.u_l1.stall_full_cycles;
            assign bench_counts[24] = dut.g_cache2.u_wbuf.received_count;
            assign bench_counts[25] = dut.g_cache2.u_wbuf.forwarding_count;
            assign bench_counts[26] = dut.g_cache2.u_wbuf.full_cycles;
            assign bench_occupancy = dut.g_cache2.u_wbuf.occupancy;
            assign bench_hit = dut.g_cache2.u_l1.hit && !dut.g_cache2.u_l1.active;
            assign bench_src = dut.g_cache2.l1_resp_src;
            // Solo cuentan las líneas válidas cuya copia de L1 fue modificada.
            wire [127:0] dirty_bits;
            for (genvar set_idx = 0; set_idx < 64; set_idx++)
                for (genvar way = 0; way < 2; way++)
                    assign dirty_bits[2*set_idx+way] = dut.g_cache2.u_l1.valid[set_idx][way] &&
                                                      dut.g_cache2.u_l1.dirty[set_idx][way];
            assign bench_dirty = $countones(dirty_bits);
            assign bench_counts[27] = dut.g_cache2.u_l2.read_count;
            assign bench_counts[28] = dut.g_cache2.u_l2.write_count;
            assign bench_counts[29] = dut.g_cache2.u_l2.read_hits;
            assign bench_counts[30] = dut.g_cache2.u_l2.read_misses;
            assign bench_counts[31] = dut.g_cache2.u_l2.write_hits;
            assign bench_counts[32] = dut.g_cache2.u_l2.write_misses;
            assign bench_counts[33] = dut.g_cache2.u_l2.stall_full_cycles;
            assign bench_counts[34] = dut.g_cache2.u_ebuf.received_count;
            assign bench_counts[35] = dut.g_cache2.u_ebuf.forwarding_count;
            assign bench_counts[36] = dut.g_cache2.u_ebuf.full_cycles;
            assign bench_ebuf_occupancy = dut.g_cache2.u_ebuf.occupancy;
        end else begin : benchmark_direct
            for (genvar k = 14; k < 37; k++) assign bench_counts[k] = 0;
            assign bench_ebuf_occupancy = 0;
            assign bench_occupancy = 0;
            assign bench_dirty = 0;
            assign bench_hit = 0;
            assign bench_src = 0;
        end
    endgenerate
    benchmark_monitor #(.START_PC(`BENCH_START_PC), .END_PC(`BENCH_END_PC),
                        .CACHE(`CACHE), .OUT_DIR(`OUT_DIR)) u_benchmark (
        .clk, .rst, .ex_commit(dut.u_core.ex_commit), .ex_pc(dut.u_core.idex_pc),
        .pass_limit(u_monitor.mem[2]), .counts(bench_counts),
        .ex_valid(dut.u_core.idex_valid), .ebuf_occupancy(bench_ebuf_occupancy),
        .occupancy(bench_occupancy), .dirty_lines(bench_dirty), .memory_busy(dut.u_memory.busy),
        .req(dut.dmem_req), .we(dut.dmem_we), .listo(dut.dmem_listo), .addr(dut.dmem_addr),
        .l1_hit(bench_hit), .resp_src(bench_src),
        .mem_accepted(dut.u_memory.accepted), .mem_ready(dut.u_memory.ready),
        .mem_we(dut.u_memory.saved_we), .mem_addr(dut.u_memory.saved_addr),
        .mem_data(dut.u_memory.saved_data), .mem_mask(dut.u_memory.saved_mask),
        .memory_snapshot(bench_memory_snapshot), .errors(bench_errors));

    int casos = 0, fallos = 0;
    int ciclo = 0, llegada = -1, ciclos_con_problema = 0;
    logic [63:0] foto_ciclos, foto_bundles, foto_instrucciones, foto_saltos;
    logic [63:0] foto_crypto, foto_memoria, foto_pausa;
    logic foto_ex_anulado;
    localparam int LLENADO = 2;
    localparam int MAX_CYCLES = `SIM_MAX_CYCLES;
    logic [63:0] mem_reads, mem_writes, mem_transfer, mem_total;
    real utilization;
    longint signed diferencia;
    real ipc;
    int auth_ejecutados = 0;
    // Observa confirmaciones antes de las actualizaciones secuenciales del flanco.
    always @(posedge clk)
        if (!rst && dut.u_core.ex_commit && dut.u_core.idex_s1_sel &&
            dut.u_core.idex_s1_crypto_op == 3'b010)
            auth_ejecutados++;

    task automatic fotografiar;
        foto_ciclos = dut.u_core.u_perf_counters.ciclos;
        foto_bundles = dut.u_core.u_perf_counters.bundles;
        foto_instrucciones = dut.u_core.u_perf_counters.instrucciones;
        foto_saltos = dut.u_core.u_perf_counters.saltos;
        foto_crypto = dut.u_core.u_perf_counters.pausa_crypto;
        foto_memoria = dut.u_core.u_perf_counters.pausa_memoria;
        foto_pausa = dut.u_core.u_perf_counters.pausa_total;
        foto_ex_anulado = !dut.u_core.idex_valid;
        mem_reads = dut.u_memory.read_count; mem_writes = dut.u_memory.write_count;
        mem_transfer = dut.u_memory.transfer_cycles; mem_total = dut.u_memory.total_cycles;
    endtask

    int archivo;
    int listadas;
    logic [31:0] esperado [0:16383];

    task automatic check(input string nombre, input logic [31:0] obtenido, esperado);
        casos++;
        if (obtenido === esperado) $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: obtenido=%h esperado=%h", nombre, obtenido, esperado);
        end
    endtask

    generate
        if (`CACHE == 1) begin : cache_info
            task automatic report;
                integer fd, entry;
                real hits, misses, accesses;
                logic [63:0] stalls;
                accesses = real'(dut.g_cache.u_l1.read_count + dut.g_cache.u_l1.write_count);
                hits = real'(dut.g_cache.u_l1.read_hits + dut.g_cache.u_l1.write_hits);
                misses = real'(dut.g_cache.u_l1.read_misses + dut.g_cache.u_l1.write_misses);
                $display("+ L1 -------------------+------------+------------+------------+");
                $display("| Acceso               | Total      | Aciertos   | Fallos     |");
                $display("| Lecturas             | %10d | %10d | %10d |", dut.g_cache.u_l1.read_count,
                         dut.g_cache.u_l1.read_hits, dut.g_cache.u_l1.read_misses);
                $display("| Escrituras           | %10d | %10d | %10d |", dut.g_cache.u_l1.write_count,
                         dut.g_cache.u_l1.write_hits, dut.g_cache.u_l1.write_misses);
                $display("+----------------------+------------+------------+------------+");
                $display("L1 tasas: hit=%.6f miss=%.6f", accesses ? hits/accesses : 0.0, accesses ? misses/accesses : 0.0);
                $display("L1 pausas: buffer=%0d L2=%0d memoria=%0d lleno=%0d pendientes=%0d",
                         dut.g_cache.u_l1.stall_buffer_cycles, dut.g_cache.u_l1.stall_l2_cycles,
                         dut.g_cache.u_l1.stall_memory_cycles, dut.g_cache.u_l1.stall_full_cycles,
                         dut.g_cache.u_l1.pending_stalls);
                $display("+ Write buffer --------+------------------+");
                $display("| Lineas recibidas     | %16d |", dut.g_cache.u_wbuf.received_count);
                $display("| Forwarding           | %16d |", dut.g_cache.u_wbuf.forwarding_count);
                $display("| Ciclos lleno         | %16d |", dut.g_cache.u_wbuf.full_cycles);
                $display("| Ocupacion maxima     | %16d |", dut.g_cache.u_wbuf.max_occupancy);
                $display("+----------------------+------------------+");
                // La respuesta lista se contabiliza por origen en el siguiente flanco.
                stalls = dut.g_cache.u_l1.stall_buffer_cycles + dut.g_cache.u_l1.stall_l2_cycles +
                         dut.g_cache.u_l1.stall_memory_cycles + dut.g_cache.u_l1.stall_full_cycles +
                         dut.g_cache.u_l1.pending_stalls;
                check("pausa_memoria coincide con pausas L1 y pendientes", {31'b0, (foto_memoria == stalls)}, 1);
                fd = $fopen({`OUT_DIR, "/l1.txt"}, "w");
                if (!fd) $fatal(1, "No se pudo abrir l1.txt");
                $fdisplay(fd, "L1 ciclo=%0d; palabras de menor a mayor direccion", ciclo);
                $fdisplay(fd, "conjunto via valido sucio etiqueta direccion palabras[0:7]");
                for (int set_idx = 0; set_idx < 64; set_idx++)
                    for (int way = 0; way < 2; way++) begin
                        $fwrite(fd, "%02d %0d %b %b %02h %04h", set_idx, way,
                                dut.g_cache.u_l1.valid[set_idx][way], dut.g_cache.u_l1.dirty[set_idx][way],
                                dut.g_cache.u_l1.tags[set_idx][way],
                                {dut.g_cache.u_l1.tags[set_idx][way], 6'(set_idx), 5'b0});
                        for (int w = 0; w < 8; w++)
                            $fwrite(fd, " %08h", dut.g_cache.u_l1.data[set_idx][way][32*w +: 32]);
                        $fwrite(fd, "\n");
                    end
                $fdisplay(fd, "Write buffer ocupacion=%0d estado=%0d; orden mas vieja a mas nueva",
                          dut.g_cache.u_wbuf.occupancy, dut.g_cache.u_wbuf.state);
                for (int i = 0; i < int'(dut.g_cache.u_wbuf.occupancy); i++) begin
                    entry = (int'(dut.g_cache.u_wbuf.head) + i) % 4;
                    $fwrite(fd, "%0d entrada=%0d direccion=%04h", i, entry,
                            {dut.g_cache.u_wbuf.addresses[entry], 5'b0});
                    for (int w = 0; w < 8; w++)
                        $fwrite(fd, " %08h", dut.g_cache.u_wbuf.lines[entry][32*w +: 32]);
                    $fwrite(fd, "\n");
                end
                $fclose(fd);
            endtask
            always @(posedge clk)
                if (!rst && $test$plusargs("TRACE_L1") && dut.g_cache.push)
                    $display("TRACE L1 ciclo=%0d victima=%04h dato0=%08h push=%b full=%b llenado_req=%b llenado=%04h ready=%b",
                             dut.u_core.u_perf_counters.ciclos+1, {dut.g_cache.push_addr, 5'b0},
                             dut.g_cache.push_data[31:0], dut.g_cache.push, dut.g_cache.full,
                             dut.g_cache.req, {dut.g_cache.addr, 5'b0}, dut.g_cache.ready);
        end else if (`CACHE == 2) begin : cache_info
            task automatic report;
                integer fd, entry;

                real l1_accesses, l1_hits, l1_misses;
                real l2_accesses, l2_hits, l2_misses;
                real miss_l1, miss_l2;
                real amat_medido, amat_formula;

                logic [63:0] stalls;

                // Same timing formula used by main_memory.sv.
                localparam int TMEM = 25 + 7 * `MEM_DIV;

                // L1 statistics
                l1_accesses = real'(
                    dut.g_cache2.u_l1.read_count +
                    dut.g_cache2.u_l1.write_count
                );

                l1_hits = real'(
                    dut.g_cache2.u_l1.read_hits +
                    dut.g_cache2.u_l1.write_hits
                );

                l1_misses = real'(
                    dut.g_cache2.u_l1.read_misses +
                    dut.g_cache2.u_l1.write_misses
                );

                miss_l1 = (l1_accesses > 0.0)
                        ? l1_misses / l1_accesses : 0.0;

                $display("+ L1 -------------------+------------+------------+------------+");
                $display("| Acceso               | Total      | Aciertos   | Fallos     |");

                $display("| Lecturas             | %10d | %10d | %10d |",
                    dut.g_cache2.u_l1.read_count,
                    dut.g_cache2.u_l1.read_hits,
                    dut.g_cache2.u_l1.read_misses);

                $display("| Escrituras           | %10d | %10d | %10d |",
                    dut.g_cache2.u_l1.write_count,
                    dut.g_cache2.u_l1.write_hits,
                    dut.g_cache2.u_l1.write_misses);

                $display("+----------------------+------------+------------+------------+");

                $display("L1 tasas: hit=%.6f miss=%.6f",
                    l1_accesses > 0.0 ? l1_hits / l1_accesses : 0.0,
                    miss_l1);

                $display("L1 pausas: buffer=%0d L2=%0d memoria=%0d lleno=%0d pendientes=%0d",
                    dut.g_cache2.u_l1.stall_buffer_cycles,
                    dut.g_cache2.u_l1.stall_l2_cycles,
                    dut.g_cache2.u_l1.stall_memory_cycles,
                    dut.g_cache2.u_l1.stall_full_cycles,
                    dut.g_cache2.u_l1.pending_stalls);

                // La respuesta lista se contabiliza por origen en el siguiente flanco.
                stalls =
                    dut.g_cache2.u_l1.stall_buffer_cycles +
                    dut.g_cache2.u_l1.stall_l2_cycles +
                    dut.g_cache2.u_l1.stall_memory_cycles +
                    dut.g_cache2.u_l1.stall_full_cycles +
                    dut.g_cache2.u_l1.pending_stalls;

                check(
                    "pausa_memoria coincide con pausas L1 y pendientes",
                    {31'b0, (foto_memoria == stalls)},
                    32'd1
                );

                // Write buffer
                $display("+ Write buffer --------+------------------+");
                $display("| Lineas recibidas     | %16d |",
                    dut.g_cache2.u_wbuf.received_count);
                $display("| Forwarding           | %16d |",
                    dut.g_cache2.u_wbuf.forwarding_count);
                $display("| Ciclos lleno         | %16d |",
                    dut.g_cache2.u_wbuf.full_cycles);
                $display("| Ocupacion maxima     | %16d |",
                    dut.g_cache2.u_wbuf.max_occupancy);
                $display("+----------------------+------------------+");

                //L2 statistics
                l2_accesses = real'(
                    dut.g_cache2.u_l2.read_count +
                    dut.g_cache2.u_l2.write_count
                );

                l2_hits = real'(
                    dut.g_cache2.u_l2.read_hits +
                    dut.g_cache2.u_l2.write_hits
                );

                l2_misses = real'(
                    dut.g_cache2.u_l2.read_misses +
                    dut.g_cache2.u_l2.write_misses
                );

                miss_l2 = (l2_accesses > 0.0)
                        ? l2_misses / l2_accesses : 0.0;

                $display("+ L2 -------------------+------------+------------+------------+");
                $display("| Acceso               | Total      | Aciertos   | Fallos     |");

                $display("| Lecturas             | %10d | %10d | %10d |",
                    dut.g_cache2.u_l2.read_count,
                    dut.g_cache2.u_l2.read_hits,
                    dut.g_cache2.u_l2.read_misses);

                $display("| Escrituras           | %10d | %10d | %10d |",
                    dut.g_cache2.u_l2.write_count,
                    dut.g_cache2.u_l2.write_hits,
                    dut.g_cache2.u_l2.write_misses);

                $display("+----------------------+------------+------------+------------+");

                $display("L2 tasas: hit=%.6f miss=%.6f",
                    l2_accesses > 0.0 ? l2_hits / l2_accesses : 0.0,
                    miss_l2);

                $display("L2 pausas: eviction buffer lleno=%0d",
                    dut.g_cache2.u_l2.stall_full_cycles);

                // Eviction buffer
                $display("+ Eviction buffer -----+------------------+");
                $display("| Lineas recibidas     | %16d |",
                    dut.g_cache2.u_ebuf.received_count);
                $display("| Forwarding           | %16d |",
                    dut.g_cache2.u_ebuf.forwarding_count);
                $display("| Ciclos lleno         | %16d |",
                    dut.g_cache2.u_ebuf.full_cycles);
                $display("| Ocupacion maxima     | %16d |",
                    dut.g_cache2.u_ebuf.max_occupancy);
                $display("+----------------------+------------------+");

                // AMAT
                amat_medido = (l1_accesses > 0.0)
                            ? 1.0 + real'(foto_memoria) / l1_accesses
                            : 0.0;

                amat_formula = 1.0 + miss_l1 * (8.0 + miss_l2 * TMEM);

                $display("+ AMAT ----------------+------------------+");
                $display("| AMAT medido          | %16.6f |", amat_medido);
                $display("| AMAT formula         | %16.6f |", amat_formula);
                $display("| Miss rate L1         | %16.6f |", miss_l1);
                $display("| Miss rate L2         | %16.6f |", miss_l2);
                $display("| Tmem                 | %16d |", TMEM);
                $display("+----------------------+------------------+");

                // L1 dump
                fd = $fopen({`OUT_DIR, "/l1.txt"}, "w");

                if (!fd)
                    $fatal(1, "No se pudo abrir l1.txt");

                $fdisplay(fd, "L1 ciclo=%0d", ciclo);
                $fdisplay(fd, "conjunto via valido sucio etiqueta direccion palabras[0:7]");

                for (int set_idx = 0; set_idx < 64; set_idx++) begin
                    for (int way = 0; way < 2; way++) begin

                        $fwrite(fd, "%02d %0d %b %b %02h %04h",
                            set_idx,
                            way,
                            dut.g_cache2.u_l1.valid[set_idx][way],
                            dut.g_cache2.u_l1.dirty[set_idx][way],
                            dut.g_cache2.u_l1.tags[set_idx][way],
                            {
                                dut.g_cache2.u_l1.tags[set_idx][way],
                                6'(set_idx),
                                5'b0
                            });

                        for (int w = 0; w < 8; w++)
                            $fwrite(fd, " %08h",
                                dut.g_cache2.u_l1.data[set_idx][way][32*w +: 32]);

                        $fwrite(fd, "\n");
                    end
                end

                $fdisplay(fd, "");
                $fdisplay(fd, "Write buffer ocupacion=%0d estado=%0d",
                    dut.g_cache2.u_wbuf.occupancy,
                    dut.g_cache2.u_wbuf.state);

                for (int i = 0; i < int'(dut.g_cache2.u_wbuf.occupancy); i++) begin

                    entry = (int'(dut.g_cache2.u_wbuf.head) + i) % 4;

                    $fwrite(fd, "%0d entrada=%0d direccion=%04h",
                        i,
                        entry,
                        {dut.g_cache2.u_wbuf.addresses[entry], 5'b0});

                    for (int w = 0; w < 8; w++)
                        $fwrite(fd, " %08h",
                            dut.g_cache2.u_wbuf.lines[entry][32*w +: 32]);

                    $fwrite(fd, "\n");
                end

                $fclose(fd);

                // L2 dump
                fd = $fopen({`OUT_DIR, "/l2.txt"}, "w");

                if (!fd)
                    $fatal(1, "No se pudo abrir l2.txt");

                $fdisplay(fd, "L2 ciclo=%0d", ciclo);
                $fdisplay(fd, "conjunto via valido sucio etiqueta direccion palabras[0:7]");

                for (int set_idx = 0; set_idx < 128; set_idx++) begin
                    for (int way = 0; way < 4; way++) begin

                        $fwrite(fd, "%03d %0d %b %b %01h %04h",
                            set_idx,
                            way,
                            dut.g_cache2.u_l2.valid[set_idx][way],
                            dut.g_cache2.u_l2.dirty[set_idx][way],
                            dut.g_cache2.u_l2.tags[set_idx][way],
                            {
                                dut.g_cache2.u_l2.tags[set_idx][way],
                                7'(set_idx),
                                5'b0
                            });

                        for (int w = 0; w < 8; w++)
                            $fwrite(fd, " %08h",
                                dut.g_cache2.u_l2.data[set_idx][way][32*w +: 32]);

                        $fwrite(fd, "\n");
                    end
                end

                // Eviction buffer dump
                $fdisplay(fd, "");
                $fdisplay(fd, "Eviction buffer ocupacion=%0d estado=%0d",
                    dut.g_cache2.u_ebuf.occupancy,
                    dut.g_cache2.u_ebuf.state);

                $fdisplay(fd, "orden entrada direccion palabras[0:7]");

                for (int i = 0; i < int'(dut.g_cache2.u_ebuf.occupancy); i++) begin

                    entry = (int'(dut.g_cache2.u_ebuf.head) + i) % 8;

                    $fwrite(fd, "%0d %0d %04h",
                        i,
                        entry,
                        {dut.g_cache2.u_ebuf.addresses[entry], 5'b0});

                    for (int w = 0; w < 8; w++)
                        $fwrite(fd, " %08h",
                            dut.g_cache2.u_ebuf.lines[entry][32*w +: 32]);

                    $fwrite(fd, "\n");
                end

                $fclose(fd);

                $display("Estado L1 guardado en %s/l1.txt", `OUT_DIR);
                $display("Estado L2 guardado en %s/l2.txt", `OUT_DIR);
            endtask
        end else begin : cache_info
            task automatic report;
            endtask
        end
    endgenerate

    // Muestreo tras la bajada, como los otros TB de integración. También durante
    // los cinco ciclos finales: un ciclo cuenta una sola vez aunque falle más de un slot.
    task automatic muestrear;
        bit problema;
        @(negedge clk); #2;
        ciclo++;
        problema = $isunknown(dut.u_core.u_fetch.pc) ||
                   $isunknown(dut.u_core.ifid_bundle);
        for (int s = 0; s < 4; s++) begin
            if (dut.u_core.exwb_valid === 1'b1 && dut.u_core.wb_we[s] === 1'b1 &&
                $isunknown(dut.u_core.wb_wdata[s])) begin
                problema = 1;
                if (ciclos_con_problema < 3)
                    $display("  ciclo=%0d WB slot=%0d dato=%h", ciclo, s, dut.u_core.wb_wdata[s]);
            end
        end
        if (problema) begin
            if (ciclos_con_problema < 3)
                $display("  ciclo=%0d pc=%h bundle=%h", ciclo,
                         dut.u_core.u_fetch.pc, dut.u_core.ifid_bundle);
            ciclos_con_problema++;
        end
    endtask

    // Punto único de obtención de la memoria final, independiente de las comprobaciones.
    task automatic volcar_memoria_final;
        $writememh({`OUT_DIR, "/dump.mem"}, u_monitor.mem);
        $writememh("build/tb_programa_dump.mem", u_monitor.mem);
    endtask

    initial begin
        if (`WAVES) begin
            $dumpfile(`WAVE_FILE);
            $dumpvars(0, tb_programa);
        end
        for (int i = 0; i < 16384; i++) esperado[i] = 32'bx;
        if (`EXP_MEM != "") begin
            archivo = $fopen(`EXP_MEM, "r");
            if (archivo == 0) $fatal(1, "No se pudo abrir EXP_MEM: %s", `EXP_MEM);
            $fclose(archivo);
            $readmemh(`EXP_MEM, esperado);
        end

        @(posedge clk);
        @(negedge clk); #1; rst = 0;
        while (llegada < 0 && ciclo < MAX_CYCLES) begin
            muestrear();
            if (dut.u_core.ifid_valid === 1'b1 &&
                dut.u_core.s2_br_op === 3'b101 && dut.u_core.s2_instr_low === 22'b0 &&
                dut.u_core.stall === 1'b0)
                begin
                    llegada = ciclo;
                    fotografiar();
                end
        end
        check("fin del programa antes del limite", {31'b0, (llegada >= 0)}, 32'd1);
        if (llegada >= 0) $display("Llegada al fin en el ciclo %0d", llegada);
        else $display("No llego al fin en %0d ciclos", MAX_CYCLES);
        if (llegada >= 0) begin
            ipc = (foto_ciclos != 0) ? real'(foto_instrucciones) / real'(foto_ciclos) : 0.0;
            $display("+ Procesador ----------+------------------+");
            $display("| Ciclos               | %16d |", foto_ciclos);
            $display("| Bundles              | %16d |", foto_bundles);
            $display("| Instrucciones        | %16d |", foto_instrucciones);
            $display("| IPC                  | %16.6f |", ipc);
            $display("| Saltos               | %16d |", foto_saltos);
            $display("| Pausa crypto         | %16d |", foto_crypto);
            $display("| Pausa memoria        | %16d |", foto_memoria);
            $display("| Pausa total          | %16d |", foto_pausa);
            $display("| AUTH ejecutados      | %16d |", auth_ejecutados);
            $display("+----------------------+------------------+");
            check("foto de ciclos coincide con llegada", {31'b0, (foto_ciclos == ciclo)}, 32'd1);
            // El llenado cuesta dos ciclos; el bundle anulado en EX descuenta
            // una burbuja contada por saltos que aún no se consumió en la foto.
            check("identidad de ciclos con validez de EX",
                  {31'b0, (foto_ciclos == foto_bundles + foto_saltos + foto_pausa +
                           64'(LLENADO) - 64'(foto_ex_anulado))}, 32'd1);
            diferencia = $signed(foto_ciclos) - $signed(foto_bundles) -
                         $signed(foto_saltos) - $signed(foto_pausa) - LLENADO +
                         longint'(foto_ex_anulado);
            $display("Identidad: ciclos - bundles - saltos - pausa_total - %0d + EX_anulado(%0d) = %0d (%s)",
                     LLENADO, foto_ex_anulado, diferencia,
                     (diferencia == 0) ? "cumple" : "no cumple");
        end

        cache_info.report();
        utilization = (mem_total != 0) ? real'(mem_transfer) / real'(mem_total) : 0.0;
        $display("+ Memoria principal ---+------------------+");
        $display("| MEM_DIV              | %16d |", `MEM_DIV);
        $display("| Lecturas             | %16d |", mem_reads);
        $display("| Escrituras           | %16d |", mem_writes);
        $display("| Transferencia        | %16d |", mem_transfer);
        $display("| Ciclos totales        | %16d |", mem_total);
        $display("| Utilizacion          | %16.6f |", utilization);
        $display("+----------------------+------------------+");

        u_benchmark.finish_report();
        if (`BENCH_START_PC >= 0)
            check("mediciones por recorrido sin errores", bench_errors, 0);
        repeat (5) muestrear();
        check("ciclos con X/Z en PC, bundle o escritura WB", ciclos_con_problema, 32'd0);
        $display("+ Monitor -------------+------------------+");
        $display("| Loads comprobados    | %16d |", u_monitor.loads_checked);
        $display("| Stores aplicados     | %16d |", u_monitor.stores_applied);
        $display("| Discrepancias        | %16d |", u_monitor.discrepancies);
        $display("+----------------------+------------------+");
        check("cero discrepancias del monitor", {31'b0, (u_monitor.discrepancies == 0)}, 1);
        volcar_memoria_final();

        if (`EXP_MEM != "") begin
            for (int i = 0; i < 16384; i++) begin
                if (esperado[i] !== 32'bx)
                    check($sformatf("mem palabra=0x%0h direccion=0x%0h", i, 4*i),
                          u_monitor.mem[i], esperado[i]);
            end
        end
        for (int r = 0; r < 16; r++)
            $display("r%0d = %0d (0x%h)", r, $signed(dut.u_core.u_regfile.regs[r]),
                     dut.u_core.u_regfile.regs[r]);

        // Solo informativo: palabras de datos distintas de cero (direcciones en bytes).
        $display("Memoria de datos, palabras distintas de cero en 0x%04h-0x%04h:",
                 16'(`MEM_DESDE), 16'(`MEM_HASTA));
        listadas = 0;
        for (int i = `MEM_DESDE / 4; i <= `MEM_HASTA / 4 && i < 16384; i++) begin
            if (u_monitor.mem[i] !== 32'b0) begin
                $display("  0x%04h: %0d (0x%h)", 16'(4*i), $signed(u_monitor.mem[i]),
                         u_monitor.mem[i]);
                listadas++;
            end
        end
        if (listadas == 0) $display("  (ninguna)");

        // Solo informativo: estado de CRYPTO al terminar.
        $display("auth=%b kvlock=%b exc=%b", dut.u_core.u_crypto.u_crypto_state.auth,
                 dut.u_core.u_crypto.u_crypto_state.kvlock, dut.u_core.u_crypto.u_crypto_state.exc);

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "tb_programa fallo");
        $display("PASS tb_programa");
        $finish;
    end
endmodule
