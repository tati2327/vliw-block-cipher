`timescale 1ns/1ps

// ISA §6.3; microarchitecture.md §§3.4, 4.3, 4.8.
// Decodificador combinacional del slot 3. Códigos libres = nopi.
module lsu_dec (
    input  logic [4:0] funct,
    output logic is_load, is_store, is_byte
);
    always_comb begin
        is_load  = 1'b0;
        is_store = 1'b0;
        is_byte  = 1'b0;
        case (funct)
            5'b00001: is_load = 1'b1;                 // lw
            5'b00010: is_store = 1'b1;                // sw
            5'b00011: begin                          // lb
                is_load = 1'b1;
                is_byte = 1'b1;
            end
            5'b00100: begin                          // sb
                is_store = 1'b1;
                is_byte = 1'b1;
            end
            default: ;
        endcase
    end
endmodule
