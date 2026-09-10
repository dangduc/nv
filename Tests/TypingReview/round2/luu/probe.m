#import <Cocoa/Cocoa.h>
#import <mach/mach_time.h>
#import "AttributedPlainText.h"
#import "NVSourceAnalysis.h"
NSString * const NVNoteWordCountDidChangeNotification = @"ProbeWordCount";
static double Now(void) { static mach_timebase_info_data_t s; if (!s.denom) mach_timebase_info(&s); return mach_absolute_time() * (double)s.numer / s.denom / 1e9; }
static void Check(BOOL ok, NSString *message) { if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); } }
@interface FixtureNote : NSObject { @public NSString *syntax; }
@end
@implementation FixtureNote
- (NSString *)sourceSyntaxIdentifier { return syntax; }
@end
@interface FixtureSession : NSObject {
@public BOOL closed; uint64_t sourceGeneration, wordCountGeneration;
NSTextStorage *textStorage; FixtureNote *note; NVSourceAnalysis *sourceAnalysis;
NSHashTable *wordCountClients; NSUInteger wordCount;
}
@end
@implementation FixtureSession
#include "publication.inc"
- (void)dealloc { [textStorage release]; [note release]; [wordCountClients release]; [super dealloc]; }
@end
static FixtureSession *Session(NSString *source) {
 FixtureSession *s = [[[FixtureSession alloc] init] autorelease];
 s->sourceGeneration=1; s->note=[[FixtureNote alloc] init]; s->note->syntax=@"plain";
 s->textStorage=[[NSTextStorage alloc] initWithString:source];
 [s->textStorage addLayoutManager:[[[NSLayoutManager alloc] init] autorelease]];
 s->wordCountClients=[[NSHashTable weakObjectsHashTable] retain];
 return s;
}
static NSString *Source(NSUInteger count) {
 NSMutableString *s=[NSMutableString stringWithString:@"heading\n"];
 for (NSUInteger i=0;i<count;i++) [s appendFormat:@"[[Reference %05lu]] body\n",(unsigned long)i];
 [s appendString:@"last editable line\n"]; return s;
}
static NSArray *ReadRuns(NSTextStorage *s) {
 NSMutableArray *a=[NSMutableArray array];
 [s enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0,s.length) options:0 usingBlock:^(id v, NSRange r, BOOL *stop){if(v)[a addObject:@{@"range":[NSValue valueWithRange:r],@"url":v}];}];
 return a;
}
static double Publish(FixtureSession *s, NSArray *runs) {
 NSDictionary *r=@{@"generation":@(s->sourceGeneration),@"syntax":s->note->syntax,@"linkRuns":runs};
 double t=Now(); [s sourceAnalysis:nil didFinish:r]; return (Now()-t)*1000;
}
static int Compare(const void *a,const void*b) { double x=*(const double*)a,y=*(const double*)b; return (x>y)-(x<y); }
static void LinkScaling(void) {
 printf("case,links,utf16,p50_ms,max_ms,edit_notifications\n");
 for(NSNumber *n in @[@1000,@4000,@10000]) for(NSString *kind in @[@"unchanged",@"prepend_shift",@"one_target",@"all_targets",@"syntax_remove_all",@"syntax_add_all"]) {
 double times[5]; NSUInteger notifications=0,length=0;
 for(NSUInteger trial=0;trial<5;trial++) @autoreleasepool {
  FixtureSession *s=Session(Source(n.unsignedIntegerValue));
  if([kind isEqual:@"syntax_add_all"]) s->note->syntax=@"org";
  NSArray *before=NVSourceLinkRuns(s->textStorage.string,s->note->syntax);
  Check(before.count==([kind isEqual:@"syntax_add_all"]?0:n.unsignedIntegerValue),@"expected initial fixture link count"); Publish(s,before);
  if([kind isEqual:@"prepend_shift"]) [s->textStorage replaceCharactersInRange:NSMakeRange(0,0) withString:@"x"];
  else if([kind isEqual:@"one_target"] || [kind isEqual:@"all_targets"]) {
   NSUInteger changes=[kind isEqual:@"one_target"]?1:before.count;
   [s->textStorage beginEditing];
   for(NSUInteger i=0;i<changes;i++) { NSRange r=[before[i][@"range"] rangeValue]; [s->textStorage replaceCharactersInRange:NSMakeRange(r.location+1,1) withString:@"Z"]; }
   [s->textStorage endEditing];
  } else if([kind isEqual:@"syntax_remove_all"]) s->note->syntax=@"org";
  else if([kind isEqual:@"syntax_add_all"]) s->note->syntax=@"plain";
  else [s->textStorage replaceCharactersInRange:NSMakeRange(s->textStorage.length-1,0) withString:@"x"];
  s->sourceGeneration++; NVSetSourceLinksCurrent(s->textStorage,NO);
  NSArray *fresh=NVSourceLinkRuns(s->textStorage.string,s->note->syntax);
  Check(fresh.count==([kind isEqual:@"syntax_remove_all"]?0:n.unsignedIntegerValue),@"expected fresh fixture link count");
  __block NSUInteger edits=0;
  id observer=[[NSNotificationCenter defaultCenter] addObserverForName:NSTextStorageDidProcessEditingNotification object:s->textStorage queue:nil usingBlock:^(NSNotification *nt){edits++;}];
  times[trial]=Publish(s,fresh); notifications+=edits; length=s->textStorage.length;
  Check([ReadRuns(s->textStorage) isEqual:fresh],@"exact publication result");
  if([kind isEqual:@"prepend_shift"]||[kind isEqual:@"unchanged"]) Check(edits==0,@"shifted/unchanged runs need no attribute edits");
  [[NSNotificationCenter defaultCenter] removeObserver:observer];
 }
 qsort(times,5,sizeof(double),Compare);
 printf("%s,%lu,%lu,%.3f,%.3f,%lu\n",kind.UTF8String,n.unsignedIntegerValue,length,times[2],times[4],notifications); fflush(stdout);
 }
}
static void SnapshotAndCount(void) {
 printf("snapshot_utf16,p50_ms,max_ms,edit_holding_snapshot_p50_ms,edit_without_snapshot_p50_ms,copy_is_immutable\n");
 for(NSNumber *size in @[@100000,@1000000,@4000000]) @autoreleasepool {
 NSMutableString *text=[NSMutableString stringWithCapacity:size.unsignedIntegerValue];
 while(text.length<size.unsignedIntegerValue) [text appendString:@"word café 日本語 sentence.\n"];
 FixtureSession *s=Session(text); [s->wordCountClients addObject:s->note];
 double times[31], retainedEdit[31], unretainedEdit[31];
 for(NSUInteger i=0;i<31;i++) @autoreleasepool {
  NVSetSourceLinksCurrent(s->textStorage,NO); s->sourceGeneration++;
  double t=Now(); NSDictionary *snap=[s snapshotForSourceAnalysis:nil]; times[i]=(Now()-t)*1000;
  unichar old=[snap[@"source"] characterAtIndex:0];
  double editStart=Now();
  [s->textStorage replaceCharactersInRange:NSMakeRange(0,1) withString:old=='w'?@"W":@"w"]; retainedEdit[i]=(Now()-editStart)*1000;
  Check([snap[@"source"] characterAtIndex:0]==old,@"snapshot immutable after storage mutation");
  Check([snap[@"words"] boolValue],@"snapshot requests count");
 }
 for(NSUInteger i=0;i<31;i++) @autoreleasepool {
  unichar old=[s->textStorage.string characterAtIndex:0]; double editStart=Now();
  [s->textStorage replaceCharactersInRange:NSMakeRange(0,1) withString:old=='w'?@"W":@"w"];
  unretainedEdit[i]=(Now()-editStart)*1000;
 }
 qsort(times,31,sizeof(double),Compare); qsort(retainedEdit,31,sizeof(double),Compare); qsort(unretainedEdit,31,sizeof(double),Compare);
 printf("%lu,%.3f,%.3f,%.3f,%.3f,yes\n",text.length,times[15],times[30],retainedEdit[15],unretainedEdit[15]); fflush(stdout);
 if(size.unsignedIntegerValue<=1000000) {
  double t=Now(); NSUInteger count=NVSourceWordCount(text); double worker=(Now()-t)*1000;
  NSDictionary *result=@{@"generation":@(s->sourceGeneration),@"syntax":@"plain",@"wordCount":@(count)};
  __block NSUInteger events=0;
  id obs=[[NSNotificationCenter defaultCenter] addObserverForName:NVNoteWordCountDidChangeNotification object:s queue:nil usingBlock:^(NSNotification *nt){NSUInteger got=0;Check([s getWordCount:&got]&&got==count,@"cached count matches worker");events++;}];
  t=Now(); for(NSUInteger i=0;i<1000;i++) [s sourceAnalysis:nil didFinish:result]; double mainMs=(Now()-t)*1000/1000;
  Check(events==1000,@"each accepted word count notifies");
  printf("word_count,%lu,%lu,worker_helper_ms=%.3f,main_publish_mean_ms=%.6f\n",text.length,count,worker,mainMs); fflush(stdout);
  [[NSNotificationCenter defaultCenter] removeObserver:obs];
 }
 }
}
int main(void) { @autoreleasepool { (void)NVSourceLinkRuns(@"[[warmup]]",@"plain"); LinkScaling(); SnapshotAndCount(); printf("PASS: production publication, shift, snapshot, and word-cache probes\n"); } return 0; }
