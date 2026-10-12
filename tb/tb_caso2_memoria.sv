`timescale 1ns/1ps

// Tarea 26. Validado con top/core de develop 08eb28b (tarea 24).
// Esperados: plan_implementacion_modulos.md, tarea 26.
module tb_caso2_memoria;
    logic clk = 0, rst = 1;
    int casos = 0, fallos = 0, stores = 0;
    top #(.IMEM_INIT("programs/caso2_memoria.hex"),
          .DMEM_INIT("data/caso2_memoria.mem")) dut (.clk, .rst);
    always #5 clk = ~clk;

    always @(posedge clk)
        if (!rst && dut.u_memory.we === 1'b1) stores++;

    task automatic check(input string nombre, input logic [31:0] obtenido, esperado);
        casos++;
        if (obtenido === esperado) $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: obtenido=%h esperado=%h", nombre, obtenido, esperado);
        end
    endtask

    initial begin
        $dumpfile("build/tb_caso2_memoria.vcd");
        $dumpvars(0, tb_caso2_memoria);
        repeat (2) @(negedge clk);
        rst = 0;
        // Diez bundles más margen para llenar y vaciar el pipeline.
        repeat (30) @(posedge clk);
        @(negedge clk); #1; // La escritura de WB ya terminó.
        check("t2 palabra original", dut.u_core.u_regfile.regs[6], 'h7F80FF01);
        check("t3 byte negativo", dut.u_core.u_regfile.regs[7], 'hFFFFFF80);
        check("t4 byte positivo", dut.u_core.u_regfile.regs[8], 'h0000007F);
        check("t5 palabra despues de sb", dut.u_core.u_regfile.regs[9], 'h7FAAFF01);
        check("t6 lw no alineado", dut.u_core.u_regfile.regs[10], 'h7F80FF01);
        check("t7 desplazamiento negativo", dut.u_core.u_regfile.regs[11], 'h7F80FF01);
        check("memoria 0x1000", dut.u_memory.mem['h400], 'h7FAAFF01);
        check("memoria 0x1004", dut.u_memory.mem['h401], 'h7F80FF01);
        check("r0 conserva cero", dut.u_core.u_regfile.regs[0], 0);
        check("exactamente dos escrituras de memoria", stores, 2);
        $writememh("build/tb_caso2_memoria_dump.mem", dut.u_memory.mem);
        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_caso2_memoria");
        $display("PASS tb_caso2_memoria");
        $finish;
    end
    initial begin
        #2000; $fatal(1, "FAIL tb_caso2_memoria: tiempo limite excedido");
    end
endmodule
