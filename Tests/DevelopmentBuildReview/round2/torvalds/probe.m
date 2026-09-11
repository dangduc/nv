#include "production.inc"

static NSUInteger Checks, Cases, LinklessScans, LinkedScans, TotalLinks, PreviousCalls, CurrentCalls;
static void Check(BOOL condition, NSString *message) {
    Checks++; if(!condition) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
}
static NSMutableAttributedString *Attributed(NSString *source) {
    NSMutableAttributedString *text=[[[NSMutableAttributedString alloc]initWithString:source attributes:@{@"ReviewMarker":@"preserved"}]autorelease];
    if(source.length)[text addAttribute:NSLinkAttributeName value:[NSURL URLWithString:@"https://example.invalid/preserved"]range:NSMakeRange(0,1)];
    return text;
}
static NSArray *Links(NSMutableAttributedString *text,NSRange scanned,BOOL normalize,NSUInteger *generated) {
    NSMutableArray *rows=[NSMutableArray array];
    __block NSUInteger count=0;
    [text enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0,text.length)options:0 usingBlock:^(id value,NSRange range,BOOL *stop) {
        if(!value)return;
        Check([value isKindOfClass:[NSURL class]],@"native link value is an NSURL");
        NSString *absolute=[value absoluteString];
        BOOL note=[[value scheme]hasPrefix:@"nvalt"];
        if(note) {
            count++;
            Check(range.location>=scanned.location&&NSMaxRange(range)<=NSMaxRange(scanned),@"generated link stays inside the exact UTF-16 scan range");
            Check([[value host]isEqual:@"find"]&&[value query]==nil&&[value fragment]==nil,@"escaped note title cannot become a query or fragment");
            if(normalize&&[absolute hasPrefix:@"nvalt-dev:"])absolute=[@"nvalt:"stringByAppendingString:[absolute substringFromIndex:@"nvalt-dev:".length]];
        }
        [rows addObject:@[@(range.location),@(range.length),absolute]];
    }];
    if(generated)*generated=count;
    return rows;
}
static void Compare(NSString *source,NSRange range) {
    NSMutableAttributedString *base=Attributed(source),*previous=Attributed(source),*current=Attributed(source);
    [base baselineScan:range];
    SchemeCalls=0; [previous previousScan:range]; NSUInteger before=SchemeCalls;
    SchemeCalls=0; [current currentScan:range]; NSUInteger after=SchemeCalls;
    NSUInteger links=0;
    NSArray *currentLinks=Links(current,range,NO,&links);
    Check([currentLinks isEqual:Links(previous,range,NO,NULL)],@"corrected scanner preserves the previous exact URL values and ranges");
    Check([Links(current,range,YES,NULL)isEqual:Links(base,range,NO,NULL)],@"release baseline link bytes and ranges survive the flavor-prefix change");
    Check(before==links,@"previous scanner calls the identity helper once per generated link");
    Check(after==(links?1:0),@"corrected scanner calls the identity helper only once and only when needed");
    for(NSMutableAttributedString *text in @[base,previous,current]) {
        Check([text.string isEqual:source],@"scanner preserves exact source characters");
        [text removeAttribute:NSLinkAttributeName range:NSMakeRange(0,text.length)];
    }
    Check([current isEqualToAttributedString:previous],@"nonlink attributes match previous scanner");
    Check([current isEqualToAttributedString:base],@"nonlink attributes match release baseline");
    Cases++; TotalLinks+=links; PreviousCalls+=before;CurrentCalls+=after;
    if(links)LinkedScans++;else LinklessScans++;
}
int main(int argc,const char **argv) { @autoreleasepool {
    Check(argc==3,@"result path and expected flavor supplied");
    Check(NSApp==nil,@"probe creates no NSApplication");
    BOOL development=[@(argv[2])isEqual:@"development"];
    Check(NVIsDevelopmentBuild()==development,@"runtime flavor follows copied bundle metadata");
    Check([NVNoteURLScheme()isEqual:development?@"nvalt-dev":@"nvalt"],@"actual identity helper selects the expected scheme");
    NSArray *fixtures=@[@"",@"plain e\u0301 👩🏽‍💻 text",@"x [[café]] [[e\u0301clair]] [[👩🏽‍💻]]",
        @"x 👩🏽‍💻 [[a/b?x#y%20 z & \"q\"]] tail",@"[[outer [[inner]] tail]]",
        @"[[ spaced]] [[tail ]] [[]] [[x]]",@"[[line\nbreak]] [[second]]",@"[[x[objc]y]] [[x]y]] [[[nested]]] [[tail"];
    for(NSString *source in fixtures)for(NSUInteger start=0;start<=source.length;start++)for(NSUInteger end=start;end<=source.length;end++)@autoreleasepool {
        Compare(source,NSMakeRange(start,end-start));
    }
    NSUInteger roundTrips=0;
    for(NSString *title in @[@"café",@"e\u0301clair",@"👩🏽‍💻",@"a/b?x#y&z=\"q\"",@"नमस्ते",@"á / 你好"]) {
        NSString *source=[NSString stringWithFormat:@"[[%@]]",title];
        NSMutableAttributedString *text=Attributed(source); [text currentScan:NSMakeRange(0,text.length)];
        NSURL *URL=[text attribute:NSLinkAttributeName atIndex:2 effectiveRange:NULL];
        NSString *prefix=[NVNoteURLScheme()stringByAppendingString:@"://find/"];
        Check([[URL absoluteString]hasPrefix:prefix],@"native URL retains the current flavor and command");
        NSString *encoded=[[URL absoluteString]substringFromIndex:prefix.length];
        Check([[encoded stringByRemovingPercentEncoding]isEqual:title],@"independent native percent decoding restores Unicode and reserved punctuation");
        roundTrips++;
    }
    Check(LinklessScans>0&&LinkedScans>0&&PreviousCalls>CurrentCalls,@"fixtures exercise both lazy branches and multiple-link scans");
    Check(NSApp==nil,@"probe finishes without NSApplication");
    NSDictionary *result=@{@"checks":@(Checks),@"cases":@(Cases),@"fixtures":@(fixtures.count),@"linklessScans":@(LinklessScans),@"linkedScans":@(LinkedScans),@"generatedLinks":@(TotalLinks),@"previousIdentityCalls":@(PreviousCalls),@"currentIdentityCalls":@(CurrentCalls),@"URLRoundTrips":@(roundTrips),@"scheme":NVNoteURLScheme(),@"passed":@YES};
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
    if(![data writeToFile:@(argv[1])atomically:YES])return 2;
    printf("PASS %lu checks, %lu range cases, %lu identity calls versus %lu before correction\n",(unsigned long)Checks,(unsigned long)Cases,(unsigned long)CurrentCalls,(unsigned long)PreviousCalls);
}return 0; }
