`timescale 1ns/1ps

// Guarda líneas modificadas que todavía deben escribirse en el nivel inferior.
// La cola es FIFO, por lo que la primera línea que entra es la primera que sale.
// Cada entrada contiene una línea completa de 32 bytes y su dirección.
//
// Una lectura puede recibir sus datos directamente de la cola. Esta entrega se
// llama forwarding y evita esperar al nivel inferior. Si una dirección aparece
// varias veces, se devuelve la versión que ingresó más recientemente.
//
// El drenaje escribe la línea más antigua en el nivel inferior. La línea permanece
// disponible para lectura hasta que termine esa escritura. Mientras tanto, pueden
// entrar otras líneas si queda espacio y pueden resolverse lecturas por forwarding.
module line_buffer #(
    parameter int DEPTH = 4
) (
    // Todos los puertos usan el mismo reloj. El reset se activa con rst=1 y
    // limpia el estado de inmediato, sin esperar un flanco de reloj.
    input  logic clk, rst,
    // El nivel superior presenta una lectura con req=1 y we=0. line_addr contiene
    // los bits de dirección que identifican la línea, sin el desplazamiento de byte.
    // wdata y wmask forman parte de la interfaz común, pero este puerto no los usa.
    //
    // accepted indica que el pedido fue recibido. ready indica que sus datos ya
    // están disponibles y deben consumirse en el siguiente flanco ascendente.
    // Una respuesta inmediata puede dar ready sin un pulso previo de accepted.
    input  logic req, we,
    input  logic [10:0] line_addr,
    input  logic [255:0] wdata,
    input  logic [31:0] wmask,
    output logic accepted, ready,
    output logic [255:0] ready_rdata,
    output logic [1:0] resp_src,
    // push solicita guardar la línea completa de push_data con su push_addr.
    // Se almacena en el flanco ascendente solo si full=0. Si full=1, el emisor
    // debe esperar y volver a presentar la línea cuando haya espacio.
    input  logic push,
    input  logic [10:0] push_addr,
    input  logic [255:0] push_data,
    output logic full,
    // Estas señales forman el canal hacia el nivel inferior. El buffer inicia
    // por él las lecturas pendientes y las escrituras de drenaje, una a la vez.
    // down_resp_src identifica de dónde salió una lectura y se devuelve sin cambios.
    output logic down_req, down_we,
    output logic [10:0] down_line_addr,
    output logic [255:0] down_wdata,
    output logic [31:0] down_wmask,
    input  logic down_accepted, down_ready,
    input  logic [255:0] down_ready_rdata,
    input  logic [1:0] down_resp_src,
    // Los contadores registran líneas recibidas, lecturas resueltas por forwarding,
    // ciclos con la cola llena y la mayor ocupación alcanzada desde el último reset.
    // Los contadores de eventos vuelven a cero si desbordan sus 64 bits.
    output logic [63:0] received_count, forwarding_count, full_cycles,
    output logic [63:0] max_occupancy
);
    // Los punteros identifican una de las DEPTH posiciones. La ocupación necesita
    // representar también DEPTH, que corresponde a la cola completamente llena.
    // Se reserva al menos un bit para permitir una cola de una sola entrada.
    localparam int PTR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;
    localparam int COUNT_W = (DEPTH > 1) ? $clog2(DEPTH+1) : 1;
    // IDLE elige el próximo acceso. READ_REQ y DRAIN_REQ esperan que el nivel
    // inferior acepte el pedido. READ_WAIT y DRAIN_WAIT esperan que lo termine.
    // Si la respuesta es inmediata, no hace falta pasar por un estado de espera.
    typedef enum logic [2:0] {IDLE, READ_REQ, READ_WAIT, DRAIN_REQ, DRAIN_WAIT} state_t;
    state_t state;
    // head identifica la línea más antigua y tail la posición donde entrará la
    // próxima. occupancy indica cuántas entradas son válidas y permite distinguir
    // una cola llena de una vacía cuando ambos punteros tienen el mismo valor.
    logic [10:0] addresses [0:DEPTH-1];
    logic [255:0] lines [0:DEPTH-1];
    logic [PTR_W-1:0] head, tail;
    logic [COUNT_W-1:0] occupancy;
    // Se conserva la dirección porque el lector puede bajar req y cambiar sus
    // entradas después de recibir accepted, aunque la lectura siga pendiente.
    logic [10:0] saved_read_addr;
    // hit indica que la dirección está en la cola. forward_read señala que esa
    // coincidencia puede usarse para responder ahora. read_route y drain_route
    // distinguen si el acceso inferior pertenece a una lectura o a un drenaje.
    logic hit, forward_read, read_route, drain_route;
    logic [255:0] hit_data;
    logic enqueue, dequeue;

    initial begin
        if (DEPTH < 1) $fatal(1, "line_buffer: DEPTH debe ser positivo");
    end

    // La búsqueda responde en el mismo ciclo, sin esperar un flanco de reloj.
    // Recorre las entradas válidas desde la más antigua hasta la más reciente.
    // Cada coincidencia reemplaza el resultado anterior, por lo que al terminar
    // queda seleccionada la versión más nueva de la dirección solicitada.
    always_comb begin : lookup
        integer index;
        hit = 0;
        hit_data = '0;
        index = 0;
        for (integer i = 0; i < DEPTH; i = i+1) begin
            // Al llegar al final del arreglo, la búsqueda continúa desde cero.
            // Como head+i es menor que 2*DEPTH, basta restar DEPTH una vez.
            index = int'(head) + i;
            if (index >= DEPTH) index = index - DEPTH;
            if (i < occupancy && addresses[index] == line_addr) begin
                hit = 1;
                hit_data = lines[index];
            end
        end
    end

    // full refleja el espacio disponible antes del flanco. Una cola llena rechaza
    // el push aunque una escritura termine y libere espacio en ese mismo flanco.
    assign full = !rst && occupancy == DEPTH;
    assign enqueue = !rst && push && !full;
    // Una lectura ya enviada al nivel inferior espera su respuesta, aunque luego
    // ingrese a la cola una línea con la misma dirección. Durante un drenaje, en
    // cambio, una lectura nueva sí puede recibir datos directamente de la cola.
    assign forward_read = !rst && req && !we && hit &&
                          state != READ_REQ && state != READ_WAIT;
    // La aceptación de un drenaje todavía no libera espacio. La línea se retira
    // únicamente cuando down_ready confirma que terminó la escritura.
    assign dequeue = !rst && drain_route && down_ready;

    // El pedido y sus datos permanecen estables hasta que el nivel inferior lo
    // acepta. También puede terminar de inmediato si ese nivel activa ready.
    always_comb begin
        // Todas las salidas reciben un valor por defecto en cada evaluación.
        // Así no conservan valores de una evaluación anterior y quedan inactivas
        // durante reset. Los casos siguientes activan solo las señales necesarias.
        down_req = 0; down_we = 0; down_line_addr = '0;
        down_wdata = '0; down_wmask = '0;
        accepted = 0; ready = 0; ready_rdata = '0; resp_src = 0;
        read_route = 0; drain_route = 0;
        if (!rst) begin
            case (state)
                IDLE: begin
                    // Una lectura que necesita el nivel inferior tiene prioridad
                    // sobre un drenaje nuevo. Si sus datos están en la cola, puede
                    // responderse por forwarding mientras comienza el drenaje.
                    if (req && !we && !hit) begin
                        read_route = 1;
                        down_req = 1;
                        down_line_addr = line_addr;
                    end else if (occupancy != 0) begin
                        drain_route = 1;
                        down_req = 1;
                    end
                end
                READ_REQ, READ_WAIT: begin
                    // down_req baja en cuanto se observa down_accepted. Mantenerlo
                    // activo podría hacer que el mismo pedido se aceptara otra vez.
                    // La dirección guardada sigue disponible mientras llega ready.
                    read_route = 1;
                    down_req = state == READ_REQ && !down_accepted;
                    down_line_addr = saved_read_addr;
                end
                DRAIN_REQ, DRAIN_WAIT: begin
                    // Un drenaje ya presentado conserva el canal hasta terminar.
                    // Una lectura que llegue después espera, salvo que encuentre
                    // sus datos en la cola y pueda responderse por forwarding.
                    drain_route = 1;
                    down_req = state == DRAIN_REQ && !down_accepted;
                end
                default: begin end
            endcase
            // head permanece en la misma entrada hasta completar el drenaje, por
            // lo que su dirección y sus datos no cambian durante la espera.
            // Cada bit de la máscara habilita un byte. Todos se activan para
            // escribir los 32 bytes de la línea.
            if (drain_route) begin
                down_we = 1;
                down_line_addr = addresses[head];
                down_wdata = lines[head];
                down_wmask = '1;
            end
            // Solo las respuestas de una lectura se entregan al nivel superior.
            // La aceptación y la terminación de un drenaje se consumen aquí.
            if (read_route) begin
                accepted = down_accepted;
                ready = down_ready;
                ready_rdata = down_ready_rdata;
                resp_src = down_resp_src;
            end
            // El forwarding entrega datos directamente de la cola y no necesita
            // el canal inferior. Por eso puede terminar durante un drenaje.
            if (forward_read) begin
                ready = 1;
                ready_rdata = hit_data;
                // El valor 2 identifica una respuesta obtenida de este buffer.
                resp_src = 2;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Vaciar la ocupación hace que todas las entradas dejen de ser válidas.
            // No hace falta borrar los datos almacenados en los arreglos.
            state <= IDLE;
            head <= 0; tail <= 0; occupancy <= 0; saved_read_addr <= 0;
            received_count <= 0; forwarding_count <= 0;
            full_cycles <= 0; max_occupancy <= 0;
        end else begin
            // Se revisa ready antes que accepted porque una respuesta puede llegar
            // sin una fase de aceptación separada. En ese caso, el acceso ya terminó.
            case (state)
                IDLE: begin
                    if (read_route) begin
                        // El pedido inicial llega abajo en el mismo ciclo. Se
                        // guarda su dirección para mantenerlo si debe esperar.
                        saved_read_addr <= line_addr;
                        if (!down_ready) state <= READ_REQ;
                    end else if (drain_route && !down_ready) state <= DRAIN_REQ;
                end
                READ_REQ: begin
                    if (down_ready) state <= IDLE;
                    else if (down_accepted) state <= READ_WAIT;
                end
                READ_WAIT: if (down_ready) state <= IDLE;
                DRAIN_REQ: begin
                    if (down_ready) state <= IDLE;
                    else if (down_accepted) state <= DRAIN_WAIT;
                end
                DRAIN_WAIT: if (down_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
            // La entrada y la salida usan el espacio que había antes del flanco.
            // Al llegar a DEPTH-1, cada puntero vuelve a cero. Esto también permite
            // profundidades que no sean potencias de dos.
            if (enqueue) begin
                addresses[tail] <= push_addr;
                lines[tail] <= push_data;
                if (int'(tail) == DEPTH-1) tail <= 0;
                else tail <= tail + 1'b1;
                received_count <= received_count + 1;
            end
            if (dequeue) begin
                if (int'(head) == DEPTH-1) head <= 0;
                else head <= head + 1'b1;
            end
            // Si entra una línea y sale otra en el mismo flanco, la ocupación se
            // mantiene. Si solo entra una línea, aumenta y puede establecer un
            // nuevo máximo. Si solo sale una línea, disminuye.
            case ({enqueue, dequeue})
                2'b10: begin
                    occupancy <= occupancy + 1;
                    if (64'(occupancy) + 64'd1 > max_occupancy)
                        max_occupancy <= 64'(occupancy) + 64'd1;
                end
                2'b01: occupancy <= occupancy - 1;
                default: begin end
            endcase
            // Cada lectura resuelta por forwarding se cuenta cuando se consume.
            // full_cycles aumenta en cada ciclo con la cola llena, incluso si en
            // ese ciclo nadie intenta insertar otra línea.
            if (forward_read) forwarding_count <= forwarding_count + 1;
            if (full) full_cycles <= full_cycles + 1;
        end
    end
endmodule
