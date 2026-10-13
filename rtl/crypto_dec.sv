`timescale 1ns/1ps

// Traduce el campo funct de la instrucción a una operación interna de CRYPTO.
// Se conecta dentro de dispatch, antes de los registros ID/EX.
// No comprueba permisos: crypto_control los evalúa durante la ejecución en EX.
module crypto_dec (
    input  logic [4:0] funct,     // Contiene los cinco bits del código de instrucción.
    output logic [2:0] crypto_op, // Entrega la operación 000..110; convierte códigos libres a NOP.
    output logic       we         // Vale 1 solo para feis, que produce un resultado para rd.
);
    logic invalido;

    // Los códigos válidos van de 00000 a 00110.
    // Rechaza cualquier bit alto activo y también el código bajo 111.
    // | aplica OR bit a bit; & reúne las condiciones del código 111.
    assign invalido = funct[4] | funct[3] | (funct[2] & funct[1] & funct[0]);

    // Conserva los tres bits bajos solo después de validar los cinco bits.
    // Así, por ejemplo, 01001 no se convierte accidentalmente en feis (001).
    // assign señal = condición ? valor_si_se_cumple : valor_si_no_se_cumple;
    assign crypto_op = invalido ? 3'b000 : funct[2:0];

    // Compara el código completo: solo 00001 habilita escritura en rd.
    // Este permiso de escritura aún depende de la autorización y validez en EX.
    assign we = (funct == 5'b00001);
endmodule
