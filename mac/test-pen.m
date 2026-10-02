#import "PenInput.h"
#include <assert.h>
int main(void){@autoreleasepool{
    // A real network byte order down packet: barrel button, x=.25, y=.75, pressure=.5.
    uint8_t bytes[26]={2,1,0,0,0,32,0x3e,0x80,0,0,0x3f,0x40,0,0,0x3f,0,0,0,0,0,0,0,0,0,0,0};
    PDPenInput input;assert(PDParsePen([NSData dataWithBytes:bytes length:26],&input));
    assert(input.buttons==32 && input.x==.25f && input.y==.75f && input.pressure==.5f);
    CGPoint point=CGPointMake(100,200);
    CGEventRef down=PDCreatePenEvent(input,kCGEventLeftMouseDown,point,kCGMouseButtonLeft,YES);
    assert(down && CGEventGetType(down)==kCGEventLeftMouseDown);
    assert(CGEventGetIntegerValueField(down,kCGMouseEventSubtype)==kCGEventMouseSubtypeTabletPoint);
    assert(fabs(CGEventGetDoubleValueField(down,kCGTabletEventPointPressure)-.5)<.001);
    assert(CGEventGetIntegerValueField(down,kCGTabletEventPointButtons)==1);CFRelease(down);
    CGEventRef up=PDCreatePenEvent(input,kCGEventLeftMouseUp,point,kCGMouseButtonLeft,NO);
    assert(CGEventGetDoubleValueField(up,kCGTabletEventPointPressure)==0);
    assert(CGEventGetIntegerValueField(up,kCGTabletEventPointButtons)==0);CFRelease(up);
    assert(!PDParsePen([NSData dataWithBytes:bytes length:25],&input));
    bytes[0]=9;assert(!PDParsePen([NSData dataWithBytes:bytes length:26],&input));bytes[0]=2;
    bytes[6]=0x7f;bytes[7]=0xc0;assert(!PDParsePen([NSData dataWithBytes:bytes length:26],&input));
    puts("PASS: network decoding, tablet pressure, button release, invalid/truncated/NaN rejection; no input posted");
}return 0;}
