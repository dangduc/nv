// The runner supplies frozen production and the committed R1 layout scaffolding.
#include "support.m"

static NSString *Fixture(NSUInteger length, BOOL paragraphs) {
    NSString *pattern=@"alpha beta gamma delta epsilon zeta eta theta iota kappa lambda omega ";
    if(!paragraphs) return [@"" stringByPaddingToLength:length withString:pattern startingAtIndex:0];
    NSString *paragraph=[[@"" stringByPaddingToLength:255 withString:pattern startingAtIndex:0] stringByAppendingString:@"\n"];
    return [@"" stringByPaddingToLength:length withString:paragraph startingAtIndex:0];
}
static void Save(NSMutableArray *records, NSMutableDictionary *row, NSString *fixture, NSString *operation, NSUInteger length, NSUInteger trial, BOOL candidate) {
    [row addEntriesFromDictionary:@{@"fixture":fixture,@"operation":operation,@"characters":@(length),@"trial":@(trial),@"variant":candidate?@"candidate":@"base"}];
    [records addObject:row];
}
int main(int argc, const char **argv) { @autoreleasepool {
    Check(argc==2,@"output path supplied");
    NSMutableArray *records=[NSMutableArray array];
#ifdef COUNTS
    NSUInteger trials=1;
#else
    NSUInteger trials=5;
#endif
    for(NSNumber *size in @[@131072,@262144]) for(NSNumber *paragraphs in @[@NO,@YES]) {
        NSString *source=Fixture(size.unsignedIntegerValue,paragraphs.boolValue);
        NSString *name=[NSString stringWithFormat:@"%@-%@",size,paragraphs.boolValue?@"short-paragraphs":@"single-paragraph"];
        NSUInteger startEdit=[source rangeOfString:@" "].location+1;
        NSUInteger endEdit=[source rangeOfString:@" " options:NSBackwardsSearch range:NSMakeRange(0,source.length-1)].location+1;
        Check(startEdit>0 && endEdit<source.length,@"both edits lie inside source");
        for(NSUInteger trial=0;trial<trials;trial++) for(NSUInteger order=0;order<2;order++) { @autoreleasepool {
            BOOL candidate=(trial+order)%2;
            System *system=[[[System alloc] initSource:source candidate:candidate font:@"Menlo-Regular"] autorelease];
            Reset(); double start=Now();
            [system->layout ensureLayoutForTextContainer:system->container];
            Save(records,Record((Now()-start)*1000),name,@"initial",source.length,trial,candidate);
            NSDictionary *initial=[system shape];
            for(NSString *position in @[@"start",@"end"]) {
                NSUInteger index=[position isEqual:@"start"]?startEdit:endEdit;
                Reset(); start=Now();
                [system->storage replaceCharactersInRange:NSMakeRange(index,0) withString:@" "];
                [system->layout ensureLayoutForTextContainer:system->container];
                [system->storage replaceCharactersInRange:NSMakeRange(index,1) withString:@""];
                [system->layout ensureLayoutForTextContainer:system->container];
                Save(records,Record((Now()-start)*1000),name,position,source.length,trial,candidate);
                Check([system->storage.string isEqual:source],@"edit pair preserves source");
                Check([[system shape] isEqual:initial],@"edit pair restores line boundaries and glyph properties");
            }
        }}
        fprintf(stderr,"complete %s\n",name.UTF8String);
    }
    Check(NSApp==nil,@"no application or GUI created");
    Check([[NSJSONSerialization dataWithJSONObject:@{@"records":records,@"checks":@(Checks)} options:0 error:NULL] writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES],@"results written");
    fprintf(stderr,"PASS %lu checks\n",(unsigned long)Checks);
    return 0;
}}
