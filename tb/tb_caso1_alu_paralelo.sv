`timescale 1ns/1ps

// Plan de implementación, tarea 25: caso 1 del enunciado §5.2.
// ALU0 y ALU1 en paralelo con BRU y LSU. Comprobaciones: negedge + 2.
module tb_caso1_alu_paralelo;
    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    top #(.IMEM_INIT("programs/caso1.hex")) dut (.clk(clk), .rst(rst));

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

    int ciclo = 1;
    int ciclo_b4 = 0;

    initial begin
        $dumpfile("build/tb_caso1_alu_paralelo.vcd");
        $dumpvars(0, tb_caso1_alu_paralelo);

        // rst = 1 desde t = 0; se baja en el flanco de bajada que sigue al primer flanco de subida.
        @(negedge clk); #1;
        rst = 1'b0;
        #1;

        // Caso A — bundle 4 en ID (ciclo 6): los cuatro slots activos a la vez
        while (ciclo <= 20 && !(dut.u_core.ifid_valid === 1'b1 && dut.u_core.ifid_pc === 10'd4)) begin
            @(negedge clk); #1; #1;
            ciclo++;
        end
        if (ciclo > 20) begin
            casos++;
            fallos++;
            $display("FAIL A bundle 4 no llego a ID en los primeros 20 ciclos");
        end else begin
            ciclo_b4 = ciclo;
            $display("INFO bundle 4 en ID en el ciclo %0d", ciclo_b4);
            check("A s0_we (ALU0)",          {31'b0, dut.u_core.s0_we},       32'd1);
            check("A s1_we (ALU1)",          {31'b0, dut.u_core.s1_we},       32'd1);
            check("A s2_br_op (BRU beq)",    {29'b0, dut.u_core.s2_br_op},    32'b001);
            check("A s3_is_load (LSU lw)",   {31'b0, dut.u_core.s3_is_load},  32'd1);
            check("A id_branch_taken",       {31'b0, dut.u_core.id_branch_taken}, 32'd1);
        end

        // Caso B — ciclo 30
        while (ciclo < 30) begin
            @(negedge clk); #1; #1;
            ciclo++;
        end

        check("B1 t2", dut.u_core.u_regfile.regs[6],  32'd12);
        check("B1 t3", dut.u_core.u_regfile.regs[7],  32'd2);
        check("B2 mem[16]", dut.u_memory.mem[16],     32'd5);
        check("B3 t4", dut.u_core.u_regfile.regs[8],  32'd2);
        check("B3 t5", dut.u_core.u_regfile.regs[9],  32'd1);
        check("B4 t6", dut.u_core.u_regfile.regs[10], 32'd5);
        check("B4 t7", dut.u_core.u_regfile.regs[11], 32'd7);
        check("B4 t8", dut.u_core.u_regfile.regs[12], 32'd5);
        check("B5 t9", dut.u_core.u_regfile.regs[13], 32'd0);
        check("B6 t0", dut.u_core.u_regfile.regs[4],  32'd5);
        check("B6 t1", dut.u_core.u_regfile.regs[5],  32'd7);

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "tb_caso1_alu_paralelo: %0d fallos", fallos);
        $finish;
    end
endmodule
