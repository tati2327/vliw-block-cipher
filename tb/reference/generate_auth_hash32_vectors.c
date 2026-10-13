#include <stdint.h>
#include <stdio.h>
#include "crypto_hash.h"

// Llama a la referencia externa de Ascon; no reproduce las ecuaciones del RTL.
int main(void) {
    const uint32_t tokens[] = {
        0x03020100, 0x00000000, 0x00000001, 0x80000000,
        0x80000001, 0x12345678, 0xffffffff, 0xa5a55a5a
    };
    for (unsigned i = 0; i < sizeof(tokens) / sizeof(tokens[0]); ++i) {
        unsigned char message[4], digest[32];
        // Serializa cuatro bytes desde el menos significativo al más significativo.
        for (unsigned j = 0; j < 4; ++j)
            message[j] = (unsigned char)(tokens[i] >> (8 * j));
        crypto_hash(digest, message, 4);
        // Muestra los primeros cuatro bytes como un entero little-endian.
        printf("%08x ", (unsigned int)tokens[i]);
        for (int j = 3; j >= 0; --j) printf("%02x", digest[j]);
        printf(" | MD = ");
        for (unsigned j = 0; j < 32; ++j) printf("%02x", digest[j]);
        puts("");
    }
    return 0;
}
