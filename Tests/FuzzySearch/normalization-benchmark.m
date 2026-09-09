#import <Foundation/Foundation.h>
#include "utf8proc-2.10.0/utf8proc.h"
int main(void) { setvbuf(stdout,NULL,_IOLBF,0); @autoreleasepool {
    for (NSNumber *size in @[@(1024*1024), @(8*1024*1024)]) {
        NSString *source = [@"e\u0301" stringByPaddingToLength:([size unsignedIntegerValue]/3)*2 withString:@"e\u0301" startingAtIndex:0];
        CFAbsoluteTime start=CFAbsoluteTimeGetCurrent(); NSData *data=[source dataUsingEncoding:NSUTF8StringEncoding]; double utf8=(CFAbsoluteTimeGetCurrent()-start)*1000;
        utf8proc_uint8_t *normalized=NULL; start=CFAbsoluteTimeGetCurrent();
        utf8proc_ssize_t length=utf8proc_map([data bytes], [data length], &normalized, UTF8PROC_STABLE|UTF8PROC_COMPOSE);
        double compose=(CFAbsoluteTimeGetCurrent()-start)*1000; free(normalized);
        printf("bytes=%lu UTF8_ms=%.3f utf8proc_compose_ms=%.3f normalized_bytes=%ld\n",[data length],utf8,compose,length);
    }
} }
