// The runner supplies exact frozen methods, typesetter, and observer scaffolding.
#include "support.m"

static NSDictionary *Snapshot(System *system) {
    NSMutableData *geometry=[NSMutableData data];
    NSDictionary *shape=[system shape];
    for(NSUInteger i=0;i<system->layout.numberOfGlyphs;i++) {
        NSPoint point=[system->layout locationForGlyphAtIndex:i];
        Check(isfinite(point.x) && isfinite(point.y),@"finite native glyph position");
        [geometry appendBytes:&point length:sizeof(point)];
    }
    [system->layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0,system->layout.numberOfGlyphs) usingBlock:^(NSRect rect,NSRect used,NSTextContainer *container,NSRange range,BOOL *stop) {
        [geometry appendBytes:&rect length:sizeof(rect)];
        [geometry appendBytes:&used length:sizeof(used)];
    }];
    return @{@"shape":shape,@"geometry":geometry};
}
static void Save(NSMutableArray *records, NSMutableDictionary *row, NSString *fixture, NSString *operation, NSUInteger length, NSUInteger trial, BOOL fixed) {
    [row addEntriesFromDictionary:@{@"fixture":fixture,@"operation":operation,@"characters":@(length),@"trial":@(trial),@"variant":fixed?@"fixed":@"pre-fix"}];
    [records addObject:row];
}
int main(int argc, const char **argv) { @autoreleasepool {
    Check(argc==2,@"output path supplied");
    NSString *ascii=@"alpha beta gamma delta epsilon zeta eta theta iota kappa lambda omega ";
    NSArray *fixtures=@[
        @{@"name":@"ascii-32768",@"text":[@"" stringByPaddingToLength:32768 withString:ascii startingAtIndex:0]},
        @{@"name":@"ascii-262144",@"text":[@"" stringByPaddingToLength:262144 withString:ascii startingAtIndex:0]},
        @{@"name":@"mixed-unicode",@"text":Repeat(@"alpha beta café e\u0302 👩🏽‍💻 中文 gamma \u0301word \ufe0fword \u200dword \u0600 next\t tail ",32768)}
    ];
    NSMutableArray *records=[NSMutableArray array];
#ifdef COUNTS
    NSUInteger trials=1;
#else
    NSUInteger trials=5;
#endif
    for(NSDictionary *fixture in fixtures) {
        NSString *source=fixture[@"text"];
        NSUInteger insertion=[source rangeOfString:@" "].location+1;
        Check(insertion>0 && insertion<source.length,@"localized start edit exists");
        for(NSUInteger trial=0;trial<trials;trial++) {
            NSDictionary *initialReference=nil, *insertedReference=nil;
            for(NSUInteger order=0;order<2;order++) { @autoreleasepool {
                BOOL fixed=(trial+order)%2;
                System *system=[[[System alloc] initSource:source candidate:fixed font:@"Menlo-Regular"] autorelease];
                Reset(); double start=Now(); [system->layout ensureLayoutForTextContainer:system->container];
                Save(records,Record((Now()-start)*1000),fixture[@"name"],@"initial",source.length,trial,fixed);
                NSDictionary *initial=Snapshot(system);
                if(!initialReference) initialReference=[initial retain];
                Check([initial isEqual:initialReference],@"actual correction preserves initial glyph geometry and properties");
                Reset(); start=Now();
                [system->storage replaceCharactersInRange:NSMakeRange(insertion,0) withString:@" "];
                [system->layout ensureLayoutForTextContainer:system->container];
                [system->storage replaceCharactersInRange:NSMakeRange(insertion,1) withString:@""];
                [system->layout ensureLayoutForTextContainer:system->container];
                Save(records,Record((Now()-start)*1000),fixture[@"name"],@"start",source.length,trial,fixed);
                Check([system->storage.string isEqual:source],@"timed start edit pair preserves source");
                Check([Snapshot(system) isEqual:initialReference],@"restored geometry and glyph properties match both variants");
                // Observe the transient inserted state in an additional untimed history.
                [system->storage replaceCharactersInRange:NSMakeRange(insertion,0) withString:@" "];
                [system->layout ensureLayoutForTextContainer:system->container];
                NSDictionary *inserted=Snapshot(system);
                if(!insertedReference) insertedReference=[inserted retain];
                Check([inserted isEqual:insertedReference],@"inserted literal-space geometry and properties match both variants");
                [system->storage replaceCharactersInRange:NSMakeRange(insertion,1) withString:@""];
                [system->layout ensureLayoutForTextContainer:system->container];
                Check([system->storage.string isEqual:source],@"untimed history preserves source");
            }}
            [initialReference release]; [insertedReference release];
        }
        fprintf(stderr,"complete %s\n",[fixture[@"name"] UTF8String]);
    }
    Check(NSApp==nil,@"no application or GUI created");
    Check([[NSJSONSerialization dataWithJSONObject:@{@"records":records,@"checks":@(Checks)} options:0 error:NULL] writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES],@"results written");
    fprintf(stderr,"PASS %lu checks\n",(unsigned long)Checks);
    return 0;
}}
