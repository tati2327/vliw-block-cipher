`timescale 1ns/1ps

// microarchitecture.md §§2.5, 3.11, 4.3 y 4.8; tarea 15, con crypto_dec (plan §9.1).
// Combinacional: separa el bundle, decodifica y extiende inmediatos. No lee el regfile.
module dispatch (
  input  logic [127:0]     bundle,
  output logic [7:0][3:0]  rf_raddr,
  // slot 0 — ALU0
  output logic [31:0] s0_imm,  output logic [3:0] s0_alu_op, output logic s0_use_imm,
  output logic [3:0]  s0_rd,   output logic       s0_we,
  // slot 1 — ALU1 o CRYPTO
  output logic [31:0] s1_imm,  output logic [3:0] s1_alu_op, output logic s1_use_imm,
  output logic        s1_sel,  output logic [2:0] s1_crypto_op,
  output logic [1:0]  s1_k,    output logic [1:0] s1_i,
  output logic [3:0]  s1_rd,   output logic       s1_we,
  // slot 2 — BRU
  output logic [21:0] s2_instr_low, output logic [2:0] s2_br_op,
  output logic [3:0]  s2_rd,        output logic       s2_we,
  // slot 3 — LSU
  output logic [31:0] s3_imm,
  output logic        s3_is_load, s3_is_store, s3_is_byte,
  output logic [3:0]  s3_rd
);
    // microarchitecture.md §3.11 — separación de slots: bundle[32s+31 : 32s]
    logic [31:0] instr0, instr1, instr2, instr3;
    assign instr0 = bundle[31:0];
    assign instr1 = bundle[63:32];
    assign instr2 = bundle[95:64];
    assign instr3 = bundle[127:96];

    // microarchitecture.md §§2.5 y 3.11 — direcciones de lectura: puerto A = rs1 en
    // los 4 slots; puerto B = rs2 (17..14) en slots 0 y 1, bits 25..22 en slots 2 y 3
    assign rf_raddr[0] = instr0[21:18];
    assign rf_raddr[1] = instr0[17:14];
    assign rf_raddr[2] = instr1[21:18];
    assign rf_raddr[3] = instr1[17:14];
    assign rf_raddr[4] = instr2[21:18];
    assign rf_raddr[5] = instr2[25:22];
    assign rf_raddr[6] = instr3[21:18];
    assign rf_raddr[7] = instr3[25:22];

    // microarchitecture.md §3.11 — extensión de signo de imm[17:0] (slots 0, 1 y 3)
    assign s0_imm = {{14{instr0[17]}}, instr0[17:0]};
    assign s1_imm = {{14{instr1[17]}}, instr1[17:0]};
    assign s3_imm = {{14{instr3[17]}}, instr3[17:0]};

    // microarchitecture.md §3.11 — slot 0: alu_dec; el bit 31 (sel) no se conecta
    alu_dec u_alu_dec0 (.funct(instr0[30:26]), .alu_op(s0_alu_op),
                        .use_imm(s0_use_imm), .we(s0_we));
    assign s0_rd = instr0[25:22];

    // microarchitecture.md §3.11 — slot 1: alu_dec y campos de CRYPTO
    logic we_alu1;
    alu_dec u_alu_dec1 (.funct(instr1[30:26]), .alu_op(s1_alu_op),
                        .use_imm(s1_use_imm), .we(we_alu1));
    assign s1_sel = instr1[31];
    assign s1_rd  = instr1[25:22];
    assign s1_k   = instr1[13:12];
    assign s1_i   = instr1[11:10];

    // microarchitecture.md §3.11 — slot 1: crypto_dec; con sel = 0 se bloquea CRYPTO
    logic [2:0] crypto_op1;
    logic       we_crypto1;
    crypto_dec u_crypto_dec (.funct(instr1[30:26]), .crypto_op(crypto_op1), .we(we_crypto1));
    assign s1_crypto_op = s1_sel ? crypto_op1 : 3'b000;
    assign s1_we        = s1_sel ? we_crypto1 : we_alu1;

    // microarchitecture.md §3.11 — slot 2: bru_dec; el bit 31 no se conecta
    bru_dec u_bru_dec (.funct(instr2[30:26]), .br_op(s2_br_op), .we(s2_we));
    assign s2_instr_low = instr2[21:0];
    assign s2_rd        = instr2[25:22];

    // microarchitecture.md §3.11 — slot 3: lsu_dec; el bit 31 no se conecta
    lsu_dec u_lsu_dec (.funct(instr3[30:26]), .is_load(s3_is_load),
                       .is_store(s3_is_store), .is_byte(s3_is_byte));
    assign s3_rd = instr3[25:22];
endmodule
