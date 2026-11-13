`timescale 1ns/1ps

module main_memory_checker #(parameter int DIV = 4)
    (output logic finished = 0, output integer casos = 0, fallos = 0);
    localparam int TMEM = 25 + 7*DIV;
    logic clk = 0, rst = 0;
    always #5 clk = ~clk;
    logic req = 0, we = 0;
    logic [10:0] line_addr = 0;
    logic [255:0] wdata = 0, rdata;
    logic [31:0] wmask = 0;
    logic accepted, done, busy;
    logic [63:0] read_count, write_count, transfer_cycles, total_cycles, timeout_count;
    main_memory #(.MEM_DIV(DIV), .INIT_FILE("data/main_memory/lines.mem")) dut
        (.clk, .rst, .req, .we, .line_addr, .wdata, .wmask,
         .rdata, .accepted, .done, .busy, .read_count, .write_count,
         .transfer_cycles, .total_cycles, .timeout_count);

    integer ticks = 0, start_tick = 0, reads = 0, writes = 0, completions = 0;
    integer last_done = 0, finish_tick = -1000;
    integer slow_edges = 0, transfers = 0, last_transfer_edge = 0, burst_finish = 0;
    integer pair_end;
    logic command_we = 0;
    logic [10:0] command_addr = 0;
    logic [255:0] command_data;
    logic [31:0] command_mask;
    logic [DIV-1:0] read_phases = 0, write_phases = 0;
    integer launch_phase;
    always @(posedge clk) launch_phase = dut.div_phase;
    logic [255:0] previous_rdata;
    logic checking = 1;
    logic [255:0] original, pattern, partial, last_line;
    task automatic check(input string name, input logic ok);
        casos++;
        if (ok !== 1'b1) begin
            fallos++;
            $display("FAIL MEM_DIV=%0d %s", DIV, name);
        end
    endtask

    // Monitor independiente del temporizador del DUT; observa después de NBA.
    always @(posedge clk) begin
        if (rst) begin
            ticks = 0; reads = 0; writes = 0; completions = 0; last_done = 0;
        end else begin
            ticks++;
            #1;
            if (checking) begin
                check("contador de ciclos totales", total_cycles === ticks);
                if (accepted) begin
                    start_tick = ticks;
                    transfers = 0;
                    command_we = we; command_addr = line_addr;
                    command_data = wdata; command_mask = wmask;
                    if (we) write_phases[launch_phase] = 1;
                    else read_phases[launch_phase] = 1;
                    previous_rdata = rdata;
                    if (we) writes++; else reads++;
                    check("aceptacion eleva busy", busy && !done);
                end
                if (busy && !accepted)
                    check("linea publica estable antes de done", rdata === previous_rdata);
                if (done) begin
                    completions++;
                    finish_tick = ticks;
                    check("busy baja junto con done", !busy);
                    check("handshake recuperado al terminar", !dut.req_mem && !dut.ack_sync &&
                          !dut.ack_mem && !dut.req_sync);
                    check("ocho transferencias antes de TMEM", transfers == 8 && burst_finish < TMEM);
                    check("latencia exacta", ticks-start_tick == TMEM);
                    check("done de un ciclo", !last_done);
                    check("transferencias acumuladas", transfer_cycles == completions*TMEM);
                end
                check("lecturas acumuladas", read_count == reads);
                check("escrituras acumuladas", write_count == writes);
                check("sin timeout normal", timeout_count == 0);
                last_done = done;
            end
            if ($test$plusargs("TRACE_MEMORY") && DIV == 4 && reads == 1 && writes == 0 &&
                ticks-start_tick <= TMEM)
                $display("TRACE c=%0d phase=%0d mclk=%b req=%b/%b/%b ack=%b/%b/%b completion=%b/%b/%b busy=%b done=%b",
                         ticks-start_tick, dut.div_phase, dut.mem_clk,
                         dut.req_mem, dut.req_meta, dut.req_sync,
                         dut.ack_mem, dut.ack_meta, dut.ack_sync,
                         dut.completion_mem, dut.completion_meta, dut.completion_sync, busy, done);
        end
    end

    // Observa cada flanco lento ANTES del NBA y verifica después sus efectos
    // sobre las ocho palabras de RAM y response. Una transferencia no puede
    // cambiar ninguna otra palabra ni ocurrir entre flancos consecutivos.
    always @(posedge dut.mem_clk) begin : physical_burst_monitor
        logic transfer;
        integer index_word;
        logic [31:0] before_ram [0:7];
        logic [255:0] before_response;
        logic [31:0] expected_word;
        if (!rst && checking) begin
            slow_edges++;
            transfer = dut.word_transfer;
            index_word = dut.word_index;
            before_response = dut.response;
            for (int i = 0; i < 8; i++) before_ram[i] = dut.mem[8*command_addr+i];
            if (transfers > 0 && transfers < 8)
                check("sin huecos dentro del burst", transfer);
            if (transfer) begin
                check("indice fisico consecutivo", index_word == transfers && transfers < 8);
                if (transfers > 0)
                    check("flancos lentos consecutivos", slow_edges == last_transfer_edge+1);
                last_transfer_edge = slow_edges;
                transfers++;
                if (transfers == 8) burst_finish = ticks-start_tick;
            end
            #0.1;
            for (int i = 0; i < 8; i++) begin
                expected_word = before_ram[i];
                if (transfer && command_we && i == index_word)
                    for (int b = 0; b < 4; b++)
                        if (command_mask[4*i+b])
                            expected_word[8*b +: 8] = command_data[32*i+8*b +: 8];
                check("RAM solo escribe palabra/carriles del flanco", dut.mem[8*command_addr+i] === expected_word);
                expected_word = before_response[32*i +: 32];
                if (transfer && !command_we && i == index_word) expected_word = before_ram[i];
                check("response solo lee palabra del flanco", dut.response[32*i +: 32] === expected_word);
            end
        end
    end

    // Valid/ready: sostener req y bus hasta accepted, incluso durante busy.
    task automatic present(input logic wr, input logic [10:0] address,
                           input logic [255:0] data, input logic [31:0] mask);
        @(negedge clk);
        we = wr; line_addr = address; wdata = data; wmask = mask; req = 1;
        do begin @(posedge clk); #2; end while (!accepted);
        @(negedge clk); req = 0;
    endtask
    task automatic complete;
        do begin @(posedge clk); #2; end while (!done);
    endtask
    task automatic idle;
        while (busy) begin @(posedge clk); #2; end
    endtask
    task automatic access(input logic wr, input logic [10:0] address,
                          input logic [255:0] data, input logic [31:0] mask);
        present(wr, address, data, mask);
        complete();
    endtask
    // El siguiente posedge acepta en la fase solicitada (fase antes del flanco).
    task automatic phase(input integer p);
        idle();
        @(negedge clk);
        while (dut.div_phase != p) @(negedge clk);
        req = 1;
        @(posedge clk); #2;
        check("acepta en fase solicitada", accepted);
        @(negedge clk); req = 0;
        complete();
    endtask

    initial begin
        #1 rst = 1;
        for (int b = 0; b < 32; b++) begin
            original[8*b +: 8] = b;
            pattern[8*b +: 8] = 255-b;
            partial[8*b +: 8] = (b%3 == 0) ? 8'haa : (255-b);
        end
        last_line = 0; last_line[255:224] = 32'hfedcba98;
        repeat (3) @(negedge clk);
        rst = 0;
        access(0, 1, 0, 0);
        check("lectura .mem por indice de palabra", rdata === original);
        access(0, 2047, 0, 0);
        check("ultima linea y palabras inicializadas a cero", rdata === last_line);
        access(1, 2, pattern, 32'hffffffff);
        access(0, 2, 0, 0);
        check("escritura completa", rdata === pattern);
        access(1, 2, {32{8'haa}}, 32'h49249249);
        access(0, 2, 0, 0);
        check("mascara parcial en todos los carriles", rdata === partial);
        access(1, 2, 0, 0);
        access(0, 2, 0, 0);
        check("mascara cero conserva", rdata === partial);

        for (int p = 0; p < DIV; p++) begin
            idle(); we = 1; line_addr = 3; wdata = pattern ^ p; wmask = '1;
            phase(p);
            pair_end = ticks;
            // req se presenta en la bajada inmediatamente posterior a done.
            access(0, 3, 0, 0);
            check("sin ciclo muerto tras done en cada fase", start_tick == pair_end+1);
            check("lectura tras escritura en cada fase", rdata === (pattern ^ p));
        end

        // El segundo pedido aparece ANTES de terminar el primero. No hay cola:
        // se mantiene válido hasta done; se acepta en el flanco siguiente.
        present(1, 4, original, '1);
        repeat (3) @(negedge clk);
        check("ocupada antes del segundo pedido", busy && !done);
        present(0, 4, 0, 0);
        check("pedido pendiente acepta inmediatamente", start_tick == finish_tick+1);
        complete();
        check("pedido durante busy espera y conserva datos", rdata === original);
        idle();
        repeat (3*DIV+5) @(negedge clk);
        check("sin perdidas ni duplicados", completions == 10+2*DIV &&
              reads == 6+DIV && writes == 4+DIV);
        check("contadores finales", read_count+write_count == 10+2*DIV &&
              transfer_cycles == (10+2*DIV)*TMEM);

        check("lecturas y escrituras cubren todas las fases", (&read_phases) && (&write_phases));

        // Reset asíncrono conserva RAM, limpia estado, contadores y CDC.
        #1 rst = 1; #1;
        check("reset asincrono", !busy && !done && !accepted && total_cycles == 0 &&
              read_count == 0 && write_count == 0 && transfer_cycles == 0 && timeout_count == 0);
        repeat (3) @(negedge clk);
        rst = 0;
        access(0, 4, 0, 0);
        check("reset conserva RAM", rdata === original);
        idle();

        // Opt-in: $error esperado no contamina make all. Sin parámetro de diseño.
        if ($test$plusargs("TEST_TIMEOUT") && DIV == 4) begin
            checking = 0;
            force dut.req_sync = 0;
            present(0, 1, 0, 0);
            repeat (2*TMEM-1) @(negedge clk);
            check("vigilante no se adelanta", timeout_count == 0 && busy && !done);
            @(negedge clk);
            check("vigilante registra cuelgue", timeout_count == 1 && busy && !done);
            repeat (TMEM) @(negedge clk);
            check("vigilante reporta una sola vez", timeout_count == 1);
            release dut.req_sync;
            complete(); idle();
            check("recuperacion al liberar CDC", rdata === original && timeout_count == 1);
        end
        checking = 0;
        $display("MEM_DIV=%0d Tmem=%0d; Casos: %0d; Fallos: %0d", DIV, TMEM, casos, fallos);
        finished = 1;
    end
endmodule

module tb_main_memory;
    wire [2:0] finished;
    wire [31:0] c2, c4, c5, f2, f4, f5;
    main_memory_checker #(.DIV(2)) d2(finished[0], c2, f2);
    main_memory_checker #(.DIV(4)) d4(finished[1], c4, f4);
    main_memory_checker #(.DIV(5)) d5(finished[2], c5, f5);
    initial begin
        wait (&finished);
        $display("Casos: %0d; Fallos: %0d", c2+c4+c5, f2+f4+f5);
        if (f2+f4+f5 != 0) $fatal(1, "FAIL tb_main_memory");
        $display("PASS tb_main_memory");
        $finish;
    end
    initial begin
        #200000;
        $fatal(1, "FAIL tb_main_memory: limite global");
    end
endmodule
