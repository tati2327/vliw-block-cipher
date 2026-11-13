`timescale 1ns/1ps

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

    top #(.IMEM_INIT(`PROG_HEX), .DMEM_INIT(`PROG_MEM), .MEM_DIV(`MEM_DIV)) dut (.clk, .rst);

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
        $writememh("build/tb_programa_dump.mem", dut.u_memory.mem);
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
            $display("Rendimiento: ciclos=%0d bundles=%0d instrucciones=%0d IPC=%.3f",
                     foto_ciclos, foto_bundles, foto_instrucciones, ipc);
            $display("Pausas: saltos=%0d crypto=%0d memoria=%0d total=%0d; auth=%0d",
                     foto_saltos, foto_crypto, foto_memoria, foto_pausa, auth_ejecutados);
            utilization = (mem_total != 0) ? real'(mem_transfer) / real'(mem_total) : 0.0;
            $display("Memoria: MEM_DIV=%0d lecturas=%0d escrituras=%0d transferencia=%0d totales=%0d utilizacion=%.6f",
                     `MEM_DIV, mem_reads, mem_writes, mem_transfer, mem_total, utilization);
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

        repeat (5) muestrear();
        check("ciclos con X/Z en PC, bundle o escritura WB", ciclos_con_problema, 32'd0);
        volcar_memoria_final();

        if (`EXP_MEM != "") begin
            for (int i = 0; i < 16384; i++) begin
                if (esperado[i] !== 32'bx)
                    check($sformatf("mem palabra=0x%0h direccion=0x%0h", i, 4*i),
                          dut.u_memory.mem[i], esperado[i]);
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
            if (dut.u_memory.mem[i] !== 32'b0) begin
                $display("  0x%04h: %0d (0x%h)", 16'(4*i), $signed(dut.u_memory.mem[i]),
                         dut.u_memory.mem[i]);
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
