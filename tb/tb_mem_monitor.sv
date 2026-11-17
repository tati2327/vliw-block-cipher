`timescale 1ns/1ps

// Ejercita confirmaciones consecutivas, espera y máscaras sin depender del procesador.
module tb_mem_monitor;
    logic clk = 0, rst = 1, req = 0, we = 0, listo = 0;
    logic [31:0] addr = 0, wdata = 0, rdata = 0;
    logic [3:0] be = 0;
    logic [63:0] loads_checked, stores_applied, discrepancies;
    int casos = 0, fallos = 0;
    always #5 clk = ~clk;
    mem_monitor #(.INIT_FILE("data/main_memory/lines.mem")) dut(.*);
    task automatic check(input string name, input logic ok);
        casos++;
        if (ok !== 1'b1) begin fallos++; $display("FAIL monitor %s", name); end
    endtask
    initial begin
        @(negedge clk); rst = 0;
        check("inicializacion", dut.mem[8] === 32'h03020100 && dut.mem[0] === 0);
        req = 1; we = 1; addr = 'h21; be = 2; wdata = 'h0000aa00;
        repeat (3) @(negedge clk);
        check("espera no modifica copia", stores_applied == 0 && dut.mem[8] === 32'h03020100);
        listo = 1;
        @(negedge clk);
        check("store por byte", stores_applied == 1 && dut.mem[8] === 32'h0302aa00);
        we = 0; rdata = 'h0302aa00;
        @(negedge clk);
        check("load consecutivo", loads_checked == 1 && discrepancies == 0);
        we = 1; be = 5; wdata = 'h44332211;
        @(negedge clk);
        check("mascara multiple", stores_applied == 2 && dut.mem[8] === 32'h0333aa11);
        be = 0; wdata = 'hffffffff;
        @(negedge clk);
        check("mascara vacia", stores_applied == 3 && dut.mem[8] === 32'h0333aa11);
        req = 0;
        repeat (2) @(negedge clk);
        check("sin duplicados", stores_applied == 3 && loads_checked == 1);
        rst = 1;
        @(negedge clk);
        check("reset conserva memoria", dut.mem[8] === 32'h0333aa11 && loads_checked == 0 && stores_applied == 0);
        rst = 0; req = 1; we = 0; rdata = 'h0333aa11;
        @(negedge clk); req = 0;
        check("lectura tras reset", loads_checked == 1 && discrepancies == 0);
        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos) $fatal(1, "tb_mem_monitor fallo");
        $display("PASS tb_mem_monitor");
        $finish;
    end
endmodule
