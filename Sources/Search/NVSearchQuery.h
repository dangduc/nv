#import <Foundation/Foundation.h>

@interface NVSearchTerm : NSObject {
    NSString *_text;
    BOOL _phrase;
}
- (id)initWithText:(NSString *)text phrase:(BOOL)phrase;
@property(nonatomic, readonly) NSString *text;
@property(nonatomic, readonly, getter=isPhrase) BOOL phrase;
@end

/* nv's existing literal grammar: quotes form phrases; space, colon, tab,
   CR and LF separate unquoted terms. Native fzf operators remain literal. */
@interface NVSearchQuery : NSObject {
    NSString *_string;
    NSArray *_terms;
}
- (id)initWithString:(NSString *)string;
@property(nonatomic, readonly) NSString *string;
@property(nonatomic, readonly) NSArray *terms;
- (BOOL)hasTerms;
- (BOOL)matchesTitle:(NSString *)title;
- (NSArray *)literalRangesInString:(NSString *)string;
@end
