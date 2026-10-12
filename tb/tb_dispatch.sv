`timescale 1ns/1ps

// Plan de implementación, tarea 15: casos de microarchitecture.md §3.11 (sin CRYPTO).
module tb_dispatch;
    // microarchitecture.md §4.8 — codificaciones internas
    localparam logic [3:0] ALU_ADD = 4'b0000, ALU_SLL = 4'b0101, ALU_PASS = 4'b1101;
    localparam logic [2:0] BR_NONE = 3'b000, BR_BLT = 3'b011, BR_JAS = 3'b110;

    logic [127:0] bundle = '0;
    logic [7:0][3:0] rf_raddr;
    logic [31:0] s0_imm, s1_imm, s3_imm;
    logic [3:0]  s0_alu_op, s1_alu_op, s0_rd, s1_rd, s2_rd, s3_rd;
    logic        s0_use_imm, s1_use_imm, s0_we, s1_we, s2_we, s1_sel;
    logic [2:0]  s1_crypto_op, s2_br_op;
    logic [1:0]  s1_k, s1_i;
    logic [21:0] s2_instr_low;
    logic        s3_is_load, s3_is_store, s3_is_byte;
    int casos = 0;
    int fallos = 0;

    dispatch u_dispatch (.*);

    task automatic check(input string nombre,
        input logic [31:0] obtenido, esperado);
        casos++;
        if (obtenido === esperado) $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: obtenido=%08h esperado=%08h", nombre, obtenido, esperado);
        end
    endtask

    // Combinacional: se aplica el bundle y se espera un retardo antes de comparar.
    task automatic poner(input logic [127:0] b);
        bundle = b;
        #1;
    endtask

    initial begin
        $dumpfile("build/tb_dispatch.vcd");
        $dumpvars(0, tb_dispatch);

        // 1 — traza de §3.11
        poner(128'h05D80000_0D0FFFFE_98100000_054D0000);
        check("1 rf_raddr[0]", rf_raddr[0], 32'd3);
        check("1 rf_raddr[1]", rf_raddr[1], 32'd4);
        check("1 rf_raddr[2]", rf_raddr[2], 32'd4);
        check("1 rf_raddr[3]", rf_raddr[3], 32'd0);
        check("1 rf_raddr[4]", rf_raddr[4], 32'd3);
        check("1 rf_raddr[5]", rf_raddr[5], 32'd4);
        check("1 rf_raddr[6]", rf_raddr[6], 32'd6);
        check("1 rf_raddr[7]", rf_raddr[7], 32'd7);
        check("1 s0_alu_op", s0_alu_op, ALU_ADD);
        check("1 s0_use_imm", s0_use_imm, 32'd0);
        check("1 s0_rd", s0_rd, 32'd5);
        check("1 s0_we", s0_we, 32'd1);
        check("1 s0_imm", s0_imm, 32'h0001_0000);
        check("1 s1_sel", s1_sel, 32'd1);            // cambia con CRYPTO (plan §9.1)
        check("1 s1_crypto_op", s1_crypto_op, 32'd0); // cambia con CRYPTO (plan §9.1)
        check("1 s1_we", s1_we, 32'd0);              // cambia con CRYPTO (plan §9.1)
        check("1 s1_rd", s1_rd, 32'd0);
        check("1 s1_k", s1_k, 32'd0);
        check("1 s1_i", s1_i, 32'd0);
        check("1 s2_br_op", s2_br_op, BR_BLT);
        check("1 s2_instr_low", s2_instr_low, 32'h0F_FFFE);
        check("1 s2_rd", s2_rd, 32'd4);
        check("1 s2_we", s2_we, 32'd0);
        check("1 s3_is_load", s3_is_load, 32'd1);
        check("1 s3_is_store", s3_is_store, 32'd0);
        check("1 s3_is_byte", s3_is_byte, 32'd0);
        check("1 s3_rd", s3_rd, 32'd7);
        check("1 s3_imm", s3_imm, 32'd0);

        // 2 — feis en el slot 1 (isa.md §6.5)
        poner(128'h00000000_00000000_854D0800_00000000);
        check("2 s1_sel", s1_sel, 32'd1);
        check("2 s1_rd", s1_rd, 32'd5);
        check("2 s1_k", s1_k, 32'd0);
        check("2 s1_i", s1_i, 32'd2);
        check("2 s1_crypto_op", s1_crypto_op, 32'd0); // cambia con CRYPTO (plan §9.1)
        check("2 s1_we", s1_we, 32'd0);               // cambia con CRYPTO (plan §9.1)
        check("2 rf_raddr[2]", rf_raddr[2], 32'd3);
        check("2 rf_raddr[3]", rf_raddr[3], 32'd4);

        // 3 — bundle vacío
        poner(128'h0);
        check("3 s0_we", s0_we, 32'd0);
        check("3 s1_we", s1_we, 32'd0);
        check("3 s2_we", s2_we, 32'd0);
        check("3 s1_sel", s1_sel, 32'd0);
        check("3 s1_crypto_op", s1_crypto_op, 32'd0);
        check("3 s2_br_op", s2_br_op, BR_NONE);
        check("3 s3_is_load", s3_is_load, 32'd0);
        check("3 s3_is_store", s3_is_store, 32'd0);
        check("3 s3_is_byte", s3_is_byte, 32'd0);
        for (int p = 0; p < 8; p++)
            check($sformatf("3 rf_raddr[%0d]", p), rf_raddr[p], 32'd0);

        // 4 — add en el slot 1 con sel = 0
        poner(128'h00000000_00000000_054D0000_00000000);
        check("4 s1_sel", s1_sel, 32'd0);
        check("4 s1_crypto_op", s1_crypto_op, 32'd0);
        check("4 s1_alu_op", s1_alu_op, ALU_ADD);
        check("4 s1_use_imm", s1_use_imm, 32'd0);
        check("4 s1_rd", s1_rd, 32'd5);
        check("4 s1_we", s1_we, 32'd1);

        // 5 — sel = 1 sin CRYPTO: alu_dec ve add, pero s1_we se anula
        poner(128'h00000000_00000000_854D0000_00000000);
        check("5 s1_sel", s1_sel, 32'd1);
        check("5 s1_crypto_op", s1_crypto_op, 32'd0); // cambia con CRYPTO (plan §9.1)
        check("5 s1_we", s1_we, 32'd0);               // cambia con CRYPTO (plan §9.1)

        // 6 — inmediato negativo, slot 0 (saddi r4, r4, -1)
        poner(128'h00000000_00000000_00000000_4113FFFF);
        check("6 s0_imm", s0_imm, 32'hFFFF_FFFF);
        check("6 s0_alu_op", s0_alu_op, ALU_ADD);
        check("6 s0_use_imm", s0_use_imm, 32'd1);
        check("6 s0_rd", s0_rd, 32'd4);
        check("6 s0_we", s0_we, 32'd1);

        // 7 — inmediato máximo, slot 0 (mov r4, 131071)
        poner(128'h00000000_00000000_00000000_4901FFFF);
        check("7 s0_imm", s0_imm, 32'h0001_FFFF);
        check("7 s0_alu_op", s0_alu_op, ALU_PASS);
        check("7 s0_use_imm", s0_use_imm, 32'd1);

        // 8 — el bit sel del slot 0 no se conecta
        poner(128'h00000000_00000000_00000000_C9000000);
        check("8 s0_alu_op", s0_alu_op, ALU_PASS);
        check("8 s0_rd", s0_rd, 32'd4);
        check("8 s0_we", s0_we, 32'd1);
        check("8 s0_imm", s0_imm, 32'd0);

        // 9 — puerto B en el slot 3 (sw r9, 4(r6))
        poner(128'h0A580004_00000000_00000000_00000000);
        check("9 rf_raddr[6]", rf_raddr[6], 32'd6);
        check("9 rf_raddr[7]", rf_raddr[7], 32'd9);
        check("9 s3_is_store", s3_is_store, 32'd1);
        check("9 s3_is_load", s3_is_load, 32'd0);
        check("9 s3_imm", s3_imm, 32'd4);

        // 10 — inmediato negativo, slot 3 (lb r2, -1(r3))
        poner(128'h0C8FFFFF_00000000_00000000_00000000);
        check("10 s3_imm", s3_imm, 32'hFFFF_FFFF);
        check("10 s3_is_load", s3_is_load, 32'd1);
        check("10 s3_is_byte", s3_is_byte, 32'd1);
        check("10 s3_rd", s3_rd, 32'd2);
        check("10 rf_raddr[6]", rf_raddr[6], 32'd3);

        // 11 — jas en el slot 2 escribe enlace
        poner(128'h00000000_47C00005_00000000_00000000);
        check("11 s2_br_op", s2_br_op, BR_JAS);
        check("11 s2_we", s2_we, 32'd1);
        check("11 s2_rd", s2_rd, 32'd15);
        check("11 s2_instr_low", s2_instr_low, 32'h00_0005);

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_dispatch");
        $display("PASS tb_dispatch");
        $finish;
    end
endmodule
