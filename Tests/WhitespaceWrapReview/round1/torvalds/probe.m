#import <Cocoa/Cocoa.h>
#import <sys/mman.h>
#import <unistd.h>

static NSUInteger Checks, Allocations, Frees, Bytes, NativeBatches, ChangedBatches;
static BOOL FailAllocation;
static void Check(BOOL pass, NSString *name) {
    Checks++;
    if (!pass) { fprintf(stderr, "FAIL: %s\n", name.UTF8String); exit(1); }
}
static void *ProbeMalloc(size_t bytes) {
    Allocations++; Bytes = bytes;
    return FailAllocation ? NULL : malloc(bytes);
}
static void ProbeFree(void *pointer) {
    Frees++;
    // The native store must consume the caller-owned array during setGlyphs.
    memset(pointer, 0xCD, Bytes);
    free(pointer);
}
@interface ProductionDelegate : NSObject <NSLayoutManagerDelegate>
@end
@implementation ProductionDelegate
#define malloc ProbeMalloc
#define free ProbeFree
// EXTRACTED_PRODUCTION_METHOD
#undef malloc
#undef free
@end

@interface CaptureLayout : NSLayoutManager {
@public NSTextStorage *source; NSData *storedProperties; NSUInteger stores;
    const CGGlyph *seenGlyphs; const NSUInteger *seenIndexes; const NSGlyphProperty *seenProperties;
    NSFont *seenFont; NSRange seenRange;
}
@end
@implementation CaptureLayout
- (NSTextStorage *)textStorage { return source; }
- (void)setGlyphs:(const CGGlyph *)glyphs properties:(const NSGlyphProperty *)properties characterIndexes:(const NSUInteger *)indexes font:(NSFont *)font forGlyphRange:(NSRange)range {
    stores++; seenGlyphs = glyphs; seenIndexes = indexes; seenProperties = properties; seenFont = font; seenRange = range;
    [storedProperties release]; storedProperties = [[NSData alloc] initWithBytes:properties length:range.length * sizeof(NSGlyphProperty)];
}
- (void)dealloc { [source release]; [storedProperties release]; [super dealloc]; }
@end

