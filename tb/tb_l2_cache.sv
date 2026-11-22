`timescale 1ns/1ps

module tb_l2_cache;
    localparam int TMEM = 53;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1;
    logic req = 0, we = 0;
    logic [10:0] line_addr = 0;
    logic [255:0] wdata = 0;
    logic [31:0] wmask = '1;
    wire accepted, ready;
    wire [255:0] ready_rdata;
    wire [1:0] resp_src;
    wire line_req, line_we;
    wire [10:0] line_line_addr;
    wire [255:0] line_wdata;
    wire [31:0] line_wmask;
    logic line_accepted = 0;
    wire line_ready;
    wire [255:0] line_rdata;
    wire [1:0] line_resp_src;
    wire push;
    wire [10:0] push_addr;
    wire [255:0] push_data;
    logic full = 0;
    wire [63:0] read_count, write_count, read_hits, read_misses;
    wire [63:0] write_hits, write_misses, stall_full_cycles;

    l2_cache dut (.*);

    int cycles = 0, cases = 0, failures = 0;
    int downstream_requests = 0, push_count = 0;
    logic [10:0] last_push_addr;
    logic [255:0] last_push_data;
    logic [10:0] last_read_addr;
    logic mem_busy = 0;
    integer mem_age = 0;
    logic block_downstream = 0;
    logic [10:0] mem_addr;
    logic [1:0] mem_source = 0;
    logic forwarding = 0;
    logic [255:0] mem_payload;

    function automatic [255:0] pattern(input logic [10:0] a);
        for (int i = 0; i < 8; i++)
            pattern[32*i +: 32] = 32'hCAFE0000 ^ (32'(a) << 8) ^ 32'(i);
    endfunction

    assign line_ready = !rst && ((mem_busy && mem_age == TMEM-1) ||
                                (forwarding && line_req && !mem_busy));
    assign line_rdata = forwarding && line_req && !mem_busy ?
                        pattern(line_line_addr) : pattern(mem_addr);
    assign line_resp_src = forwarding && line_req && !mem_busy ? 2'd2 : mem_source;

    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (rst) begin
            line_accepted <= 0;
            mem_busy <= 0;
            mem_age <= 0;
            downstream_requests <= 0;
            push_count <= 0;
            last_push_addr <= 0;
            last_push_data <= 0;
            last_read_addr <= 0;
        end else begin
            line_accepted <= 0;
            if (push && !full) begin
                push_count <= push_count + 1;
                last_push_addr <= push_addr;
                last_push_data <= push_data;
            end
            if (mem_busy) begin
                if (line_ready) begin
                    mem_busy <= 0;
                    mem_age <= 0;
                end else mem_age <= mem_age + 1;
            end else if (line_req && !block_downstream) begin
                downstream_requests <= downstream_requests + 1;
                last_read_addr <= line_line_addr;
                line_accepted <= 1;
                if (!forwarding) begin
                    mem_busy <= 1;
                    mem_addr <= line_line_addr;
                    mem_age <= 0;
                end
            end
        end
    end

    task automatic check(input bit condition, input string description);
        cases++;
        if (!condition) begin
            failures++;
            $display("FAIL: %s (cycle %0d)", description, cycles);
        end else $display("PASS: %s", description);
    endtask

    // Emite una solicitud y muestrea ready inmediatamente antes de los flancos.
    // El primer flanco que acepta req es el ciclo cero de la transacción.
    task automatic transaction(
        input bit write_op,
        input logic [10:0] addr,
        input logic [255:0] payload,
        input int expected_latency,
        input logic [255:0] expected_data,
        input logic [1:0] expected_src,
        input bit verify_data,
        input string description
    );
        int elapsed;
        bit got_accept, got_ready;
        @(negedge clk);
        req = 1;
        we = write_op;
        line_addr = addr;
        wdata = payload;
        wmask = '1;
        got_accept = 0;
        for (int k = 0; k < 20 && !got_accept; k++) begin
            @(posedge clk);
            #1;
            got_accept = accepted;
        end
        check(got_accept, {description, ": accepted"});
        @(negedge clk);
        req = 0;
        elapsed = 0;
        got_ready = 0;
        // En cada flanco de subida posterior se muestrea ready combinacional
        // antes de que cambie el estado secuencial del módulo.
        for (int k = 0; k < 250 && !got_ready; k++) begin
            @(posedge clk);
            elapsed++;
            if (ready) begin
                got_ready = 1;
                check(expected_latency < 0 ? elapsed > 8 : elapsed == expected_latency,
                      $sformatf("%s: latency expected %0d, got %0d",
                                description, expected_latency, elapsed));
                check(resp_src == expected_src, {description, ": resp_src"});
                if (verify_data)
                    check(ready_rdata === expected_data, {description, ": data"});
            end
        end
        check(got_ready, {description, ": completion"});
        @(negedge clk);
    endtask

    task automatic test_downstream_busy;
        int previous_requests;
        int elapsed;
        int accepted_count;
        bit got_ready;
        bit request_seen;
        logic [10:0] expected_addr;

        previous_requests = downstream_requests;
        accepted_count = 0;
        elapsed = 0;
        got_ready = 0;
        request_seen = 0;
        expected_addr = F;

        begin : busy_test
            $display("\n--- Read miss with downstream busy ---");

            // Impide que el nivel inferior acepte solicitudes.
            @(negedge clk);
            block_downstream = 1;

            // Inicia una lectura con fallo de caché.
            req = 1;
            we = 0;
            line_addr = F;
            wdata = '0;
            wmask = '1;

            // Espera a que L2 acepte la solicitud.
            @(posedge clk);
            #1;
            check(accepted, "busy test: L2 accepted request");

            @(negedge clk);
            req = 0;

            // Espera a que L2 emita la solicitud al nivel inferior.
            for (int k = 0; k < 20 && !request_seen; k++) begin
                @(negedge clk);
                if (line_req)
                    request_seen = 1;
            end

            check(request_seen, "busy test: downstream request issued");

            if (!request_seen)
                disable busy_test;

            check(line_line_addr == expected_addr,
                "busy test: correct downstream address");

            check(!line_we,
                "busy test: downstream operation is read");

            // Mantiene el nivel inferior bloqueado durante varios ciclos.
            for (int k = 0; k < 6; k++) begin
                @(negedge clk);

                check(line_req,
                    $sformatf("busy test: request held cycle %0d", k));

                check(line_line_addr == expected_addr,
                    $sformatf("busy test: address stable cycle %0d", k));

                check(!line_accepted,
                    $sformatf("busy test: no acceptance cycle %0d", k));
            end

            check(downstream_requests == previous_requests,
                "busy test: no request accepted while blocked");

            // Permite que el nivel inferior acepte la solicitud pendiente.
            block_downstream = 0;

            // Espera el pulso registrado de aceptación.
            for (int k = 0; k < 10 && !line_accepted; k++) begin
                @(posedge clk);
                #1;
            end

            check(line_accepted,
                "busy test: downstream eventually accepts");

            // Espera la respuesta de memoria.
            for (int k = 0; k < TMEM + 20 && !got_ready; k++) begin
                @(posedge clk);

                if (ready) begin
                    got_ready = 1;

                    check(ready_rdata === pattern(F),
                        "busy test: returned data correct");

                    check(resp_src == 2'd0,
                        "busy test: response came from memory");
                end
            end

            check(got_ready,
                "busy test: transaction completes");

            check(downstream_requests == previous_requests + 1,
                "busy test: exactly one downstream request accepted");

            @(negedge clk);
        end
    endtask

    localparam logic [10:0] A = 11'h012;
    localparam logic [10:0] B = 11'h092;
    localparam logic [10:0] C = 11'h112;
    localparam logic [10:0] D = 11'h192;
    localparam logic [10:0] E = 11'h212;
    localparam logic [10:0] F = 11'h035;
    logic [255:0] custom_data;
    int prior_reads, prior_pushes;

    initial begin
        $dumpfile("build/tb_l2_cache.vcd");
        $dumpvars(0, tb_l2_cache);
        repeat (4) @(negedge clk);
        rst = 0;
        custom_data = {8{32'h12345678}};

        prior_reads = downstream_requests;
        transaction(1, A, custom_data, 8, custom_data, 1, 0, "write miss A");
        check(downstream_requests == prior_reads, "write miss does not read memory");
        transaction(0, A, '0, 8, custom_data, 1, 1, "read hit A");
        transaction(1, A, {8{32'h87654321}}, 8, '0, 1, 0, "write hit A");
        transaction(0, A, '0, 8, {8{32'h87654321}}, 1, 1, "read updated A");

        prior_reads = downstream_requests;
        transaction(0, B, '0, 8+TMEM, pattern(B), 0, 1, "read miss B");
        check(downstream_requests == prior_reads + 1, "read miss requests one line");
        check(last_read_addr == B, "read miss requests correct address");
        transaction(0, B, '0, 8, pattern(B), 1, 1, "read hit B");

        forwarding = 1;
        transaction(0, C, '0, 8, pattern(C), 2, 1, "forwarded miss C");
        forwarding = 0;
        transaction(1, B, pattern(B), 8, '0, 1, 0, "dirty B");
        transaction(1, C, pattern(C), 8, '0, 1, 0, "dirty C");
        transaction(1, D, pattern(D), 8, '0, 1, 0, "fill fourth way D");

        prior_pushes = push_count;
        full = 1;
        // E comparte conjunto con A-D. Provoca una pausa por desalojo antes de liberar el buffer.
        fork
            begin
                transaction(1, E, pattern(E), -1, '0, 1, 0, "dirty eviction E");
            end
            begin
                wait (dut.state == 2'd2);
                repeat (4) @(negedge clk);
                full = 0;
            end
        join
        check(push_count == prior_pushes + 1, "one dirty victim pushed");
        check(last_push_addr == A || last_push_addr == B ||
              last_push_addr == C || last_push_addr == D,
              "eviction address identifies a dirty resident");
        check(stall_full_cycles >= 1, "buffer full stall counter increments");

        test_downstream_busy();

        check(read_count == read_hits + read_misses, "read counters consistent");
        check(write_count == write_hits + write_misses, "write counters consistent");

        $display("Casos: %0d; Fallos: %0d", cases, failures);
        if (failures != 0) $fatal(1, "tb_l2_cache: failed");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "tb_l2_cache: global timeout");
    end
endmodule
