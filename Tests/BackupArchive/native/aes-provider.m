// Test-only AES provider for native ARM execution. Shipping OpenSSL is Intel-only.
// AES-256-CBC/PKCS7 is the same format, but this does not exercise shipping OpenSSL.
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCryptor.h>
@implementation NSMutableData (NVBackupNativeAES)
- (BOOL)nv_transform:(CCOperation)operation key:(NSData*)key iv:(NSData*)iv {
    if ([key length] != 32 || [iv length] != 16) return NO;
    NSMutableData *output = [NSMutableData dataWithLength:[self length] + kCCBlockSizeAES128];
    size_t written = 0;
    CCCryptorStatus status = CCCrypt(operation, kCCAlgorithmAES, kCCOptionPKCS7Padding,
        [key bytes], [key length], [iv bytes], [self bytes], [self length], [output mutableBytes], [output length], &written);
    if (status != kCCSuccess) return NO;
    [output setLength:written]; [self setData:output]; return YES;
}
- (BOOL)encryptAESDataWithKey:(NSData*)key iv:(NSData*)iv { return [self nv_transform:kCCEncrypt key:key iv:iv]; }
- (BOOL)decryptAESDataWithKey:(NSData*)key iv:(NSData*)iv { return [self nv_transform:kCCDecrypt key:key iv:iv]; }
@end
