#import "TouchInput.h"
#include <assert.h>
int main(void){@autoreleasepool{
    uint8_t bytes[17]={6,0x3e,0x80,0,0,0x3f,0x40,0,0,0,0,0,0,0xbd,0x80,0,0};
    PDTouchInput input;assert(PDParseTouch([NSData dataWithBytes:bytes length:17],&input));
    assert(input.x==.25f && input.y==.75f && input.dx==0 && input.dy==-.0625f);
    CGEventRef down=PDCreateTouchEvent(kCGEventLeftMouseDown,CGPointMake(100,200),2,99);
    assert(CGEventGetIntegerValueField(down,kCGMouseEventSubtype)==kCGEventMouseSubtypeDefault);
    assert(CGEventGetIntegerValueField(down,kCGMouseEventClickState)==2);CFRelease(down);
    CGEventRef scroll=CGEventCreateScrollWheelEvent(NULL,kCGScrollEventUnitPixel,2,-50,0);
    assert(CGEventGetDoubleValueField(scroll,kCGScrollWheelEventPointDeltaAxis1)==-50);CFRelease(scroll);
    assert(!PDParseTouch([NSData dataWithBytes:bytes length:16],&input));
    bytes[0]=5;assert(!PDParseTouch([NSData dataWithBytes:bytes length:17],&input));bytes[0]=6;
    bytes[1]=0x7f;bytes[2]=0xc0;assert(!PDParseTouch([NSData dataWithBytes:bytes length:17],&input));
    puts("PASS: touch wire format, normal mouse event, pixel scroll direction, invalid/truncated/NaN rejection; no input posted");
}return 0;}
