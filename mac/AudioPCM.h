#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include <math.h>

// Wire format: 48 kHz, stereo, signed 16-bit little-endian PCM.
static NSData *PDAudioPCM16(const AudioStreamBasicDescription *format,const AudioBufferList *buffers,size_t frames){
    if(!format || !buffers || !frames || frames>16384 || format->mFormatID!=kAudioFormatLinearPCM ||
       format->mSampleRate!=48000 || format->mChannelsPerFrame!=2)return nil;
    BOOL floating=(format->mFormatFlags&kAudioFormatFlagIsFloat)!=0;
    BOOL planar=(format->mFormatFlags&kAudioFormatFlagIsNonInterleaved)!=0;
    BOOL big=(format->mFormatFlags&kAudioFormatFlagIsBigEndian)!=0;
    if((floating && format->mBitsPerChannel!=32) || (!floating && (format->mBitsPerChannel!=16 || !(format->mFormatFlags&kAudioFormatFlagIsSignedInteger))))return nil;
    size_t sampleBytes=floating?4:2;
    if(buffers->mNumberBuffers!=(planar?2:1) || format->mBytesPerFrame!=sampleBytes*(planar?1:2))return nil;
    for(UInt32 i=0;i<buffers->mNumberBuffers;i++)if(!buffers->mBuffers[i].mData || buffers->mBuffers[i].mDataByteSize<frames*format->mBytesPerFrame)return nil;
    NSMutableData *output=[NSMutableData dataWithLength:frames*4];uint8_t *dst=output.mutableBytes;
    for(size_t frame=0;frame<frames;frame++)for(int channel=0;channel<2;channel++){
        const uint8_t *src=buffers->mBuffers[planar?channel:0].mData;
        src+=(planar?frame:frame*2+channel)*sampleBytes;int16_t value;
        if(floating){
            uint32_t bits;memcpy(&bits,src,4);bits=big?CFSwapInt32BigToHost(bits):CFSwapInt32LittleToHost(bits);
            float sample;memcpy(&sample,&bits,4);if(!isfinite(sample))sample=0;
            sample=fmaxf(-1,fminf(1,sample));value=sample<=-1?INT16_MIN:(int16_t)lrintf(sample*INT16_MAX);
        }else{uint16_t bits;memcpy(&bits,src,2);value=(int16_t)(big?CFSwapInt16BigToHost(bits):CFSwapInt16LittleToHost(bits));}
        size_t index=(frame*2+channel)*2;dst[index]=(uint16_t)value&255;dst[index+1]=((uint16_t)value>>8)&255;
    }
    return output;
}
