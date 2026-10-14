`timescale 1ns/1ps

`ifndef PROG_HEX
  `define PROG_HEX "programs/ej1.hex"
`endif
`ifndef PROG_MEM
  `define PROG_MEM ""
`endif
`ifndef EXP_MEM
  `define EXP_MEM "programs/ej1.exp.mem"
`endif

// Programa, datos y resultados se seleccionan al compilar, sin valores del programa.
module tb_programa;
    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    top #(.IMEM_INIT(`PROG_HEX), .DMEM_INIT(`PROG_MEM)) dut (.clk, .rst);

    int casos = 0, fallos = 0;
    int ciclo = 0, llegada = -1, ciclos_con_problema = 0;
    int archivo;
    logic [31:0] esperado [0:16383];

    task automatic check(input string nombre, input logic [31:0] obtenido, esperado);
        casos++;
        if (obtenido === esperado) $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: obtenido=%h esperado=%h", nombre, obtenido, esperado);
        end
    endtask

    // Muestreo tras la bajada, como los otros TB de integración. También durante
    // los cinco ciclos finales: un ciclo cuenta una sola vez aunque falle más de un slot.
    task automatic muestrear;
        bit problema;
        @(negedge clk); #2;
        ciclo++;
        problema = $isunknown(dut.u_core.u_fetch.pc) ||
                   $isunknown(dut.u_core.ifid_bundle);
        for (int s = 0; s < 4; s++) begin
            if (dut.u_core.exwb_valid === 1'b1 && dut.u_core.wb_we[s] === 1'b1 &&
                $isunknown(dut.u_core.wb_wdata[s])) begin
                problema = 1;
                if (ciclos_con_problema < 3)
                    $display("  ciclo=%0d WB slot=%0d dato=%h", ciclo, s, dut.u_core.wb_wdata[s]);
            end
        end
        if (problema) begin
            if (ciclos_con_problema < 3)
                $display("  ciclo=%0d pc=%h bundle=%h", ciclo,
                         dut.u_core.u_fetch.pc, dut.u_core.ifid_bundle);
            ciclos_con_problema++;
        end
    endtask

    initial begin
        $dumpfile("build/tb_programa.vcd");
        $dumpvars(0, tb_programa);
        for (int i = 0; i < 16384; i++) esperado[i] = 32'bx;
        if (`EXP_MEM != "") begin
            archivo = $fopen(`EXP_MEM, "r");
            if (archivo == 0) $fatal(1, "No se pudo abrir EXP_MEM: %s", `EXP_MEM);
            $fclose(archivo);
            $readmemh(`EXP_MEM, esperado);
        end

        @(posedge clk);
        @(negedge clk); #1; rst = 0;
        while (llegada < 0 && ciclo < 50000) begin
            muestrear();
            if (dut.u_core.ifid_valid === 1'b1 &&
                dut.u_core.s2_br_op === 3'b101 && dut.u_core.s2_instr_low === 22'b0)
                llegada = ciclo;
        end
        check("fin del programa antes del limite", {31'b0, (llegada >= 0)}, 32'd1);
        if (llegada >= 0) $display("Llegada al fin en el ciclo %0d", llegada);
        else $display("No llego al fin en 50000 ciclos");

        repeat (5) muestrear();
        check("ciclos con X/Z en PC, bundle o escritura WB", ciclos_con_problema, 32'd0);
        // M-07: volcado completo, sin rango.
        $writememh("build/tb_programa_dump.mem", dut.u_memory.mem);

        if (`EXP_MEM != "") begin
            for (int i = 0; i < 16384; i++) begin
                if (esperado[i] !== 32'bx)
                    check($sformatf("mem palabra=0x%0h direccion=0x%0h", i, 4*i),
                          dut.u_memory.mem[i], esperado[i]);
            end
        end
        for (int r = 0; r < 16; r++)
            $display("r%0d = %h", r, dut.u_core.u_regfile.regs[r]);

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "tb_programa fallo");
        $display("PASS tb_programa");
        $finish;
    end
endmodule
