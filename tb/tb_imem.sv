`timescale 1ns/1ps

// Plan de implementación, tarea 9: vectores y fronteras de lectura.
module tb_imem;
    localparam int DEPTH = 4096;
    localparam logic [127:0] BUNDLE0 = 128'h00000000_00000000_49400003_49000000;
    localparam logic [127:0] BUNDLE2 = 128'h00000000_0D500000_00000000_41100001;
    logic [21:0] addr = '0;
    logic [127:0] rdata, rdata_comentado, rdata_vacio, rdata_tres, rdata_uno;
    int casos = 0;
    int fallos = 0;

    imem #(.INIT_FILE("programs/ejemplo_isa11.hex"))
        u_imem (.addr, .rdata);
    imem #(.INIT_FILE("programs/ejemplo_isa11_comentado.hex"))
        u_comentado (.addr, .rdata(rdata_comentado));
    imem u_vacio (.addr, .rdata(rdata_vacio));
    // Profundidad no potencia de dos: el comparador debe rechazar índice 3.
    imem #(.DEPTH(3), .INIT_FILE("programs/ejemplo_isa11.hex"))
        u_tres (.addr, .rdata(rdata_tres));
    imem #(.DEPTH(1)) u_uno (.addr, .rdata(rdata_uno));

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
        addr = direccion;
        #1; // Lectura combinacional; no existe clk en imem.
        check({nombre, " archivo normal"}, rdata, esperado);
        check({nombre, " archivo comentado"}, rdata_comentado, esperado);
        check({nombre, " sin INIT_FILE"}, rdata_vacio, 128'b0);
        check({nombre, " DEPTH=3"}, rdata_tres, esperado);
        check({nombre, " DEPTH=1 sin archivo"}, rdata_uno, 128'b0);
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
        $display("Casos: %0d; Fallos: %0d", casos, fallos);
        if (fallos != 0) $fatal(1, "FAIL tb_imem");
        $display("PASS tb_imem");
        $finish;
    end
endmodule
