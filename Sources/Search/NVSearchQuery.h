#import <Foundation/Foundation.h>

/* Presentation only; matching and ordered results never use this limit. */
enum { NVSearchMaximumDisplayedRanges = 2048 };

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
/* Stops discovery at maximumCount literal occurrences. Nil means cancelled. */
- (NSArray *)literalRangesInString:(NSString *)string maximumCount:(NSUInteger)maximumCount cancellation:(BOOL (^)(void))cancelled;
@end
