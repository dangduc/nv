#include "support.h"

static void RecordBudget(NSString *stage,NSArray *layouts,NSArray *delegates,BOOL expectASCIIOnly,BOOL expectFallback) {
    for(NSUInteger i=0;i<layouts.count;i++) {
        NSLayoutManager *layout=layouts[i]; CountingDelegate *delegate=delegates[i];
        NSDictionary *actual=Snapshot(layout),*fresh=Fresh(layout);
        Check([actual isEqual:fresh],[stage stringByAppendingString:@" cached layout matches fresh production layout"]);
        CheckPolicy(layout);
        Check(delegate->callbacks>0,[stage stringByAppendingString:@" edit regenerated native glyphs"]);
        if(expectASCIIOnly) Check(delegate->queries==0,[stage stringByAppendingString:@" uses no composed-range query"]);
        if(expectFallback) Check(delegate->queries>0,[stage stringByAppendingString:@" exercises the Unicode fallback"]);
        [Rows addObject:@{@"stage":stage,@"layout":@(i),@"length":@(layout.textStorage.length),
                         @"glyphs":@(delegate->generated),@"callbacks":@(delegate->callbacks),
                         @"characterReads":@(delegate->reads),@"composedQueries":@(delegate->queries),
                         @"asciiCandidates":@(delegate->asciiCandidates),@"fallbackCandidates":@(delegate->fallbackCandidates)}];
        delegate->generated=delegate->reads=delegate->queries=delegate->asciiCandidates=delegate->fallbackCandidates=delegate->callbacks=0;
    }
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        Check(argc==2,@"expected result path");
        Rows=[NSMutableArray array];
        NSTextStorage *storage=[[[NSTextStorage alloc] initWithAttributedString:Attributed(@"alpha beta gamma delta")] autorelease];
        InstallCounters(storage.string);
        CountingDelegate *first=[[[CountingDelegate alloc] init] autorelease];
        CountingDelegate *second=[[[CountingDelegate alloc] init] autorelease];
        NSArray *delegates=@[first,second];
        NSArray *layouts=@[NewLayout(storage,first,117,NO),NewLayout(storage,second,203,YES)];
        Check(storage.layoutManagers.count==2 && [layouts[0] typesetter]!=[layouts[1] typesetter],
              @"two layouts retain one native storage owner and distinct typesetters");
        RecordBudget(@"ASCII-initial",layouts,delegates,YES,NO);
        [storage replaceCharactersInRange:NSMakeRange(4,1) withString:@"é"];
        RecordBudget(@"left-neighbor-Latin",layouts,delegates,NO,YES);
        [storage replaceCharactersInRange:NSMakeRange(4,1) withString:@"a"];
        RecordBudget(@"left-neighbor-back-to-ASCII",layouts,delegates,YES,NO);
        [storage replaceCharactersInRange:NSMakeRange(6,1) withString:@"中"];
        RecordBudget(@"right-neighbor-CJK",layouts,delegates,NO,YES);
        [storage replaceCharactersInRange:NSMakeRange(6,1) withString:@"b"];
        RecordBudget(@"right-neighbor-back-to-ASCII",layouts,delegates,YES,NO);
        [storage replaceCharactersInRange:NSMakeRange(6,0) withString:@"\u0301"];
        RecordBudget(@"attached-mark",layouts,delegates,NO,YES);
        [storage replaceCharactersInRange:NSMakeRange(6,1) withString:@""];
        RecordBudget(@"attached-mark-removed",layouts,delegates,YES,NO);
        [storage addAttributes:@{NSFontAttributeName:[NSFont fontWithName:@"Helvetica" size:19],NSBaselineOffsetAttributeName:@2}
                       range:NSMakeRange(5,1)];
        RecordBudget(@"ASCII-attributed-space-edit",layouts,delegates,YES,NO);
        [storage beginEditing];
        [storage replaceCharactersInRange:NSMakeRange(4,1) withString:@"é"];
        [storage replaceCharactersInRange:NSMakeRange(11,1) withString:@"中"];
        [storage addAttribute:NSForegroundColorAttributeName value:[NSColor blueColor] range:NSMakeRange(4,8)];
        [storage endEditing];
        RecordBudget(@"disjoint-Unicode-and-attributes",layouts,delegates,NO,YES);
        [storage setAttributedString:Attributed(@"alpha beta gamma delta")];
        RecordBudget(@"restore-ASCII-note",layouts,delegates,YES,NO);
        [storage replaceCharactersInRange:NSMakeRange(4,1) withString:@"\t"];
        RecordBudget(@"whitespace-neighbor",layouts,delegates,YES,NO);
        [storage setAttributedString:Attributed(@"! ~")];
        RecordBudget(@"printable-ASCII-boundaries",layouts,delegates,YES,NO);
        [storage setAttributedString:Attributed(@"! \x7f")];
        RecordBudget(@"outside-printable-ASCII",layouts,delegates,NO,YES);
        [storage setAttributedString:Attributed(@"! ~")];
        RecordBudget(@"restore-printable-ASCII-boundaries",layouts,delegates,YES,NO);
        Check(storage.layoutManagers.count==2,@"all edits preserve native shared ownership");
        for(NSLayoutManager *layout in layouts) { layout.delegate=nil; [storage removeLayoutManager:layout]; }
        Check(storage.layoutManagers.count==0 && !InProductionCallback && ObservedSource==nil,
              @"the fixture leaves no layout attachment or cached callback context");
        RemoveCounters();
        Check(NSApp==nil,@"no application or GUI session exists");
        NSDictionary *report=@{@"checks":@(Checks+1),@"layoutComparisons":@(Rows.count),
                              @"budgetedCallbacks":@(BudgetCallbacks),@"rows":Rows};
        Check([[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL]
                writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES],@"save compact evidence");
        printf("PASS: %lu checks; %lu shared-layout histories; %lu callback budgets\n",
               (unsigned long)Checks,(unsigned long)Rows.count,(unsigned long)BudgetCallbacks);
    }
    return 0;
}
