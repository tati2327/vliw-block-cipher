`timescale 1ns/1ps

// Plan de implementación, tarea 20: IF + ID (microarchitecture.md §§2.7, 3.12, 3.13, 4.1, 4.4 y 4.6).
// El testbench hace de BRU y de crypto_unit: maneja stall, branch_taken y branch_target a mano.
// Entradas: se cambian en negedge + 1. Comprobaciones: en negedge + 2 (salidas combinacionales estables).
module tb_front;
    // microarchitecture.md §4.8 — codificaciones internas
    localparam logic [3:0] ALU_ADD = 4'b0000, ALU_PASS = 4'b1101;
    localparam logic [2:0] BR_BLT = 3'b011;
    localparam logic [127:0] BUNDLE0 = 128'h00000000_00000000_49400003_49000000;
    localparam logic [127:0] BUNDLE2 = 128'h00000000_0D500000_00000000_41100001;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    // Entradas manejadas por el tb
    logic        stall = 1'b0;
    logic        branch_taken = 1'b0;
    logic [21:0] branch_target = '0;
    logic [3:0][3:0]  waddr = '0;
    logic [3:0][31:0] wdata = '0;
    logic [3:0]       we = '0;

    // IF
    logic [21:0]  pc;
    logic [127:0] imem_rdata;
    logic         id_redirect;
    assign id_redirect = branch_taken & ~stall;   // salto retenido durante la pausa

    // IF/ID
    logic [127:0] ifid_bundle;
    logic [21:0]  ifid_pc;
    logic         ifid_valid;

    // ID
    logic [7:0][3:0]  rf_raddr;
    logic [7:0][31:0] rf_rdata;
    logic [31:0] s0_imm, s1_imm, s3_imm;
    logic [3:0]  s0_alu_op, s1_alu_op, s0_rd, s1_rd, s2_rd, s3_rd;
    logic        s0_use_imm, s1_use_imm, s0_we, s1_we, s2_we, s1_sel;
    logic [2:0]  s1_crypto_op, s2_br_op;
    logic [1:0]  s1_k, s1_i;
    logic [21:0] s2_instr_low;
    logic        s3_is_load, s3_is_store, s3_is_byte;

    int casos = 0;
    int fallos = 0;

    fetch u_fetch (.clk(clk), .rst(rst), .stall(stall), .branch_taken(id_redirect),
                   .branch_target(branch_target), .pc(pc));

    imem #(.INIT_FILE("programs/ejemplo_isa11.hex")) u_imem (.addr(pc), .rdata(imem_rdata));

    pipe_reg #(.W(128)) u_ifid_bundle (.clk(clk), .rst(rst), .flush(id_redirect),
                                       .en(~stall), .d(imem_rdata), .q(ifid_bundle));
    pipe_reg #(.W(22))  u_ifid_pc     (.clk(clk), .rst(rst), .flush(id_redirect),
                                       .en(~stall), .d(pc), .q(ifid_pc));
    pipe_reg #(.W(1))   u_ifid_valid  (.clk(clk), .rst(rst), .flush(id_redirect),
                                       .en(~stall), .d(1'b1), .q(ifid_valid));

    dispatch u_dispatch (.bundle(ifid_bundle), .*);

    regfile u_regfile (.clk(clk), .rst(rst), .raddr(rf_raddr), .rdata(rf_rdata),
                       .waddr(waddr), .wdata(wdata), .we(we));

    task automatic check(input string nombre,
        input logic [127:0] obtenido, esperado);
        casos++;
        if (obtenido === esperado) $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: obtenido=%h esperado=%h", nombre, obtenido, esperado);
        end
    endtask

    // Comprobación del estado de IF/ID y del PC.
    task automatic check_if(input string nombre,
        input logic [21:0] e_pc, input logic [127:0] e_bundle,
        input logic [21:0] e_ifid_pc, input logic e_valid);
        check({nombre, " pc"},          {106'b0, pc},          {106'b0, e_pc});
        check({nombre, " ifid_bundle"}, ifid_bundle,           e_bundle);
        check({nombre, " ifid_pc"},     {106'b0, ifid_pc},     {106'b0, e_ifid_pc});
        check({nombre, " ifid_valid"},  {127'b0, ifid_valid},  {127'b0, e_valid});
    endtask

    logic [21:0] pc_pausa, ifid_pc_pausa;

    initial begin
        $dumpfile("build/tb_front.vcd");
        $dumpvars(0, tb_front);

        // rst = 1 desde t = 0; se baja en el flanco de bajada que sigue al primer flanco de subida.
        @(negedge clk); #1;
        rst = 1'b0;
        #1;
        // 1a — ciclo 1
        check_if("1a", 22'd0, 128'd0, 22'd0, 1'b0);

        // 1b — ciclo 2; caso 3: escritura previa al regfile (la hace efectiva el flanco ↓ del ciclo 3)
        @(negedge clk); #1;
        waddr[0] = 4'd4; wdata[0] = 32'h44; we[0] = 1'b1;
        waddr[1] = 4'd5; wdata[1] = 32'h55; we[1] = 1'b1;
        #1;
        check_if("1b", 22'd1, BUNDLE0, 22'd0, 1'b1);
        // 2 — dispatch decodifica el bundle 0
        check("2 s0_alu_op", {124'b0, s0_alu_op}, {124'b0, ALU_PASS});
        check("2 s0_rd",     {124'b0, s0_rd},     128'd4);
        check("2 s0_imm",    {96'b0, s0_imm},     128'd0);
        check("2 s0_we",     {127'b0, s0_we},     128'd1);
        check("2 s1_alu_op", {124'b0, s1_alu_op}, {124'b0, ALU_PASS});
        check("2 s1_rd",     {124'b0, s1_rd},     128'd5);
        check("2 s1_imm",    {96'b0, s1_imm},     128'd3);
        check("2 s1_we",     {127'b0, s1_we},     128'd1);
        check("2 s2_we",     {127'b0, s2_we},     128'd0);
        check("2 s3_is_load", {127'b0, s3_is_load}, 128'd0);

        // 1c — ciclo 3; los we se bajan tras el flanco ↓ que escribió r4 y r5
        @(negedge clk); #1;
        we = '0;
        #1;
        check_if("1c", 22'd2, 128'd0, 22'd1, 1'b1);

        // 1d — ciclo 4; 5a: se activa el salto tomado a 2 durante este ciclo
        @(negedge clk); #1;
        branch_taken = 1'b1; branch_target = 22'd2;
        #1;
        check_if("1d", 22'd3, BUNDLE2, 22'd2, 1'b1);
        check("5a id_redirect", {127'b0, id_redirect}, 128'd1);
        // 4 — direcciones y datos de lectura del bundle 2
        check("4 rf_raddr[0]", {124'b0, rf_raddr[0]}, 128'd4);
        check("4 rf_raddr[4]", {124'b0, rf_raddr[4]}, 128'd4);
        check("4 rf_raddr[5]", {124'b0, rf_raddr[5]}, 128'd5);
        check("4 rf_rdata[0]", {96'b0, rf_rdata[0]},  128'h44);
        check("4 rf_rdata[4]", {96'b0, rf_rdata[4]},  128'h44);
        check("4 rf_rdata[5]", {96'b0, rf_rdata[5]},  128'h55);
        check("4 s0_alu_op",   {124'b0, s0_alu_op},   {124'b0, ALU_ADD});
        check("4 s0_use_imm",  {127'b0, s0_use_imm},  128'd1);
        check("4 s0_imm",      {96'b0, s0_imm},       128'd1);
        check("4 s0_rd",       {124'b0, s0_rd},       128'd4);
        check("4 s2_br_op",    {125'b0, s2_br_op},    {125'b0, BR_BLT});
        check("4 s2_instr_low", {106'b0, s2_instr_low}, {106'b0, 22'h100000});

        // 5a — tras el flanco ↑: IF/ID vaciado (el bundle 3 se descarta); se baja branch_taken
        @(negedge clk); #1;
        branch_taken = 1'b0;
        #1;
        check_if("5a", 22'd2, 128'd0, 22'd0, 1'b0);

        // 5b — ciclo 6; 6a: se activa el salto a 8 durante este ciclo
        @(negedge clk); #1;
        branch_taken = 1'b1; branch_target = 22'd8;
        #1;
        check_if("5b", 22'd3, BUNDLE2, 22'd2, 1'b1);

        // 6a — tras el flanco ↑: pc = 8 e IF/ID vacío; se baja branch_taken
        @(negedge clk); #1;
        branch_taken = 1'b0;
        #1;
        check_if("6a", 22'd8, 128'd0, 22'd0, 1'b0);

        // 6b — después del salto a 8; 7a: empieza la pausa en este ciclo
        @(negedge clk); #1;
        stall = 1'b1;
        #1;
        check_if("6b", 22'd9, 128'd0, 22'd8, 1'b1);
        pc_pausa = pc; ifid_pc_pausa = ifid_pc;

        // 7a — dos flancos ↑ con stall = 1: nada cambia
        @(negedge clk); #1; #1;
        check_if("7a flanco 1", pc_pausa, 128'd0, ifid_pc_pausa, 1'b1);
        @(negedge clk); #1;
        branch_taken = 1'b1; branch_target = 22'd2;   // 7b: salto durante la pausa
        #1;
        check_if("7a flanco 2", pc_pausa, 128'd0, ifid_pc_pausa, 1'b1);
        check("7b id_redirect (antes del flanco)", {127'b0, id_redirect}, 128'd0);

        // 7b — un flanco ↑ con stall = 1 y branch_taken = 1: ni se aplica ni vacía
        @(negedge clk); #1; #1;
        check_if("7b", pc_pausa, 128'd0, ifid_pc_pausa, 1'b1);
        check("7b id_redirect", {127'b0, id_redirect}, 128'd0);

        // 7c — fin de la pausa: se bajan stall y branch_taken; un flanco ↑
        stall = 1'b0; branch_taken = 1'b0;
        @(negedge clk); #1; #1;
        check_if("7c", pc_pausa + 22'd1, 128'd0, pc_pausa, 1'b1);

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_front");
        $display("PASS tb_front");
        $finish;
    end
endmodule
