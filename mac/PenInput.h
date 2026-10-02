#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

typedef struct { uint8_t action, tool; uint32_t buttons; float x,y,pressure,tilt,orientation; } PDPenInput;
static BOOL PDParsePen(NSData *data,PDPenInput *input) {
    if(data.length!=26)return NO;
    const uint8_t *bytes=data.bytes;input->action=bytes[0];input->tool=bytes[1];
    if(input->action>5 || (input->tool!=1 && input->tool!=2))return NO;
    uint32_t bits;memcpy(&bits,bytes+2,4);input->buttons=CFSwapInt32BigToHost(bits);
    float values[5];
    for(int i=0;i<5;i++){memcpy(&bits,bytes+6+i*4,4);bits=CFSwapInt32BigToHost(bits);memcpy(values+i,&bits,4);if(!isfinite(values[i]))return NO;}
    input->x=fmaxf(0,fminf(1,values[0]));input->y=fmaxf(0,fminf(1,values[1]));
    input->pressure=fmaxf(0,fminf(1,values[2]));input->tilt=fmaxf(0,fminf(M_PI_2,values[3]));input->orientation=values[4];
    return YES;
}
static CGEventRef PDCreatePenEvent(PDPenInput input,CGEventType type,CGPoint point,CGMouseButton button,BOOL down) {
    CGEventRef event=CGEventCreateMouseEvent(NULL,type,point,button);if(!event)return NULL;
    CGEventSetIntegerValueField(event,kCGMouseEventSubtype,kCGEventMouseSubtypeTabletPoint);
    CGEventSetDoubleValueField(event,kCGMouseEventPressure,down?input.pressure:0);
    CGEventSetDoubleValueField(event,kCGTabletEventPointPressure,down?input.pressure:0);
    CGEventSetDoubleValueField(event,kCGTabletEventTiltX,sin(input.orientation)*sin(input.tilt));
    CGEventSetDoubleValueField(event,kCGTabletEventTiltY,-cos(input.orientation)*sin(input.tilt));
    CGEventSetIntegerValueField(event,kCGTabletEventPointX,lround(input.x*65535));
    CGEventSetIntegerValueField(event,kCGTabletEventPointY,lround((1-input.y)*65535));
    CGEventSetIntegerValueField(event,kCGTabletEventPointButtons,down?(button==kCGMouseButtonRight?2:1):0);
    CGEventSetIntegerValueField(event,kCGTabletEventDeviceID,1);
    return event;
}
