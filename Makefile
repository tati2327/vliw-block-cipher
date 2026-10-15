# Ejecuta los testbenches existentes y los de CRYPTO desde la raíz del repo.
IV   = iverilog -g2012 -Wall
RTL  = $(wildcard rtl/*.sv)
PROV = $(wildcard rtl/prov/*.sv)
TBS  = $(patsubst tb/%.sv,%,$(wildcard tb/tb_*.sv))
CRYPTO_TBS = tb_auth_hash32 tb_key_vault tb_crypto_state tb_crypto_control tb_crypto_datapath tb_crypto_dec tb_lamport tb_crypto_unit

.PHONY: all sim crypto lamport clean help waves_prog FORCE

all: $(TBS)
crypto: $(CRYPTO_TBS)

# make sim: sin PROG corre todos los TB (alias de all); con PROG corre solo ese programa.
# Variables: PROG (nombre o ruta, con o sin .hex/.asm), DATA, EXP, DESDE, HASTA (byte address,
# decimal o 0x..) y ASM (ensamblador; se usa si falta el .hex o el .asm es más nuevo).
ASM ?= python3 tools/asm.py
ifdef PROG
PROG_SIN  = $(patsubst %.hex,%,$(patsubst %.asm,%,$(PROG)))
BASE      = $(if $(findstring /,$(PROG_SIN)),$(PROG_SIN),programs/$(PROG_SIN))
NAME      = $(notdir $(BASE))
OUT       = build/$(NAME)
DATA_USO  = $(if $(DATA),$(DATA),$(if $(wildcard $(BASE).mem),$(BASE).mem))
EXP_USO   = $(if $(EXP),$(EXP),$(if $(wildcard $(BASE).exp.mem),$(BASE).exp.mem))
DESDE_DEC = $(if $(DESDE),$(shell printf '%d' $(DESDE)))
HASTA_DEC = $(if $(HASTA),$(shell printf '%d' $(HASTA)))

sim:
	@test -f $(BASE).hex || test -f $(BASE).asm || { echo "No existe $(BASE).hex ni $(BASE).asm"; exit 1; }
	@if [ -f $(BASE).asm ] && { [ ! -f $(BASE).hex ] || [ $(BASE).asm -nt $(BASE).hex ]; }; then \
		echo "Ensamblando $(BASE).asm"; $(ASM) $(BASE).asm -o $(BASE).hex || exit 1; \
	fi
	@mkdir -p $(OUT)
	$(IV) -I data/lamport_demo -s tb_programa -o $(OUT)/tb_programa \
		'-DPROG_HEX="$(BASE).hex"' '-DPROG_MEM="$(DATA_USO)"' '-DEXP_MEM="$(EXP_USO)"' \
		$(if $(DESDE),-DMEM_DESDE=$(DESDE_DEC)) $(if $(HASTA),-DMEM_HASTA=$(HASTA_DEC)) \
		$(RTL) $(PROV) tb/tb_programa.sv
	@vvp $(OUT)/tb_programa; rc=$$?; \
	cp build/tb_programa.vcd $(OUT)/ondas.vcd; cp build/tb_programa_dump.mem $(OUT)/dump.mem; \
	echo "Ondas: $(OUT)/ondas.vcd"; echo "Volcado: $(OUT)/dump.mem"; exit $$rc
else
sim: all
endif

# Abre las ondas de la última corrida de make sim PROG=...
waves_prog:
	@test -n "$(PROG)" || { echo "Uso: make waves_prog PROG=<programa>"; exit 1; }
	gtkwave build/$(notdir $(patsubst %.hex,%,$(patsubst %.asm,%,$(PROG))))/ondas.vcd

help:
	@printf '%s\n' \
		'Targets:' \
		'  all               corre todos los testbenches' \
		'  sim               alias de all; con PROG corre solo ese programa' \
		'  crypto            corre los testbenches de CRYPTO' \
		'  lamport           regenera la cadena Lamport en data/lamport_demo' \
		'  tb_<nombre>       corre un testbench (tb/tb_<nombre>.sv)' \
		'  waves_<tb>        corre el testbench y abre sus ondas en gtkwave' \
		'  waves_prog        abre las ondas de la última corrida de make sim PROG=...' \
		'  clean             borra build/ y los .vcd' \
		'' \
		'make sim PROG=<programa> [DATA=...] [EXP=...] [DESDE=...] [HASTA=...] [ASM=...]' \
		'  PROG   nombre (ej1 -> programs/ej1) o ruta, con o sin .hex/.asm' \
		'          usa <base>.hex; ensambla <base>.asm con ASM si el .hex falta o es más viejo' \
		'  DATA   memoria de datos (.mem); por defecto <base>.mem si existe' \
		'  EXP    memoria esperada (.mem); por defecto <base>.exp.mem si existe, si no no compara' \
		'  DESDE, HASTA  rango de memoria a listar, en bytes (decimal o 0x..)' \
		'  ASM    ensamblador; por defecto python3 tools/asm.py' \
		'  Salida en build/<nombre>/ondas.vcd y build/<nombre>/dump.mem' \
		'' \
		'Ejemplos:' \
		'  make sim PROG=ej1' \
		'  make sim PROG=programs/ejercicio3 DATA=build/cifrado_datos.mem' \
		'  make sim PROG=programs/mi_prueba DESDE=0x40 HASTA=0x60'

# Regenera la cadena reproducible de Café de CE y comprueba los vectores externos.
lamport:
	python3 tools/lamport.py --self-test --seed 0xCAFEDECE --length 100 --out data/lamport_demo

tb_crypto_state tb_lamport tb_crypto_unit: lamport

# Selecciona el TB como raíz; evita simular módulos ajenos no instanciados.
# FORCE ejecuta las comprobaciones incluso si existe un archivo llamado tb_nombre.
tb_%: tb/tb_%.sv FORCE
	@mkdir -p build
	$(IV) -I data/lamport_demo -s $@ -o build/$@ $(RTL) $(PROV) $<
	vvp build/$@

# Los nuevos TB de CRYPTO generan sus archivos VCD dentro de build/.
waves_%: tb_% FORCE
	gtkwave build/tb_$*.vcd

FORCE:

clean:
	rm -rf build *.vcd
