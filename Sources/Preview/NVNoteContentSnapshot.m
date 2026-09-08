#import "NVNoteContentSnapshot.h"

@implementation NVNoteContentSnapshot
@synthesize libraryIdentifier = _libraryIdentifier, noteIdentifier = _noteIdentifier;
@synthesize generation = _generation, title = _title, source = _source, contentType = _contentType;
@synthesize assetRootURL = _assetRootURL, nativeData = _nativeData, nativeFileURL = _nativeFileURL;
- (id)initWithLibraryIdentifier:(NSString *)libraryIdentifier noteIdentifier:(NSString *)noteIdentifier generation:(NSUInteger)generation title:(NSString *)title source:(NSString *)source contentType:(NSString *)contentType assetRootURL:(NSURL *)assetRootURL {
    return [self initWithLibraryIdentifier:libraryIdentifier noteIdentifier:noteIdentifier generation:generation title:title source:source contentType:contentType assetRootURL:assetRootURL nativeData:nil nativeFileURL:nil];
}
- (id)initWithLibraryIdentifier:(NSString *)libraryIdentifier noteIdentifier:(NSString *)noteIdentifier generation:(NSUInteger)generation title:(NSString *)title source:(NSString *)source contentType:(NSString *)contentType assetRootURL:(NSURL *)assetRootURL nativeData:(NSData *)nativeData nativeFileURL:(NSURL *)nativeFileURL {
    if ((self = [super init])) {
        _libraryIdentifier = [(libraryIdentifier ?: @"") copy];
        _noteIdentifier = [(noteIdentifier ?: @"") copy];
        _generation = generation;
        _title = [(title ?: @"") copy];
        _source = [source copy];
        _contentType = [(contentType ?: @"public.plain-text") copy];
        _assetRootURL = [assetRootURL copy];
        _nativeData = [nativeData copy];
        _nativeFileURL = [nativeFileURL copy];
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (void)dealloc {
    [_libraryIdentifier release]; [_noteIdentifier release]; [_title release]; [_source release];
    [_contentType release]; [_assetRootURL release]; [_nativeData release]; [_nativeFileURL release];
    [super dealloc];
}
@end
