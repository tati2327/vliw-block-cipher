`timescale 1ns/1ps

// Plan de implementación, tarea 24 (sin CRYPTO): microarchitecture.md §3.14 y §4.6.
// Seis procesadores con distinto programa corren a la vez con el mismo clk y rst.
// Entradas: negedge + 1. Comprobaciones: negedge + 2.
module tb_top;
    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    top #(.IMEM_INIT("programs/ejemplo_isa11.hex")) dut       (.clk(clk), .rst(rst));
    top #(.IMEM_INIT("programs/core_dep.hex"))      dut_dep   (.clk(clk), .rst(rst));
    top #(.IMEM_INIT("programs/core_salto.hex"))    dut_salto (.clk(clk), .rst(rst));
    top #(.IMEM_INIT("programs/core_ifmov.hex"))    dut_ifmov (.clk(clk), .rst(rst));
    top #(.IMEM_INIT("programs/core_swlw.hex"))     dut_swlw  (.clk(clk), .rst(rst));
    top #(.IMEM_INIT("programs/core_jas.hex"))      dut_jas   (.clk(clk), .rst(rst));

    int casos = 0;
    int fallos = 0;

    task automatic check(input string nombre,
        input logic [31:0] obtenido, esperado);
        casos++;
        if (obtenido === esperado) $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: obtenido=%h esperado=%h", nombre, obtenido, esperado);
        end
    endtask

    // Traza de §4.6, ciclos 1 a 14. Etapa: -1 = vacío (valid = 0, pc = 0), n = bundle n.
    localparam int N = 14;
    int e_pc [1:N];
    int e_id [1:N];
    int e_ex [1:N];
    int e_wb [1:N];
    int e_tk [1:N];
    int e_r4 [1:N];
    int e_r5 [1:N];

    task automatic fila(input int c, p, i, x, w, t, r4, r5);
        e_pc[c] = p; e_id[c] = i; e_ex[c] = x; e_wb[c] = w;
        e_tk[c] = t; e_r4[c] = r4; e_r5[c] = r5;
    endtask

    // columnas: ciclo, PC, ID, EX, WB, taken, r4, r5
    task automatic carga_traza();
        fila(1, 0, -1, -1, -1, 0, 0, 0);
        fila(2, 1, 0, -1, -1, 0, 0, 0);
        fila(3, 2, 1, 0, -1, 0, 0, 0);
        fila(4, 3, 2, 1, 0, 1, 0, 3);
        fila(5, 2, -1, 2, 1, 0, 0, 3);
        fila(6, 3, 2, -1, 2, 1, 1, 3);
        fila(7, 2, -1, 2, -1, 0, 1, 3);
        fila(8, 3, 2, -1, 2, 1, 2, 3);
        fila(9, 2, -1, 2, -1, 0, 2, 3);
        fila(10, 3, 2, -1, 2, 0, 3, 3);
        fila(11, 4, 3, 2, -1, 0, 3, 3);
        fila(12, 5, 4, 3, 2, 0, 4, 3);
        fila(13, 6, 5, 4, 3, 0, 4, 3);
        fila(14, 7, 6, 5, 4, 0, 4, 3);
    endtask

    bit traza_fallo = 1'b0;

    // Compara una fila completa; al primer fallo la imprime y se salta el resto de la traza.
    task automatic check_fila(input int c);
        int o_pc, o_id, o_ex, o_wb, o_tk, o_r4, o_r5;
        bit ok;
        if (!traza_fallo) begin
            // Un vacío se lee como -1 si valid = 0 y pc = 0
            o_pc = int'(dut.u_core.u_fetch.pc);
            o_id = (dut.u_core.ifid_valid === 1'b1) ? int'(dut.u_core.ifid_pc) :
                   (dut.u_core.ifid_valid === 1'b0 && dut.u_core.ifid_pc === '0) ? -1 : -2;
            o_ex = (dut.u_core.ex_valid === 1'b1) ? int'(dut.u_core.idex_pc) :
                   (dut.u_core.ex_valid === 1'b0 && dut.u_core.idex_pc === '0) ? -1 : -2;
            o_wb = (dut.u_core.exwb_valid === 1'b1) ? int'(dut.u_core.exwb_pc) :
                   (dut.u_core.exwb_valid === 1'b0 && dut.u_core.exwb_pc === '0) ? -1 : -2;
            o_tk = (dut.u_core.id_branch_taken === 1'b1) ? 1 :
                   (dut.u_core.id_branch_taken === 1'b0) ? 0 : -2;
            o_r4 = int'(dut.u_core.u_regfile.regs[4]);
            o_r5 = int'(dut.u_core.u_regfile.regs[5]);
            ok = (o_pc == e_pc[c]) && (o_id == e_id[c]) && (o_ex == e_ex[c]) &&
                 (o_wb == e_wb[c]) && (o_tk == e_tk[c]) && (o_r4 == e_r4[c]) &&
                 (o_r5 == e_r5[c]);
            casos++;
            if (ok) $display("PASS 1 traza ciclo %0d", c);
            else begin
                fallos++;
                traza_fallo = 1'b1;
                $display("FAIL 1 traza ciclo %0d (vacio = -1, indefinido = -2; se omite el resto)", c);
                $display("  esperado: PC=%0d ID=%0d EX=%0d WB=%0d taken=%0d r4=%0d r5=%0d",
                         e_pc[c], e_id[c], e_ex[c], e_wb[c], e_tk[c], e_r4[c], e_r5[c]);
                $display("  obtenido: PC=%0d ID=%0d EX=%0d WB=%0d taken=%0d r4=%0d r5=%0d",
                         o_pc, o_id, o_ex, o_wb, o_tk, o_r4, o_r5);
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_top.vcd");
        $dumpvars(0, tb_top);

        // rst = 1 desde t = 0; se baja en el flanco de bajada que sigue al primer flanco de subida.
        @(negedge clk); #1;
        rst = 1'b0;
        #1;

        // Caso 1 — traza de §4.6, ciclos 1 a 14
        carga_traza();
        for (int c = 1; c <= N; c++) begin
            check_fila(c);
            @(negedge clk); #1; #1;
        end

        // El bucle anterior terminó al inicio del ciclo 15; faltan 16 flancos ↑ para el ciclo 31
        for (int c = N + 2; c <= 31; c++) begin
            @(negedge clk); #1; #1;
        end

        // Casos 2 a 7 — ciclo 31
        check("2 dut r4",  dut.u_core.u_regfile.regs[4], 32'd4);
        check("2 dut r5",  dut.u_core.u_regfile.regs[5], 32'd3);
        check("2 dut pc",  {10'b0, dut.u_core.u_fetch.pc}, 32'd24);

        check("3a dut_dep t1", dut_dep.u_core.u_regfile.regs[5], 32'd0);
        check("3b dut_dep t2", dut_dep.u_core.u_regfile.regs[6], 32'd5);

        check("4a dut_salto t2", dut_salto.u_core.u_regfile.regs[6], 32'd1);
        check("4b dut_salto t3", dut_salto.u_core.u_regfile.regs[7], 32'd0);
        check("4c dut_salto t4", dut_salto.u_core.u_regfile.regs[8], 32'd1);

        check("5a dut_ifmov t0", dut_ifmov.u_core.u_regfile.regs[4], 32'd7);
        check("5b dut_ifmov t2", dut_ifmov.u_core.u_regfile.regs[6], 32'd9);

        check("6a dut_swlw t2",      dut_swlw.u_core.u_regfile.regs[6], 32'h00000ABC);
        check("6b dut_swlw mem[64]", dut_swlw.u_memory.mem[64],         32'h00000ABC);

        check("7a dut_jas rl", dut_jas.u_core.u_regfile.regs[1], 32'd1);
        check("7b dut_jas t0", dut_jas.u_core.u_regfile.regs[4], 32'd0);
        check("7b dut_jas t1", dut_jas.u_core.u_regfile.regs[5], 32'd0);
        check("7c dut_jas t2", dut_jas.u_core.u_regfile.regs[6], 32'd1);

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_top");
        $display("PASS tb_top");
        $finish;
    end
endmodule
