# Ejecuta los testbenches existentes y los de CRYPTO desde la raíz del repo.
IV   = iverilog -g2012 -Wall
RTL  = $(wildcard rtl/*.sv)
PROV = $(wildcard rtl/prov/*.sv)
TBS  = $(patsubst tb/%.sv,%,$(wildcard tb/tb_*.sv))
CRYPTO_TBS = tb_auth_hash32 tb_key_vault tb_crypto_state tb_crypto_control tb_crypto_datapath tb_crypto_dec tb_lamport tb_crypto_unit

.PHONY: all sim crypto lamport clean help waves_prog mem FORCE datos_bench metricas test_benchmarks costos_bench

all: $(TBS)
crypto: $(CRYPTO_TBS)

# make sim: sin PROG corre todos los TB (alias de all); con PROG corre solo ese programa.
# Variables: PROG (nombre o ruta, con o sin .hex/.asm), DATA, EXP, DESDE, HASTA (byte address,
# decimal o 0x..) y ASM (ensamblador; se usa si falta el .hex o el .asm es más nuevo).
ASM ?= python3 tools/asm.py
MEM_DIV ?= 4
CACHE ?= 2
MAX_CYCLES ?= 2000000
WAVES ?= 1
VVP_ARGS ?=
ifdef PROG
PROG_SIN  = $(patsubst %.hex,%,$(patsubst %.asm,%,$(PROG)))
BASE      = $(if $(findstring /,$(PROG_SIN)),$(PROG_SIN),programs/$(PROG_SIN))
NAME      = $(notdir $(BASE))
BENCH_FLAGS := $(shell python3 tools/bench_data.py metadata $(BASE).asm)
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
	@mkdir -p "$(OUT)"
	$(IV) -I data/lamport_demo -s tb_programa -o "$(OUT)/tb_programa" \
		-DCACHE=$(CACHE) -DMEM_DIV=$(MEM_DIV) -DSIM_MAX_CYCLES=$(MAX_CYCLES) -DWAVES=$(WAVES) $(BENCH_FLAGS) '-DOUT_DIR="$(OUT)"' '-DWAVE_FILE="$(OUT)/ondas.vcd"' '-DPROG_HEX="$(BASE).hex"' '-DPROG_MEM="$(DATA_USO)"' '-DEXP_MEM="$(EXP_USO)"' \
		$(if $(DESDE),-DMEM_DESDE=$(DESDE_DEC)) $(if $(HASTA),-DMEM_HASTA=$(HASTA_DEC)) \
		$(RTL) $(PROV) tb/mem_monitor.sv tb/benchmark_monitor.sv tb/tb_programa.sv
	@vvp "$(OUT)/tb_programa" $(VVP_ARGS); rc=$$?; \
	if [ "$(WAVES)" = "1" ]; then echo "Ondas en $(OUT)/ondas.vcd"; fi; \
	echo "Volcado en $(OUT)/dump.mem"; exit $$rc

# Muestra la memoria de la última corrida de make sim PROG=... (DESDE, HASTA, FORMATO, EXP).
mem:
	@test -f $(OUT)/dump.mem || { echo "Primero corre make sim PROG=$(NAME)"; exit 1; }
	@python3 tools/ver_mem.py $(OUT)/dump.mem $(if $(DESDE),--desde $(DESDE)) $(if $(HASTA),--hasta $(HASTA)) \
		$(if $(FORMATO),--formato $(FORMATO)) $(if $(EXP),--esperado $(EXP))
else
sim: all
mem:
	@echo "Uso: make mem PROG=<programa> [DESDE=...] [HASTA=...] [FORMATO=palabras|bytes] [EXP=...]"; exit 1
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
		'  mem               muestra la memoria de la última corrida de make sim PROG=...' \
		'  datos_bench       prepara las entradas de los cinco benchmarks' \
		'  metricas          ejecuta y verifica la matriz de mediciones' \
		'  test_benchmarks   comprueba los datos y la validación de resultados' \
		'  costos_bench      comprueba latencias de escritura en casos controlados' \
		'  clean             borra build/ y los .vcd' \
		'' \
		'make sim PROG=<programa> [CACHE=0|1|2] [MEM_DIV=2|4|5] [DATA=...] [EXP=...] [DESDE=...] [HASTA=...] [ASM=...]' \
		'  PROG   nombre (ejercicio1 -> programs/ejercicio1) o ruta, con o sin .hex/.asm' \
		'          usa <base>.hex; ensambla <base>.asm con ASM si el .hex falta o es más viejo' \
		'  CACHE  2: L1 + write buffer + L2 + eviction buffer (por defecto); 1: L1 y write buffer; 0: adaptador directo' \
		'  VVP_ARGS argumentos de vvp; +LOG_MEM registra transacciones' \
		'  MAX_CYCLES limite de ciclos de simulacion, por defecto 2000000' \
		'  WAVES  0 desactiva las ondas, 1 las genera por defecto' \
		'  MEM_DIV divisor de memoria: 2, 4 o 5 (por defecto 4)' \
		'  DATA   memoria de datos (.mem); por defecto <base>.mem si existe' \
		'  EXP    memoria esperada (.mem); por defecto <base>.exp.mem si existe, si no no compara' \
		'  DESDE, HASTA  rango de memoria a listar, en bytes (decimal o 0x..)' \
		'  ASM    ensamblador; por defecto python3 tools/asm.py' \
		'  Salida en build/<nombre>/ondas.vcd y build/<nombre>/dump.mem' \
		'' \
		'make mem PROG=<programa> [DESDE=...] [HASTA=...] [FORMATO=palabras|bytes] [EXP=...]' \
		'  FORMATO  palabras (por defecto, omite las que valen 0) o bytes (hexdump con ASCII)' \
		'  EXP      compara con un .exp.mem y devuelve error si hay fallas' \
		'' \
		'Ejemplos:' \
		'  make sim PROG=ejercicio1' \
		'  make sim PROG=programs/ejercicio3 DATA=build/cifrado_datos.mem' \
		'  make sim PROG=programs/mi_prueba DESDE=0x40 HASTA=0x60' \
		'  make mem PROG=ejercicio1 DESDE=0 HASTA=0x48' \
		'  make mem PROG=programs/ejercicio3 FORMATO=bytes DESDE=0x2000 HASTA=0x203F'

# Regenera la cadena reproducible de Café de CE y comprueba los vectores externos.
lamport:
	python3 tools/lamport.py --self-test --seed 0xCAFEDECE --length 100 --out data/lamport_demo

tb_crypto_state tb_lamport tb_crypto_unit: lamport

# Selecciona el TB como raíz; evita simular módulos ajenos no instanciados.
# FORCE ejecuta las comprobaciones incluso si existe un archivo llamado tb_nombre.
tb_%: tb/tb_%.sv FORCE
	@mkdir -p build
	$(IV) -I data/lamport_demo -s $@ -o build/$@ $(RTL) $(PROV) tb/mem_monitor.sv tb/benchmark_monitor.sv $<
	vvp build/$@

# Los nuevos TB de CRYPTO generan sus archivos VCD dentro de build/.
waves_%: tb_% FORCE
	gtkwave build/tb_$*.vcd

FORCE:

clean:
	rm -rf build *.vcd

# La preparación de datos no genera instrucciones de ensamblador.
PATRONES ?= secuencial stride aleatorio escritura lectura_escritura
TAMANOS ?= 1 8 32
DIVISORES ?= 2 4 5
CACHES ?= 0 1 2
RECORRIDOS ?= 4
METRICAS_MAX_CYCLES ?= 10000000
METRICAS_OUT ?= build/metricas

datos_bench:
	python3 tools/bench_data.py generate --sizes $(TAMANOS) --passes $(RECORRIDOS)

metricas:
	python3 tools/metricas.py --patterns $(PATRONES) --sizes $(TAMANOS) --divisors $(DIVISORES) \
		--caches $(CACHES) --passes $(RECORRIDOS) --max-cycles $(METRICAS_MAX_CYCLES) --out "$(METRICAS_OUT)"

test_benchmarks:
	python3 -m unittest discover -s tools -p test_benchmarks.py -v

# Separa la preparación de cada caso del acceso cuyo costo se mide.
costos_bench: tb_bench_escritura
