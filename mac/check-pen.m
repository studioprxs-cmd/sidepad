#import <Cocoa/Cocoa.h>
@interface PenCheckView:NSView
@property(strong) NSMutableArray *segments;
@property NSPoint last;
@property BOOL down;
@property NSUInteger events;
@property float pressure,maxPressure;
@end
@implementation PenCheckView
- (instancetype)initWithFrame:(NSRect)frame { if((self=[super initWithFrame:frame]))_segments=[NSMutableArray new];return self; }
- (BOOL)isFlipped{return YES;}
- (BOOL)acceptsFirstMouse:(NSEvent *)event{return YES;}
- (void)drawRect:(NSRect)dirty {
    [[NSColor colorWithSRGBRed:.96 green:.97 blue:.99 alpha:1]setFill];NSRectFill(self.bounds);
    NSDictionary *title=@{NSFontAttributeName:[NSFont systemFontOfSize:28 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:NSColor.blackColor};
    [@"레노버 펜 입력 테스트" drawAtPoint:NSMakePoint(30,30) withAttributes:title];
    NSDictionary *text=@{NSFontAttributeName:[NSFont systemFontOfSize:17],NSForegroundColorAttributeName:NSColor.darkGrayColor};
    [@"펜으로 아래 빈 공간에 선을 그려 주세요. 약하게, 강하게 눌러 보세요." drawAtPoint:NSMakePoint(30,80) withAttributes:text];
    [[NSString stringWithFormat:@"입력 %lu회 · 현재 필압 %.3f · 최대 필압 %.3f",_events,_pressure,_maxPressure] drawAtPoint:NSMakePoint(30,116) withAttributes:text];
    [[NSColor colorWithSRGBRed:.05 green:.35 blue:.9 alpha:1]setStroke];
    for(NSDictionary *segment in _segments){NSBezierPath *path=segment[@"path"];path.lineWidth=[segment[@"width"]doubleValue];path.lineCapStyle=NSLineCapStyleRound;[path stroke];}
}
- (void)mouseDown:(NSEvent *)event {
    _last=[self convertPoint:event.locationInWindow fromView:nil];_down=YES;_events++;_pressure=event.pressure;_maxPressure=MAX(_maxPressure,_pressure);
    NSLog(@"PEN down subtype=%ld pressure=%.4f",(long)event.subtype,event.pressure);self.needsDisplay=YES;
}
- (void)mouseDragged:(NSEvent *)event {
    if(!_down)return;NSPoint point=[self convertPoint:event.locationInWindow fromView:nil];
    NSBezierPath *path=[NSBezierPath bezierPath];[path moveToPoint:_last];[path lineToPoint:point];
    _pressure=event.pressure;_maxPressure=MAX(_maxPressure,_pressure);_events++;
    [_segments addObject:@{@"path":path,@"width":@(1+_pressure*8)}];_last=point;self.needsDisplay=YES;
    if(_events%30==0)NSLog(@"PEN drag subtype=%ld pressure=%.4f events=%lu",(long)event.subtype,event.pressure,_events);
}
- (void)mouseUp:(NSEvent *)event { _down=NO;_pressure=event.pressure;_events++;self.needsDisplay=YES;NSLog(@"PEN up pressure=%.4f events=%lu",event.pressure,_events); }
@end
int main(void){@autoreleasepool{
    NSApplication *app=NSApplication.sharedApplication;app.activationPolicy=NSApplicationActivationPolicyAccessory;
    NSScreen *screen=nil;for(NSScreen *s in NSScreen.screens)if([s.localizedName containsString:@"SidePad"])screen=s;
    if(!screen)return 2;
    NSRect frame=NSInsetRect(screen.frame,40,40);frame.size.height-=25;
    NSWindow *window=[[NSWindow alloc]initWithContentRect:frame styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    window.title=@"SidePad · 펜 테스트";window.contentView=[[PenCheckView alloc]initWithFrame:NSMakeRect(0,0,frame.size.width,frame.size.height)];
    [window makeKeyAndOrderFront:nil];[app activateIgnoringOtherApps:YES];
    [NSTimer scheduledTimerWithTimeInterval:300 repeats:NO block:^(NSTimer *timer){[app terminate:nil];}];
    [app run];
}return 0;}
