#import <Foundation/Foundation.h>

// Immutable input shared by source analysis and read-only viewers. Native payload
// fields reserve the provider boundary; native storage is a separate milestone.
@interface NVNoteContentSnapshot : NSObject <NSCopying> {
    NSString *_libraryIdentifier;
    NSString *_noteIdentifier;
    NSUInteger _generation;
    NSString *_title;
    NSString *_source;
    NSString *_contentType;
    NSURL *_assetRootURL;
    NSData *_nativeData;
    NSURL *_nativeFileURL;
}
@property (readonly, copy) NSString *libraryIdentifier;
@property (readonly, copy) NSString *noteIdentifier;
@property (readonly) NSUInteger generation;
@property (readonly, copy) NSString *title;
@property (readonly, copy) NSString *source;
@property (readonly, copy) NSString *contentType;
@property (readonly, copy) NSURL *assetRootURL;
@property (readonly, copy) NSData *nativeData;
@property (readonly, copy) NSURL *nativeFileURL;
- (id)initWithLibraryIdentifier:(NSString *)libraryIdentifier noteIdentifier:(NSString *)noteIdentifier generation:(NSUInteger)generation title:(NSString *)title source:(NSString *)source contentType:(NSString *)contentType assetRootURL:(NSURL *)assetRootURL;
- (id)initWithLibraryIdentifier:(NSString *)libraryIdentifier noteIdentifier:(NSString *)noteIdentifier generation:(NSUInteger)generation title:(NSString *)title source:(NSString *)source contentType:(NSString *)contentType assetRootURL:(NSURL *)assetRootURL nativeData:(NSData *)nativeData nativeFileURL:(NSURL *)nativeFileURL;
@end
