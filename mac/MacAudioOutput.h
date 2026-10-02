#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

static NSString *PDOutputUID(AudioDeviceID device){
    AudioObjectPropertyAddress address={kAudioDevicePropertyDeviceUID,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    CFStringRef uid=NULL;UInt32 size=sizeof(uid);
    if(AudioObjectGetPropertyData(device,&address,0,NULL,&size,&uid)!=noErr)return nil;
    return CFBridgingRelease(uid);
}
static AudioDeviceID PDDefaultOutput(void){
    AudioObjectPropertyAddress address={kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    AudioDeviceID device=0;UInt32 size=sizeof(device);
    AudioObjectGetPropertyData(kAudioObjectSystemObject,&address,0,NULL,&size,&device);return device;
}

// Only restore mute changes owned by this app. Device UIDs survive relaunches.
@interface PDMacAudioOutput:NSObject
@property AudioDeviceID selectedDevice;
@property(strong) NSMutableDictionary<NSString *,NSNumber *> *savedMute;
- (BOOL)setPadOnly:(BOOL)padOnly;
- (void)restore;
@end
@implementation PDMacAudioOutput
- (instancetype)init{
    if((self=[super init])){
        NSDictionary *saved=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"PadOwnedOutputMute"];
        _savedMute=saved?[saved mutableCopy]:[NSMutableDictionary new];[self restore];
    }return self;
}
- (void)persist{
    [NSUserDefaults.standardUserDefaults setObject:_savedMute forKey:@"PadOwnedOutputMute"];
    [NSUserDefaults.standardUserDefaults synchronize];
}
- (void)restore{
    _selectedDevice=0;if(!_savedMute.count)return;
    AudioObjectPropertyAddress list={kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    UInt32 size=0;if(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&list,0,NULL,&size)!=noErr || !size)return;
    NSMutableData *data=[NSMutableData dataWithLength:size];
    if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&list,0,NULL,&size,data.mutableBytes)!=noErr)return;
    const AudioDeviceID *devices=data.bytes;
    AudioObjectPropertyAddress mute={kAudioDevicePropertyMute,kAudioDevicePropertyScopeOutput,kAudioObjectPropertyElementMain};
    for(UInt32 i=0;i<size/sizeof(AudioDeviceID);i++){
        NSString *uid=PDOutputUID(devices[i]);NSNumber *saved=uid?_savedMute[uid]:nil;if(!saved)continue;
        UInt32 current=0,bytes=sizeof(current);
        if(AudioObjectGetPropertyData(devices[i],&mute,0,NULL,&bytes,&current)!=noErr)continue;
        UInt32 original=saved.unsignedIntValue;
        if(!current || AudioObjectSetPropertyData(devices[i],&mute,0,NULL,sizeof(original),&original)==noErr)[_savedMute removeObjectForKey:uid];
    }
    [self persist];
}
- (BOOL)setPadOnly:(BOOL)padOnly{
    if(!padOnly){[self restore];return YES;}
    AudioDeviceID device=PDDefaultOutput();if(!device)return NO;
    if(device==_selectedDevice)return YES;
    [self restore];
    AudioObjectPropertyAddress mute={kAudioDevicePropertyMute,kAudioDevicePropertyScopeOutput,kAudioObjectPropertyElementMain};
    Boolean writable=NO;UInt32 original=0,size=sizeof(original);NSString *uid=PDOutputUID(device);
    if(!uid || AudioObjectIsPropertySettable(device,&mute,&writable)!=noErr || !writable || AudioObjectGetPropertyData(device,&mute,0,NULL,&size,&original)!=noErr)return NO;
    if(!original){
        _savedMute[uid]=@(original);[self persist];UInt32 value=1;
        if(AudioObjectSetPropertyData(device,&mute,0,NULL,sizeof(value),&value)!=noErr){[_savedMute removeObjectForKey:uid];[self persist];return NO;}
    }
    _selectedDevice=device;return YES;
}
@end
