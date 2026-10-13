`timescale 1ns/1ps

// microarchitecture.md §§2.6, 2.7, 2.11, 3.14, 4.3, 4.4 y 4.5; tarea 24, con CRYPTO (plan §9.1).
// Pipeline de 4 etapas: IF, ID, EX, WB. Los campos de cada pipe_reg se concatenan
// en d y se separan a la salida en el mismo orden de §4.4.
module core #(parameter int PC_W = 22)(
  input  logic            clk, rst, init_anchor,
  output logic [PC_W-1:0] imem_addr,
  input  logic [127:0]    imem_rdata,
  output logic [31:0]     dmem_addr, dmem_wdata,
  output logic            dmem_we,
  output logic [3:0]      dmem_be,
  input  logic [31:0]     dmem_rdata
);
    // ---------------------------------------------------------------- señales
    // Pausa de auth (§2.11)
    logic crypto_stall;
    logic [31:0] crypto_result;
    logic        crypto_allowed;
    logic ex_valid, ex_commit;

    // IF
    logic [PC_W-1:0] pc;

    // IF/ID
    logic [127:0]    ifid_bundle;
    logic [PC_W-1:0] ifid_pc;
    logic            ifid_valid;

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
    logic            id_branch_taken, id_redirect;
    logic [PC_W-1:0] id_branch_target;
    logic [31:0]     id_link;

    // ID/EX
    logic [105:0] idex_s0_q;
    logic [113:0] idex_s1_q;
    logic [36:0]  idex_s2_q;
    logic [102:0] idex_s3_q;
    logic [PC_W-1:0] idex_pc;
    logic            idex_valid;
    logic [31:0] idex_s0_a, idex_s0_b, idex_s0_imm;
    logic [3:0]  idex_s0_alu_op, idex_s0_rd;
    logic        idex_s0_use_imm, idex_s0_we;
    logic [31:0] idex_s1_a, idex_s1_b, idex_s1_imm;
    logic [3:0]  idex_s1_alu_op, idex_s1_rd;
    logic        idex_s1_use_imm, idex_s1_sel, idex_s1_we;
    logic [2:0]  idex_s1_crypto_op;
    logic [1:0]  idex_s1_k, idex_s1_i;
    logic [31:0] idex_s2_link;
    logic [3:0]  idex_s2_rd;
    logic        idex_s2_we;
    logic [31:0] idex_s3_base, idex_s3_sdata, idex_s3_imm;
    logic        idex_s3_is_load, idex_s3_is_store, idex_s3_is_byte;
    logic [3:0]  idex_s3_rd;

    // EX
    logic [31:0] alu0_y, alu1_y, lsu_load_data;
    logic        alu0_cond_ok, alu1_cond_ok, lsu_dmem_we;
    logic [31:0] ex_s0_result, ex_s1_result, ex_s2_result, ex_s3_result;
    logic        ex_s0_we, ex_s1_we, ex_s2_we, ex_s3_we;

    // EX/WB
    logic [36:0] exwb_s0_q, exwb_s1_q, exwb_s2_q, exwb_s3_q;
    logic [PC_W-1:0] exwb_pc;
    logic            exwb_valid;
    logic [31:0] exwb_s0_result, exwb_s1_result, exwb_s2_result, exwb_s3_result;
    logic [3:0]  exwb_s0_rd, exwb_s1_rd, exwb_s2_rd, exwb_s3_rd;
    logic        exwb_s0_we, exwb_s1_we, exwb_s2_we, exwb_s3_we;

    // WB
    logic [3:0][3:0]  wb_waddr;
    logic [3:0][31:0] wb_wdata;
    logic [3:0]       wb_we;

    // ------------------------------------------------------------- etapa IF
    // §§3.12 y 3.14: u_fetch.pc va a la memoria de instrucciones y a IF/ID.
    fetch #(.PC_W(PC_W)) u_fetch (
        .clk(clk), .rst(rst), .stall(crypto_stall),
        .branch_taken(id_redirect), .branch_target(id_branch_target), .pc(pc)
    );
    assign imem_addr = pc;

    // ------------------------------------------------------- registro IF/ID
    // §4.4: flush = id_redirect, en = ~crypto_stall; validez según §2.11.
    pipe_reg #(.W(128)) u_ifid_bundle (.clk(clk), .rst(rst), .flush(id_redirect),
        .en(~crypto_stall), .d(imem_rdata), .q(ifid_bundle));
    pipe_reg #(.W(PC_W)) u_ifid_pc (.clk(clk), .rst(rst), .flush(id_redirect),
        .en(~crypto_stall), .d(pc), .q(ifid_pc));
    pipe_reg #(.W(1)) u_ifid_valid (.clk(clk), .rst(rst), .flush(id_redirect),
        .en(~crypto_stall), .d(1'b1), .q(ifid_valid));

    // ------------------------------------------------------------- etapa ID
    // §§2.5, 2.7, 3.11 y 3.14: dispatch separa y decodifica, regfile lee y la BRU resuelve el salto.
    dispatch u_dispatch (.bundle(ifid_bundle), .*);

    regfile u_regfile (
        .clk(clk), .rst(rst), .raddr(rf_raddr), .rdata(rf_rdata),
        .waddr(wb_waddr), .wdata(wb_wdata), .we(wb_we)
    );

    bru #(.PC_W(PC_W)) u_bru (
        .pc(ifid_pc), .a(rf_rdata[4]), .b(rf_rdata[5]),
        .instr_low(s2_instr_low), .br_op(s2_br_op),
        .taken(id_branch_taken), .target(id_branch_target), .link(id_link)
    );

    // Salto retenido durante la pausa (§2.11)
    assign id_redirect = id_branch_taken & ~crypto_stall;

    // ------------------------------------------------------- registro ID/EX
    // §4.4: flush = 0, en = ~crypto_stall. u_idex_s1 lleva los 114 bits (sel, crypto_op, k, i)
    // aunque hoy no se usen: al integrar CRYPTO, ID/EX no cambia.
    pipe_reg #(.W(106)) u_idex_s0 (.clk(clk), .rst(rst), .flush(1'b0), .en(~crypto_stall),
        .d({rf_rdata[0], rf_rdata[1], s0_imm, s0_alu_op, s0_use_imm, s0_rd, s0_we}),
        .q(idex_s0_q));
    assign {idex_s0_a, idex_s0_b, idex_s0_imm, idex_s0_alu_op,
            idex_s0_use_imm, idex_s0_rd, idex_s0_we} = idex_s0_q;

    pipe_reg #(.W(114)) u_idex_s1 (.clk(clk), .rst(rst), .flush(1'b0), .en(~crypto_stall),
        .d({rf_rdata[2], rf_rdata[3], s1_imm, s1_alu_op, s1_use_imm, s1_sel,
            s1_crypto_op, s1_k, s1_i, s1_rd, s1_we}),
        .q(idex_s1_q));
    assign {idex_s1_a, idex_s1_b, idex_s1_imm, idex_s1_alu_op, idex_s1_use_imm,
            idex_s1_sel, idex_s1_crypto_op, idex_s1_k, idex_s1_i,
            idex_s1_rd, idex_s1_we} = idex_s1_q;

    pipe_reg #(.W(37)) u_idex_s2 (.clk(clk), .rst(rst), .flush(1'b0), .en(~crypto_stall),
        .d({id_link, s2_rd, s2_we}), .q(idex_s2_q));
    assign {idex_s2_link, idex_s2_rd, idex_s2_we} = idex_s2_q;

    pipe_reg #(.W(103)) u_idex_s3 (.clk(clk), .rst(rst), .flush(1'b0), .en(~crypto_stall),
        .d({rf_rdata[6], rf_rdata[7], s3_imm, s3_is_load, s3_is_store, s3_is_byte, s3_rd}),
        .q(idex_s3_q));
    assign {idex_s3_base, idex_s3_sdata, idex_s3_imm, idex_s3_is_load,
            idex_s3_is_store, idex_s3_is_byte, idex_s3_rd} = idex_s3_q;

    pipe_reg #(.W(PC_W)) u_idex_pc (.clk(clk), .rst(rst), .flush(1'b0), .en(~crypto_stall),
        .d(ifid_pc), .q(idex_pc));
    pipe_reg #(.W(1)) u_idex_valid (.clk(clk), .rst(rst), .flush(1'b0), .en(~crypto_stall),
        .d(ifid_valid), .q(idex_valid));
    assign ex_valid = idex_valid;

    // ------------------------------------------------------------- etapa EX
    // §§3.3, 3.5 y 3.14: ALU0, ALU1 y LSU; la lógica propia de la etapa va aquí.
    alu u_alu0 (.a(idex_s0_a), .b(idex_s0_b), .imm(idex_s0_imm), .alu_op(idex_s0_alu_op),
        .use_imm(idex_s0_use_imm), .y(alu0_y), .cond_ok(alu0_cond_ok));
    alu u_alu1 (.a(idex_s1_a), .b(idex_s1_b), .imm(idex_s1_imm), .alu_op(idex_s1_alu_op),
        .use_imm(idex_s1_use_imm), .y(alu1_y), .cond_ok(alu1_cond_ok));

    // CRYPTO comparte los operandos de ALU1; su pausa sale de crypto_stall (§2.11, §3.10)
    crypto_unit u_crypto (
        .clk(clk), .rst(rst), .init_anchor(init_anchor),
        .en(idex_s1_sel), .ex_valid(ex_valid), .ex_commit(ex_commit),
        .crypto_op(idex_s1_crypto_op), .k(idex_s1_k), .i(idex_s1_i),
        .a(idex_s1_a), .b(idex_s1_b),
        .result(crypto_result), .allowed(crypto_allowed), .crypto_stall(crypto_stall)
    );

    lsu u_lsu (
        .base(idex_s3_base), .sdata(idex_s3_sdata), .imm(idex_s3_imm),
        .is_load(idex_s3_is_load), .is_store(idex_s3_is_store), .is_byte(idex_s3_is_byte),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_we(lsu_dmem_we),
        .dmem_be(dmem_be), .dmem_rdata(dmem_rdata), .load_data(lsu_load_data)
    );

    // Resultados hacia EX/WB (§4.4)
    assign ex_s0_result = alu0_y;
    // Slot 1 (isa.md §3.1): ALU1 o CRYPTO según sel.
    assign ex_s1_result = idex_s1_sel ? crypto_result : alu1_y;
    assign ex_s2_result = idex_s2_link;
    assign ex_s3_result = lsu_load_data;

    // we final de cada slot (§4.5)
    assign ex_s0_we = idex_s0_we & alu0_cond_ok;                       // ifmov
    assign ex_s1_we = idex_s1_sel ? (idex_s1_we & crypto_allowed)      // feis
                                  : (idex_s1_we & alu1_cond_ok);       // ifmov
    assign ex_s2_we = idex_s2_we;                                      // jas, jefR
    assign ex_s3_we = idex_s3_is_load;                                 // lw, lb

    // Pausa de auth (§2.11): se deja completa, para no tocarla al integrar CRYPTO
    assign ex_commit   = ex_valid & ~crypto_stall & ~rst;
    assign dmem_we     = lsu_dmem_we & ex_commit;                      // store una sola vez

    // ------------------------------------------------------- registro EX/WB
    // §4.4: flush = crypto_stall, en = 1.
    pipe_reg #(.W(37)) u_exwb_s0 (.clk(clk), .rst(rst), .flush(crypto_stall), .en(1'b1),
        .d({ex_s0_result, idex_s0_rd, ex_s0_we}), .q(exwb_s0_q));
    assign {exwb_s0_result, exwb_s0_rd, exwb_s0_we} = exwb_s0_q;

    pipe_reg #(.W(37)) u_exwb_s1 (.clk(clk), .rst(rst), .flush(crypto_stall), .en(1'b1),
        .d({ex_s1_result, idex_s1_rd, ex_s1_we}), .q(exwb_s1_q));
    assign {exwb_s1_result, exwb_s1_rd, exwb_s1_we} = exwb_s1_q;

    pipe_reg #(.W(37)) u_exwb_s2 (.clk(clk), .rst(rst), .flush(crypto_stall), .en(1'b1),
        .d({ex_s2_result, idex_s2_rd, ex_s2_we}), .q(exwb_s2_q));
    assign {exwb_s2_result, exwb_s2_rd, exwb_s2_we} = exwb_s2_q;

    pipe_reg #(.W(37)) u_exwb_s3 (.clk(clk), .rst(rst), .flush(crypto_stall), .en(1'b1),
        .d({ex_s3_result, idex_s3_rd, ex_s3_we}), .q(exwb_s3_q));
    assign {exwb_s3_result, exwb_s3_rd, exwb_s3_we} = exwb_s3_q;

    pipe_reg #(.W(PC_W)) u_exwb_pc (.clk(clk), .rst(rst), .flush(crypto_stall), .en(1'b1),
        .d(idex_pc), .q(exwb_pc));
    pipe_reg #(.W(1)) u_exwb_valid (.clk(clk), .rst(rst), .flush(1'b0), .en(1'b1),
        .d(ex_commit), .q(exwb_valid));

    // ------------------------------------------------------------- etapa WB
    // §§3.1 y 3.14: el regfile escribe en el flanco de bajada; solo bundles válidos.
    assign wb_waddr = {exwb_s3_rd, exwb_s2_rd, exwb_s1_rd, exwb_s0_rd};
    assign wb_wdata = {exwb_s3_result, exwb_s2_result, exwb_s1_result, exwb_s0_result};
    assign wb_we    = {exwb_s3_we & exwb_valid, exwb_s2_we & exwb_valid,
                       exwb_s1_we & exwb_valid, exwb_s0_we & exwb_valid};
endmodule
