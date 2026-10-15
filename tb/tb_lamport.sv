`timescale 1ns/1ps
`include "lamport_config.svh"

// Compara cada eslabón generado por Python con el motor SystemVerilog.
module tb_lamport;
    localparam int N = `LAMPORT_TOKEN_COUNT;
    logic clk = 1'b0, rst = 1'b0, start = 1'b0, accept = 1'b0;
    logic [31:0] token = 32'b0;
    logic [31:0] hash32;
    logic busy, done;
    logic [63:0] vectores [0:N-1];
    logic [31:0] tokens [0:N-1];
    logic [31:0] esperado;
    int fallos = 0;
    int comprobaciones = 0;
    bit ciclos_correctos;

    auth_hash32 u_auth_hash32 (
        .clk(clk), .rst(rst), .start(start), .accept(accept), .token(token),
        .hash32(hash32), .busy(busy), .done(done)
    );
    always #5 clk = ~clk;

    initial begin
        $dumpfile("build/tb_lamport.vcd");
        $dumpvars(0, tb_lamport);
        $readmemh("data/lamport_demo/hash_vectors.mem", vectores);
        $readmemh("data/lamport_demo/tokens.mem", tokens);
        #2;
        rst = 1'b1;
        @(negedge clk);
        rst = 1'b0;

        for (int index = 0; index < N; index++) begin
            @(negedge clk);
            token = tokens[index];
            esperado = (index == 0) ? `LAMPORT_RESET_ANCHOR : tokens[index - 1];
            start = 1'b1;
            @(posedge clk);
            #1;
            ciclos_correctos = ({busy, done} === 2'b10);
            @(negedge clk);
            start = 1'b0;
            repeat (11) begin
                @(posedge clk);
                #1;
                ciclos_correctos &= ({busy, done} === 2'b10);
            end
            @(posedge clk);
            #1;
            ciclos_correctos &= ({busy, done} === 2'b01);
            comprobaciones++;
            if (ciclos_correctos && hash32 === esperado &&
                vectores[N - 1 - index] === {token, esperado}) begin
                $display("PASS: x%0d=%08h H=%08h", N - 1 - index, token, hash32);
            end else begin
                fallos++;
                $display("FAIL: x%0d=%08h H=%08h esperado=%08h ciclos=%b",
                         N - 1 - index, token, hash32, esperado, ciclos_correctos);
            end
            @(negedge clk);
            accept = 1'b1;
            @(posedge clk);
            #1;
            if ({busy, done} !== 2'b00) begin
                fallos++;
                $display("FAIL: accept no libera el motor");
            end
            @(negedge clk);
            accept = 1'b0;
        end
        $display("Comprobaciones Lamport RTL: %0d | Fallos: %0d", comprobaciones, fallos);
        if (fallos != 0) $fatal(1, "La cadena Python no coincide con el hardware");
        $finish;
    end

    initial begin
        #(N * 200 + 1000);
        $fatal(1, "Tiempo máximo de simulación excedido");
    end
endmodule
