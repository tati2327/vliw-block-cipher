`timescale 1ns/1ps

// Caso 7 (enunciado §5.2, tarea 31): programa mixto sobre un archivo real.
// Cifra con CRYPTO el texto de data/caso7_ensayo.mem (0x1000) hacia 0x2000 y lo descifra hacia 0x3000.
module tb_caso7_mixto;
    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    top #(.IMEM_INIT("programs/feistel4.hex"), .DMEM_INIT("data/caso7_ensayo.mem")) dut (.clk(clk), .rst(rst));

    `define C dut.u_core
    `define S dut.u_core.u_crypto.u_crypto_state

    localparam logic [31:0] K0 = 32'h0F1E2D3C, K1 = 32'h4B5A6978, K2 = 32'h8796A5B4, K3 = 32'hC3D2E1F0;

    int casos = 0, fallos = 0;
    int ciclo = 0, llegada = -1;
    int err_b = 0, err_e = 0;
    int paralelo = 0, feis_ciclos = 0;
    logic [21:0] ultimo_pc = '0;
    logic [31:0] l, r;
    logic [31:0] esp [0:255];

    task automatic check(input string nombre, input logic [31:0] obtenido, esperado);
        casos++;
        if (obtenido === esperado) $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: obtenido=%h esperado=%h", nombre, obtenido, esperado);
        end
    endtask

    function automatic logic [31:0] f(input logic [31:0] x, k);
        logic [31:0] r5, r13;
        r5  = {x[26:0], x[31:27]};
        r13 = {x[18:0], x[31:19]};
        return (r5 + k) ^ r13;
    endfunction

    // Evidencia del paralelismo: bundles válidos en ID, sin contar ciclos de pausa de auth.
    always @(negedge clk) begin
        #2;
        if (!rst && `C.ifid_valid === 1'b1 && `C.crypto_stall !== 1'b1) begin
            if (`C.s0_we === 1'b1 && `C.s2_br_op !== 3'b000 && `C.s3_is_store === 1'b1) paralelo++;
            if (`C.s1_crypto_op === 3'b001) feis_ciclos++;
        end
    end

    initial begin
        $dumpfile("build/tb_caso7_mixto.vcd");
        $dumpvars(0, tb_caso7_mixto);
        @(posedge clk);
        @(negedge clk); #1; rst = 0;

        while (llegada < 0 && ciclo < 8000) begin
            @(negedge clk); #2;
            ciclo++;
            ultimo_pc = `C.ifid_pc;
            if (`C.ifid_valid === 1'b1 && `C.ifid_pc === 22'd44) llegada = ciclo;
        end
        casos++;
        if (llegada >= 0) $display("PASS A llegada a fin en el ciclo %0d", llegada);
        else begin
            fallos++;
            $display("FAIL A no llego a fin en 8000 ciclos; ultimo pc=%0d", ultimo_pc);
        end

        repeat (5) @(negedge clk);
        #2;
        $writememh("build/tb_caso7_mixto_dump.mem", dut.u_memory.mem);

        // B: modelo contra 0x2000
        for (int b = 0; b < 128; b++) begin
            l = dut.u_memory.mem[32'h400 + 2*b];
            r = dut.u_memory.mem[32'h401 + 2*b];
            l ^= f(r, K0); r ^= f(l, K1); l ^= f(r, K2); r ^= f(l, K3);
            esp[2*b] = l; esp[2*b+1] = r;
        end
        for (int j = 0; j < 256; j++)
            if (dut.u_memory.mem[32'h800 + j] !== esp[j]) begin
                if (err_b < 3)
                    $display("  B j=%0d obtenido=%h esperado=%h", j, dut.u_memory.mem[32'h800 + j], esp[j]);
                err_b++;
            end
        casos++;
        if (err_b == 0) $display("PASS B 256/256 palabras contra el modelo");
        else begin fallos++; $display("FAIL B %0d/256 palabras distintas", err_b); end

        // E: 0x3000 igual a 0x1000
        for (int j = 0; j < 256; j++)
            if (dut.u_memory.mem[32'hC00 + j] !== dut.u_memory.mem[32'h400 + j]) begin
                if (err_e < 3)
                    $display("  E j=%0d obtenido=%h esperado=%h", j,
                             dut.u_memory.mem[32'hC00 + j], dut.u_memory.mem[32'h400 + j]);
                err_e++;
            end
        casos++;
        if (err_e == 0) $display("PASS E 256/256 palabras descifradas");
        else begin fallos++; $display("FAIL E %0d/256 palabras distintas", err_e); end

        check("auth", {31'b0, `S.auth}, 32'd1);

        $display("Paralelismo: ciclos con saddi + blt + sw en el mismo bundle = %0d (esperado 256)", paralelo);
        $display("Paralelismo: ciclos con feis en ID = %0d (esperado 1024)", feis_ciclos);
        check("conteo saddi+blt+sw", paralelo, 32'd256);
        check("conteo feis", feis_ciclos, 32'd1024);

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "tb_caso7_mixto fallo");
        $display("PASS tb_caso7_mixto");
        $finish;
    end
endmodule
