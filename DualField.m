/* DualField */

/*Copyright (c) 2010, Zachary Schneirov. All rights reserved.
  Redistribution and use in source and binary forms, with or without modification, are permitted 
  provided that the following conditions are met:
   - Redistributions of source code must retain the above copyright notice, this list of conditions 
     and the following disclaimer.
   - Redistributions in binary form must reproduce the above copyright notice, this list of 
	 conditions and the following disclaimer in the documentation and/or other materials provided with
     the distribution.
   - Neither the name of Notational Velocity nor the names of its contributors may be used to endorse 
     or promote products derived from this software without specific prior written permission. */


#import "DualField.h"
#import "AppController.h"
#import "NVApplicationController.h"
#import "BookmarksController.h"

@implementation DualField
- (id)initWithCoder:(NSCoder *)decoder {
    if (!(self = [super initWithCoder:decoder])) return nil;
    // Old nibs contain an NSTextFieldCell. Replace it with a native search cell.
    NSSearchFieldCell *searchCell = [[[NSSearchFieldCell alloc] initTextCell:@""] autorelease];
    [searchCell setTarget:[[self cell] target]];
    [searchCell setAction:[[self cell] action]];
    [searchCell setEditable:YES];
    [searchCell setSelectable:YES];
    [searchCell setScrollable:YES];
    [searchCell setBezeled:YES];
    [self setCell:searchCell];
    [self setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
    [self setPlaceholderString:NSLocalizedString(@"Search or Create", nil)];
    [self setAccessibilityLabel:NSLocalizedString(@"Search or Create", nil)];
    [self setSendsSearchStringImmediately:YES];
    [self setSendsWholeSearchString:NO];
    [self setRecentsAutosaveName:nil];
    [self setMaximumRecents:0];
    followedLinks = [[NSMutableArray alloc] init];
    return self;
}
- (void)awakeFromNib {
    [super awakeFromNib];
    [self setTarget:nil];
    [self setAction:NULL];
}
- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [followedLinks release];
    [snapbackString release];
    [super dealloc];
}
- (BOOL)hasFollowedLinks { return [followedLinks count] != 0; }
- (void)clearFollowedLinks { [followedLinks removeAllObjects]; }
- (void)pushFollowedLink:(NoteBookmark *)bookmark { [followedLinks addObject:bookmark]; }
- (NoteBookmark *)popLastFollowedLink {
    NoteBookmark *bookmark = [[followedLinks lastObject] retain];
    if (!bookmark) return nil;
    [followedLinks removeLastObject];
    [NVControllerForView(self) searchForString:[bookmark searchString]];
    [NVControllerForView(self) revealNote:[bookmark noteObject] options:0];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(clearFollowedLinks) object:nil];
    return [bookmark autorelease];
}
- (void)setSnapbackString:(NSString *)string {
    if (snapbackString != string) { [snapbackString release]; snapbackString = [string copy]; }
    [self performSelector:@selector(clearFollowedLinks) withObject:nil afterDelay:0];
}
- (NSString *)snapbackString { return snapbackString; }
- (void)snapback:(id)sender {
    if ([self hasFollowedLinks]) [self popLastFollowedLink];
    else [notesTable deselectAll:sender];
}
- (void)flagsChanged:(NSEvent *)event { [NVControllerForView(self) flagsChanged:event]; }
@end
