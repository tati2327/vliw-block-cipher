`timescale 1ns/1ps

// plan_implementacion_modulos.md, tarea 5; esperados del contrato oficial.
module tb_regfile;
    logic clk = 0;
    logic rst = 0;
    logic [7:0][3:0] raddr = '0;
    logic [7:0][31:0] rdata;
    logic [3:0][3:0] waddr = '0;
    logic [3:0][31:0] wdata = '0;
    logic [3:0] we = '0;
    int casos = 0;
    int fallos = 0;

    regfile u_regfile (.clk, .rst, .raddr, .rdata, .waddr, .wdata, .we);
    always #5 clk = ~clk;

    task automatic check(input string nombre,
        input logic [31:0] obtenido, esperado);
        casos++;
        if (obtenido === esperado) $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: obtenido=%h esperado=%h", nombre, obtenido, esperado);
        end
    endtask

    // Cambiar estímulos después de subida, comprobar después de bajada.
    task automatic preparar;
        @(posedge clk); #1;
        we = '0; waddr = '0; wdata = '0;
    endtask
    task automatic escribir;
        @(negedge clk); #1;
    endtask

    initial begin
        $dumpfile("build/tb_regfile.vcd");
        $dumpvars(0, tb_regfile);
        #2; rst = 1; #1;
        // Se examina el estado por jerarquía; no hay puertos de depuración.
        for (int j = 0; j < 16; j++)
            check($sformatf("reset inicial r%0d", j), u_regfile.regs[j], 0);
        rst = 0;

        preparar(); we[0] = 1; waddr[0] = 5; wdata[0] = 'hCAFE;
        raddr[0] = 5;
        #1; check("r5 antes de bajada", rdata[0], 0);
        escribir(); check("escritura simple r5", rdata[0], 'hCAFE);

        preparar(); we[0] = 1; waddr[0] = 0; wdata[0] = 'h1234;
        raddr[0] = 0;
        escribir(); check("r0 ignora escritura", rdata[0], 0);

        preparar(); we = 4'b1111;
        for (int s = 0; s < 4; s++) begin
            waddr[s] = s + 1;
            wdata[s] = s + 1;
            raddr[s] = s + 1;
        end
        escribir();
        for (int p = 0; p < 4; p++)
            check($sformatf("cuatro escrituras r%0d", p+1), rdata[p], p+1);

        preparar(); we = 4'b1010; waddr[1] = 6; waddr[3] = 6;
        wdata[1] = 'hAAAA; wdata[3] = 'hBBBB; raddr[0] = 6;
        escribir(); check("prioridad slot3 sobre slot1", rdata[0], 'hBBBB);

        preparar(); waddr[0] = 7; wdata[0] = 'h99; raddr[0] = 7;
        escribir(); check("we cero conserva r7", rdata[0], 0);

        // Carga ocho registros con valores distintos para probar los ocho MUX.
        for (int grupo = 0; grupo < 2; grupo++) begin
            preparar(); we = 4'b1111;
            for (int s = 0; s < 4; s++) begin
                waddr[s] = 4*grupo+s+1;
                wdata[s] = 'h1000 + 4*grupo+s+1;
            end
            escribir();
        end
        we = '0;
        for (int p = 0; p < 8; p++) raddr[p] = p+1;
        #1;
        for (int p = 0; p < 8; p++)
            check($sformatf("lectura simultanea puerto %0d", p), rdata[p], 'h1000+p+1);

        for (int p = 0; p < 8; p++) raddr[p] = 7;
        #1;
        for (int p = 0; p < 8; p++)
            check($sformatf("r7 compartido puerto %0d", p), rdata[p], 'h1007);

        // Habilitar antes de subida; no debe escribir hasta la bajada siguiente.
        @(negedge clk); #1;
        we = 4'b0001; waddr[0] = 9; wdata[0] = 'h1111; raddr[0] = 9;
        #1; check("r9 valor viejo antes de subida", rdata[0], 0);
        @(posedge clk); #1;
        check("subida no escribe r9", rdata[0], 0);
        escribir(); check("bajada actualiza r9 en mismo ciclo", rdata[0], 'h1111);

        preparar(); we = 4'b1111;
        for (int s = 0; s < 4; s++) begin
            waddr[s] = 10; wdata[s] = 'hA0+s;
        end
        raddr[0] = 10;
        escribir(); check("cuatro slots mismo destino gana slot3", rdata[0], 'hA3);

        preparar(); we = 4'b0101;
        waddr[0] = 10; wdata[0] = 'hB0;
        waddr[2] = 10; wdata[2] = 'hB2;
        waddr[3] = 10; wdata[3] = 'hB3;
        escribir(); check("slot3 deshabilitado gana slot2", rdata[0], 'hB2);

        preparar(); we = 4'b1111;
        for (int s = 0; s < 4; s++) begin
            waddr[s] = 0; wdata[s] = 'hF0+s;
        end
        raddr[0] = 0;
        escribir(); check("cuatro escrituras a r0 bloqueadas", rdata[0], 0);

        // Después de cargar el banco, el reset debe limpiar sin esperar bajada.
        #1; rst = 1; #1;
        for (int j = 0; j < 16; j++)
            check($sformatf("reset entre flancos r%0d", j), u_regfile.regs[j], 0);
        escribir(); check("reset domina escritura habilitada", rdata[0], 0);
        we = 0; rst = 0;

        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_regfile");
        $display("PASS tb_regfile");
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "FAIL tb_regfile: tiempo limite excedido");
    end
endmodule
