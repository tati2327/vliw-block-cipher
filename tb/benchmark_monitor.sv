`timescale 1ns/1ps

// Observa los límites de cada vuelta sin ejecutar instrucciones adicionales.
// Los contadores llegan desde el procesador y las muestras se guardan por diferencia.
// Las escrituras de palabra y los drenajes a memoria tienen archivos separados,
// porque confirmar un store no implica que sus datos ya estén en memoria principal.
module benchmark_monitor #(
    parameter int START_PC = -1,
    parameter int END_PC = -1,
    parameter int CACHE = 0,
    parameter OUT_DIR = "build"
) (
    input wire clk, rst,
    input wire ex_commit, ex_valid,
    input wire [21:0] ex_pc,
    input wire [31:0] pass_limit,
    input wire [63:0] counts [0:36],
    input wire [31:0] occupancy, dirty_lines, ebuf_occupancy,
    input wire memory_busy,
    input wire req, we, listo,
    input wire [31:0] addr,
    input wire l1_hit,
    input wire [1:0] resp_src,
    input wire mem_accepted, mem_ready, mem_we,
    input wire [10:0] mem_addr,
    input wire [255:0] mem_data, memory_snapshot,
    input wire [31:0] mem_mask,
    output integer errors = 0
);
    integer rows_fd = 0, stores_fd = 0, memory_fd = 0;
    integer rounds = 0;
    logic started = 0, finalized = 0;
    logic [63:0] previous [0:36];
    logic [63:0] segment_sum [0:36];
    logic [31:0] peak = 0, global_peak = 0, first_occupancy = 0, first_dirty = 0;
    logic [31:0] ebuf_peak = 0, ebuf_global_peak = 0, first_ebuf_occupancy = 0;
    logic first_busy = 0;
    logic store_tracking = 0, store_was_hit = 0;
    logic memory_pending = 0, pending_write = 0;
    logic [10:0] pending_addr;
    logic [255:0] pending_data;
    logic [31:0] pending_mask;
    logic [63:0] memory_start = 0, store_wait = 0;
    integer memory_round = 0;

    task automatic require(input logic ok, input string message);
        if (ok !== 1'b1) begin
            errors++;
            $display("FAIL medicion de recorridos %s", message);
        end
    endtask

    // Cada contador aditivo conserva su valor anterior. Los máximos se observan
    // durante el intervalo y no se calculan restando máximos acumulados.
    task automatic row(input string segment, input integer number, input logic total);
        logic [63:0] delta;
        $fwrite(rows_fd, "%s,%0d", segment, number);
        for (integer k = 0; k < 37; k++) begin
            delta = total ? counts[k] : counts[k] - previous[k];
            $fwrite(rows_fd, ",%0d", delta);
            if (!total) begin
                segment_sum[k] = segment_sum[k] + delta;
                previous[k] = counts[k];
            end
        end
        $fdisplay(rows_fd, ",%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                  total ? global_peak : peak, total ? 0 : first_occupancy,
                  occupancy, total ? 0 : first_dirty, dirty_lines,
                  total ? 0 : first_busy, memory_busy,
                  total ? ebuf_global_peak : ebuf_peak,
                  total ? 0 : first_ebuf_occupancy, ebuf_occupancy, !ex_valid);
        first_ebuf_occupancy = ebuf_occupancy;
        ebuf_peak = ebuf_occupancy;
        first_occupancy = occupancy;
        first_dirty = dirty_lines;
        first_busy = memory_busy;
        peak = occupancy;
    endtask

    // Se llama en el mismo instante de la muestra final del programa. No espera
    // al vaciado de buffers ni modifica el estado de las cachés.
    task automatic finish_report;
        if (START_PC >= 0 && !finalized) begin
            require(started, "se observo el inicio");
            require(rounds == pass_limit, "terminaron todas las vueltas previstas");
            row("cierre", 0, 0);
            for (integer k = 0; k < 37; k++)
                require(segment_sum[k] === counts[k], "los intervalos reconstruyen el total");
            row("total", 0, 1);
            finalized = 1;
            $fclose(rows_fd); $fclose(stores_fd); $fclose(memory_fd);
        end
    endtask

    initial begin
        for (integer k = 0; k < 37; k++) begin
            previous[k] = 0;
            segment_sum[k] = 0;
        end
        if (START_PC >= 0) begin
            rows_fd = $fopen({OUT_DIR, "/recorridos.csv"}, "w");
            stores_fd = $fopen({OUT_DIR, "/escrituras.csv"}, "w");
            memory_fd = $fopen({OUT_DIR, "/memoria_escrituras.csv"}, "w");
            if (!rows_fd || !stores_fd || !memory_fd)
                $fatal(1, "No se pudieron abrir los archivos de medicion");
            $fwrite(rows_fd, "segmento,recorrido,ciclos,bundles,instrucciones,saltos,pausa_crypto,pausa_memoria,pausa_total");
            $fwrite(rows_fd, ",mem_lecturas,mem_escrituras,mem_transferencia,mem_ciclos,lecturas_cpu,escrituras_cpu,discrepancias");
            $fwrite(rows_fd, ",l1_lecturas,l1_escrituras,l1_hits_lectura,l1_misses_lectura,l1_hits_escritura,l1_misses_escritura");
            $fwrite(rows_fd, ",l1_pausa_buffer,l1_pausa_l2,l1_pausa_memoria,l1_pausa_lleno,buffer_recibidas,buffer_forwarding,buffer_ciclos_lleno");
            $fwrite(rows_fd, ",l2_lecturas,l2_escrituras,l2_hits_lectura,l2_misses_lectura,l2_hits_escritura,l2_misses_escritura,l2_pausa_lleno");
            $fwrite(rows_fd, ",ebuf_recibidas,ebuf_forwarding,ebuf_ciclos_lleno");
            $fdisplay(rows_fd, ",buffer_max,buffer_inicio,buffer_fin,sucias_inicio,sucias_fin,mem_pendiente_inicio,mem_pendiente_fin,ebuf_max,ebuf_inicio,ebuf_fin,ex_anulado");
            $fdisplay(stores_fd, "ciclo,recorrido,direccion,caso,ciclos_pausa");
            $fdisplay(memory_fd, "ciclo_inicio,ciclo_fin,recorrido_inicio,recorrido_fin,linea,ciclos,mascara,datos");
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            rounds = 0; started = 0;
            peak = 0; global_peak = 0;
            ebuf_peak = 0; ebuf_global_peak = 0; first_ebuf_occupancy = 0;
            first_occupancy = 0; first_dirty = 0; first_busy = 0;
            store_tracking = 0; store_wait = 0;
            memory_pending = 0;
            for (integer k = 0; k < 37; k++) begin
                previous[k] = 0; segment_sum[k] = 0;
            end
        end else if (START_PC >= 0 && !finalized) begin
            if (ebuf_occupancy > ebuf_peak) ebuf_peak = ebuf_occupancy;
            if (ebuf_occupancy > ebuf_global_peak) ebuf_global_peak = ebuf_occupancy;
            if (occupancy > peak) peak = occupancy;
            if (occupancy > global_peak) global_peak = occupancy;

            // La preparación termina justo antes de confirmar el primer paquete
            // de la primera vuelta. Ese paquete pertenece al primer recorrido.
            if (!started && ex_commit && ex_pc == START_PC) begin
                row("preparacion", 0, 0);
                started = 1;
            end

            // El estado de acierto se toma al presentar el store, antes de que
            // un llenado pueda convertir su fallo inicial en una línea instalada.
            if (req && we) begin
                if (!store_tracking) begin
                    store_tracking = 1;
                    store_was_hit = l1_hit;
                    store_wait = 0;
                end
                if (listo) begin : completed_store
                    string kind;
                    if (CACHE == 0) kind = "memoria_directa";
                    else if (store_was_hit) kind = "l1_hit";
                    else case (resp_src)
                        2'd1: kind = "l1_miss_l2";
                        2'd2: kind = "l1_miss_buffer";
                        default: kind = "l1_miss_memoria";
                    endcase
                    $fdisplay(stores_fd, "%0d,%0d,%08h,%s,%0d", counts[0]+1,
                              started && rounds < pass_limit ? rounds+1 : 0,
                              addr, kind, store_wait);
                    store_tracking = 0;
                end else store_wait = store_wait + 1;
            end

            // Se mide el intervalo desde aceptación hasta terminación de cada
            // escritura de línea. Puede cruzar el límite entre dos recorridos.
            if (mem_ready && memory_pending) begin
                if (pending_write) begin
                    // Se compara la versión aceptada por memoria, aunque L1 ya
                    // conserve una versión posterior de la misma línea.
                    for (integer b = 0; b < 32; b++)
                        if (pending_mask[b])
                            require(memory_snapshot[8*b +: 8] === pending_data[8*b +: 8],
                                    "byte escrito coincide con la transferencia aceptada");
                    $fdisplay(memory_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%08h,%064h",
                              memory_start, counts[0]+1, memory_round,
                              started && rounds < pass_limit ? rounds+1 : 0,
                              pending_addr, counts[0]+1-memory_start, pending_mask, pending_data);
                end
                memory_pending = 0;
            end

            // El fin se reconoce con el paquete confirmado, no con su aparición
            // en búsqueda o decodificación. La muestra espera las actualizaciones
            // secuenciales de ese mismo flanco para incluir sus contadores.
            if (ex_commit && ex_pc == END_PC) begin
                #1;
                if (ebuf_occupancy > ebuf_peak) ebuf_peak = ebuf_occupancy;
                if (ebuf_occupancy > ebuf_global_peak) ebuf_global_peak = ebuf_occupancy;
                if (occupancy > peak) peak = occupancy;
                if (occupancy > global_peak) global_peak = occupancy;
                require(started && rounds < pass_limit, "limite de vuelta valido");
                rounds++;
                row("recorrido", rounds, 0);
            end else #1;
            if (ebuf_occupancy > ebuf_peak) ebuf_peak = ebuf_occupancy;
            if (ebuf_occupancy > ebuf_global_peak) ebuf_global_peak = ebuf_occupancy;
            if (occupancy > peak) peak = occupancy;
            if (occupancy > global_peak) global_peak = occupancy;
            if (mem_accepted) begin
                memory_pending = 1;
                pending_write = mem_we;
                pending_addr = mem_addr;
                pending_data = mem_data;
                pending_mask = mem_mask;
                memory_start = counts[0];
                memory_round = started && rounds < pass_limit ? rounds+1 : 0;
            end
        end
    end
endmodule
