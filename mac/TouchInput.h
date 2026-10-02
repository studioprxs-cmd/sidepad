#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

typedef struct {uint8_t action;float x,y,dx,dy;} PDTouchInput;
static BOOL PDParseTouch(NSData *data,PDTouchInput *input){
    if(data.length!=17)return NO;
    const uint8_t *bytes=data.bytes;input->action=bytes[0];
    if(input->action>6 || input->action==5)return NO;
    float values[4];uint32_t bits;
    for(int i=0;i<4;i++){memcpy(&bits,bytes+1+i*4,4);bits=CFSwapInt32BigToHost(bits);memcpy(values+i,&bits,4);if(!isfinite(values[i]))return NO;}
    input->x=fmaxf(0,fminf(1,values[0]));input->y=fmaxf(0,fminf(1,values[1]));
    input->dx=fmaxf(-1,fminf(1,values[2]));input->dy=fmaxf(-1,fminf(1,values[3]));return YES;
}
static CGEventRef PDCreateTouchEvent(CGEventType type,CGPoint point,NSInteger clicks,uint64_t number){
    CGEventRef event=CGEventCreateMouseEvent(NULL,type,point,kCGMouseButtonLeft);if(!event)return NULL;
    CGEventSetIntegerValueField(event,kCGMouseEventSubtype,kCGEventMouseSubtypeDefault);
    CGEventSetIntegerValueField(event,kCGMouseEventClickState,clicks);
    CGEventSetIntegerValueField(event,kCGMouseEventNumber,number);return event;
}
