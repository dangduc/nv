#include "support.m"

int main(int argc, const char **argv) { @autoreleasepool {
    Check(argc==2,@"output path supplied");
    NSString *pattern=@"alpha beta gamma delta epsilon zeta eta theta iota kappa lambda omega ";
    NSString *source=[@"" stringByPaddingToLength:262144 withString:pattern startingAtIndex:0];
    NSMutableArray *records=[NSMutableArray array];
    for(NSUInteger trial=0;trial<3;trial++) {
        NSDictionary *reference=nil;
        for(NSUInteger order=0;order<2;order++) { @autoreleasepool {
            BOOL experiment=(trial+order)%2;
            System *system=[[[System alloc] initSource:source candidate:experiment font:@"Menlo-Regular"] autorelease];
            Reset(); double start=Now(); [system->layout ensureLayoutForTextContainer:system->container];
            NSMutableDictionary *initial=Record((Now()-start)*1000);
            NSDictionary *shape=[system shape];
            if(!reference) reference=[shape copy];
            Check([reference isEqual:shape],@"ASCII shortcut preserves initial geometry and glyph properties");
            Reset(); start=Now();
            [system->storage replaceCharactersInRange:NSMakeRange(6,0) withString:@" "];
            [system->layout ensureLayoutForTextContainer:system->container];
            [system->storage replaceCharactersInRange:NSMakeRange(6,1) withString:@""];
            [system->layout ensureLayoutForTextContainer:system->container];
            NSMutableDictionary *edit=Record((Now()-start)*1000);
            Check([source isEqual:system->storage.string] && [[system shape] isEqual:reference],@"ASCII shortcut preserves incremental restoration");
            for(NSMutableDictionary *row in @[initial,edit]) {
                NSMutableDictionary *compact=[NSMutableDictionary dictionary];
                for(NSString *key in @[@"wall_ms",@"delegate_ms",@"composed_queries",@"glyphs_visited",@"snapshot_characters",@"explicit_buffer_allocations"]) compact[key]=row[key];
                [compact addEntriesFromDictionary:@{@"operation":row==initial?@"initial":@"start",@"variant":experiment?@"ascii-experiment":@"current",@"trial":@(trial)}];
                [records addObject:compact];
            }
        }}
        [reference release];
    }
    NSArray *controls=@[@"alpha beta gamma",@"alpha  beta",@"alpha \u0301beta",@"alpha \ufe0fbeta",@"alpha \u200dbeta",@"é e\u0302",@"👩🏽‍💻 中文 next",@"\u0600 beta",@"word\n next",@"word\t next",@"word ",@" word",[NSString stringWithFormat:@"a %Cb",(unichar)1],[NSString stringWithFormat:@"a %Cb",(unichar)0x7f]];
    NSUInteger fallbackQueries=0;
    for(NSString *text in controls) { @autoreleasepool {
        NSDictionary *reference=nil;
        for(NSUInteger mode=0;mode<2;mode++) {
            System *system=[[[System alloc] initSource:text candidate:mode font:@"Menlo-Regular"] autorelease];
            Reset(); [system->layout ensureLayoutForTextContainer:system->container];
            if(mode) fallbackQueries+=Composed;
            NSDictionary *shape=[system shape];
            if(!reference) reference=[shape copy];
            Check([reference isEqual:shape] && [system->storage.string isEqual:text],@"mixed/composed control retains identical layout and properties");
        }
        [reference release];
    }}
    Check(fallbackQueries>0,@"non-printable-ASCII cases still use the composed guard");
    Check(NSApp==nil,@"no application or GUI created");
    NSDictionary *report=@{@"records":records,@"controls":@(controls.count),@"fallback_queries_in_controls":@(fallbackQueries),@"checks":@(Checks),@"result":@"PASS"};
    Check([[NSJSONSerialization dataWithJSONObject:report options:0 error:NULL] writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES],@"results written");
    fprintf(stderr,"PASS %lu checks; %lu mixed/composed controls; %lu fallback queries\n",(unsigned long)Checks,(unsigned long)controls.count,(unsigned long)fallbackQueries);
    return 0;
}}
