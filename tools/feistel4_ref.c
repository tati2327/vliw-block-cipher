/*
 * feistel4_ref.c — Referencia en C de Feistel4 (tarea 17, CE 4301, Grupo 6).
 *
 * ROL32, feistel4_F, feistel4_encrypt y feistel4_decrypt están copiados tal cual de la
 * Fig. 1 del enunciado (solo se quitaron los espacios que agrega el PDF). El resto es el
 * envoltorio para usarla como referencia de los casos de prueba del procesador.
 *
 * Bloques: 8 bytes = L (bytes 0..3) y R (bytes 4..7), cada mitad en little endian, igual que
 * las lee `lw` (microarchitecture.md §1.5). Un archivo que no sea múltiplo de 8 se completa con
 * ceros, igual que la zona de memoria que recorre el programa; la salida se recorta al tamaño
 * original, igual que la recorta `extract_data.py`.
 *
 * Uso:
 *   feistel4_ref --pruebas
 *   feistel4_ref [-d] --llave K0,K1,K2,K3 entrada salida
 *   feistel4_ref [-d] --llave K0,K1,K2,K3 --llave2 K0,K1,K2,K3 --segmento N entrada salida
 *       (llave y llave2 alternadas por segmentos de N bloques: segmento par con --llave,
 *        impar con --llave2; es el ejercicio 3 de la validación conjunta)
 * Las llaves aceptan decimal, hexadecimal (0x...) o negativos (-1985229329 = 0x89ABCDEF).
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---------------- Fig. 1 del enunciado, tal cual ---------------- */
#define ROL32(x, r) (((x) << (r)) | ((x) >> (32 - (r))))

// Funcion de ronda F: rotacion + suma modular 2^32, combinada con XOR
uint32_t feistel4_F(uint32_t x, uint32_t k) {
    uint32_t t = ROL32(x, 5) + k;
    return t ^ ROL32(x, 13);
}

// Cifrado de un bloque de 64 bits (L, R) con red Feistel de 4 rondas
void feistel4_encrypt(uint32_t *L, uint32_t *R, const uint32_t key[4])
{
    for (int i = 0; i < 4; ++i) {               // 4 rondas
        uint32_t temp = *R;
        *R = *L ^ feistel4_F(*R, key[i]);
        *L = temp;
    }
}

// Descifrado: se recorren las mismas 4 subllaves en orden inverso
void feistel4_decrypt(uint32_t *L, uint32_t *R, const uint32_t key[4])
{
    for (int i = 3; i >= 0; --i) {               // orden inverso de subllaves
        uint32_t temp = *L;
        *L = *R ^ feistel4_F(*L, key[i]);
        *R = temp;
    }
}
/* ---------------- fin de la Fig. 1 ---------------- */

static uint32_t rd32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static void wr32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24);
}

static int parse_key(const char *s, uint32_t key[4]) {
    char buf[256];
    strncpy(buf, s, sizeof buf - 1); buf[sizeof buf - 1] = 0;
    char *tok = strtok(buf, ",");
    for (int i = 0; i < 4; i++) {
        if (!tok) return 0;
        key[i] = (uint32_t)strtoll(tok, NULL, 0);
        tok = strtok(NULL, ",");
    }
    return tok == NULL;
}

/* Procesa un buffer (múltiplo de 8) bloque a bloque. */
static void process(uint8_t *buf, size_t nbytes, int decrypt,
                    const uint32_t k1[4], const uint32_t k2[4], long seg) {
    size_t nblocks = nbytes / 8;
    for (size_t b = 0; b < nblocks; b++) {
        const uint32_t *key = k1;
        if (seg > 0 && ((b / (size_t)seg) % 2 == 1)) key = k2;
        uint32_t L = rd32(buf + 8 * b), R = rd32(buf + 8 * b + 4);
        if (decrypt) feistel4_decrypt(&L, &R, key); else feistel4_encrypt(&L, &R, key);
        wr32(buf + 8 * b, L); wr32(buf + 8 * b + 4, R);
    }
}

static int fallos = 0, casos = 0;
static void check(const char *nombre, uint32_t obt, uint32_t esp) {
    casos++;
    if (obt == esp) printf("PASS %s = %08X\n", nombre, obt);
    else { fallos++; printf("FAIL %s: obtenido %08X, esperado %08X\n", nombre, obt, esp); }
}

