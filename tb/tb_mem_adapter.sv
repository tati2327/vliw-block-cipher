`timescale 1ns/1ps

module adapter_checker #(parameter int DIV=4)
    (output logic finished=0, output integer casos=0, fallos=0);
    logic clk=0, rst=0;
    always #5 clk=~clk;
    logic req=0, we=0, listo;
    logic [31:0] addr=0, wdata=0, rdata;
    logic [3:0] be=0;
    logic line_req, line_we, line_accepted, line_ready;
    logic [10:0] line_addr;
    logic [255:0] line_wdata, line_rdata;
    logic [31:0] line_mask;
    logic [63:0] reads, writes;
    integer accepted_count=0, accesses=0;
    logic [31:0] expected_word;
    mem_adapter dut(.*);
    main_memory #(.MEM_DIV(DIV)) memory_model(
        .clk, .rst, .req(line_req), .we(line_we), .line_addr,
        .wdata(line_wdata), .wmask(line_mask), .rdata(),
        .accepted(line_accepted), .done(), .busy(),
        .ready(line_ready), .ready_rdata(line_rdata),
        .read_count(reads), .write_count(writes), .transfer_cycles(), .total_cycles(), .timeout_count());
    task automatic check(input string name, input logic ok);
        casos++;
        if (ok !== 1'b1) begin fallos++; $display("FAIL adapter DIV=%0d %s", DIV, name); end
    endtask
    always @(negedge clk) if (!rst && line_accepted) begin
        accepted_count++;
        check("req baja al observar accepted", !line_req);
    end
    task automatic access(input logic wr, input logic [31:0] a,d, input logic [3:0] mask);
        @(negedge clk); req=1; we=wr; addr=a; wdata=d; be=mask;
        // Espera una respuesta válida antes del flanco que la consume.
        do begin @(negedge clk); end while (!listo);
        if (!wr) check("palabra leida", rdata === expected_word);
        @(posedge clk); #1;
        accesses++;
        check("un acceso de linea por pedido", reads+writes == accesses && accepted_count == accesses);
        @(negedge clk); req=0;
    endtask
    initial begin
        #1 rst=1; repeat(3) @(negedge clk); rst=0;
        // Ocho palabras de una línea; cada carril de byte conserva los demás.
        for (int w=0; w<8; w++) begin
            expected_word=32'h12345600+w;
            access(1, 32'h100+4*w, expected_word, 4'hf);
            access(0, 32'h100+4*w, 0, 0);
            for (int b=0; b<4; b++) begin
                access(1, 32'h100+4*w+b, 32'('ha0+b) << (8*b), 4'(1<<b));
                expected_word[8*b +: 8]=8'('ha0+b);
                access(0, 32'h100+4*w+b, 0, 0);
            end
        end
        check("contadores finales", reads == 40 && writes == 40);
        // El receptor puede estar ocupado al presentar el pedido: req debe persistir.
        force memory_model.busy=1;
        @(negedge clk); req=1; we=0; addr=32'h100;
        repeat(3) begin @(negedge clk); check("pedido espera aceptacion", line_req && !listo); end
        release memory_model.busy;
        // Libera también el estado forzado hasta que llegue la primera aceptación.
        memory_model.busy=0;
        do begin @(negedge clk); end while (!listo);
        check("datos tras espera", rdata === 32'ha3a2a1a0);
        @(posedge clk); #1; @(negedge clk); req=0;
        check("espera sin duplicados", reads == 41 && writes == 40 && accepted_count == 81);
        $display("adapter MEM_DIV=%0d; Casos: %0d; Fallos: %0d",DIV,casos,fallos);
        finished=1;
    end
endmodule
module tb_mem_adapter;
    wire [2:0] finished;
    wire [31:0] c2,c4,c5,f2,f4,f5;
    adapter_checker #(.DIV(2)) a2(finished[0],c2,f2);
    adapter_checker #(.DIV(4)) a4(finished[1],c4,f4);
    adapter_checker #(.DIV(5)) a5(finished[2],c5,f5);
    initial begin
        wait(&finished);
        $display("Casos: %0d; Fallos: %0d",c2+c4+c5,f2+f4+f5);
        if(f2+f4+f5) $fatal(1,"FAIL tb_mem_adapter");
        $display("PASS tb_mem_adapter"); $finish;
    end
    initial begin #200000; $fatal(1,"FAIL adapter limite global"); end
endmodule
