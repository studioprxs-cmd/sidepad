#import <Cocoa/Cocoa.h>
@interface TouchCheckView:NSView
@property(strong) NSMutableArray *paths;
@property NSPoint last;
@property BOOL down;
@property NSUInteger taps,drags,scrolls;
@property CGFloat offset;
@end
@implementation TouchCheckView
- (instancetype)initWithFrame:(NSRect)r{if((self=[super initWithFrame:r]))_paths=[NSMutableArray new];return self;}
- (BOOL)isFlipped{return YES;}
- (BOOL)acceptsFirstMouse:(NSEvent *)e{return YES;}
- (void)drawRect:(NSRect)rect{
    [[NSColor colorWithSRGBRed:.96 green:.97 blue:.99 alpha:1]setFill];NSRectFill(self.bounds);
    NSDictionary *title=@{NSFontAttributeName:[NSFont systemFontOfSize:28 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:NSColor.blackColor};
    [@"손가락 터치 테스트" drawAtPoint:NSMakePoint(30,25) withAttributes:title];
    NSDictionary *text=@{NSFontAttributeName:[NSFont systemFontOfSize:17],NSForegroundColorAttributeName:NSColor.darkGrayColor};
    [@"왼쪽: 탭·드래그 / 오른쪽: 두 손가락 스크롤" drawAtPoint:NSMakePoint(30,75) withAttributes:text];
    [[NSString stringWithFormat:@"클릭 %lu회 · 드래그 %lu회 · 스크롤 %lu회",_taps,_drags,_scrolls] drawAtPoint:NSMakePoint(30,115) withAttributes:text];
    [[NSColor systemBlueColor]setStroke];for(NSBezierPath *p in _paths){p.lineWidth=3;p.lineCapStyle=NSLineCapStyleRound;[p stroke];}
    NSRect list=NSMakeRect(self.bounds.size.width*.55,165,self.bounds.size.width*.4,self.bounds.size.height-195);
    [NSGraphicsContext saveGraphicsState];NSRectClip(list);
    [[NSColor whiteColor]setFill];NSRectFill(list);
    for(int i=0;i<30;i++)[[NSString stringWithFormat:@"스크롤 항목 %02d",i+1]drawAtPoint:NSMakePoint(list.origin.x+20,list.origin.y+20+i*60+_offset)withAttributes:text];
    [NSGraphicsContext restoreGraphicsState];
}
- (void)mouseDown:(NSEvent *)e{_down=YES;_taps++;_last=[self convertPoint:e.locationInWindow fromView:nil];self.needsDisplay=YES;NSLog(@"TOUCH down subtype=%ld count=%lu",(long)e.subtype,_taps);}
- (void)mouseDragged:(NSEvent *)e{if(!_down)return;NSPoint point=[self convertPoint:e.locationInWindow fromView:nil];NSBezierPath *p=[NSBezierPath bezierPath];[p moveToPoint:_last];[p lineToPoint:point];[_paths addObject:p];_last=point;_drags++;self.needsDisplay=YES;}
- (void)mouseUp:(NSEvent *)e{_down=NO;NSLog(@"TOUCH up drags=%lu",_drags);}
- (void)scrollWheel:(NSEvent *)e{_scrolls++;_offset=MAX(-1200,MIN(0,_offset+e.scrollingDeltaY));self.needsDisplay=YES;NSLog(@"TOUCH scroll delta=%.2f count=%lu offset=%.1f",e.scrollingDeltaY,_scrolls,_offset);}
@end
int main(void){@autoreleasepool{
    NSApplication *app=NSApplication.sharedApplication;app.activationPolicy=NSApplicationActivationPolicyAccessory;
    NSScreen *screen=nil;for(NSScreen *s in NSScreen.screens)if([s.localizedName containsString:@"SidePad"])screen=s;if(!screen)return 2;
    NSRect rect=NSInsetRect(screen.frame,35,35);rect.size.height-=25;
    NSWindow *window=[[NSWindow alloc]initWithContentRect:rect styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    window.title=@"SidePad · 터치 테스트";window.contentView=[[TouchCheckView alloc]initWithFrame:NSMakeRect(0,0,rect.size.width,rect.size.height)];
    window.level=NSFloatingWindowLevel;
    [window setFrame:rect display:YES];
    [window makeKeyAndOrderFront:nil];[app activateIgnoringOtherApps:YES];
    NSLog(@"TOUCH fixture target=%@ screen=%@ frame=%@ visible=%d",NSStringFromRect(rect),window.screen.localizedName,NSStringFromRect(window.frame),window.visible);
    [NSTimer scheduledTimerWithTimeInterval:180 repeats:NO block:^(NSTimer *timer){[window orderOut:nil];[app terminate:nil];}];[app run];
}return 0;}
