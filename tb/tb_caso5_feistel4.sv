`timescale 1ns/1ps

// Caso 5 (enunciado §5.2, tarea 29): Feistel4 sobre 1 KB, cifrar de 0x1000 a 0x2000
// y descifrar de 0x2000 a 0x3000. dut_n0 repite el programa con 0 bloques (prueba de borde).
module tb_caso5_feistel4;
    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    top #(.IMEM_INIT("programs/feistel4.hex"),    .DMEM_INIT("data/caso5_feistel4.mem")) dut    (.clk(clk), .rst(rst));
    top #(.IMEM_INIT("programs/feistel4_n0.hex"), .DMEM_INIT("data/caso5_feistel4.mem")) dut_n0 (.clk(clk), .rst(rst));

    `define C dut.u_core
    `define S dut.u_core.u_crypto.u_crypto_state
    `define V dut.u_core.u_crypto.u_key_vault

    localparam logic [31:0] K0 = 32'h0F1E2D3C, K1 = 32'h4B5A6978, K2 = 32'h8796A5B4, K3 = 32'hC3D2E1F0;

    int casos = 0, fallos = 0;
    int ciclo = 0, llegada = -1, llegada_n0 = -1;
    logic [21:0] ultimo_pc = '0;
    int err_b = 0, err_e = 0, no_cero = 0;
    logic [31:0] xor_total, l, r;
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

    initial begin
        $dumpfile("build/tb_caso5_feistel4.vcd");
        $dumpvars(0, tb_caso5_feistel4);
        @(posedge clk);
        @(negedge clk); #1; rst = 0;

        while (llegada < 0 && ciclo < 8000) begin
            @(negedge clk); #2;
            ciclo++;
            ultimo_pc = `C.ifid_pc;
            if (`C.ifid_valid === 1'b1 && `C.ifid_pc === 22'd44) llegada = ciclo;
            // jef fin alterna fin y una burbuja: se registra la primera llegada, no una instantánea
            if (llegada_n0 < 0 && dut_n0.u_core.ifid_valid === 1'b1 && dut_n0.u_core.ifid_pc === 22'd44)
                llegada_n0 = ciclo;
        end
        casos++;
        if (llegada >= 0) $display("PASS A llegada a fin en el ciclo %0d", llegada);
        else begin
            fallos++;
            $display("FAIL A no llego a fin en 8000 ciclos; ultimo pc=%0d", ultimo_pc);
        end

        repeat (5) @(negedge clk);
        #2;

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

        // C: valores fijos que anclan el modelo
        check("C mem[0x800]", dut.u_memory.mem[32'h800], 32'hD2163C19);
        check("C mem[0x801]", dut.u_memory.mem[32'h801], 32'h9738F433);
        check("C mem[0x8FE]", dut.u_memory.mem[32'h8FE], 32'h66DD2E5B);
        check("C mem[0x8FF]", dut.u_memory.mem[32'h8FF], 32'h3A7D47FD);

        // D: XOR de las 256 palabras cifradas
        xor_total = '0;
        for (int j = 0; j < 256; j++) xor_total ^= dut.u_memory.mem[32'h800 + j];
        check("D xor de 0x2000..0x23FC", xor_total, 32'h5DEEA565);

        // E: descifrado = original
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

        // F: estado de CRYPTO
        check("F1 auth", {31'b0, `S.auth}, 32'd1);
        check("F2 exc", {31'b0, `S.exc}, 32'd0);
        check("F3 llave0[0]", `V.llaves[0][0], K0);
        check("F4 llave0[1]", `V.llaves[0][1], K1);
        check("F5 llave0[2]", `V.llaves[0][2], K2);
        check("F6 llave0[3]", `V.llaves[0][3], K3);

        // G: 0 bloques, no se escribe nada (dut_n0 ya termino antes que dut)
        casos++;
        if (llegada_n0 >= 0) $display("PASS G0 dut_n0 llego a fin en el ciclo %0d", llegada_n0);
        else begin
            fallos++;
            $display("FAIL G0 dut_n0 no llego a fin");
        end
        for (int j = 0; j < 256; j++) begin
            if (dut_n0.u_memory.mem[32'h800 + j] !== 32'h0) no_cero++;
            if (dut_n0.u_memory.mem[32'hC00 + j] !== 32'h0) no_cero++;
        end
        casos++;
        if (no_cero == 0) $display("PASS G dut_n0: 0x2000 y 0x3000 en cero");
        else begin fallos++; $display("FAIL G dut_n0: %0d palabras distintas de cero", no_cero); end

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "tb_caso5_feistel4 fallo");
        $display("PASS tb_caso5_feistel4");
        $finish;
    end
endmodule
