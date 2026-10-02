#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

@interface CheckView : NSView
@property NSUInteger tickCount;
@end
@implementation CheckView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)rect {
    [[NSColor colorWithSRGBRed:.035 green:.055 blue:.09 alpha:1] setFill]; NSRectFill(self.bounds);
    // Draw the identical physical-pixel workload in 1x and Retina modes.
    CGFloat scale=self.window.backingScaleFactor;
    [NSGraphicsContext saveGraphicsState];
    CGContextScaleCTM(NSGraphicsContext.currentContext.CGContext,1.0/scale,1.0/scale);
    NSDictionary *big = @{NSFontAttributeName:[NSFont monospacedSystemFontOfSize:84 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:[NSColor colorWithSRGBRed:.2 green:.9 blue:.75 alpha:1]};
    [@"2944 × 1840" drawAtPoint:NSMakePoint(100,150) withAttributes:big];
    NSDictionary *middle = @{NSFontAttributeName:[NSFont systemFontOfSize:32 weight:NSFontWeightMedium],NSForegroundColorAttributeName:NSColor.whiteColor};
    [@"USB-C · 패드 원본 해상도" drawAtPoint:NSMakePoint(105,290) withAttributes:middle];
    [@"맥의 확장 화면이 패드에 표시되고 있습니다." drawAtPoint:NSMakePoint(105,355) withAttributes:middle];
    NSDictionary *small = @{NSFontAttributeName:[NSFont monospacedSystemFontOfSize:18 weight:NSFontWeightRegular],NSForegroundColorAttributeName:NSColor.whiteColor};
    [[NSString stringWithFormat:@"실시간 프레임 %06lu",(unsigned long)_tickCount] drawAtPoint:NSMakePoint(105,445) withAttributes:small];
    [@"가나다라마바사 ABCDEFG 0123456789 — 원본 픽셀 텍스트" drawAtPoint:NSMakePoint(105,500) withAttributes:small];
    [[NSColor colorWithSRGBRed:.2 green:.9 blue:.75 alpha:1] setFill];
    CGFloat x = 100 + (_tickCount % 180) * 6;
    NSRectFill(NSMakeRect(x,600,100,80));
    for(int i=0;i<512;i++) { [(i%2?NSColor.whiteColor:NSColor.blackColor) setFill]; NSRectFill(NSMakeRect(1100+i,160,1,260)); }
    [NSGraphicsContext restoreGraphicsState];
}
@end
int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication; app.activationPolicy = NSApplicationActivationPolicyAccessory;
        NSScreen *target = nil;
        for (NSScreen *screen in NSScreen.screens) if ([screen.localizedName containsString:@"Pad Display"]) target = screen;
        if (!target) { NSLog(@"No Pad Display screen"); return 2; }
        NSWindow *window = [[NSWindow alloc] initWithContentRect:target.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        CheckView *view = [[CheckView alloc] initWithFrame:NSMakeRect(0,0,target.frame.size.width,target.frame.size.height)];
        window.contentView = view; window.backgroundColor = NSColor.blackColor; [window orderFront:nil];
        NSLog(@"CHECK screen=%@ logical=%@", target.localizedName, NSStringFromRect(target.frame));
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0/60 repeats:YES block:^(NSTimer *timer) { view.tickCount++; view.needsDisplay = YES; }];
        [NSTimer scheduledTimerWithTimeInterval:24 repeats:NO block:^(NSTimer *t) { [timer invalidate]; [window orderOut:nil]; [app terminate:nil]; }];
        [app run];
    } return 0;
}
