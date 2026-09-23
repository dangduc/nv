//
//  NotesTableHeaderCell.m
//  Notation
//
//  Created by David Halter on 6/12/13.
//  Copyright (c) 2013 David Halter. All rights reserved.
//

#import "NotesTableHeaderCell.h"

@interface NotesTableHeaderCell (Private)

- (void)_drawBorderWithFrame:(NSRect)cellFrame;
- (void)_drawGradientFromColor:(NSColor *)baseColor inRect:(NSRect)cellFrame;

@end


@implementation NotesTableHeaderCell

- (id)initTextCell:(NSString *)text{
    if ((self = [super initTextCell:text])) {
        if (!text || (text.length==0)) {
            [self setTitle:@"Title"];
        }
    }
    return self;
}


- (BOOL)isOpaque{
    return YES;
}

- (NSRect)drawingRectForBounds:(NSRect)theRect {
	return NSIntegralRect(NSInsetRect(theRect, 6.0f, 1.0f));
}

- (NSRect)sortIndicatorRectForBounds:(NSRect)theRect{
    theRect=[super sortIndicatorRectForBounds:theRect];
    theRect.origin.y = floor(theRect.origin.y-0.5f);
    return NSIntegralRect(theRect);
}

//- (void)drawSortIndicatorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView ascending:(BOOL)ascending priority:(NSInteger)priority{
//	NSLog(@"draw sort");
//}

//- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView{
////    cellFrame=NSInsetRect(cellFrame, 0.0f, 1.0f);
////    cellFrame.size.height-=1.0f;
//    [super drawInteriorWithFrame:cellFrame inView:controlView];
//}



- (void)drawWithFrame:(NSRect)inFrame inView:(NSView*)inView{
    // NSTextFieldCell retains the colors supplied by this column's browser.
    NSColor *background = [self backgroundColor] ?: [NSColor controlBackgroundColor];
    if ([self isHighlighted]) background = [background blendedColorWithFraction:0.05 ofColor:[self textColor]];
    [background setFill];
    NSRectFill(inFrame);
    [self drawInteriorWithFrame:inFrame inView:inView];
    if ([inView isKindOfClass:[NSTableHeaderView class]]) {
        NSTableView *table = [(NSTableHeaderView *)inView tableView];
        NSTableColumn *column = [table highlightedTableColumn];
        NSImage *indicator = [table indicatorImageInTableColumn:column];
        if ([column headerCell] == self && indicator)
            [self drawSortIndicatorWithFrame:inFrame inView:inView
                ascending:[[indicator name] isEqualToString:@"NSAscendingSortIndicator"] priority:0];
    }
    [self _drawBorderWithFrame:inFrame];
}

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view {
    NSRect titleRect = [self drawingRectForBounds:frame];
    if ([view isKindOfClass:[NSTableHeaderView class]]) {
        NSTableView *table = [(NSTableHeaderView *)view tableView];
        if ([[table highlightedTableColumn] headerCell] == self)
            titleRect.size.width = MAX(0, MIN(NSMaxX(titleRect), NSMinX([self sortIndicatorRectForBounds:frame]) - 4) - NSMinX(titleRect));
    }
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setLineBreakMode:NSLineBreakByTruncatingTail];
    [style setAlignment:[self alignment]];
    NSDictionary *attributes = @{NSFontAttributeName: [self font] ?: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]],
        NSForegroundColorAttributeName: [self textColor] ?: [NSColor controlTextColor], NSParagraphStyleAttributeName: style};
    CGFloat height = [[self stringValue] sizeWithAttributes:attributes].height;
    titleRect.origin.y = floor(NSMidY(frame) - height / 2);
    titleRect.size.height = height;
    [[self stringValue] drawInRect:titleRect withAttributes:attributes];
}

- (void)highlight:(BOOL)hBool withFrame:(NSRect)inFrame inView:(NSView *)controlView{
    BOOL previous = [self isHighlighted];
    [self setHighlighted:hBool];
    [self drawWithFrame:inFrame inView:controlView];
    [self setHighlighted:previous];
}



@end


@implementation NotesTableHeaderCell (Private)

- (void)_drawBorderWithFrame:(NSRect)cellFrame{
    NSBezierPath* thePath = [NSBezierPath new];
    [thePath removeAllPoints];
    NSPoint pt=NSMakePoint(cellFrame.origin.x, (cellFrame.origin.y +  cellFrame.size.height-0.5f));
    [thePath moveToPoint:NSMakePoint(NSMaxX(cellFrame),pt.y)];
    [thePath lineToPoint:pt];
    
    [[[self backgroundColor] blendedColorWithFraction:0.20 ofColor:[self textColor]] setStroke];
    [thePath setLineWidth:1.0f];
    [thePath stroke];
    
    if (cellFrame.origin.x>5.0f) {
        [thePath removeAllPoints];
         [thePath moveToPoint:NSMakePoint(cellFrame.origin.x,(cellFrame.origin.y + cellFrame.size.height))];
        [thePath lineToPoint:cellFrame.origin];
        
//        [[tColor colorWithAlphaComponent:0.95f]setStroke];
        [thePath setLineWidth:1.0f];
        [thePath stroke];
    }
//    if ([self state]) {
//         NSLog(@"isHigh :>%d<  title :>%@<",[self isHighlighted],[self title]);
//    }
//    [thePath ]
    [thePath release];
}

- (void)_drawGradientFromColor:(NSColor *)baseColor inRect:(NSRect)cellFrame{
    
    baseColor = [baseColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];//[bColor    
    NSColor *startColor = [baseColor blendedColorWithFraction:0.25f ofColor:[[NSColor colorWithCalibratedWhite:0.9f alpha:1.0f] colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
    
    NSColor *endColor = [baseColor blendedColorWithFraction:0.4f ofColor:[[NSColor colorWithCalibratedWhite:0.1f alpha:1.0f] colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
 
    
    NSGradient *theGrad = [[NSGradient alloc] initWithColorsAndLocations: startColor, 0.14f,
                                endColor, 0.94f, nil];
    [theGrad drawInRect:cellFrame angle:90.0f];
    [theGrad release];
}


@end