static int pruebas(void) {
    /* Llave 0 de los casos 4 a 7 del procesador. */
    const uint32_t K[4] = {0x0F1E2D3Cu, 0x4B5A6978u, 0x8796A5B4u, 0xC3D2E1F0u};

    /* Caso 4: una ronda, L XOR F(R, K0). */
    uint32_t L = 0x01234567u, R = 0x89ABCDEFu;
    check("caso4 F(89ABCDEF, K0)", feistel4_F(R, K[0]), 0x3D2A1A18u);
    check("caso4 L XOR F(R, K0)", L ^ feistel4_F(R, K[0]), 0x3C095F7Fu);

    /* Caso 5: 1 KB con palabra i = i*0x9E3779B9 + 0x01234567. */
    uint32_t w[256], c[256];
    for (uint32_t i = 0; i < 256; i++) w[i] = i * 0x9E3779B9u + 0x01234567u;
    memcpy(c, w, sizeof w);
    for (int b = 0; b < 128; b++) feistel4_encrypt(&c[2 * b], &c[2 * b + 1], K);
    uint32_t x = 0;
    for (int i = 0; i < 256; i++) x ^= c[i];
    check("caso5 0x2000 palabra 0", c[0], 0xD2163C19u);
    check("caso5 0x2000 palabra 1", c[1], 0x9738F433u);
    check("caso5 0x2000 palabra 254", c[254], 0x66DD2E5Bu);
    check("caso5 0x2000 palabra 255", c[255], 0x3A7D47FDu);
    check("caso5 XOR de 0x2000", x, 0x5DEEA565u);
    for (int b = 0; b < 128; b++) feistel4_decrypt(&c[2 * b], &c[2 * b + 1], K);
    casos++;
    if (memcmp(c, w, sizeof w) == 0) printf("PASS caso5 descifrado = original (1 KB)\n");
    else { fallos++; printf("FAIL caso5 descifrado distinto del original\n"); }

    /* Caso 6: valor de la ronda con sesión, 5 XOR F(5, 0x1A010). */
    check("caso6 5 XOR F(5, 0x1A010)", 5u ^ feistel4_F(5u, 0x1A010u), 0x000100B5u);

    printf("Casos: %d; Fallos: %d\n", casos, fallos);
    return fallos ? 1 : 0;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--pruebas") == 0) return pruebas();

    int decrypt = 0, completo = 0; long seg = 0; int have1 = 0, have2 = 0;
    uint32_t k1[4], k2[4];
    const char *in = NULL, *out = NULL;
    for (int a = 1; a < argc; a++) {
        if (strcmp(argv[a], "-d") == 0) decrypt = 1;
        else if (strcmp(argv[a], "--completo") == 0) completo = 1;
        else if (strcmp(argv[a], "--llave") == 0 && a + 1 < argc) have1 = parse_key(argv[++a], k1);
        else if (strcmp(argv[a], "--llave2") == 0 && a + 1 < argc) have2 = parse_key(argv[++a], k2);
        else if (strcmp(argv[a], "--segmento") == 0 && a + 1 < argc) seg = strtol(argv[++a], NULL, 0);
        else if (!in) in = argv[a];
        else if (!out) out = argv[a];
        else { fprintf(stderr, "argumento de más: %s\n", argv[a]); return 2; }
    }
    if (!have1 || !in || !out || (seg > 0 && !have2) || (have2 && seg <= 0)) {
        fprintf(stderr, "uso: feistel4_ref --pruebas\n"
                        "     feistel4_ref [-d] --llave K0,K1,K2,K3 [--llave2 K0,K1,K2,K3 --segmento N] [--completo] entrada salida\n");
        return 2;
    }
    FILE *f = fopen(in, "rb");
    if (!f) { perror(in); return 1; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    size_t padded = ((size_t)n + 7) / 8 * 8;
    uint8_t *buf = calloc(padded ? padded : 8, 1);
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) { perror("lectura"); return 1; }
    fclose(f);
    process(buf, padded, decrypt, k1, have2 ? k2 : k1, seg);
    FILE *g = fopen(out, "wb");
    if (!g) { perror(out); return 1; }
    fwrite(buf, 1, completo ? padded : (size_t)n, g);    /* recortado al tamaño original salvo --completo */
    fclose(g);
    printf("%ld bytes, %zu bloques, %s\n", n, padded / 8, decrypt ? "descifrado" : "cifrado");
    free(buf);
    return 0;
}
