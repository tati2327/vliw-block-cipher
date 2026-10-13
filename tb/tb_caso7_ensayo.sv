`timescale 1ns/1ps

// Ensayo del caso 7 (sin CRYPTO): xor en lugar de feis. No es el caso 7 final.
module tb_caso7_ensayo;
    logic clk = 0, rst = 1;
    int casos = 0, fallos = 0;
    int ciclo = 0, llegada = -1;
    int err_e1 = 0, err_e2 = 0;
    logic [21:0] ultimo_pc = '0;
    top #(.IMEM_INIT("programs/caso7_ensayo.hex"), .DMEM_INIT("data/caso7_ensayo.mem")) dut (.clk, .rst);
    always #5 clk = ~clk;

    task automatic check(input string nombre, input logic [31:0] obtenido, esperado);
        casos++;
        if (obtenido === esperado) $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: obtenido=%h esperado=%h", nombre, obtenido, esperado);
        end
    endtask

    initial begin
        $dumpfile("build/tb_caso7_ensayo.vcd");
        $dumpvars(0, tb_caso7_ensayo);
        @(posedge clk);
        @(negedge clk); rst = 0;

        // Llegada a fin (bundle 10), con límite de 5000 ciclos
        while (llegada < 0 && ciclo < 5000) begin
            @(negedge clk); #2;
            ciclo++;
            ultimo_pc = dut.u_core.ifid_pc;
            if (dut.u_core.ifid_valid === 1'b1 && dut.u_core.ifid_pc === 22'd10)
                llegada = ciclo;
        end
        casos++;
        if (llegada >= 0) $display("PASS llegada a fin en el ciclo %0d", llegada);
        else begin
            fallos++;
            $display("FAIL no llego a fin en 5000 ciclos; ultimo pc=%0d", ultimo_pc);
        end

        repeat (5) @(negedge clk);
        #2;
        $writememh("build/tb_caso7_ensayo_dump.mem", dut.u_memory.mem);

        for (int i = 0; i < 256; i++) begin
            if (dut.u_memory.mem[32'hC00 + i] !== dut.u_memory.mem[32'h400 + i]) begin
                if (err_e1 < 3)
                    $display("  E1 i=%0d obtenido=%h esperado=%h", i,
                             dut.u_memory.mem[32'hC00 + i], dut.u_memory.mem[32'h400 + i]);
                err_e1++;
            end
            if (dut.u_memory.mem[32'h800 + i] !== (dut.u_memory.mem[32'h400 + i] ^ 32'h0001A5A5)) begin
                if (err_e2 < 3)
                    $display("  E2 i=%0d obtenido=%h esperado=%h", i, dut.u_memory.mem[32'h800 + i],
                             dut.u_memory.mem[32'h400 + i] ^ 32'h0001A5A5);
                err_e2++;
            end
        end
        casos++;
        if (err_e1 == 0) $display("PASS E1 256/256 palabras");
        else begin fallos++; $display("FAIL E1 %0d/256 palabras distintas", err_e1); end
        casos++;
        if (err_e2 == 0) $display("PASS E2 256/256 palabras");
        else begin fallos++; $display("FAIL E2 %0d/256 palabras distintas", err_e2); end

        casos++;
        if (dut.u_memory.mem[32'h400] !== 32'h0 && ^dut.u_memory.mem[32'h400] !== 1'bx)
            $display("PASS E3 mem[0x400] cargada");
        else begin fallos++; $display("FAIL E3 mem[0x400]=%h", dut.u_memory.mem[32'h400]); end
        check("E4 t0 final", dut.u_core.u_regfile.regs[4], 32'h00001400);

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "tb_caso7_ensayo fallo");
        $display("PASS tb_caso7_ensayo");
        $finish;
    end
endmodule
