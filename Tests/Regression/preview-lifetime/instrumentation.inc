        __block NSUInteger browserDeaths = 0, editorDeaths = 0, previewBirths = 0, previewDeaths = 0, webBirths = 0, webDeaths = 0;
        NSMutableSet *webPointers = [NSMutableSet set];
        IMP oldBrowser = class_getMethodImplementation([AppController class], @selector(dealloc));
        IMP oldEditor = class_getMethodImplementation([LinkingEditor class], @selector(dealloc));
        IMP oldPreviewInit = class_getMethodImplementation([PreviewController class], @selector(init));
        IMP oldPreview = class_getMethodImplementation([PreviewController class], @selector(dealloc));
        IMP oldLoadView = class_getMethodImplementation([PreviewController class], @selector(loadView));
        IMP oldWebInit = class_getMethodImplementation([WKWebView class], @selector(initWithFrame:configuration:));
        IMP oldWeb = class_getMethodImplementation([WKWebView class], @selector(dealloc));
        method_setImplementation(class_getInstanceMethod([AppController class], @selector(dealloc)), imp_implementationWithBlock(^(id object) {
            browserDeaths++; ((void(*)(id, SEL))oldBrowser)(object, @selector(dealloc));
        }));
        method_setImplementation(class_getInstanceMethod([LinkingEditor class], @selector(dealloc)), imp_implementationWithBlock(^(id object) {
            editorDeaths++; ((void(*)(id, SEL))oldEditor)(object, @selector(dealloc));
        }));
        method_setImplementation(class_getInstanceMethod([PreviewController class], @selector(init)), imp_implementationWithBlock(^id(id object) {
            id result = ((id(*)(id, SEL))oldPreviewInit)(object, @selector(init));
            if (result) previewBirths++;
            return result;
        }));
        method_setImplementation(class_getInstanceMethod([PreviewController class], @selector(loadView)), imp_implementationWithBlock(^(id object) {
            ((void(*)(id, SEL))oldLoadView)(object, @selector(loadView));
            [webPointers addObject:[NSValue valueWithPointer:[object webView]]];
        }));
        method_setImplementation(class_getInstanceMethod([WKWebView class], @selector(initWithFrame:configuration:)), imp_implementationWithBlock(^id(id object, NSRect frame, WKWebViewConfiguration *configuration) {
            id result = ((id(*)(id, SEL, NSRect, id))oldWebInit)(object, @selector(initWithFrame:configuration:), frame, configuration);
            if (result) webBirths++;
            return result;
        }));
        method_setImplementation(class_getInstanceMethod([PreviewController class], @selector(dealloc)), imp_implementationWithBlock(^(id object) {
            previewDeaths++; ((void(*)(id, SEL))oldPreview)(object, @selector(dealloc));
        }));
        method_setImplementation(class_getInstanceMethod([WKWebView class], @selector(dealloc)), imp_implementationWithBlock(^(id object) {
            if ([webPointers containsObject:[NSValue valueWithPointer:object]]) webDeaths++;
            ((void(*)(id, SEL))oldWeb)(object, @selector(dealloc));
        }));
