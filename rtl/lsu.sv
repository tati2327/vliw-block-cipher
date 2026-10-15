`timescale 1ns/1ps

// ISA §§5.4, 6.3; microarchitecture.md §§3.5, 4.3.
// Sin estado: la memoria y los registros de segmentación están fuera de LSU.
module lsu (
    input  logic [31:0] base, sdata, imm,
    input  logic is_load, is_store, is_byte,
    output logic [31:0] dmem_addr, dmem_wdata,
    output logic dmem_we,
    output logic [3:0] dmem_be,
    input  logic [31:0] dmem_rdata,
    output logic [31:0] load_data
);
    logic [1:0] lane;
    logic [31:0] placed;
    logic [7:0] byte_value;
    logic [3:0] onehot;
    // Bytes seleccionados fuera de los always_comb: Icarus no admite selecciones
    // constantes dentro de always_* (incluiría todo el vector en la sensibilidad).
    logic [7:0] sbyte, rbyte0, rbyte1, rbyte2, rbyte3;
    logic [31:0] byte_ext;

    // Sumador independiente. imm ya llega extendido con signo desde ID.
    assign dmem_addr = base + imm;
    assign lane = dmem_addr[1:0];
    assign sbyte  = sdata[7:0];
    assign rbyte0 = dmem_rdata[7:0];
    assign rbyte1 = dmem_rdata[15:8];
    assign rbyte2 = dmem_rdata[23:16];
    assign rbyte3 = dmem_rdata[31:24];

    // MUX 4:1 para colocación, MUX 4:1 para lectura y decodificador 2 a 4.
    // Carril 0 = byte menos significativo (little endian).
    always_comb begin
        placed = 32'b0;
        byte_value = 8'b0;
        onehot = 4'b0;
        case (lane)
            2'b00: begin
                placed = {24'b0, sbyte};
                byte_value = rbyte0;
                onehot = 4'b0001;
            end
            2'b01: begin
                placed = {16'b0, sbyte, 8'b0};
                byte_value = rbyte1;
                onehot = 4'b0010;
            end
            2'b10: begin
                placed = {8'b0, sbyte, 16'b0};
                byte_value = rbyte2;
                onehot = 4'b0100;
            end
            2'b11: begin
                placed = {sbyte, 24'b0};
                byte_value = rbyte3;
                onehot = 4'b1000;
            end
            default: ;
        endcase
    end

    // Extensor de signo 8 a 32 bits. No equivale a extensión con ceros.
    assign byte_ext = {{24{byte_value[7]}}, byte_value};

    // MUX de tamaño y habilitaciones. No se escribe memoria en una carga.
    always_comb begin
        dmem_we = is_store;
        dmem_wdata = 32'b0;
        dmem_be = 4'b0;
        load_data = 32'b0;
        if (is_store) begin
            dmem_wdata = is_byte ? placed : sdata;
            dmem_be = is_byte ? onehot : 4'b1111;
        end
        if (is_load) begin
            load_data = is_byte ? byte_ext : dmem_rdata;
        end
    end
endmodule
