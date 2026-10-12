# Makefile minimo del procesador VLIW — Grupo 6
# Uso:   make tb_<nombre>   compila rtl/ + rtl/prov/ + tb/tb_<nombre>.sv y simula
#        make all           corre todos los testbenches de tb/
#        make clean         borra build/ y los .vcd

IV   = iverilog -g2012 -Wall
RTL  = $(wildcard rtl/*.sv)
PROV = $(wildcard rtl/prov/*.sv)
TBS  = $(patsubst tb/%.sv,%,$(wildcard tb/tb_*.sv))

.PHONY: all clean

all: $(TBS)

tb_%: tb/tb_%.sv
	@mkdir -p build
	$(IV) -o build/$@ $(RTL) $(PROV) $<
	vvp build/$@

clean:
	rm -rf build *.vcd
