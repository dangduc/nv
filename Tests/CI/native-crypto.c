/* Compare the rebuilt EVP ABI with the system crypto implementation. */
#include <CommonCrypto/CommonCryptor.h>
#include <openssl/evp.h>
#include <openssl/md5.h>
#include <stdio.h>
#include <string.h>

#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL line %d\n", __LINE__); return 1; } } while (0)

int main(void) {
    const unsigned char md5abc[] = {0x90,0x01,0x50,0x98,0x3c,0xd2,0x4f,0xb0,0xd6,0x96,0x3f,0x7d,0x28,0xe1,0x7f,0x72};
    unsigned char digest[16];
    MD5((const unsigned char *)"abc", 3, digest);
    CHECK(memcmp(digest, md5abc, sizeof(digest)) == 0);
    unsigned char key[32], iv[16], plain[4096], expected[4112], actual[4112], restored[4112];
    for (unsigned i = 0; i < sizeof(key); i++) key[i] = (unsigned char)i;
    for (unsigned i = 0; i < sizeof(iv); i++) iv[i] = (unsigned char)(31 - i);
    for (unsigned i = 0; i < sizeof(plain); i++) plain[i] = (unsigned char)(i * 17);
    const unsigned lengths[] = {0, 1, 15, 16, 17, 255, 4096};
    for (unsigned i = 0; i < sizeof(lengths)/sizeof(lengths[0]); i++) {
        size_t count = 0;
        CHECK(CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                      key, sizeof(key), iv, plain, lengths[i], expected, sizeof(expected), &count) == kCCSuccess);
        EVP_CIPHER_CTX context;
        EVP_CIPHER_CTX_init(&context);
        int first = 0, last = 0;
        CHECK(EVP_EncryptInit_ex(&context, EVP_aes_256_cbc(), NULL, key, iv));
        CHECK(EVP_EncryptUpdate(&context, actual, &first, plain, lengths[i]));
        CHECK(EVP_EncryptFinal_ex(&context, actual + first, &last));
        CHECK((size_t)(first + last) == count && memcmp(actual, expected, count) == 0);
        EVP_CIPHER_CTX_cleanup(&context);
        EVP_CIPHER_CTX_init(&context);
        CHECK(EVP_DecryptInit_ex(&context, EVP_aes_256_cbc(), NULL, key, iv));
        CHECK(EVP_DecryptUpdate(&context, restored, &first, expected, (int)count));
        CHECK(EVP_DecryptFinal_ex(&context, restored + first, &last));
        CHECK((unsigned)(first + last) == lengths[i] && memcmp(restored, plain, lengths[i]) == 0);
        EVP_CIPHER_CTX_cleanup(&context);
    }
    puts("PASS: native OpenSSL MD5 vector and AES-256-CBC/PKCS7 compatibility with CommonCrypto");
    return 0;
}
