`timescale 1ns/1ps

// Nivel inferior controlable: respuesta inmediata o acceso con aceptación registrada.
module l1_line_model (
    input logic clk, rst, req,
    input logic [10:0] line_addr,
    input logic immediate,
    input integer latency, accept_wait,
    input logic [1:0] source,
    input logic push,
    input logic [10:0] push_addr,
    input logic [255:0] push_data,
    output logic accepted, ready,
    output logic [255:0] ready_rdata,
    output logic [1:0] resp_src,
    output integer transactions
);
    logic [31:0] mem [0:16383];
    logic busy = 0;
    logic [10:0] saved_addr;
    integer age = 0, waiting = 0;
    initial for (int w = 0; w < 16384; w++) mem[w] = 32'hcafe0000 ^ w;
    assign ready = !rst && ((immediate && req) || (busy && age+1 >= latency));
    assign resp_src = source;
    wire [10:0] response_addr = busy ? saved_addr : line_addr;
    for (genvar w = 0; w < 8; w++) begin : response_words
        assign ready_rdata[32*w +: 32] = mem[8*response_addr+w];
    end
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy <= 0; accepted <= 0; age <= 0; waiting <= 0; transactions <= 0;
            saved_addr <= 0;
        end else begin
            accepted <= 0;
            if (busy) begin
                age <= age + 1;
                if (ready) busy <= 0;
            end else if (req) begin
                if (immediate) begin
                    transactions <= transactions + 1;
                    waiting <= 0;
                end else if (waiting < accept_wait) waiting <= waiting + 1;
                else begin
                    busy <= 1; accepted <= 1; saved_addr <= line_addr;
                    age <= 0; waiting <= 0; transactions <= transactions + 1;
                end
            end
            // El sumidero conserva las líneas entregadas, sin añadir presión al buffer.
            if (push)
                for (int w = 0; w < 8; w++) mem[8*push_addr+w] <= push_data[32*w +: 32];
        end
    end
endmodule

module l1_cache_checker(output logic finished = 0, output integer casos = 0, fallos = 0);
    logic clk = 0, rst = 0;
    always #5 clk = ~clk;
    logic req = 0, we = 0;
    logic [31:0] addr = 0, wdata = 0, rdata;
    logic [3:0] be = 0;
    logic listo, line_req, line_we, line_accepted, line_ready;
    logic [10:0] line_addr, push_addr;
    logic [255:0] line_wdata, line_rdata, push_data;
    logic [31:0] line_mask;
    logic [1:0] resp_src;
    logic push, full = 0;
    logic [63:0] read_count, write_count, read_hits, read_misses, write_hits, write_misses;
    logic [63:0] stall_buffer_cycles, stall_l2_cycles, stall_memory_cycles, stall_full_cycles;
    logic immediate = 0;
    integer latency = 8, accept_wait = 0, transactions;
    logic [1:0] source = 1;
    integer pushes = 0;
    logic [10:0] last_push_addr;
    logic [255:0] last_push_data;
    l1_cache dut(.*);
    l1_line_model lower(.clk, .rst, .req(line_req), .line_addr, .immediate,
        .latency, .accept_wait, .source, .push, .push_addr, .push_data,
        .accepted(line_accepted), .ready(line_ready), .ready_rdata(line_rdata), .resp_src,
        .transactions);

    task automatic check(input string name, input logic ok);
        casos++;
        if (ok !== 1'b1) begin fallos++; $display("FAIL L1 %s", name); end
    endtask
    always @(posedge clk) if (!rst && push) begin
        pushes++;
        last_push_addr = push_addr; last_push_data = push_data;
        check("push solo con espacio y llenado simultaneo", !full && line_req);
    end
    always @(negedge clk) if (!rst && line_accepted)
        check("req baja al observar accepted", !line_req);

    task automatic reset_cache;
        @(negedge clk); rst = 1; req = 0; full = 0;
        repeat (2) @(negedge clk);
        rst = 0;
        pushes = 0;
    endtask

    // Se muestrea antes del flanco que consume listo, también para los aciertos inmediatos.
    task automatic access(input logic wr, input logic [31:0] a, d,
                          input logic [3:0] mask, input logic [31:0] expected,
                          input integer expected_stalls);
        integer stalls;
        @(negedge clk); req = 1; we = wr; addr = a; wdata = d; be = mask;
        #1; stalls = 0;
        while (!listo && stalls < 150) begin
            @(posedge clk); #1; stalls++;
            @(negedge clk); #1;
        end
        check("respuesta dentro del limite", listo);
        if (!wr) check($sformatf("dato en %h: recibido %h esperado %h", a, rdata, expected), rdata === expected);
        if (expected_stalls >= 0)
            check($sformatf("pausas en %h: %0d esperadas %0d", a, stalls, expected_stalls), stalls == expected_stalls);
        @(posedge clk); #1;
        @(negedge clk); req = 0;
    endtask

    logic [31:0] expected_word, reference_mem [0:16383];
    logic [63:0] before_count;
    integer before_tx, before_pushes;
    integer rng = 32'h13579bdf;
    integer random_word, random_mask;
    logic [31:0] random_data;
    initial begin
        #1 rst = 1; repeat (3) @(negedge clk); rst = 0;
        check("reset de contadores", read_count == 0 && write_count == 0 &&
            read_hits == 0 && read_misses == 0 && write_hits == 0 && write_misses == 0 &&
            stall_full_cycles == 0 && stall_memory_cycles == 0 && stall_l2_cycles == 0 && stall_buffer_cycles == 0);
        // Las ocho palabras usan carriles independientes dentro de la línea.
        for (int w = 0; w < 8; w++) begin
            expected_word = 32'hcafe0000 ^ (64+w);
            access(0, 32'h100+4*w, 0, 0, expected_word, w == 0 ? 8 : 0);
            access(1, 32'h100+4*w, 32'h12345600+w, 4'hf, 0, 0);
            expected_word = 32'h12345600+w;
            for (int b = 0; b < 4; b++) begin
                access(1, 32'h100+4*w+b, 32'('ha0+b) << (8*b), 4'(1<<b), 0, 0);
                expected_word[8*b +: 8] = 8'('ha0+b);
                access(0, 32'h100+4*w+b, 0, 0, expected_word, 0);
            end
        end
        check("cuenta cada pedido una vez", read_count == 40 && write_count == 40 &&
            read_misses == 1 && read_hits == 39 && write_hits == 40 && write_misses == 0);
        check("una sola lectura inferior, sin write-through", transactions == 1 && pushes == 0);
        check("ocho pausas atribuidas a L2", stall_l2_cycles == 8 && stall_memory_cycles == 0);
        access(1, 32'h100, 32'hffffffff, 0, 0, 0);
        access(0, 32'h100, 0, 0, 32'ha3a2a1a0, 0);

        // Fallos de escritura con máscara en los cuatro carriles, preservando el resto.
        for (int b = 0; b < 4; b++) begin
            expected_word = 32'hcafe0000 ^ (128+8*b);
            expected_word[8*b +: 8] = 8'h55;
            access(1, 32'h200+32*b+b, 32'h55 << (8*b), 4'(1<<b), 0, 8);
            access(0, 32'h200+32*b, 0, 0, expected_word, 0);
            access(0, 32'h204+32*b, 0, 0, 32'hcafe0000 ^ (129+8*b), 0);
        end
        check("write allocate", write_misses == 4);

        reset_cache();
        // Las tres líneas comparten conjunto; tocar A obliga a desalojar B.
        access(0, 'h0000, 0, 0, 32'hcafe0000, 8);
        access(1, 'h0800, 32'h11223344, 15, 0, 8);
        access(0, 'h0000, 0, 0, 32'hcafe0000, 0);
        access(0, 'h1000, 0, 0, 32'hcafe0400, 8);
        check("LRU desaloja B sucia", pushes == 1 && last_push_addr == 11'h040 &&
            last_push_data[31:0] === 32'h11223344 && last_push_data[63:32] === 32'hcafe0201);
        check("push único durante espera de ready", transactions == 3);
        access(0, 'h0800, 0, 0, 32'h11223344, 8);
        check("desalojo limpio no hace push", pushes == 1);

        reset_cache();
        access(1, 'h0000, 32'h55667788, 15, 0, 8);
        access(0, 'h0800, 0, 0, 32'h11223344, 8);
        access(0, 'h0000, 0, 0, 32'h55667788, 0);
        access(0, 'h0800, 0, 0, 32'h11223344, 0);
        access(0, 'h1000, 0, 0, 32'hcafe0400, 8);
        check("LRU inverso desaloja A", pushes == 1 && last_push_addr == 0 &&
            last_push_data[31:0] === 32'h55667788);
        check("A y B ocupan vías distintas antes del reemplazo", read_misses == 2 && read_hits == 2);

        reset_cache();
        access(1, 'h0020, 32'habcd1234, 15, 0, 8);
        access(0, 'h0820, 0, 0, 32'hcafe0208, 8);
        // A es víctima sucia. No se puede pedir el llenado hasta entregar A.
        before_tx = transactions;
        @(negedge clk); full = 1; req = 1; we = 0; addr = 'h1020;
        repeat (4) begin
            #1; check("buffer lleno bloquea push y llenado", !push && !line_req && !listo);
            @(posedge clk); #1; @(negedge clk);
        end
        check("sin pedidos mientras full", transactions == before_tx && pushes == 0 && stall_full_cycles == 4);
        full = 0; #1;
        check("push y llenado al liberar espacio", push && line_req);
        while (!listo) begin @(negedge clk); #1; end
        check("dato tras buffer lleno", rdata === 32'hcafe0408);
        @(posedge clk); #1; @(negedge clk); req = 0;
        check("pausas de lleno separadas del origen", stall_full_cycles == 4 && stall_l2_cycles == 24 && pushes == 1);

        reset_cache();
        full = 1;
        access(0, 'h0060, 0, 0, 32'hcafe0018, 8);
        check("full no frena víctima inválida", stall_full_cycles == 0);
        full = 0;
        access(0, 'h0860, 0, 0, 32'hcafe0218, 8);
        full = 1;
        access(0, 'h1060, 0, 0, 32'hcafe0418, 8);
        check("full no frena víctima limpia", stall_full_cycles == 0 && pushes == 0);
        full = 0;

        reset_cache(); immediate = 1; source = 2;
        access(0, 'h0040, 0, 0, 32'hcafe0010, 0);
        access(1, 'h0840, 32'hdeadbeef, 15, 0, 0);
        access(0, 'h0040, 0, 0, 32'hcafe0010, 0);
        access(1, 'h1040, 32'h66778899, 15, 0, 0);
        check("forwarding acepta desalojo y store en el mismo ciclo", pushes == 1 && last_push_addr == 11'h042 &&
            last_push_data[31:0] === 32'hdeadbeef && transactions == 3);
        access(0, 'h1040, 0, 0, 32'h66778899, 0);
        repeat (3) @(negedge clk);
        check("stores únicos sin pedidos residuales", write_count == 2 && write_misses == 2 && transactions == 3 && !line_req);
        check("forwarding sin pausas", stall_buffer_cycles == 0 && stall_l2_cycles == 0 && stall_memory_cycles == 0);

        reset_cache(); immediate = 0; source = 0; latency = 53; accept_wait = 3;
        access(0, 'h00a0, 0, 0, 32'hcafe0028, 56);
        check("espera aceptacion y latencia atribuidas a memoria", transactions == 1 && stall_memory_cycles == 56);
        source = 2; latency = 8; accept_wait = 0;
        access(0, 'h00c0, 0, 0, 32'hcafe0030, 8);
        check("origen buffer con latencia acumulada", stall_buffer_cycles == 8);

        reset_cache(); source = 1; latency = 8;
        // El pedido guardado debe sobrevivir a cambios del bus mientras está en curso.
        @(negedge clk); req = 1; we = 1; addr = 'h00e3; wdata = 32'h5a000000; be = 8;
        @(posedge clk); #1;
        @(negedge clk); req = 0; we = 0; addr = 'h7000; wdata = 0; be = 0;
        while (!listo) begin
            #1; check("dirección de fallo guardada", line_addr == 7);
            @(negedge clk);
        end
        @(posedge clk); #1;
        access(0, 'h00e0, 0, 0, 32'h5afe0038, 0);
        check("store pendiente aplicado una vez", write_count == 1 && write_misses == 1 && transactions == 1);

        // Peticiones consecutivas sin ciclo vacío entre ellas.
        @(negedge clk); req = 1; we = 1; addr = 'h00e0; wdata = 32'h01020304; be = 15;
        #1; check("store consecutivo inmediato", listo);
        @(posedge clk); #1;
        @(negedge clk); we = 0;
        #1; check("load consecutivo ve store", listo && rdata === 32'h01020304);
        @(posedge clk); #1;
        @(negedge clk); req = 0;
        check("pedidos consecutivos contados", write_count == 2 && read_count == 2 && write_hits == 1 && read_hits == 2);

        // Tráfico reproducible con referencia por palabra y conflictos en todos los conjuntos.
        reset_cache(); latency = 2;
        for (int w = 0; w < 16384; w++) reference_mem[w] = lower.mem[w];
        for (int n = 0; n < 300; n++) begin
            rng = (rng << 1) ^ ((rng < 0) ? 32'h04c11db7 : 0);
            random_word = (rng & 32'h3fff);
            random_mask = (rng >> 16) & 15;
            random_data = 32'h9e3779b9 ^ rng;
            if ((n % 3) == 0) begin
                access(1, 32'(4*random_word), random_data, 4'(random_mask), 0, -1);
                for (int b = 0; b < 4; b++)
                    if (random_mask & (1<<b)) reference_mem[random_word][8*b +: 8] = random_data[8*b +: 8];
            end else access(0, 32'(4*random_word), 0, 0, reference_mem[random_word], -1);
            access(0, 32'(4*random_word), 0, 0, reference_mem[random_word], 0);
        end
        check("identidades de contadores", read_count == read_hits+read_misses && write_count == write_hits+write_misses &&
            transactions == read_misses+write_misses && read_count == 500 && write_count == 100);
        check("pausas del tráfico por referencia", stall_l2_cycles == 2*transactions);
        // Recorre también las direcciones que podrían haber quedado solo en el nivel inferior.
        for (int w = 0; w < 16384; w += 8)
            access(0, 32'(4*w), 0, 0, reference_mem[w], -1);
        check("sin escrituras de línea en el puerto de lectura", !line_we && line_wdata == 0 && line_mask == 0);

        reset_cache();
        check("reset invalida contenido y contadores", read_count == 0 && write_count == 0 && !line_req && !push);
        $display("L1 modelo; Casos: %0d; Fallos: %0d", casos, fallos);
        finished = 1;
    end
endmodule

// La memoria real usa el mismo puerto de lectura; el sumidero recoge los desalojos.
module l1_memory_checker #(parameter int DIV = 4)
    (output logic finished = 0, output integer casos = 0, fallos = 0);
    localparam int TMEM = 25+7*DIV;
    logic clk = 0, rst = 0;
    always #5 clk = ~clk;
    logic req = 0, we = 0;
    logic [31:0] addr = 0, wdata = 0, rdata;
    logic [3:0] be = 0;
    logic listo, line_req, line_we, line_accepted, line_ready;
    logic [10:0] line_addr, push_addr;
    logic [255:0] line_wdata, line_rdata, push_data;
    logic [31:0] line_mask;
    logic [1:0] resp_src = 0;
    logic push, full = 0;
    logic [63:0] read_count, write_count, read_hits, read_misses, write_hits, write_misses;
    logic [63:0] stall_buffer_cycles, stall_l2_cycles, stall_memory_cycles, stall_full_cycles;
    logic [63:0] memory_reads, memory_writes, timeouts;
    integer pushes = 0;
    logic [10:0] last_push_addr;
    logic [255:0] last_push_data;
    l1_cache dut(.*);
    main_memory #(.MEM_DIV(DIV), .INIT_FILE("data/main_memory/lines.mem")) memory_model(
        .clk, .rst, .req(line_req), .we(line_we), .line_addr, .wdata(line_wdata), .wmask(line_mask),
        .rdata(), .accepted(line_accepted), .done(), .busy(), .ready(line_ready), .ready_rdata(line_rdata),
        .read_count(memory_reads), .write_count(memory_writes), .transfer_cycles(), .total_cycles(), .timeout_count(timeouts));
    task automatic check(input string name, input logic ok);
        casos++;
        if (ok !== 1'b1) begin fallos++; $display("FAIL L1 memoria DIV=%0d %s", DIV, name); end
    endtask
    always @(posedge clk) if (!rst && push) begin
        pushes++; last_push_addr = push_addr; last_push_data = push_data;
        check("push y llenado juntos", !full && line_req);
    end
    task automatic access(input logic wr, input logic [31:0] a, d,
                          input logic [3:0] mask, input logic [31:0] expected, input integer expected_stalls);
        integer stalls;
        @(negedge clk); req = 1; we = wr; addr = a; wdata = d; be = mask;
        #1; stalls = 0;
        while (!listo && stalls < 150) begin
            @(posedge clk); #1; stalls++;
            @(negedge clk); #1;
        end
        check("respuesta dentro del limite", listo);
        check("pausas exactas", stalls == expected_stalls);
        if (!wr) check("datos de memoria real", rdata === expected);
        @(posedge clk); #1;
        @(negedge clk); req = 0;
    endtask
    initial begin
        #1 rst = 1; repeat (3) @(negedge clk); rst = 0;
        access(0, 'h20, 0, 0, 32'h03020100, TMEM);
        access(0, 'h3c, 0, 0, 32'h1f1e1d1c, 0);
        access(1, 'h21, 32'h0000aa00, 2, 0, 0);
        access(0, 'h20, 0, 0, 32'h0302aa00, 0);
        access(1, 'h820, 32'h12345678, 15, 0, TMEM);
        access(0, 'h820, 0, 0, 32'h12345678, 0);
        access(0, 'h1020, 0, 0, 0, TMEM);
        check("victima sucia conserva bytes", pushes == 1 && last_push_addr == 1 &&
            last_push_data[31:0] === 32'h0302aa00 && last_push_data[255:224] === 32'h1f1e1d1c);
        access(0, 'hfffc, 0, 0, 32'hfedcba98, TMEM);
        check("conteo memoria sin duplicados ni write-through", memory_reads == 4 && memory_writes == 0 && timeouts == 0);
        check("conteo L1", read_count == 6 && write_count == 2 && read_misses == 3 && write_misses == 1 &&
            read_hits == 3 && write_hits == 1 && stall_memory_cycles == 4*TMEM && stall_full_cycles == 0);
        $display("L1 main_memory DIV=%0d; Casos: %0d; Fallos: %0d", DIV, casos, fallos);
        finished = 1;
    end
endmodule

module tb_l1_cache;
    wire [3:0] finished;
    wire [31:0] c0, c2, c4, c5, f0, f2, f4, f5;
    l1_cache_checker model(finished[0], c0, f0);
    l1_memory_checker #(.DIV(2)) m2(finished[1], c2, f2);
    l1_memory_checker #(.DIV(4)) m4(finished[2], c4, f4);
    l1_memory_checker #(.DIV(5)) m5(finished[3], c5, f5);
    initial begin
        $dumpfile("build/tb_l1_cache.vcd");
        $dumpvars(0, tb_l1_cache);
        wait (&finished);
        $display("Casos: %0d; Fallos: %0d", c0+c2+c4+c5, f0+f2+f4+f5);
        if (f0+f2+f4+f5) $fatal(1, "FAIL tb_l1_cache");
        $display("PASS tb_l1_cache"); $finish;
    end
    initial begin #1000000; $fatal(1, "FAIL L1 limite global"); end
endmodule
