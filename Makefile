# Ejecuta los testbenches existentes y los de CRYPTO desde la raíz del repo.
IV   = iverilog -g2012 -Wall
RTL  = $(wildcard rtl/*.sv)
PROV = $(wildcard rtl/prov/*.sv)
TBS  = $(patsubst tb/%.sv,%,$(wildcard tb/tb_*.sv))
CRYPTO_TBS = tb_auth_hash32 tb_key_vault tb_crypto_state tb_crypto_control tb_crypto_datapath tb_crypto_dec tb_lamport tb_crypto_unit

.PHONY: all sim crypto lamport clean FORCE

all: $(TBS)
sim: all
crypto: $(CRYPTO_TBS)

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
