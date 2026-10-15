`timescale 1ns/1ps

// Caso 4 (enunciado §5.2, tarea 28): una ronda feis con auth, kv_write y memoria.
module tb_caso4_feis;
    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    top #(.IMEM_INIT("programs/caso4_feis.hex"), .DMEM_INIT("data/caso4_feis.mem")) dut (.clk(clk), .rst(rst));

    `define C dut.u_core
    `define S dut.u_core.u_crypto.u_crypto_state
    `define V dut.u_core.u_crypto.u_key_vault

    localparam logic [31:0] K0 = 32'h0F1E2D3C, K1 = 32'h4B5A6978, K2 = 32'h8796A5B4, K3 = 32'hC3D2E1F0;

    int casos = 0, fallos = 0;
    int ciclo = 0, llegada = -1;
    logic [21:0] ultimo_pc = '0;

    task automatic check(input string nombre, input logic [31:0] obtenido, esperado);
        casos++;
        if (obtenido === esperado) $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: obtenido=%h esperado=%h", nombre, obtenido, esperado);
        end
    endtask

    // F(x, k) = ((x <<< 5) + k) XOR (x <<< 13), suma de 32 bits
    function automatic logic [31:0] f(input logic [31:0] x, k);
        logic [31:0] r5, r13;
        r5  = {x[26:0], x[31:27]};
        r13 = {x[18:0], x[31:19]};
        return (r5 + k) ^ r13;
    endfunction

    initial begin
        $dumpfile("build/tb_caso4_feis.vcd");
        $dumpvars(0, tb_caso4_feis);
        @(posedge clk);
        @(negedge clk); #1; rst = 0;

        while (llegada < 0 && ciclo < 200) begin
            @(negedge clk); #2;
            ciclo++;
            ultimo_pc = `C.ifid_pc;
            if (`C.ifid_valid === 1'b1 && `C.ifid_pc === 22'd20) llegada = ciclo;
        end
        casos++;
        if (llegada >= 0) $display("PASS A llegada a fin en el ciclo %0d", llegada);
        else begin
            fallos++;
            $display("FAIL A no llego a fin en 200 ciclos; ultimo pc=%0d", ultimo_pc);
        end

        repeat (5) @(negedge clk);
        #2;

        check("modelo F (01234567 ^ F(89ABCDEF,K0))", 32'h01234567 ^ f(32'h89ABCDEF, K0), 32'h3C095F7F);
        check("B mem[0x2000]", dut.u_memory.mem[32'h800], 32'h3C095F7F);
        check("C t0", `C.u_regfile.regs[4], 32'h3C095F7F);
        check("D1 auth", {31'b0, `S.auth}, 32'd1);
        check("D2 exc", {31'b0, `S.exc}, 32'd0);
        check("E1 llave0[0]", `V.llaves[0][0], K0);
        check("E2 llave0[1]", `V.llaves[0][1], K1);
        check("E3 llave0[2]", `V.llaves[0][2], K2);
        check("E4 llave0[3]", `V.llaves[0][3], K3);
        check("F ancla_otp", `S.ancla_otp, 32'hF47BD70B);

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "tb_caso4_feis fallo");
        $display("PASS tb_caso4_feis");
        $finish;
    end
endmodule
