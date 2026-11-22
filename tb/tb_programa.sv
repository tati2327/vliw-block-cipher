`timescale 1ns/1ps

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

    int casos = 0, fallos = 0;
    int ciclo = 0, llegada = -1, ciclos_con_problema = 0;
    logic [63:0] foto_ciclos, foto_bundles, foto_instrucciones, foto_saltos;
    logic [63:0] foto_crypto, foto_memoria, foto_pausa;
    localparam int LLENADO = 2;
    localparam int MAX_CYCLES = 2000000;
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
                $display("L1 pausas: buffer=%0d L2=%0d memoria=%0d lleno=%0d",
                         dut.g_cache.u_l1.stall_buffer_cycles, dut.g_cache.u_l1.stall_l2_cycles,
                         dut.g_cache.u_l1.stall_memory_cycles, dut.g_cache.u_l1.stall_full_cycles);
                $display("+ Write buffer --------+------------------+");
                $display("| Lineas recibidas     | %16d |", dut.g_cache.u_wbuf.received_count);
                $display("| Forwarding           | %16d |", dut.g_cache.u_wbuf.forwarding_count);
                $display("| Ciclos lleno         | %16d |", dut.g_cache.u_wbuf.full_cycles);
                $display("| Ocupacion maxima     | %16d |", dut.g_cache.u_wbuf.max_occupancy);
                $display("+----------------------+------------------+");
                stalls = dut.g_cache.u_l1.stall_buffer_cycles + dut.g_cache.u_l1.stall_l2_cycles +
                         dut.g_cache.u_l1.stall_memory_cycles + dut.g_cache.u_l1.stall_full_cycles;
                check("pausa_memoria coincide con pausas L1", {31'b0, (foto_memoria == stalls)}, 1);
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

                $display("L1 pausas: buffer=%0d L2=%0d memoria=%0d lleno=%0d",
                    dut.g_cache2.u_l1.stall_buffer_cycles,
                    dut.g_cache2.u_l1.stall_l2_cycles,
                    dut.g_cache2.u_l1.stall_memory_cycles,
                    dut.g_cache2.u_l1.stall_full_cycles);

                stalls =
                    dut.g_cache2.u_l1.stall_buffer_cycles +
                    dut.g_cache2.u_l1.stall_l2_cycles +
                    dut.g_cache2.u_l1.stall_memory_cycles +
                    dut.g_cache2.u_l1.stall_full_cycles;

                check(
                    "pausa_memoria coincide con pausas L1",
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
        $writememh("build/tb_programa_dump.mem", u_monitor.mem);
    endtask

    initial begin
        $dumpfile("build/tb_programa.vcd");
        $dumpvars(0, tb_programa);
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
                dut.u_core.s2_br_op === 3'b101 && dut.u_core.s2_instr_low === 22'b0)
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
            // El llenado cuesta dos ciclos. Se resta uno porque la redirección
            // del salto hacia el final ya se contó, pero su burbuja aún no se
            // consumió en EX al tomar la foto.
            check("identidad de ciclos con ajuste del salto final",
                  {31'b0, (foto_ciclos == foto_bundles + foto_saltos + foto_pausa +
                           64'(LLENADO) - 64'd1)}, 32'd1);
            diferencia = $signed(foto_ciclos) - $signed(foto_bundles) -
                         $signed(foto_saltos) - $signed(foto_pausa) - LLENADO + 1;
            $display("Identidad: ciclos - bundles - saltos - pausa_total - %0d + 1 = %0d (%s)",
                     LLENADO, diferencia, (diferencia == 0) ? "cumple" : "no cumple");
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
