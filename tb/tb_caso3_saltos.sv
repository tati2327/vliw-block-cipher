`timescale 1ns/1ps

// Tarea 27. Requiere top/core de la tarea 24 y sus nombres oficiales de §3.14.
module tb_caso3_saltos;
    logic clk = 0, rst = 1;
    int casos = 0, fallos = 0, visitas = 0;
    function automatic int esperado_pc(input int visita);
        case (visita)
            0: esperado_pc = 0;
            1: esperado_pc = 1;
            2: esperado_pc = 2;
            3: esperado_pc = 4;
            4: esperado_pc = 5;
            5: esperado_pc = 6;
            6: esperado_pc = 8;
            7: esperado_pc = 9;
            8: esperado_pc = 10;
            9: esperado_pc = 14;
            10: esperado_pc = 15;
            11: esperado_pc = 11;
            12: esperado_pc = 16;
            default: esperado_pc = 17;
        endcase
    endfunction
    top #(.IMEM_INIT("programs/caso3_saltos.hex")) dut (.clk, .rst);
    always #5 clk = ~clk;

    task automatic check(input string nombre, input logic [31:0] obtenido, esperado);
        casos++;
        if (obtenido === esperado) $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: obtenido=%h esperado=%h", nombre, obtenido, esperado);
        end
    endtask

    // Después de subida: IF/ID ya se actualizó, antes de terminar ese ID.
    // Se excluyen burbujas por validez; un nopi real (bundle 1) sí se cuenta.
    always @(posedge clk) begin
        #1;
        if (!rst && dut.u_core.ifid_valid === 1'b1) begin
            if (visitas < 14)
                check($sformatf("PC en ID, visita %0d", visitas),
                    {10'b0, dut.u_core.ifid_pc}, esperado_pc(visitas));
            else
                check("lazo final permanece en bundle 17", {10'b0, dut.u_core.ifid_pc}, 17);
            visitas++;
        end
    end

    initial begin
        $dumpfile("build/tb_caso3_saltos.vcd");
        $dumpvars(0, tb_caso3_saltos);
        repeat (2) @(negedge clk); rst = 0;
        repeat (60) @(posedge clk);
        @(negedge clk); #1;
        check("t2 saltado", dut.u_core.u_regfile.regs[6], 0);
        check("t4 saltado", dut.u_core.u_regfile.regs[8], 0);
        check("t6 saltado", dut.u_core.u_regfile.regs[10], 0);
        check("t3 ejecutado", dut.u_core.u_regfile.regs[7], 1);
        check("t5 ejecutado", dut.u_core.u_regfile.regs[9], 1);
        check("t7 subrutina", dut.u_core.u_regfile.regs[11], 1);
        check("t8 despues de retorno", dut.u_core.u_regfile.regs[12], 1);
        check("rl enlace de jas", dut.u_core.u_regfile.regs[1], 11);
        check("r0 descarta enlace de jefR", dut.u_core.u_regfile.regs[0], 0);
        check("se completo la secuencia minima de ID", (visitas >= 14), 1);
        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_caso3_saltos");
        $display("PASS tb_caso3_saltos");
        $finish;
    end
    initial begin
        #2000; $fatal(1, "FAIL tb_caso3_saltos: tiempo limite excedido");
    end
endmodule
