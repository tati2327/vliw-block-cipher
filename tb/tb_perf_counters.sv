`timescale 1ns/1ps

// Secuencias conocidas de confirmaciones, operaciones, redirecciones y pausas.
module tb_perf_counters;
    logic clk = 0, rst = 0;
    always #5 clk = ~clk;
    logic ex_commit = 0, id_redirect = 0, crypto_stall = 0, mem_stall = 0;
    wire stall = crypto_stall | mem_stall;
    logic [2:0] ops_count = 0;
    logic [63:0] ciclos, bundles, instrucciones, saltos;
    logic [63:0] pausa_crypto, pausa_memoria, pausa_total;
    int casos = 0, fallos = 0;
    perf_counters dut (.*);

    // La decodificación real permite comprobar también códigos libres y NOP.
    logic [127:0] probe_bundle = 0;
    logic probe_rst = 1;
    core probe (.clk(clk), .rst(probe_rst), .init_anchor(1'b0),
        .imem_addr(), .imem_en(), .imem_flush(), .imem_rdata(probe_bundle),
        .dmem_addr(), .dmem_wdata(), .dmem_we(), .dmem_be(), .dmem_rdata(32'b0));

    task automatic check(input string name, input logic ok);
        casos++;
        if (ok !== 1'b1) begin
            fallos++;
            $display("FAIL %s", name);
        end
    endtask
    task automatic values(input logic [63:0] c, b, i, j, pc, pm, pt);
        check("ciclos", ciclos === c);
        check("bundles", bundles === b);
        check("instrucciones", instrucciones === i);
        check("saltos", saltos === j);
        check("pausa crypto", pausa_crypto === pc);
        check("pausa memoria", pausa_memoria === pm);
        check("pausa total sin duplicar", pausa_total === pt);
    endtask
    task automatic step(input logic commit, input logic [2:0] ops,
                        input logic jump, crypto, memory_pause);
        @(negedge clk);
        ex_commit = commit; ops_count = ops; id_redirect = jump;
        crypto_stall = crypto; mem_stall = memory_pause;
        @(posedge clk); #1;
    endtask

    initial begin
        #1 rst = 1;
        #1; values(0, 0, 0, 0, 0, 0, 0);
        @(negedge clk); rst = 0;
        // El primer flanco libre cuenta tiempo aunque no confirme un bundle.
        @(posedge clk); #1; values(1, 0, 0, 0, 0, 0, 0);
        step(1, 0, 0, 0, 0); values(2, 1, 0, 0, 0, 0, 0);
        step(1, 1, 0, 0, 0); values(3, 2, 1, 0, 0, 0, 0);
        step(0, 4, 1, 0, 0); values(4, 2, 1, 1, 0, 0, 0);
        step(0, 4, 0, 1, 0); values(5, 2, 1, 1, 1, 0, 1);
        step(0, 4, 0, 1, 1); values(6, 2, 1, 1, 2, 1, 2);
        step(0, 4, 0, 0, 1); values(7, 2, 1, 1, 2, 2, 3);
        step(1, 4, 0, 0, 0); values(8, 3, 5, 1, 2, 2, 3);
        step(1, 2, 1, 0, 0); values(9, 4, 7, 2, 2, 2, 3);
        step(1, 3, 0, 0, 0); values(10, 5, 10, 2, 2, 2, 3);
        // El reset entre flancos borra todos los contadores inmediatamente.
        #1 rst = 1; #1; values(0, 0, 0, 0, 0, 0, 0);
        @(posedge clk); #1; values(0, 0, 0, 0, 0, 0, 0);
        check("contadores de 64 bits", $bits(ciclos) == 64 && $bits(bundles) == 64 &&
              $bits(instrucciones) == 64 && $bits(saltos) == 64 &&
              $bits(pausa_crypto) == 64 && $bits(pausa_memoria) == 64 && $bits(pausa_total) == 64);

        // Prueba los 32 códigos en los cuatro slots, con ambas selecciones del slot 1.
        for (int sel = 0; sel < 2; sel++)
            for (int f = 0; f < 32; f++) begin
                int expected_ops;
                bit alu_op, crypto_op, branch_op, memory_op;
                alu_op = (f >= 1 && f <= 13) || (f >= 16 && f <= 18);
                crypto_op = f >= 1 && f <= 6;
                branch_op = (f >= 1 && f <= 5) || f == 16 || f == 17;
                memory_op = f >= 1 && f <= 4;
                expected_ops = int'(alu_op) + int'(sel ? crypto_op : alu_op) +
                               int'(branch_op) + int'(memory_op);
                probe_bundle = {4{(32'(f) << 26)}};
                probe_bundle[63] = 1'(sel);
                #1;
                check($sformatf("operaciones decodificadas funct=%0d sel=%0d", f, sel),
                      probe.id_ops_count === 3'(expected_ops));
            end
        // Un bundle de cuatro operaciones permanece en EX durante tres pausas.
        @(negedge clk); probe_bundle = 0; probe_rst = 0;
        @(posedge clk); #1;
        @(negedge clk);
        probe_bundle = {32'h08000000, 32'h0c000000, 32'h8c000000, 32'h04000000};
        @(posedge clk); #1;
        check("cantidad viaja con el bundle", probe.idex_ops_count == 4);
        check("dos ciclos iniciales sin confirmar", probe.u_perf_counters.ciclos == 2 &&
              probe.u_perf_counters.bundles == 0);
        @(negedge clk); probe_bundle = 0;
        force probe.mem_stall = 1;
        repeat (3) begin
            @(posedge clk); #1;
            check("pausa conserva cantidad", probe.idex_ops_count == 4);
            check("pausa no cuenta instrucciones", probe.u_perf_counters.instrucciones == 0);
        end
        @(negedge clk); release probe.mem_stall;
        @(posedge clk); #1;
        check("bundle detenido confirma una vez", probe.u_perf_counters.bundles == 1 &&
              probe.u_perf_counters.instrucciones == 4);
        check("pausa integrada de memoria", probe.u_perf_counters.pausa_memoria == 3 &&
              probe.u_perf_counters.pausa_total == 3);
        @(posedge clk); #1;
        check("NOP posterior no suma instrucciones", probe.u_perf_counters.bundles == 2 &&
              probe.u_perf_counters.instrucciones == 4);

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_perf_counters");
        $display("PASS tb_perf_counters");
        $finish;
    end
endmodule
