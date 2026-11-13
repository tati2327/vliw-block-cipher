`timescale 1ns/1ps

module auth_lsu_checker #(parameter int DIV=4, parameter bit FAST=0)
    (output logic finished=0, output integer casos=0, fallos=0);
    localparam int TMEM=25+7*DIV;
    logic clk=0, rst=0;
    always #5 clk=~clk;
    wire [63:0] cycles, pauses;
    wire [31:0] value, stored, copy_value;
    wire session, exception;
    wire commit, selected;
    wire [2:0] op;
    wire start_auth, req, we, ready;
    wire [21:0] id_pc;
    wire id_valid;
    integer starts=0, auths=0, loads=0, stores=0;
    generate if (!FAST) begin : slow
        top #(.IMEM_INIT("programs/auth_lsu.hex"), .DMEM_INIT("programs/auth_lsu.mem"), .MEM_DIV(DIV)) dut(.clk,.rst);
        assign cycles=dut.u_core.u_perf_counters.ciclos;
        assign pauses=dut.u_core.u_perf_counters.pausa_total;
        assign value=dut.u_core.u_regfile.regs[7];
        assign stored=dut.u_memory.mem[16]; assign copy_value=dut.u_memory.mem[17];
        assign session=dut.u_core.u_crypto.auth; assign exception=dut.u_core.u_crypto.exc;
        assign commit=dut.u_core.ex_commit; assign selected=dut.u_core.idex_s1_sel;
        assign op=dut.u_core.idex_s1_crypto_op;
        assign start_auth=dut.u_core.u_crypto.auth_start;
        assign req=dut.dmem_req; assign we=dut.dmem_we; assign ready=dut.dmem_listo;
        assign id_pc=dut.u_core.ifid_pc; assign id_valid=dut.u_core.ifid_valid;
        // Muestra las señales consumidas antes del flanco y los pulsos registrados después.
        always @(posedge clk) begin : trace_memory_bundle
            integer c, ex_pc;
            logic request_before, ready_before, stall_before, saved_before, commit_before, crypto_before;
            if ($test$plusargs("TRACE_BASELINE") && DIV==4 && !rst &&
                dut.u_core.ex_valid && (dut.u_core.idex_pc==0 || dut.u_core.idex_pc==5)) begin
                c=32'(cycles+1); ex_pc=dut.u_core.idex_pc;
                request_before=req; ready_before=ready;
                stall_before=dut.u_core.mem_stall; saved_before=dut.u_core.hecho;
                commit_before=commit; crypto_before=dut.u_core.crypto_stall;
                #1;
                $display("TRACE c=%0d EX=%0d req=%b accepted=%b done=%b listo=%b mem_stall=%b hecho=%b commit=%b crypto=%b",
                         c,ex_pc,request_before,dut.u_memory.accepted,dut.u_memory.done,ready_before,
                         stall_before,saved_before,commit_before,crypto_before);
            end
        end
    end else begin : fast
        logic [21:0] address;
        logic en, flush;
        logic [127:0] bundle;
        logic [31:0] addr,wdata,rdata;
        logic [3:0] be;
        core dut(.clk,.rst,.init_anchor(rst),.imem_addr(address),.imem_en(en),.imem_flush(flush),.imem_rdata(bundle),
                 .dmem_req(req),.dmem_we(we),.dmem_addr(addr),.dmem_wdata(wdata),.dmem_be(be),.dmem_rdata(rdata),.dmem_listo(ready));
        imem #(.INIT_FILE("programs/auth_lsu.hex")) rom(.clk,.rst,.en,.flush,.addr(address),.rdata(bundle));
        memory #(.INIT_FILE("programs/auth_lsu.mem")) ram(.clk,.addr,.wdata,.we,.be,.rdata);
        assign ready=req;
        assign cycles=dut.u_perf_counters.ciclos; assign pauses=dut.u_perf_counters.pausa_total;
        assign value=dut.u_regfile.regs[7]; assign stored=ram.mem[16]; assign copy_value=ram.mem[17];
        assign session=dut.u_crypto.auth; assign exception=dut.u_crypto.exc;
        assign commit=dut.ex_commit; assign selected=dut.idex_s1_sel; assign op=dut.idex_s1_crypto_op;
        assign start_auth=dut.u_crypto.auth_start; assign id_pc=dut.ifid_pc; assign id_valid=dut.ifid_valid;
    end endgenerate
    task automatic check(input string name, input logic ok);
        casos++; if(ok !== 1'b1) begin fallos++; $display("FAIL auth_lsu DIV=%0d FAST=%b %s",DIV,FAST,name); end
    endtask
    always @(posedge clk) if(!rst) begin
        if(start_auth) starts++;
        if(commit && selected && op==2) auths++;
        if(req && ready) begin if(we) stores++; else loads++; end
    end
    initial begin
        #1 rst=1; repeat(3) @(negedge clk); rst=0;
        do begin @(negedge clk); #2; end while(!(id_valid && id_pc==13));
        check("lw recibe dato",value===32'h1234abcd);
        check("store y copia correctos",stored===32'h1234abcd && copy_value===32'h1234abcd);
        check("auth valida sin excepcion",session && !exception);
        check("sin repetir hash",starts==2 && auths==2);
        check("un pedido por operacion",loads==4 && stores==2);
        check("latencia y solape",cycles==(FAST ? 41 : 41+6*TMEM - 26));
        check("pausas combinadas",pauses==(FAST ? 26 : 6*TMEM));
        $display("auth_lsu MEM_DIV=%0d FAST=%b ciclos=%0d; Casos: %0d; Fallos: %0d",DIV,FAST,cycles,casos,fallos);
        finished=1;
    end
endmodule
module tb_auth_lsu;
    wire [3:0] finished;
    wire [31:0] c2,c4,c5,cf,f2,f4,f5,ff;
    auth_lsu_checker #(.DIV(2)) a2(finished[0],c2,f2);
    auth_lsu_checker #(.DIV(4)) a4(finished[1],c4,f4);
    auth_lsu_checker #(.DIV(5)) a5(finished[2],c5,f5);
    auth_lsu_checker #(.FAST(1)) af(finished[3],cf,ff);
    initial begin wait(&finished); $display("Casos: %0d; Fallos: %0d",c2+c4+c5+cf,f2+f4+f5+ff);
        if(f2+f4+f5+ff) $fatal(1,"FAIL tb_auth_lsu");
        $display("PASS tb_auth_lsu"); $finish; end
    initial begin #20000; $fatal(1,"FAIL auth_lsu limite global"); end
endmodule
