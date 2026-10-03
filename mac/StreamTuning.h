#import <Foundation/Foundation.h>
#include <math.h>

static int PDInitialBitrate(int width,int height,int fps) {
    double bits=(double)width*height*6.65*(fps==30 ? .65 : 1);
    return (int)fmax(4000000,fmin(40000000,bits));
}

// Hysteresis prevents idle desktops or a single delayed callback from lowering quality.
@interface PDStreamTuning : NSObject
@property(nonatomic,readonly) int bitrate;
- (instancetype)initWithBitrate:(int)bitrate;
- (int)observeDecode:(double)decodeMs send:(double)sendMs submitted:(uint64_t)submitted dropped:(uint64_t)dropped;
@end
@implementation PDStreamTuning {
    int _maximum,_minimum,_bad,_good;
    uint64_t _submitted,_dropped;
}
- (instancetype)initWithBitrate:(int)bitrate {
    if ((self=[super init])) { _bitrate=_maximum=bitrate; _minimum=MAX(4000000,bitrate/3); }
    return self;
}
- (int)observeDecode:(double)decodeMs send:(double)sendMs submitted:(uint64_t)submitted dropped:(uint64_t)dropped {
    if (submitted<_submitted || dropped<_dropped) { _submitted=submitted;_dropped=dropped;_bad=_good=0;return _bitrate; }
    uint64_t delivered=submitted-_submitted,skipped=dropped-_dropped;
    _submitted=submitted;_dropped=dropped;
    if (delivered+skipped<10 || !isfinite(decodeMs) || !isfinite(sendMs)) { _bad=_good=0;return _bitrate; }
    BOOL congested=decodeMs>80 || sendMs>40 || (double)skipped/(delivered+skipped)>.15;
    if (congested) { _good=0;if(++_bad>=2){_bitrate=MAX(_minimum,_bitrate*4/5);_bad=0;} }
    else {
        _bad=0;
        if(decodeMs>=0 && decodeMs<40 && sendMs<20 && skipped==0){
            if(++_good>=8){_bitrate=MIN(_maximum,_bitrate+MAX(250000,_maximum/20));_good=0;}
        }else _good=0;
    }
    return _bitrate;
}
@end
