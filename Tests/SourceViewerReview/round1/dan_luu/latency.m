#import <Cocoa/Cocoa.h>
#import "NVSourceHighlighter.h"
@interface NVSourceHighlighter (Measure)
- (void)applyCaptures;
@end
static double Now(void) { return [NSDate timeIntervalSinceReferenceDate]; }
int main(int argc, const char **argv) {
 @autoreleasepool {
  NSString *directory = [NSString stringWithUTF8String:argv[1]];
  printf("syntax,rows,utf16,captures,layouts,parse_ms,first_apply_ms,median_reapply_ms,clear_ms,empty_apply_ms\n");
  for (NSString *syntax in @[@"json", @"html", @"markdown"]) {
   for (NSNumber *count in @[@100, @1000, @3000, @6000]) {
    @autoreleasepool {
     NSMutableString *source = [NSMutableString stringWithString:[syntax isEqual:@"json"] ? @"{\n" : @""];
     for (NSUInteger i=0; i<[count unsignedIntegerValue]; i++) {
      if ([syntax isEqual:@"json"]) [source appendFormat:@"\"key%lu\":%lu%@\n", i, i, i+1<[count unsignedIntegerValue] ? @"," : @""];
      else if ([syntax isEqual:@"html"]) [source appendFormat:@"<p id=\"key%lu\">value %lu</p>\n", i, i];
      else [source appendFormat:@"## Title %lu\n\nThis is **bold** with `code`.\n\n", i];
     }
     if ([syntax isEqual:@"json"]) [source appendString:@"}\n"];
     NVSourceParser *parser = [[NVSourceParser alloc] initWithQueryDirectory:directory];
     double started=Now();
     NSArray *captures = [[parser capturesForString:source syntaxIdentifier:syntax cancellationToken:NULL generation:0] retain];
     double parse=(Now()-started)*1000;
     for (NSNumber *layoutCount in @[@1,@2,@4,@20]) {
      NSTextStorage *storage=[[NSTextStorage alloc] initWithString:source];
      NSMutableArray *layouts=[NSMutableArray array];
      for (NSUInteger j=0;j<[layoutCount unsignedIntegerValue];j++) {
       NSLayoutManager *layout=[[[NSLayoutManager alloc] init] autorelease];
       NSTextContainer *container=[[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(500,CGFLOAT_MAX)] autorelease];
       [layout addTextContainer:container]; [storage addLayoutManager:layout]; [layouts addObject:layout];
      }
      NVSourceHighlighter *highlighter=[[NVSourceHighlighter alloc] initWithTextStorage:storage syntaxIdentifier:syntax queryDirectory:directory];
      started=Now(); [highlighter applyCaptures]; double empty=(Now()-started)*1000;
      [highlighter setValue:captures forKey:@"captures"];
      double samples[3];
      for (NSUInteger trial=0; trial<3;trial++) {
       started=Now(); [highlighter applyCaptures]; samples[trial]=(Now()-started)*1000;
      }
      double first=samples[0];
      if(samples[0]>samples[1]) {double t=samples[0];samples[0]=samples[1];samples[1]=t;}
      if(samples[1]>samples[2]) {double t=samples[1];samples[1]=samples[2];samples[2]=t;}
      if(samples[0]>samples[1]) {double t=samples[0];samples[0]=samples[1];samples[1]=t;}
      double apply=samples[1];
      started=Now(); [highlighter close]; double clear=(Now()-started)*1000;
      printf("%s,%lu,%lu,%ld,%lu,%.3f,%.3f,%.3f,%.3f,%.3f\n", [syntax UTF8String], [count unsignedIntegerValue], [source length], captures?(long)[captures count]:-1,[layoutCount unsignedIntegerValue],parse,first,apply,clear,empty); fflush(stdout);
      [highlighter release];
      for (NSLayoutManager *layout in layouts) [storage removeLayoutManager:layout];
      [storage release];
     }
     [captures release]; [parser release];
    }
   }
  }
 }
 return 0;
}
