`timescale 1ns/1ps

// Prueba el buffer con una profundidad determinada. Primero utiliza un modelo
// cuyo tiempo de respuesta se puede controlar para provocar casos concretos.
// Después conecta la memoria principal y comprueba que los datos escritos puedan
// leerse de nuevo cuando las líneas ya hayan salido del buffer.
//
// Una cola de referencia mantiene el resultado esperado usando solo las señales
// externas. Es FIFO, por lo que retira las líneas en el mismo orden en que entran.
// No consulta el estado interno del módulo que se está probando.
module line_buffer_checker #(parameter int DEPTH = 4)
    (output logic finished = 0, output integer casos = 0, fallos = 0);
    // Cada profundidad se prueba con su propio reloj y reset. Así las cuatro
    // instancias pueden avanzar en paralelo sin compartir el estado de sus pruebas.
    logic clk = 0, rst = 1;
    always #5 clk = ~clk;
    logic req = 0, we = 0, push = 0;
    logic [10:0] line_addr = 0, push_addr = 0;
    logic [255:0] push_data = 0, ready_rdata;
    logic accepted, ready, full;
    logic [1:0] resp_src;
    logic down_req, down_we, down_accepted, down_ready;
    logic [10:0] down_line_addr;
    logic [255:0] down_wdata, down_ready_rdata;
    logic [31:0] down_wmask;
    logic [1:0] down_resp_src;
    logic [63:0] received_count, forwarding_count, full_cycles, max_occupancy;
    // El puerto superior se usa para leer. Las líneas modificadas entran por push,
    // por lo que los datos y la máscara de escritura superiores se fijan a cero.
    line_buffer #(.DEPTH(DEPTH)) dut (
        .clk, .rst, .req, .we, .line_addr, .wdata(256'b0), .wmask(32'b0),
        .accepted, .ready, .ready_rdata, .resp_src,
        .push, .push_addr, .push_data, .full,
        .down_req, .down_we, .down_line_addr, .down_wdata, .down_wmask,
        .down_accepted, .down_ready, .down_ready_rdata, .down_resp_src,
        .received_count, .forwarding_count, .full_cycles, .max_occupancy);

    // El modelo atiende un pedido a la vez y permite elegir cuántos ciclos tarda.
    // Con allow_accept=0 se retrasa la aceptación. Con immediate=1, una lectura
    // responde en el mismo ciclo y no genera un pulso de accepted.
    // source selecciona el origen de la respuesta para comprobar su propagación.
    // real_memory cambia del modelo a main_memory en la segunda fase.
    logic real_memory = 0, allow_accept = 1, immediate = 0;
    integer latency = 6, remaining = 0, model_reads = 0, model_writes = 0;
    logic model_accepted = 0, model_busy = 0;
    logic [10:0] saved_addr;
    logic [1:0] source = 1;
    // Se guardan la dirección y los datos de cada escritura aceptada. El historial
    // permite comprobar el orden de salida y detectar pedidos duplicados.
    logic [10:0] write_addresses [0:255];
    logic [255:0] write_data [0:255];
    // ready se activa antes del flanco que completa el acceso. Así el buffer puede
    // entregar la respuesta en ese mismo flanco, sin añadir un ciclo de espera.
    wire model_ready = (model_busy && remaining == 1) ||
                       (immediate && !model_busy && down_req && !down_we);
    // Se genera una línea con ocho palabras distintas de 32 bits. El contenido
    // depende del valor solicitado y de la posición de cada palabra. Esto permite
    // detectar datos antiguos, palabras intercambiadas y líneas incompletas.
    function automatic [255:0] pattern(input integer n);
        for (integer i = 0; i < 8; i++) pattern[32*i +: 32] = 32'habc00000 + 32'(n*8+i);
    endfunction
    always @(posedge clk) begin
        if (rst) begin
            model_accepted <= 0; model_busy <= 0; remaining <= 0;
            model_reads <= 0; model_writes <= 0;
            saved_addr <= 0;
        end else if (!real_memory) begin
            model_accepted <= 0;
            if (model_busy) begin
                if (remaining == 1) model_busy <= 0;
                else remaining <= remaining - 1;
            end else if (allow_accept && down_req && !immediate) begin
                // El modelo guarda el pedido solo cuando está libre. accepted
                // confirma que lo recibió, pero la operación todavía debe esperar
                // los ciclos indicados por latency antes de activar ready.
                model_accepted <= 1; model_busy <= 1; remaining <= latency;
                saved_addr <= down_line_addr;
                if (down_we) begin
                    write_addresses[model_writes] <= down_line_addr;
                    write_data[model_writes] <= down_wdata;
                    model_writes <= model_writes + 1;
                end else model_reads <= model_reads + 1;
            end
        end
    end
    wire ram_accepted, ram_ready, ram_busy;
    wire [255:0] ram_data;
    wire [63:0] ram_reads, ram_writes;
    // main_memory permanece en reset mientras se usa el modelo controlado.
    // En la segunda fase recibe las mismas señales de dirección, datos y control.
    // MEM_DIV=4 selecciona el divisor de reloj previsto para la memoria.
    main_memory #(.MEM_DIV(4)) ram (
        .clk, .rst(rst || !real_memory), .req(down_req && real_memory),
        .we(down_we), .line_addr(down_line_addr), .wdata(down_wdata), .wmask(down_wmask),
        .accepted(ram_accepted), .ready(ram_ready), .ready_rdata(ram_data),
        .busy(ram_busy), .read_count(ram_reads), .write_count(ram_writes),
        .rdata(), .done(), .transfer_cycles(), .total_cycles(), .timeout_count());
    // Se elige la respuesta del nivel que esté activo. La memoria principal tiene
    // origen cero. El modelo puede devolver cero, uno o dos para probar cada caso.
    assign down_accepted = real_memory ? ram_accepted : model_accepted;
    assign down_ready = real_memory ? ram_ready : model_ready;
    assign down_ready_rdata = real_memory ? ram_data : pattern(model_busy ? int'(saved_addr) : int'(down_line_addr));
    assign down_resp_src = real_memory ? 2'd0 : source;

    // Solo una condición igual a uno se considera correcta. Los valores cero,
    // desconocido y de alta impedancia cuentan como fallos. Cada instancia conserva
    // sus totales y la prueba completa termina con error si alguna comprobación falla.
    task automatic check(input string name, input logic ok);
        casos++;
        if (ok !== 1'b1) begin
            fallos++;
            $display("FAIL DEPTH=%0d %s", DEPTH, name);
        end
    endtask
    // La cola de referencia agrega una línea cuando push encuentra espacio y la
    // retira cuando termina su escritura en el nivel inferior. De esas operaciones
    // también se calculan los contadores esperados, sin consultar los registros
    // internos del buffer.
    integer ref_count = 0, ref_head = 0, ref_tail = 0;
    logic [10:0] ref_addresses [0:DEPTH-1];
    logic [255:0] ref_data [0:DEPTH-1];
    logic [63:0] expected_received = 0, expected_forwarding = 0;
    logic [63:0] expected_full_cycles = 0, expected_maximum = 0;
    // read_presented recuerda que hay una lectura enviada al nivel inferior,
    // aunque el emisor ya haya bajado req. pending_bus indica que el pedido espera
    // aceptación. Los valores previous_* permiten comprobar que sus campos no cambien.
    logic read_presented = 0, pending_bus = 0;
    logic previous_we;
    logic [10:0] previous_addr;
    logic [255:0] previous_data;
    logic [31:0] previous_mask;
    always @(posedge clk) begin : reference_monitor
        integer index;
        logic local_hit, incoming, outgoing;
        logic [255:0] newest;
        if (rst) begin
            ref_count = 0; ref_head = 0; ref_tail = 0;
            expected_received = 0; expected_forwarding = 0;
            expected_full_cycles = 0; expected_maximum = 0;
            read_presented = 0; pending_bus = 0;
        end else if (!finished) begin
            check("full coincide con ocupacion externa", full === (ref_count == DEPTH));
            // La aceptación de una línea depende del espacio anterior al flanco.
            // Si la cola estaba llena, una salida en ese mismo flanco no permite
            // aceptar el push que ya se había presentado con full=1.
            incoming = push && ref_count < DEPTH;
            outgoing = down_ready && down_we;
            if (ref_count == DEPTH) expected_full_cycles++;

            // La búsqueda recorre la cola de referencia en orden de llegada.
            // La última coincidencia contiene la versión más reciente de la línea.
            // Este resultado se calcula sin usar los punteros ni la búsqueda del buffer.
            local_hit = 0; newest = 0;
            for (integer i = 0; i < ref_count; i++) begin
                index = (ref_head+i) % DEPTH;
                if (ref_addresses[index] == line_addr) begin
                    local_hit = 1;
                    newest = ref_data[index];
                end
            end
            if (req && !we && local_hit && !read_presented) begin
                check("forwarding combinacional segun cola externa", ready &&
                      ready_rdata === newest && resp_src == 2);
                expected_forwarding++;
            end
            // Un pedido pendiente debe mantener activa su solicitud y conservar
            // la dirección, los datos y la máscara hasta su aceptación o respuesta.
            if (pending_bus && !down_accepted && !down_ready)
                check("pedido estable mientras espera accepted", down_req &&
                      down_we === previous_we && down_line_addr === previous_addr &&
                      down_wdata === previous_data && down_wmask === previous_mask);
            pending_bus = down_req && !down_accepted && !down_ready;
            previous_we = down_we; previous_addr = down_line_addr;
            previous_data = down_wdata; previous_mask = down_wmask;
            // Se comparan las respuestas superior e inferior en el mismo flanco.
            // Si el buffer retuviera la respuesta durante un ciclo adicional,
            // las señales no coincidirían y la comprobación fallaría.
            if (read_presented || (down_req && !down_we)) begin
                check("ready pasa sin ciclo adicional", ready === down_ready);
                check("accepted de lectura se propaga", accepted === down_accepted);
                if (down_ready)
                    check("datos y origen se propagan intactos", ready_rdata === down_ready_rdata &&
                          resp_src === down_resp_src);
            end
            if (down_accepted)
                check("req baja despues de accepted", !down_req);
            if (down_req && !down_we) read_presented = 1;
            if (down_ready && !down_we) read_presented = 0;

            // Primero se retira la línea que terminó de escribirse y después se
            // almacena la nueva. incoming ya se decidió con el espacio anterior
            // al flanco, por lo que este orden no permite aceptar un push con full=1.
            if (outgoing) begin
                check("retiro corresponde a cabeza FIFO", ref_count > 0 &&
                      down_line_addr === ref_addresses[ref_head] &&
                      down_wdata === ref_data[ref_head] && down_wmask == 32'hffffffff);
                ref_head = (ref_head+1) % DEPTH;
                ref_count--;
            end
            if (incoming) begin
                ref_addresses[ref_tail] = push_addr;
                ref_data[ref_tail] = push_data;
                ref_tail = (ref_tail+1) % DEPTH;
                ref_count++;
                expected_received++;
            end
            if (64'(ref_count) > expected_maximum) expected_maximum = 64'(ref_count);
            // Las asignaciones secuenciales del buffer se aplican después de
            // evaluar el flanco. Se espera a que terminen antes de comparar sus
            // contadores con los valores esperados para ese mismo flanco.
            #2;
            check("lineas recibidas sin perdidas ni duplicados", received_count === expected_received);
            check("contador forwarding exacto", forwarding_count === expected_forwarding);
            check("ciclos lleno exactos", full_cycles === expected_full_cycles);
            check("ocupacion maxima exacta", max_occupancy === expected_maximum);
        end
    end

    // Se espera un flanco ascendente y se devuelve el control en el descendente.
    // Así las entradas cambian lejos del momento en que el buffer las toma y no
    // compiten con sus actualizaciones secuenciales dentro de la simulación.
    task automatic step;
        @(posedge clk); #1; @(negedge clk);
    endtask
    // Se reinician juntos el buffer y el nivel inferior seleccionado. Cada grupo
    // de pruebas comienza sin líneas pendientes y con los contadores en cero.
    task automatic reset_buffer;
        rst = 1; req = 0; push = 0; we = 0;
        repeat (3) step();
        rst = 0;
        #1;
        check("reset limpia cola y contadores", ref_count == 0 && !full &&
              !ready && !accepted && received_count == 0 && forwarding_count == 0 &&
              full_cycles == 0 && max_occupancy == 0);
    endtask
    // Se presenta una línea durante un solo flanco ascendente. Algunas pruebas
    // lo hacen con full=1 para comprobar que el buffer rechace la inserción.
    task automatic put(input integer address, input integer value);
        push = 1; push_addr = 11'(address); push_data = pattern(value);
        step(); push = 0;
    endtask
    // Se espera hasta que la cola de referencia quede vacía. Si el drenaje no
    // progresa dentro del límite, se registra un fallo. Después se avanza otro
    // flanco para dar tiempo a que aparezca un posible pedido duplicado.
    task automatic drain_all;
        integer guard;
        guard = 0;
        while (ref_count != 0 && guard < 2000) begin step(); guard++; end
        check("drenaje termina", ref_count == 0);
        step();
    endtask
    // La lectura mantiene req hasta recibir accepted o una respuesta inmediata.
    // Después de accepted se baja req y se sigue esperando ready. Al terminar,
    // se comprueban los datos de la línea y el origen de la respuesta.
    task automatic read_line(input integer address, input logic [255:0] expected,
                             input logic [1:0] expected_source);
        integer guard;
        req = 1; line_addr = 11'(address); guard = 0;
        #1;
        if (expected_source == 2 && !immediate)
            check("forwarding en el mismo ciclo", ready && !accepted);
        while (!ready && guard < 2000) begin
            @(posedge clk); #1;
            if (accepted) begin @(negedge clk); req = 0; end
            else @(negedge clk);
            #1; guard++;
        end
        check("lectura dentro del limite", guard < 2000);
        check("lectura termina con datos y origen", ready && ready_rdata === expected &&
              resp_src === expected_source);
        step(); req = 0;
    endtask
    integer before_writes;
    logic [63:0] before_full;
    initial begin
        // Se impide que el modelo acepte el drenaje para llenar todas las entradas.
        // Con la cola llena se comprueban el rechazo de un push y los contadores.
        // Luego se permite el drenaje y se verifica el orden de las líneas escritas.
        reset_buffer();
        allow_accept = 0;
        for (integer i = 0; i < DEPTH; i++) put(i+10, i+10);
        check("FIFO llena y maximo", full && ref_count == DEPTH &&
              received_count == DEPTH && max_occupancy == DEPTH);
        before_full = full_cycles;
        put(99, 99);
        check("rechaza push llena y cuenta ciclo", ref_count == DEPTH &&
              received_count == DEPTH && full_cycles == before_full+1);
        before_full = full_cycles;
        repeat (3) step();
        check("full cuenta ciclos sin push", full_cycles == before_full+3);
        read_line(10, pattern(10), 2);
        check("forwarding no retira entrada", ref_count == DEPTH && forwarding_count == 1);
        allow_accept = 1;
        drain_all();
        check("exactamente una escritura por entrada", model_writes == DEPTH);
        for (integer i = 0; i < DEPTH; i++) begin
            check("orden FIFO y datos completos", write_addresses[i] == i+10 &&
                  write_data[i] === pattern(i+10));
        end

        // Una lectura que necesita bajar debe ganar sobre un drenaje nuevo.
        // La línea ya está en la cola cuando se presenta esa lectura.
        reset_buffer(); allow_accept = 0;
        put(20, 20);
        req = 1; line_addr = 70; #1;
        check("lectura sin hit pasa en el mismo ciclo", down_req && !down_we && down_line_addr == 70);
        allow_accept = 1;
        step();
        check("lectura tiene prioridad sobre drenaje", accepted && model_reads == 1 && model_writes == 0);
        req = 0;
        while (!ready) step();
        check("respuesta conserva origen L2", ready_rdata === pattern(70) && resp_src == 1);
        step(); drain_all();

        // Se insertan varias versiones de una dirección. La lectura debe devolver
        // la más reciente, pero la salida debe conservar el orden de llegada.
        // También se verifica que leer la cola no interrumpa una escritura pendiente.
        reset_buffer(); allow_accept = 0;
        for (integer i = 0; i < DEPTH; i++) put(30, i+100);
        read_line(30, pattern(DEPTH+99), 2);
        check("gana duplicado mas nuevo", forwarding_count == 1 && ref_count == DEPTH);
        allow_accept = 1;
        step();
        check("drenaje aceptado", model_accepted && down_we && down_wmask == 32'hffffffff);
        read_line(30, pattern(DEPTH+99), 2);
        check("forwarding durante drenaje aceptado", model_busy && ref_count == DEPTH);
        req = 1; line_addr = 90;
        #1;
        check("lectura no interrumpe drenaje", !ready && !accepted && down_we && down_line_addr == 30);
        while (model_busy) begin
            check("bus de drenaje estable", down_we && down_line_addr == 30 && down_wdata === pattern(100));
            step();
        end
        #1;
        check("lectura pendiente sale antes del siguiente drenaje", down_req && !down_we && down_line_addr == 90);
        read_line(90, pattern(90), 1);
        drain_all();

        // Se llena y se vacía la cola varias veces para hacer que los punteros
        // vuelvan al principio del arreglo. La búsqueda y el orden de salida deben
        // seguir siendo correctos después de esas vueltas.
        for (integer round = 0; round < 3; round++) begin
            before_writes = model_writes;
            allow_accept = 0;
            for (integer i = 0; i < DEPTH; i++) put(40, round*DEPTH+i);
            read_line(40, pattern(round*DEPTH+DEPTH-1), 2);
            allow_accept = 1; drain_all();
            for (integer i = 0; i < DEPTH; i++)
                check("wrap conserva FIFO", write_data[before_writes+i] === pattern(round*DEPTH+i));
        end

        // Las escrituras solo entran mediante push. Un pedido superior con we=1
        // debe quedar sin respuesta y no debe enviarse al nivel inferior.
        reset_buffer();
        we = 1; req = 1; line_addr = 77;
        #1;
        check("puerto superior rechaza escrituras", !ready && !accepted && !down_req);
        step(); we = 0; req = 0;

        // Después de accepted, el emisor puede cambiar sus entradas. El buffer
        // debe conservar la dirección de la lectura original hasta que termine.
        req = 1; line_addr = 72; step();
        check("lectura aceptada una vez", accepted && model_reads == 1);
        req = 0; line_addr = 73;
        while (!ready) begin
            check("direccion aceptada queda guardada", down_line_addr == 72 && !down_we);
            step();
        end
        check("respuesta de la direccion original", ready_rdata === pattern(72));
        step();

        // Se inserta una línea con la misma dirección que una lectura ya enviada.
        // La lectura debe esperar su respuesta inferior y la nueva línea debe
        // permanecer en la cola para escribirse después.
        reset_buffer(); allow_accept = 0;
        req = 1; line_addr = 74; step();
        put(74, 999);
        #1;
        check("lectura presentada no cambia a forwarding", !ready && down_req && !down_we &&
              down_line_addr == 74);
        repeat (3) step();
        allow_accept = 1; step();
        check("lectura pendiente acepta al liberarse abajo", accepted);
        req = 0;
        while (!ready) step();
        check("lectura pendiente conserva respuesta inferior", ready_rdata === pattern(74) && resp_src == 1);
        step(); drain_all();
        check("push durante lectura queda para drenaje", model_writes == 1 && write_data[0] === pattern(999));

        // Se prueban respuestas inmediatas y los tres valores de origen.
        // Una respuesta de origen dos recibida desde abajo debe conservar ese valor,
        // pero no debe aumentar el contador de lecturas resueltas por este buffer.
        reset_buffer(); immediate = 1;
        req = 1; line_addr = 88; #1;
        check("respuesta combinacional sin accepted", down_req && ready && !accepted &&
              ready_rdata === pattern(88) && resp_src == 1);
        step(); req = 0; immediate = 0;
        immediate = 1; source = 2;
        read_line(87, pattern(87), 2);
        immediate = 0; source = 0;
        read_line(89, pattern(89), 0);
        check("sin duplicar lectura tras accepted", model_reads == 1);
        source = 1;

        // Si había espacio, una línea puede entrar en el mismo flanco en que
        // termina otro drenaje. La nueva línea debe conservarse sin alterar el orden.
        if (DEPTH > 1) begin
            reset_buffer(); latency = 10;
            put(60, 60);
            step();
            while (!model_ready) step();
            put(61, 61);
            check("push y drenaje simultaneos", ref_count == 1 && received_count == 2);
            drain_all();
            check("simultaneidad conserva nueva linea", model_writes == 2 && write_addresses[1] == 61);
        end

        // Si la cola estaba llena, el push se rechaza aunque termine una escritura
        // en ese mismo flanco. El emisor debe esperar al espacio disponible después.
        reset_buffer(); allow_accept = 0;
        for (integer i = 0; i < DEPTH; i++) put(100+i, 100+i);
        allow_accept = 1; step();
        while (!model_ready) step();
        put(200, 200);
        check("push con full se rechaza aun al retirar", ref_count == DEPTH-1 && received_count == DEPTH);
        drain_all();

        // La línea insertada queda disponible para lectura después del flanco
        // que la almacena. Se comprueba que pueda responderse desde la cola.
        reset_buffer(); allow_accept = 0;
        push = 1; push_addr = 6; push_data = pattern(6);
        step(); push = 0;
        read_line(6, pattern(6), 2);
        allow_accept = 1; drain_all();

        // Se activa reset mientras hay una escritura pendiente y entre flancos.
        // Las salidas y los contadores deben limpiarse de inmediato. El nivel
        // inferior también se reinicia para descartar su operación pendiente.
        put(7, 7); step();
        #1 rst = 1; #1;
        check("reset asincrono suprime salidas", !down_req && !accepted && !ready && !full &&
              received_count == 0 && forwarding_count == 0 && full_cycles == 0 && max_occupancy == 0);
        reset_buffer();
        check("reset cancela bus", !down_req && !ready && !accepted);

        // Ahora se utiliza main_memory. Primero se comprueba una lectura desde
        // la cola y luego se dejan salir todas las líneas. Al leerlas de nuevo,
        // los datos deben venir de memoria y conservar el contenido escrito.
        // La segunda ronda cambia los datos de las mismas direcciones para detectar
        // valores antiguos y accesos duplicados.
        real_memory = 1;
        reset_buffer();
        for (integer round = 0; round < 2; round++) begin
            for (integer i = 0; i < DEPTH; i++) put(300+i, round*DEPTH+i);
            read_line(300+DEPTH-1, pattern(round*DEPTH+DEPTH-1), 2);
            drain_all();
            for (integer i = 0; i < DEPTH; i++)
                read_line(300+i, pattern(round*DEPTH+i), 0);
        end
        check("memoria real sin escrituras duplicadas", ram_writes == 2*DEPTH && ram_reads == 2*DEPTH);
        check("estadisticas finales", received_count == 2*DEPTH && forwarding_count == 2 &&
              max_occupancy == DEPTH && ref_count == 0);
        $display("DEPTH=%0d; Casos: %0d; Fallos: %0d", DEPTH, casos, fallos);
        finished = 1;
    end
endmodule

// Reúne los resultados de cuatro profundidades. Una entrada prueba el tamaño
// mínimo. Tres entradas comprueban una profundidad que no es potencia de dos.
// Cuatro y ocho entradas corresponden a las dos configuraciones previstas.
module tb_line_buffer;
    wire [3:0] finished;
    wire [31:0] c1, c3, c4, c8, f1, f3, f4, f8;
    line_buffer_checker #(.DEPTH(1)) d1(finished[0], c1, f1);
    line_buffer_checker #(.DEPTH(3)) d3(finished[1], c3, f3);
    line_buffer_checker #(.DEPTH(4)) d4(finished[2], c4, f4);
    line_buffer_checker #(.DEPTH(8)) d8(finished[3], c8, f8);
    initial begin
        // El resultado global se calcula cuando terminan las cuatro instancias.
        wait (&finished);
        $display("Casos: %0d; Fallos: %0d", c1+c3+c4+c8, f1+f3+f4+f8);
        if (f1+f3+f4+f8 != 0) $fatal(1, "FAIL tb_line_buffer");
        $display("PASS tb_line_buffer");
        $finish;
    end
    initial begin
        // Este límite termina la simulación con error si alguna instancia queda
        // esperando para siempre y no llega a entregar su resultado.
        #500000;
        $fatal(1, "FAIL tb_line_buffer: limite global");
    end
endmodule
