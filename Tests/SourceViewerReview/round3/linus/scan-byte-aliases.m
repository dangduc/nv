#import <Foundation/Foundation.h>
int main(void) {
    @autoreleasepool {
        NSUInteger encodings[] = {0x80000203, 0x8000020F, 0x8000001D, 0x80000007, 0x80000A01, 0x80000632, 0x80000631, 0x80000A03, 0x80000A06, 0x80000940};
        NSUInteger changed = 0, accepted = 0;
        for (NSUInteger i = 0; i < sizeof(encodings) / sizeof(encodings[0]); i++) {
            BOOL found = NO;
            for (unsigned int pair = 0; pair <= 0xffff && !found; pair++) {
                @autoreleasepool {
                    unsigned char bytes[] = {pair >> 8, pair & 0xff};
                    if (bytes[0] < 0x81 || bytes[1] < 0x40 || bytes[1] == 0x7f) continue;
                    NSData *input = [NSData dataWithBytes:bytes length:2];
                    NSString *text = [[[NSString alloc] initWithData:input encoding:encodings[i]] autorelease];
                    if (!text) continue;
                    accepted++;
                    NSData *output = [text dataUsingEncoding:encodings[i] allowLossyConversion:NO];
                    if (output && ![input isEqualToData:output]) {
                        printf("ALIAS: encoding=%lx input=%04x output=%s string=%s\n", encodings[i], pair, [[output description] UTF8String], [[text debugDescription] UTF8String]);
                        changed++; found = YES;
                    }
                }
            }
        }
        printf("SCAN: accepted=%lu aliases=%lu\n", (unsigned long)accepted, (unsigned long)changed);
    }
}