static void *ReadonlyTail(const void *bytes, size_t size, void **mapping) {
    size_t page = (size_t)getpagesize();
    Check(size < page, @"fixture fits one guarded page");
    *mapping = mmap(NULL, page * 2, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    Check(*mapping != MAP_FAILED, @"guard mapping exists");
    void *tail = (char *)*mapping + page - size;
    memcpy(tail, bytes, size);
    Check(mprotect(*mapping, page, PROT_READ) == 0, @"input array is read only");
    Check(mprotect((char *)*mapping + page, page, PROT_NONE) == 0, @"array ends at inaccessible page");
    return tail;
}
static void RunVector(ProductionDelegate *delegate, NSString *name, NSString *text,
                      const NSGlyphProperty *properties, const NSUInteger *indexes,
                      const NSGlyphProperty *expected, NSUInteger count, BOOL changed, BOOL fail) {
    CaptureLayout *manager = [CaptureLayout new];
    manager->source = [[NSTextStorage alloc] initWithString:text];
    CGGlyph glyphs[64]; Check(count <= 64, @"fixture glyph bound");
    for (NSUInteger i = 0; i < count; i++) glyphs[i] = (CGGlyph)(17 + i);
    void *gm, *pm, *im;
    const CGGlyph *g = ReadonlyTail(glyphs, count * sizeof(*g), &gm);
    const NSGlyphProperty *p = ReadonlyTail(properties, count * sizeof(*p), &pm);
    const NSUInteger *ix = ReadonlyTail(indexes, count * sizeof(*ix), &im);
    NSFont *fontToken = (NSFont *)text; // Identity token; the production method never messages it.
    Allocations = Frees = Bytes = 0; FailAllocation = fail;
    NSRange range = NSMakeRange(53, count);
    NSUInteger returned = [delegate layoutManager:manager shouldGenerateGlyphs:g properties:p characterIndexes:ix font:fontToken forGlyphRange:range];
    Check(returned == ((changed && !fail) ? count : 0), [name stringByAppendingString:@" return contract"]);
    Check(manager->stores == ((changed && !fail) ? 1 : 0), [name stringByAppendingString:@" store count"]);
    Check(Allocations == (changed ? 1 : 0), [name stringByAppendingString:@" lazy allocation"]);
    Check(Frees == ((changed && !fail) ? 1 : 0), [name stringByAppendingString:@" balanced allocation"]);
    Check(!memcmp(g, glyphs, count * sizeof(*g)) && !memcmp(p, properties, count * sizeof(*p)) && !memcmp(ix, indexes, count * sizeof(*ix)), @"all caller arrays remain unchanged");
    Check([manager.textStorage.string isEqual:text], @"source remains unchanged");
    if (manager->stores) {
        Check(Bytes == count * sizeof(*p), @"allocation size matches full glyph batch");
        Check(manager->seenGlyphs == g && manager->seenIndexes == ix && manager->seenProperties != p, @"glyph and index buffers preserve identity; property buffer is separate");
        Check(manager->seenFont == fontToken && NSEqualRanges(manager->seenRange, range), @"font and nonzero glyph range preserve identity");
        Check(!memcmp(manager->storedProperties.bytes, expected, count * sizeof(*p)), [name stringByAppendingString:@" exact expected flags"]);
    }
    size_t page = (size_t)getpagesize(); munmap(gm,page*2); munmap(pm,page*2); munmap(im,page*2);
    [manager release]; FailAllocation = NO;
    fprintf(stderr,"PASS: %s\n", name.UTF8String);
}

@interface AuditDelegate : ProductionDelegate
@end
@implementation AuditDelegate
- (NSUInteger)layoutManager:(NSLayoutManager *)manager shouldGenerateGlyphs:(const CGGlyph *)glyphs properties:(const NSGlyphProperty *)properties characterIndexes:(const NSUInteger *)indexes font:(NSFont *)font forGlyphRange:(NSRange)range {
    NativeBatches++;
    NSData *g = [NSData dataWithBytes:glyphs length:range.length*sizeof(*glyphs)];
    NSData *p = [NSData dataWithBytes:properties length:range.length*sizeof(*properties)];
    NSData *ix = [NSData dataWithBytes:indexes length:range.length*sizeof(*indexes)];
    NSUInteger result = [super layoutManager:manager shouldGenerateGlyphs:glyphs properties:properties characterIndexes:indexes font:font forGlyphRange:range];
    if (result) ChangedBatches++;
    Check(result == 0 || result == range.length, @"native delegate consumes zero or the complete batch");
    Check(!memcmp(g.bytes,glyphs,g.length) && !memcmp(p.bytes,properties,p.length) && !memcmp(ix.bytes,indexes,ix.length), @"native callback arrays remain unchanged");
    return result;
}
@end
static NSDictionary *NativeGlyphs(NSString *text, id delegate) {
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:text attributes:@{NSFontAttributeName:[NSFont fontWithName:@"Times-Roman" size:14], NSLigatureAttributeName:@2}];
    NSLayoutManager *manager = [NSLayoutManager new];
    NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(120,100000)];
    [storage addLayoutManager:manager]; [manager addTextContainer:container]; manager.delegate = delegate;
    [manager ensureGlyphsForCharacterRange:NSMakeRange(0,text.length)];
    NSUInteger count = manager.numberOfGlyphs;
    NSMutableData *g = [NSMutableData dataWithLength:count*sizeof(CGGlyph)];
    NSMutableData *p = [NSMutableData dataWithLength:count*sizeof(NSGlyphProperty)];
    NSMutableData *ix = [NSMutableData dataWithLength:count*sizeof(NSUInteger)];
    NSMutableData *b = [NSMutableData dataWithLength:count*sizeof(unsigned char)];
    Check([manager getGlyphsInRange:NSMakeRange(0,count) glyphs:g.mutableBytes properties:p.mutableBytes characterIndexes:ix.mutableBytes bidiLevels:b.mutableBytes] == count, @"native glyph readback is complete after scratch buffer free");
    Check([storage.string isEqual:text], @"native glyph generation preserves UTF16 source");
    NSDictionary *result = @{ @"glyphs":g, @"properties":p, @"indexes":ix, @"bidi":b, @"count":@(count) };
    manager.delegate = nil; [container release]; [manager release]; [storage release];
    return result;
}
int main(void) {
    @autoreleasepool {
        ProductionDelegate *delegate = [ProductionDelegate new];
        CaptureLayout *unused = [CaptureLayout new];
        NSUInteger (*invoke)(id, SEL, id, const CGGlyph *, const NSGlyphProperty *, const NSUInteger *, id, NSRange) = (void *)[delegate methodForSelector:@selector(layoutManager:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:)];
        SEL selector = @selector(layoutManager:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:);
        Check(invoke(delegate,selector,unused,NULL,NULL,NULL,nil,NSMakeRange(NSNotFound,0)) == 0, @"zero batch needs no buffers");
        Check(invoke(delegate,selector,unused,NULL,NULL,NULL,nil,NSMakeRange(0,SIZE_MAX/sizeof(NSGlyphProperty)+1)) == 0, @"allocation overflow rejects batch before buffer access");
        [unused release];
        NSGlyphProperty e=NSGlyphPropertyElastic, c=NSGlyphPropertyControlCharacter, n=NSGlyphPropertyNonBaseCharacter, z=NSGlyphPropertyNull, extra=(1L<<24);
        NSString *text=@" a\t\n\u00a0\u2002e\u0301👩‍💻 ";
        NSUInteger i[]={0,0,0,0,1,2,3,4,5,6,7,8,text.length-1,text.length-1,text.length,NSNotFound};
        NSGlyphProperty p[]={e,e|c,e|n,e|z|n,e,e|c,e|c,e,e,e|n,e|n,e|n,0,e|extra,e,e};
        NSGlyphProperty want[]={0,e|c,n,z|n,e,e|c,e|c,e,e,e|n,e|n,e|n,0,extra,e,e};
        RunVector(delegate,@"UTF16 boundary indexes, repeated mappings, and all retained flag kinds",text,p,i,want,16,YES,NO);
        RunVector(delegate,@"allocation failure returns native fallback",text,p,i,want,16,YES,YES);
        NSUInteger skip[]={1,2,4,5,text.length,NSNotFound};
        NSGlyphProperty unchanged[]={e,e|c,e,e,e,e};
        RunVector(delegate,@"nonspace, control, out-of-range indexes allocate nothing",text,unchanged,skip,unchanged,6,NO,NO);
        NSUInteger one[]={0}; NSGlyphProperty eligible[]={e}, plain[]={0};
        RunVector(delegate,@"single glyph exact boundary",@" ",eligible,one,plain,1,YES,NO);
        RunVector(delegate,@"empty source rejects index zero",@"",eligible,one,eligible,1,NO,NO);
        AuditDelegate *audit = [AuditDelegate new];
        NSArray *fixtures=@[@"office affine fi fl     ",@"e\u0301 a\u0308 \u0301  ",@"\u0301\u0308 alpha  ",@"👩🏽‍💻 👨‍👩‍👧‍👦 😀  ",@"مرحبا بالعالم   שלום עולם  ",@"क्षि नमस्ते  中文   ",@"x\t y\r\n\u00a0\u2002\u2003\u2028  ",[@"e\u0301 👩‍💻   " stringByPaddingToLength:4096 withString:@"e\u0301 👩‍💻   " startingAtIndex:0]];
        NSUInteger nativeGlyphs=0, changed=0, repeated=0, nonbase=0, divergent=0;
        for (NSString *fixture in fixtures) {
            NSDictionary *base=NativeGlyphs(fixture,nil), *candidate=NativeGlyphs(fixture,audit);
            Check([base[@"glyphs"] isEqual:candidate[@"glyphs"]],@"native glyph IDs match unmodified delegate");
            Check([base[@"indexes"] isEqual:candidate[@"indexes"]],@"native UTF16 mapping matches unmodified delegate");
            Check([base[@"bidi"] isEqual:candidate[@"bidi"]],@"native bidi levels match unmodified delegate");
            NSUInteger count=[base[@"count"] unsignedIntegerValue]; nativeGlyphs+=count;
            if (count != fixture.length) divergent++;
            const NSGlyphProperty *bp=[base[@"properties"] bytes],*cp=[candidate[@"properties"] bytes];
            const NSUInteger *ix=[base[@"indexes"] bytes];
            for (NSUInteger k=0;k<count;k++) {
                if (k && ix[k]==ix[k-1]) repeated++;
                if (bp[k]&NSGlyphPropertyNonBaseCharacter) nonbase++;
                if (bp[k] != cp[k]) {
                    changed++;
                    Check((bp[k]^cp[k])==NSGlyphPropertyElastic && !(cp[k]&NSGlyphPropertyElastic),@"native property difference only removes Elastic");
                    Check(!(bp[k]&NSGlyphPropertyControlCharacter) && ix[k]<fixture.length && [fixture characterAtIndex:ix[k]]==' ',@"native property difference belongs to non-control U0020");
                } else if (!(bp[k]&NSGlyphPropertyControlCharacter) && ix[k]<fixture.length && [fixture characterAtIndex:ix[k]]==' ') {
                    Check(!(cp[k]&NSGlyphPropertyElastic),@"all eligible native spaces lose Elastic");
                }
            }
        }
        fprintf(stderr,"OBSERVE native changed=%lu repeated=%lu nonbase=%lu unequal=%lu\n",(unsigned long)changed,(unsigned long)repeated,(unsigned long)nonbase,(unsigned long)divergent);
        Check(changed>0,@"native fixtures exercise changed spaces");
        Check(Frees<=Allocations,@"scratch allocation counts remain valid");
        printf("{\"checks\":%lu,\"native_batches\":%lu,\"changed_batches\":%lu,\"native_glyphs\":%lu,\"changed_space_glyphs\":%lu,\"repeated_character_indexes\":%lu,\"nonbase_glyphs\":%lu,\"fixtures_with_unequal_utf16_glyph_count\":%lu,\"passed\":true}\n",(unsigned long)Checks,(unsigned long)NativeBatches,(unsigned long)ChangedBatches,(unsigned long)nativeGlyphs,(unsigned long)changed,(unsigned long)repeated,(unsigned long)nonbase,(unsigned long)divergent);
        [audit release]; [delegate release];
    }
    return 0;
}
