`timescale 1ns/1ps

// Plan de implementación, tarea 9: vectores y fronteras de lectura.
module tb_imem;
    localparam int DEPTH = 4096;
    localparam logic [127:0] BUNDLE0 = 128'h00000000_00000000_49400003_49000000;
    localparam logic [127:0] BUNDLE2 = 128'h00000000_0D500000_00000000_41100001;
    // ROM síncrona (P2 §3.2.1; D6): el bundle aparece un flanco de subida después de addr.
    logic clk = 1'b0;
    logic rst = 1'b0;
    logic en = 1'b1;
    logic flush = 1'b0;
    always #5 clk = ~clk;
    logic [21:0] addr = '0;
    logic [127:0] rdata, rdata_comentado, rdata_vacio, rdata_tres, rdata_uno;
    int casos = 0;
    int fallos = 0;

    imem #(.INIT_FILE("programs/ejemplo_isa11.hex"))
        u_imem (.clk, .rst, .flush, .en, .addr, .rdata);
    imem #(.INIT_FILE("programs/ejemplo_isa11_comentado.hex"))
        u_comentado (.clk, .rst, .flush, .en, .addr, .rdata(rdata_comentado));
    imem u_vacio (.clk, .rst, .flush, .en, .addr, .rdata(rdata_vacio));
    // Profundidad no potencia de dos: el comparador debe rechazar índice 3.
    imem #(.DEPTH(3), .INIT_FILE("programs/ejemplo_isa11.hex"))
        u_tres (.clk, .rst, .flush, .en, .addr, .rdata(rdata_tres));
    imem #(.DEPTH(1)) u_uno (.clk, .rst, .flush, .en, .addr, .rdata(rdata_uno));

    task automatic check(input string nombre,
        input logic [127:0] obtenido, esperado);
        casos++;
        if (obtenido === esperado) $display("PASS %s", nombre);
        else begin
            fallos++;
            $display("FAIL %s: obtenido=%032h esperado=%032h", nombre, obtenido, esperado);
        end
    endtask

    task automatic leer(input string nombre,
        input logic [21:0] direccion,
        input logic [127:0] esperado);
        @(negedge clk);
        addr = direccion;
        @(posedge clk); #1; // Lectura síncrona: el bundle llega un flanco después.
        check({nombre, " archivo normal"}, rdata, esperado);
        check({nombre, " archivo comentado"}, rdata_comentado, esperado);
        check({nombre, " sin INIT_FILE"}, rdata_vacio, 128'b0);
        check({nombre, " DEPTH=3"}, rdata_tres, esperado);
        check({nombre, " DEPTH=1 sin archivo"}, rdata_uno, 128'b0);
    endtask

    // en = 0 conserva el bundle aunque addr cambie y pasen flancos (pausa, D9); al volver en = 1 carga.
    task automatic prueba_en0();
        @(negedge clk); addr = 0; en = 1'b1;
        @(posedge clk); #1;
        check("en=0 previo: bundle 0", rdata, BUNDLE0);
        @(negedge clk); en = 1'b0; addr = 2;
        repeat (3) @(posedge clk);
        #1;
        check("en=0 conserva (3 flancos, addr distinta)", rdata, BUNDLE0);
        check("en=0 conserva archivo comentado", rdata_comentado, BUNDLE0);
        @(negedge clk); en = 1'b1;
        @(posedge clk); #1;
        check("en=1 carga el bundle de la nueva addr", rdata, BUNDLE2);
    endtask

    // flush síncrono: pone rdata en 0 en el flanco, tiene prioridad sobre en y no actúa antes del flanco.
    task automatic prueba_flush();
        @(negedge clk); addr = 0; en = 1'b1; flush = 1'b0;
        @(posedge clk); #1;
        check("flush previo: bundle 0", rdata, BUNDLE0);
        @(negedge clk); addr = 2; flush = 1'b1;
        #1;
        check("flush es sincrono: rdata no cambia antes del flanco", rdata, BUNDLE0);
        @(posedge clk); #1;
        check("flush pone rdata en 0 (en=1)", rdata, 128'b0);
        check("flush archivo comentado", rdata_comentado, 128'b0);
        @(negedge clk); en = 1'b0;
        @(posedge clk); #1;
        check("flush con en=0 pone rdata en 0 (prioridad sobre en)", rdata, 128'b0);
        // Con en=0 y flush=0 conserva el cero aunque addr apunte a un bundle no nulo.
        @(negedge clk); flush = 1'b0;
        @(posedge clk); #1;
        check("sin flush y en=0 conserva el cero", rdata, 128'b0);
        @(negedge clk); en = 1'b1;
        @(posedge clk); #1;
        check("tras flush carga normalmente", rdata, BUNDLE2);
    endtask

    // Reset asíncrono pone la salida en cero y tiene prioridad sobre en.
    task automatic prueba_reset();
        #1 rst = 1'b1; #1;
        check("reset asincrono pone rdata en 0", rdata, 128'b0);
        @(posedge clk); #1;
        check("reset mantiene rdata en 0 con en=1", rdata, 128'b0);
        @(negedge clk); rst = 1'b0;
        @(posedge clk); #1;
        check("tras reset carga addr", rdata, BUNDLE2);
    endtask

    initial begin
        $dumpfile("build/tb_imem.vcd");
        $dumpvars(0, tb_imem);
        // Esperados literales del programa oficial, no calculados desde DUT.
        leer("bundle 0", 0, BUNDLE0);
        leer("bundle 1 nopi", 1, 128'b0);
        leer("bundle 2", 2, BUNDLE2);
        leer("posicion 3 no cargada o fuera de rango", 3, 128'b0);
        leer("ultima posicion de ROM grande", DEPTH-1, 128'b0);
        leer("primera fuera de rango", DEPTH, 128'b0);
        leer("segunda fuera de rango", DEPTH+1, 128'b0);
        leer("direccion maxima del PC", 22'h3FFFFF, 128'b0);
        leer("bits bajos cero sin reflejar bundle 0", 22'h100000, 128'b0);
        leer("retorno a direccion valida", 0, BUNDLE0);
        prueba_en0();
        prueba_flush();
        prueba_reset();
        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_imem");
        $display("PASS tb_imem");
        $finish;
    end
endmodule
