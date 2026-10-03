#import "StreamTuning.h"
#include <assert.h>
int main(void) {
    @autoreleasepool {
        int maximum=PDInitialBitrate(2944,1840,60);
        assert(maximum>35000000 && maximum<37000000);
        assert(PDInitialBitrate(1280,800,30)<PDInitialBitrate(1920,1200,60));
        PDStreamTuning *t=[[PDStreamTuning alloc] initWithBitrate:maximum];
        assert([t observeDecode:-1 send:0 submitted:0 dropped:0]==maximum);
        assert([t observeDecode:100 send:50 submitted:60 dropped:0]==maximum);
        int lowered=[t observeDecode:100 send:50 submitted:120 dropped:0];assert(lowered<maximum);
        for(int i=3;i<60;i++)[t observeDecode:120 send:80 submitted:i*60 dropped:0];
        assert(t.bitrate>=maximum/3);
        int minimum=t.bitrate;
        for(int i=60;i<90;i++)[t observeDecode:15 send:2 submitted:i*60 dropped:0];
        assert(t.bitrate>minimum && t.bitrate<=maximum);
        int before=t.bitrate;
        for(int i=0;i<20;i++)[t observeDecode:-1 send:2 submitted:89*60 dropped:0];
        assert(t.bitrate==before); // Idle screens must neither lose quality nor pretend to recover.
        assert([t observeDecode:15 send:2 submitted:0 dropped:0]==before); // Counter reset.
        assert([t observeDecode:NAN send:2 submitted:60 dropped:0]==before);
        puts("Adaptive bitrate bounds, congestion hysteresis and idle-screen tests passed");
    }
}
