`timescale 1ns/1ps

// ISA §§5.3, 6.2, 10; microarchitecture.md §§3.9, 4.3.
// Combinacional en ID: el PC y su actualización están fuera de este módulo.
module bru #(parameter int PC_W = 22) (
    input  logic [PC_W-1:0] pc,
    input  logic [31:0] a, b,
    input  logic [21:0] instr_low,
    input  logic [2:0] br_op,
    output logic taken,
    output logic [PC_W-1:0] target,
    output logic [31:0] link
);
    localparam logic [2:0] BR_NONE = 3'b000, BR_BEQ = 3'b001,
        BR_BNE = 3'b010, BR_BLT = 3'b011, BR_BGE = 3'b100,
        BR_JEF = 3'b101, BR_JAS = 3'b110, BR_JEFR = 3'b111;
    logic [PC_W-1:0] off_ext, j_delta, delta, relative, pc_next;
    logic eq, lt, is_j, is_jefr;

    // Extensión con signo. El ancho arquitectónico predeterminado es 22.
    assign off_ext = $signed(instr_low[17:0]);
    assign j_delta = $signed(instr_low[21:0]);
    assign is_j = (br_op == BR_JEF) || (br_op == BR_JAS);
    assign is_jefr = (br_op == BR_JEFR);

    // Un sumador relativo y un incrementador separado para el enlace.
    assign delta = is_j ? j_delta : off_ext;
    assign relative = pc + delta;
    assign target = is_jefr ? a[21:0] : relative;
    assign pc_next = pc + 1'b1;
    // pc_next ya está recortado a PC_W: primero se descarta el acarreo.
    assign link = pc_next;

    // Comparadores dedicados a BRU; no usa la ALU ni un registro de banderas.
    assign eq = (a == b);
    assign lt = ($signed(a) < $signed(b));
    always_comb begin
        taken = 1'b0;
        case (br_op)
            BR_BEQ: taken = eq;
            BR_BNE: taken = !eq;
            BR_BLT: taken = lt;
            BR_BGE: taken = !lt;
            BR_JEF, BR_JAS, BR_JEFR: taken = 1'b1;
            default: ;
        endcase
    end
endmodule
