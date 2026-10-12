// tb_icarus.sv — Tarea 1 del plan (F-03).
// Comprueba que la version de Icarus acepta arreglos EMPAQUETADOS como puertos
// de modulo (logic [N-1:0][W-1:0]). Las cabeceras de regfile, dispatch y core
// dependen de esto (microarchitecture.md §3.1 y §4.3; DA-16).
// Esperado: imprime "PASS". Si imprime "FAIL" o no compila, AVISAR antes de
// que nadie escriba codigo: habria que cambiar esas cabeceras.

module icarus_empaquetado (
  input  logic [7:0][3:0] a,     // 8 elementos de 4 bits, como raddr del regfile
  output logic [7:0][3:0] y
);
  assign y = a;
endmodule

module tb_icarus;
  logic [7:0][3:0] a, y;

  icarus_empaquetado u_dut (.a(a), .y(y));

  initial begin
    $dumpfile("tb_icarus.vcd");
    $dumpvars(0, tb_icarus);

    a = 32'h06000043;            // elementos: y[0]=3, y[1]=4, y[6]=6
    #1;
    if (y[0] == 4'd3 && y[1] == 4'd4 && y[6] == 4'd6)
      $display("PASS arreglos empaquetados como puertos");
    else
      $display("FAIL arreglos empaquetados: y=%h", y);
    $finish;
  end
endmodule
