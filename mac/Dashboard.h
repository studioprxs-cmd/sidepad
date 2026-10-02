#import <Cocoa/Cocoa.h>

static NSTextField *PDText(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *label=[NSTextField wrappingLabelWithString:text];
    label.font=[NSFont systemFontOfSize:size weight:weight];
    label.textColor=NSColor.labelColor;
    label.translatesAutoresizingMaskIntoConstraints=NO;
    return label;
}
static NSStackView *PDStack(NSArray<NSView *> *views, NSUserInterfaceLayoutOrientation orientation, CGFloat spacing) {
    NSStackView *stack=[NSStackView stackViewWithViews:views];
    stack.orientation=orientation; stack.spacing=spacing;
    stack.alignment=orientation==NSUserInterfaceLayoutOrientationVertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    return stack;
}
static NSView *PDSpacer(void) {
    NSView *view=[NSView new]; view.translatesAutoresizingMaskIntoConstraints=NO;
    [view setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return view;
}
static NSButton *PDAction(NSString *title, NSString *symbol, id target, SEL action) {
    NSButton *button=[NSButton buttonWithTitle:title target:target action:action];
    button.translatesAutoresizingMaskIntoConstraints=NO;
    button.bezelStyle=NSBezelStyleRounded; button.controlSize=NSControlSizeRegular;
    button.font=[NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    if (symbol) { button.image=[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]; button.imagePosition=NSImageLeading; }
    return button;
}
static void PDPin(NSView *parent, NSView *child, CGFloat inset) {
    [parent addSubview:child];
    [NSLayoutConstraint activateConstraints:@[
        [child.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor constant:inset],
        [child.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:-inset],
        [child.topAnchor constraintEqualToAnchor:parent.topAnchor constant:inset],
        [child.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor constant:-inset]]];
}

@interface PDCard : NSView
@property BOOL tinted;
@end
@implementation PDCard
- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,.5,.5) xRadius:18 yRadius:18];
    [NSColor.controlBackgroundColor setFill]; [shape fill];
    if (_tinted) { [[NSColor.controlAccentColor colorWithAlphaComponent:.055] setFill]; [shape fill]; }
    [[NSColor.separatorColor colorWithAlphaComponent:.45] setStroke]; shape.lineWidth=1; [shape stroke];
}
@end

// A small static illustration; connection state changes only the indicator.
// It does not animate or add work to the display/cursor streaming loops.
@interface PDConnectionArtwork : NSView
@property(nonatomic) NSInteger connectionState;
@end
@implementation PDConnectionArtwork
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self=[super initWithFrame:frame])) { self.accessibilityElement=NO; }
    return self;
}
- (void)setConnectionState:(NSInteger)state {
    if (_connectionState==state) return;
    _connectionState=state; self.needsDisplay=YES;
}
- (void)screen:(NSRect)rect radius:(CGFloat)radius {
    NSBezierPath *frame=[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
    [[NSColor colorWithSRGBRed:.14 green:.19 blue:.28 alpha:1] setFill]; [frame fill];
    NSRect glass=NSInsetRect(rect,5,5);
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRoundedRect:glass xRadius:MAX(radius-3,2) yRadius:MAX(radius-3,2)] addClip];
    NSGradient *gradient=[[NSGradient alloc] initWithStartingColor:[NSColor colorWithSRGBRed:.05 green:.20 blue:.48 alpha:1]
        endingColor:[NSColor colorWithSRGBRed:.27 green:.67 blue:1 alpha:1]];
    [gradient drawInRect:glass angle:35];
    NSBezierPath *wave=[NSBezierPath bezierPath];
    [wave moveToPoint:NSMakePoint(NSMinX(glass)-10,NSMinY(glass))];
    [wave curveToPoint:NSMakePoint(NSMaxX(glass)+15,NSMaxY(glass)*.65)
        controlPoint1:NSMakePoint(NSMidX(glass)-30,NSMaxY(glass)+12)
        controlPoint2:NSMakePoint(NSMidX(glass)+24,NSMinY(glass)+2)];
    [wave lineToPoint:NSMakePoint(NSMaxX(glass)+15,NSMinY(glass)-10)]; [wave closePath];
    [[NSColor colorWithSRGBRed:.39 green:.82 blue:1 alpha:.55] setFill]; [wave fill];
    [NSGraphicsContext restoreGraphicsState];
}
- (void)drawRect:(NSRect)dirtyRect {
    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *scale=[NSAffineTransform transform];
    [scale translateXBy:(self.bounds.size.width-218)/2 yBy:(self.bounds.size.height-150)/2]; [scale concat];
    [[NSColor.controlAccentColor colorWithAlphaComponent:.06] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(4,3,205,139)] fill];
    [[NSColor.secondaryLabelColor colorWithAlphaComponent:.4] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(69,30,11,28) xRadius:3 yRadius:3] fill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(47,26,54,6) xRadius:3 yRadius:3] fill];
    [self screen:NSMakeRect(5,52,144,92) radius:9];
    [self screen:NSMakeRect(111,21,102,68) radius:10];
    NSColor *dot=_connectionState==2 ? NSColor.systemGreenColor : (_connectionState==3 ? NSColor.systemOrangeColor : NSColor.controlAccentColor);
    [[dot colorWithAlphaComponent:.14] setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(155,106,34,34)] fill];
    [dot setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(167,118,10,10)] fill];
    NSDictionary *labels=@{NSFontAttributeName:[NSFont systemFontOfSize:10 weight:NSFontWeightMedium],NSForegroundColorAttributeName:NSColor.secondaryLabelColor};
    [@"Mac" drawAtPoint:NSMakePoint(64,7) withAttributes:labels];
    [@"SidePad" drawAtPoint:NSMakePoint(143,3) withAttributes:labels];
    [NSGraphicsContext restoreGraphicsState];
}
@end
