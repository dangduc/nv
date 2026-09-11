// Appended to the first-round recording harness with production escaping methods.
int main(int argc,const char **argv) {
    @autoreleasepool {
        BOOL development=!strcmp(argv[1],"development");
        Check(NVIsDevelopmentBuild()==development,@"fixture bundle supplies the expected flavor");
        Routes=[NSMutableArray array];
        UXEditor *editor=[[[UXEditor alloc] init] autorelease];
        NSMutableArray *records=[NSMutableArray array];
        for(NSString *title in @[@"café 雪",@"e\u0301 notes",@"👩🏽‍💻 ideas",@"שלום עולם"]) {
            NSString *input=[NSString stringWithFormat:@"[[%@]]",title];
            NSMutableAttributedString *wiki=[[[NSMutableAttributedString alloc] initWithString:input] autorelease];
            [wiki _addDoubleBracketedNVLinkAttributesForRange:NSMakeRange(0,wiki.length)];
            NSRange linked=NSMakeRange(0,0);
            NSURL *url=[wiki attribute:NSLinkAttributeName atIndex:2 effectiveRange:&linked];
            Check(url!=nil && [url.scheme isEqualToString:NVNoteURLScheme()],@"Unicode wiki link uses the active app scheme");
            Check(NSEqualRanges(linked,NSMakeRange(2,title.length)),@"Unicode wiki attributes cover the exact source title");
            Check([url.path isEqualToString:[@"/" stringByAppendingString:title]],@"production escaping preserves Unicode path text");
            Route(editor,url,NO,YES,@"Unicode wiki ordinary click");
            Check([LocalURL isEqual:url],@"ordinary click sends the original Unicode URL to the owning controller");
            Route(editor,url,YES,YES,@"Unicode wiki Command-click");
            NSURLComponents *parts=[NSURLComponents componentsWithURL:LocalURL resolvingAgainstBaseURL:NO];
            NSMutableDictionary *query=[NSMutableDictionary dictionary];
            for(NSURLQueryItem *item in parts.queryItems) query[item.name]=item.value ?: @"";
            Check([query[@"title"] isEqual:title],@"Command-click preserves Unicode title through real URL query escaping");
            Check([query[@"txt"] isEqual:input],@"Command-click preserves the complete Unicode wiki source");
            Check([wiki.string isEqual:input],@"link generation and routing preserve the source");
            [records addObject:@{@"title":title,@"wikiURL":url.absoluteString,@"commandURL":LocalURL.absoluteString}];
        }
        for(NSString *title in @[@"",@"café 雪",@"e\u0301 notes",@"👩🏽‍💻 ideas",@"שלום עולם"]) {
            UXNote *note=[[[UXNote alloc] init] autorelease];
            [note setValue:title forKey:@"titleString"];
            NSURL *url=[note uniqueNoteLink];
            Check(url!=nil && [url.scheme isEqual:NVNoteURLScheme()],@"empty and Unicode copied note links retain active flavor");
            Check([url.path isEqual:[@"/" stringByAppendingString:title]],@"copied note title survives production escaping");
            NSURLComponents *parts=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
            Check(parts.queryItems.count==1 && [parts.queryItems[0].name isEqual:@"NV"],@"copied note keeps one UUID query field");
            NSData *UUID=[[[NSData alloc] initWithBase64EncodedString:parts.queryItems[0].value options:0] autorelease];
            Check(UUID.length==16,@"copied note retains its 16-byte UUID with an empty or Unicode title");
            Route(editor,url,NO,YES,@"empty or Unicode copied note ordinary click");
        }
        for(NSString *input in @[@"",@"[[]]"]) {
            NSMutableAttributedString *empty=[[[NSMutableAttributedString alloc] initWithString:input] autorelease];
            [empty _addDoubleBracketedNVLinkAttributesForRange:NSMakeRange(0,empty.length)];
            __block NSUInteger links=0;
            [empty enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0,empty.length) options:0
                usingBlock:^(id value,NSRange range,BOOL *stop){ if(value) links++; }];
            Check(!links && [empty.string isEqual:input],@"empty source and empty wiki target remain unchanged and unlinked");
        }
        NSDictionary *result=@{@"flavor":development?@"development":@"release",@"checks":@(Checks),@"UnicodeTitles":records,
            @"copiedTitleCases":@5,@"emptyWikiCases":@2,@"routes":Routes};
        NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
        fwrite(data.bytes,1,data.length,stdout); putchar('\n');
    }
    return 0;
}
