static NSDictionary *InstallProductionStyle(NSMutableDictionary *noteBodyAttributes) {
// EXTRACTED_STYLE_BLOCK
}
static void StyleChecks(void) {
    const size_t count=64;
    NSParagraphStyle **observed=calloc(count,sizeof(*observed));
    BOOL *modes=calloc(count,sizeof(*modes));
    dispatch_apply(count,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(size_t i) {
        @autoreleasepool {
            NSDictionary *attrs=InstallProductionStyle([NSMutableDictionary dictionary]);
            observed[i]=[attrs objectForKey:NSParagraphStyleAttributeName];
            modes[i]=[observed[i] lineBreakMode]==NSLineBreakByCharWrapping;
        }
    });
    NSParagraphStyle *shared=observed[0];
    Check(shared!=nil,@"simultaneous first access publishes a style");
    for(size_t i=0;i<count;i++) {
        Check(observed[i]==shared,@"concurrent callers receive one shared style identity");
        Check(modes[i],@"concurrent callers observe fully configured character wrapping");
    }
    free(observed);free(modes);
    Check(![shared isKindOfClass:[NSMutableParagraphStyle class]],@"published style is immutable");
    Check([NSParagraphStyle defaultParagraphStyle].lineBreakMode==NSLineBreakByWordWrapping,@"system default style retains word wrapping");
    NSParagraphStyle *saved=[shared copy];
    @autoreleasepool {
        NSMutableParagraphStyle *local=[[shared mutableCopy] autorelease];
        local.lineBreakMode=NSLineBreakByClipping;local.alignment=NSTextAlignmentRight;
        local.baseWritingDirection=NSWritingDirectionRightToLeft;local.firstLineHeadIndent=17;
        Check(shared.lineBreakMode==NSLineBreakByCharWrapping&&[shared isEqual:saved],@"mutable local copy cannot modify the shared constant");
    }
    NSMutableDictionary *a=[NSMutableDictionary dictionaryWithObject:[NSFont fontWithName:@"Menlo-Regular" size:18] forKey:NSFontAttributeName];
    NSMutableDictionary *b=[NSMutableDictionary dictionaryWithObject:[NSFont fontWithName:@"Helvetica" size:14] forKey:NSFontAttributeName];
    InstallProductionStyle(a);InstallProductionStyle(b);
    NSString *text=@"alpha beta                                        👩🏽‍💻 e\u0301\t\u00a0";
    NSTextStorage *sa=[[[NSTextStorage alloc]initWithString:text attributes:a]autorelease];
    NSTextStorage *sb=[[[NSTextStorage alloc]initWithString:text attributes:b]autorelease];
    Check([sa attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL]==shared&&[sb attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL]==shared,@"independent storages initially share the immutable style");
    NSMutableParagraphStyle *override=[[shared mutableCopy]autorelease];override.lineBreakMode=NSLineBreakByClipping;
    [sa addAttribute:NSParagraphStyleAttributeName value:override range:NSMakeRange(0,sa.length)];
    Check([[sb attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL] lineBreakMode]==NSLineBreakByCharWrapping,@"one storage paragraph replacement leaves its peer unchanged");
    Check([shared isEqual:saved],@"storage replacement preserves the style constant");
    // Match the public attribute operation in refreshSourceFont, using production style installation.
    [a setObject:[NSFont fontWithName:@"Times-Roman" size:22] forKey:NSFontAttributeName];
    [sa addAttributes:InstallProductionStyle(a) range:NSMakeRange(0,sa.length)];
    Check([sa attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL]==shared,@"font refresh attributes restore the shared wrapping policy");
    // Match source snapshot normalization, including an empty-source boundary.
    [sa setAttributes:InstallProductionStyle(a) range:NSMakeRange(0,sa.length)];
    NSTextStorage *empty=[[[NSTextStorage alloc]initWithString:@"" attributes:InstallProductionStyle(a)]autorelease];
    [empty setAttributes:InstallProductionStyle(a) range:NSMakeRange(0,0)];
    Check([sa.string isEqual:text]&&[sb.string isEqual:text]&&empty.length==0,@"style replacement and zero-length normalization preserve source");
    [a removeAllObjects];[b removeAllObjects];
    Check([shared isEqual:saved]&&shared.lineBreakMode==NSLineBreakByCharWrapping,@"shared style survives caller dictionary removal and autorelease pools");
    Check([[InstallProductionStyle([NSMutableDictionary dictionary]) objectForKey:NSParagraphStyleAttributeName] isEqual:saved],@"later style installation retains the original value");
    [saved release];
    fprintf(stderr,"PASS: shared style concurrent initialization, immutable ownership, and storage normalization\n");
}
