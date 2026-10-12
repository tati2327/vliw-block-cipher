`timescale 1ns/1ps

// Prueba conjunta lsu_dec + lsu. No instancia memoria ni procesador.
// Esperados de plan_implementacion_modulos.md, tarea 10.
module tb_lsu;
    logic [4:0] funct;
    logic is_load, is_store, is_byte;
    logic [31:0] base, sdata, imm, dmem_rdata;
    logic [31:0] dmem_addr, dmem_wdata, load_data;
    logic dmem_we;
    logic [3:0] dmem_be;
    int casos = 0;
    int fallos = 0;

    lsu_dec u_lsu_dec (.funct, .is_load, .is_store, .is_byte);
    lsu u_lsu (.base, .sdata, .imm, .is_load, .is_store, .is_byte,
        .dmem_addr, .dmem_wdata, .dmem_we, .dmem_be, .dmem_rdata, .load_data);

    task automatic comprobar (
        input string nombre,
        input logic [4:0] f,
        input logic [31:0] bas, dato, desplazamiento, lectura,
        input logic [31:0] direccion_esperada, escritura_esperada,
        input logic we_esperado,
        input logic [3:0] be_esperado,
        input logic [31:0] carga_esperada
    );
        funct = f;
        base = bas;
        sdata = dato;
        imm = desplazamiento;
        dmem_rdata = lectura;
        #1;
        casos++;
        if ({dmem_addr, dmem_wdata, dmem_we, dmem_be, load_data} ===
            {direccion_esperada, escritura_esperada, we_esperado, be_esperado, carga_esperada})
            $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s", nombre);
            $display("  obtenido: addr=%h wdata=%h we=%b be=%b load=%h",
                dmem_addr, dmem_wdata, dmem_we, dmem_be, load_data);
            $display("  esperado: addr=%h wdata=%h we=%b be=%b load=%h",
                direccion_esperada, escritura_esperada, we_esperado, be_esperado, carga_esperada);
        end
    endtask

    initial begin
        $dumpfile("build/tb_lsu.vcd");
        $dumpvars(0, tb_lsu);
        comprobar("lw no alineado", 1, 'h1000, 0, 2, 'h7F80FF01,
            'h1002, 0, 0, 0, 'h7F80FF01);
        comprobar("sw palabra", 2, 'h1000, 'h12345678, 0, 0,
            'h1000, 'h12345678, 1, 4'b1111, 0);
        comprobar("sb carril 0", 4, 'h1000, 'h123456AA, 0, 0,
            'h1000, 'h000000AA, 1, 4'b0001, 0);
        comprobar("sb carril 1", 4, 'h1000, 'h123456AA, 1, 0,
            'h1001, 'h0000AA00, 1, 4'b0010, 0);
        comprobar("sb carril 2", 4, 'h1000, 'h123456AA, 2, 0,
            'h1002, 'h00AA0000, 1, 4'b0100, 0);
        comprobar("sb carril 3", 4, 'h1000, 'h123456AA, 3, 0,
            'h1003, 'hAA000000, 1, 4'b1000, 0);
        comprobar("lb carril 2 negativo", 3, 'h1000, 0, 2, 'h7F80FF01,
            'h1002, 0, 0, 0, 'hFFFFFF80);
        comprobar("lb carril 3 positivo", 3, 'h1000, 0, 3, 'h7F80FF01,
            'h1003, 0, 0, 0, 'h0000007F);
        comprobar("lb carril 0", 3, 'h1000, 0, 0, 'h7F80FF01,
            'h1000, 0, 0, 0, 1);
        comprobar("lb carril 1 negativo", 3, 'h1000, 0, 1, 'h7F80FF01,
            'h1001, 0, 0, 0, 'hFFFFFFFF);
        comprobar("desplazamiento negativo", 1, 'h1004, 0, 'hFFFFFFFC, 'hCAFEBABE,
            'h1000, 0, 0, 0, 'hCAFEBABE);
        comprobar("nopi despues de carga", 0, 'h1000, 'hFFFFFFFF, 3, 'hFFFFFFFF,
            'h1003, 0, 0, 0, 0);
        comprobar("reservado 00101", 5, 'h1000, 'hFFFFFFFF, 0, 'hFFFFFFFF,
            'h1000, 0, 0, 0, 0);
        comprobar("reservado 11111", 31, 'h1000, 'hFFFFFFFF, 0, 'hFFFFFFFF,
            'h1000, 0, 0, 0, 0);
        comprobar("sw no alineado conserva direccion", 2, 'h1000, 'hDEADBEEF, 3, 0,
            'h1003, 'hDEADBEEF, 1, 4'b1111, 0);
        comprobar("suma con acarreo descartado", 1, 'hFFFFFFFF, 0, 1, 'h12345678,
            0, 0, 0, 0, 'h12345678);
        comprobar("sb descarta 24 bits altos", 4, 'h1000, 'hFFFFFF00, 2, 0,
            'h1002, 0, 1, 4'b0100, 0);
        comprobar("nopi despues de store", 0, 'h1000, 'hAA, 2, 0,
            'h1002, 0, 0, 0, 0);
        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_lsu");
        $display("PASS tb_lsu");
        $finish;
    end
endmodule
