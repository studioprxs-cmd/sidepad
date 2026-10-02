#import "AudioPCM.h"
#include <assert.h>
int main(void){@autoreleasepool{
    AudioStreamBasicDescription format={.mSampleRate=48000,.mFormatID=kAudioFormatLinearPCM,.mFormatFlags=kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked|kAudioFormatFlagIsNonInterleaved,.mBytesPerFrame=4,.mChannelsPerFrame=2,.mBitsPerChannel=32};
    float left[]={1,-1,NAN,2},right[]={.5,-.5,INFINITY,-2};
    struct{UInt32 count;AudioBuffer buffers[2];} source={2,{{1,sizeof(left),left},{1,sizeof(right),right}}};
    NSData *data=PDAudioPCM16(&format,(AudioBufferList *)&source,4);assert(data.length==16);
    const int16_t *samples=data.bytes;
    assert(samples[0]==32767 && samples[1]==16384 && samples[2]==-32768 && samples[3]==-16384);
    assert(samples[4]==0 && samples[5]==0 && samples[6]==32767 && samples[7]==-32768);
    const uint8_t *bytes=data.bytes;assert(bytes[0]==255 && bytes[1]==127 && bytes[4]==0 && bytes[5]==128);
    source.buffers[1].mDataByteSize=1;assert(!PDAudioPCM16(&format,(AudioBufferList *)&source,4));
    float packed[]={.5,-.5,0,1};source.count=1;source.buffers[0]=(AudioBuffer){2,sizeof(packed),packed};
    format.mFormatFlags=kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked;format.mBytesPerFrame=8;
    data=PDAudioPCM16(&format,(AudioBufferList *)&source,2);assert(data.length==8);samples=data.bytes;assert(samples[0]==16384 && samples[1]==-16384 && samples[3]==32767);
    uint8_t big[]={0x12,0x34,0xfe,0xdc};source.buffers[0]=(AudioBuffer){2,sizeof(big),big};
    format.mFormatFlags=kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked|kAudioFormatFlagIsBigEndian;format.mBitsPerChannel=16;format.mBytesPerFrame=4;
    data=PDAudioPCM16(&format,(AudioBufferList *)&source,1);bytes=data.bytes;assert(data.length==4 && bytes[0]==0x34 && bytes[1]==0x12 && bytes[2]==0xdc && bytes[3]==0xfe);
    assert(!PDAudioPCM16(&format,(AudioBufferList *)&source,0));format.mSampleRate=44100;assert(!PDAudioPCM16(&format,(AudioBufferList *)&source,1));
    puts("PASS: planar/interleaved float, PCM16 byte order, clipping, non-finite silence, truncated/unsupported rejection");
}return 0;}
