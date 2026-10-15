`timescale 1ns/1ps

// Caso 6 (enunciado §5.2, tarea 30): bóveda de llaves, sesión, sello y no fuga de llaves.
module tb_caso6_boveda;
    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    top #(.IMEM_INIT("programs/caso6_boveda.hex")) dut (.clk(clk), .rst(rst));

    `define C dut.u_core
    `define S dut.u_core.u_crypto.u_crypto_state
    `define V dut.u_core.u_crypto.u_key_vault

    int casos = 0, fallos = 0;
    int ciclo = 0;
    logic [31:0] clave [0:15];
    int errores;

    task automatic check(input string nombre, input logic [31:0] obtenido, esperado);
        casos++;
        if (obtenido === esperado) $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: obtenido=%h esperado=%h", nombre, obtenido, esperado);
        end
    endtask

    // Espera el ciclo con ifid_pc == pc y ifid_valid == 1 (límite global de 600 ciclos).
    // Deja el tiempo en negedge + 2.
    task automatic espera_pc(input string nombre, input int pc);
        bit llego = 0;
        while (!llego && ciclo < 600) begin
            @(negedge clk); #2;
            ciclo++;
            if (`C.ifid_valid === 1'b1 && `C.ifid_pc === 22'(pc)) llego = 1;
        end
        casos++;
        if (llego) $display("PASS llegada a %s (pc=%0d) en el ciclo %0d", nombre, pc, ciclo);
        else begin
            fallos++;
            $display("FAIL no llego a %s (pc=%0d) en 600 ciclos; ultimo pc=%0d", nombre, pc, `C.ifid_pc);
        end
    endtask

    // Compara las 16 palabras de la bóveda con las esperadas; un caso por grupo.
    task automatic check_boveda(input string nombre);
        errores = 0;
        for (int k = 0; k < 4; k++)
            for (int w = 0; w < 4; w++)
                if (`V.llaves[k][w] !== clave[4*k + w]) begin
                    if (errores < 3)
                        $display("  %s llaves[%0d][%0d]=%h esperado=%h", nombre, k, w, `V.llaves[k][w], clave[4*k + w]);
                    errores++;
                end
        casos++;
        if (errores == 0) $display("PASS %s 16/16 palabras de la boveda", nombre);
        else begin fallos++; $display("FAIL %s %0d/16 palabras distintas", nombre, errores); end
    endtask

    initial begin
        for (int i = 0; i < 16; i++) clave[i] = 32'h1A010 + 32'h111 * i;

        $dumpfile("build/tb_caso6_boveda.vcd");
        $dumpvars(0, tb_caso6_boveda);
        @(posedge clk);
        @(negedge clk); #1; rst = 0;

        // ---- marca1 ----
        espera_pc("marca1", 11);
        check("1a auth", {31'b0, `S.auth}, 32'd0);
        check("1a exc", {31'b0, `S.exc}, 32'd1);
        check("1b ancla_otp", `S.ancla_otp, 32'hFEFF95FF);
        check("1c t3 centinela", `C.u_regfile.regs[7], 32'h77);

        // ---- marca2 ----
        espera_pc("marca2", 40);
        check("2a auth", {31'b0, `S.auth}, 32'd1);
        check("2a exc", {31'b0, `S.exc}, 32'd0);
        check("2a kvlock", {31'b0, `S.kvlock}, 32'd1);
        check("2b ancla_otp", `S.ancla_otp, 32'hF47BD70B);
        check_boveda("2c");
        check("2d t4", `C.u_regfile.regs[8], 32'd0);
        check("2d t5", `C.u_regfile.regs[9], 32'd0);
        check("2d t6", `C.u_regfile.regs[10], 32'd0);

        // ---- marca3 ----
        espera_pc("marca3", 46);
        check("3a exc", {31'b0, `S.exc}, 32'd1);
        check("3a auth", {31'b0, `S.auth}, 32'd1);
        check("3a kvlock", {31'b0, `S.kvlock}, 32'd1);
        check("3b llaves[1][1]", `V.llaves[1][1], 32'h1A565);
        check("3c t8", `C.u_regfile.regs[12], 32'h000100B5);

        // ---- marca4 ----
        espera_pc("marca4", 55);
        check("4a auth", {31'b0, `S.auth}, 32'd1);
        check("4a exc", {31'b0, `S.exc}, 32'd0);
        check("4a ancla_otp", `S.ancla_otp, 32'hA45326BA);

        // ---- fin + 5 ciclos ----
        espera_pc("fin", 60);
        repeat (5) @(negedge clk);
        #2;
        check("5a auth", {31'b0, `S.auth}, 32'd0);
        check("5a exc", {31'b0, `S.exc}, 32'd1);
        check("5a kvlock", {31'b0, `S.kvlock}, 32'd1);
        check("5b t9", `C.u_regfile.regs[13], 32'd0);
        check("5f mem[0x100]", dut.u_memory.mem[64], 32'd0);
        check_boveda("5c");

        // 5d: ningún registro igual a una palabra de llave
        errores = 0;
        for (int r = 1; r < 16; r++)
            for (int w = 0; w < 16; w++)
                if (`C.u_regfile.regs[r] === clave[w]) begin
                    $display("  5d regs[%0d]=%h igual a la palabra de llave %0d", r, `C.u_regfile.regs[r], w);
                    errores++;
                end
        casos++;
        if (errores == 0) $display("PASS 5d ningun registro contiene una palabra de llave");
        else begin fallos++; $display("FAIL 5d %0d coincidencias", errores); end

        // 5e: ninguna palabra de memoria igual a una palabra de llave
        errores = 0;
        for (int a = 0; a < 16384; a++)
            for (int w = 0; w < 16; w++)
                if (dut.u_memory.mem[a] === clave[w]) begin
                    if (errores < 3)
                        $display("  5e mem[%0d] (0x%0h)=%h igual a la palabra de llave %0d", a, a*4, dut.u_memory.mem[a], w);
                    errores++;
                end
        casos++;
        if (errores == 0) $display("PASS 5e ninguna palabra de memoria es una palabra de llave");
        else begin fallos++; $display("FAIL 5e %0d coincidencias", errores); end

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "tb_caso6_boveda fallo");
        $display("PASS tb_caso6_boveda");
        $finish;
    end
endmodule
