#import <Cocoa/Cocoa.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <VideoToolbox/VideoToolbox.h>
#import <Security/Security.h>
#import <ApplicationServices/ApplicationServices.h>
#import "VirtualDisplay.h"
#import "PenInput.h"
#import "TouchInput.h"
#import "AudioPCM.h"
#import "MacAudioOutput.h"
#import "DisplayLayout.h"
#import "ForegroundSession.h"
#import "Updater.h"
#import "Dashboard.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <unistd.h>
#include <stdatomic.h>
#include <time.h>

static const uint16_t PDPort = 28765;
static uint64_t PDClockNS(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint64_t)t.tv_sec*1000000000ull+t.tv_nsec; }
static BOOL PDRead(int fd, void *bytes, size_t length) {
    size_t offset = 0;
    while (offset < length) { ssize_t n = recv(fd,(char *)bytes+offset,length-offset,0); if (n < 0 && errno == EINTR) continue; if (n <= 0) return NO; offset += n; }
    return YES;
}
static void PDLog(NSString *message) { NSLog(@"PadDisplay: %@", message); }

@interface PDPeer : NSObject
@property int fd;
@property BOOL configured;
@property(strong) NSData *cursorImagePayload;
@property BOOL hasCursorPosition, cursorVisible;
@property float cursorX, cursorY;
@property uint64_t cursorSentAt;
@property(strong) NSLock *lock;
- (BOOL)packet:(uint8_t)type data:(NSData *)data;
- (void)close;
- (BOOL)isConnected;
@end
@implementation PDPeer
- (instancetype)init { if ((self = [super init])) { _fd = -1; _lock = [NSLock new]; } return self; }
- (BOOL)packet:(uint8_t)type data:(NSData *)data {
    [_lock lock];
    BOOL ok = _fd >= 0;
    uint32_t length = htonl((uint32_t)data.length);
    uint8_t header[5]; header[0] = type; memcpy(header+1, &length, 4);
    NSMutableData *packet = [NSMutableData dataWithBytes:header length:5]; [packet appendData:data];
    const char *bytes = packet.bytes; size_t offset = 0;
    while (offset < packet.length && ok) {
            ssize_t result = send(_fd, bytes+offset, packet.length-offset, 0);
            if (result < 0 && errno == EINTR) continue;
            if (result <= 0) { ok = NO; break; } offset += result;
    }
    if (!ok && _fd >= 0) { shutdown(_fd, SHUT_RDWR); close(_fd); _fd = -1; }
    [_lock unlock]; return ok;
}
- (void)close { [_lock lock]; if (_fd >= 0) { shutdown(_fd, SHUT_RDWR); close(_fd); _fd = -1; } [_lock unlock]; }
- (BOOL)isConnected {
    [_lock lock]; BOOL connected = _fd >= 0;
    if (connected) {
        uint8_t byte; ssize_t result = recv(_fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT);
        if (result == 0 || (result < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)) connected = NO;
    }
    [_lock unlock]; return connected;
}
- (void)dealloc { if (_fd >= 0) close(_fd); }
@end

@class PDApp;
@interface PDCapture : NSObject <SCStreamOutput, SCStreamDelegate> {
@public VTCompressionSessionRef encoder;
    atomic_int pending;
    atomic_bool running;
    uint64_t frameNumber;
}
@property(strong) SCStream *stream;
@property(strong) SCStreamConfiguration *configuration;
@property(strong) dispatch_queue_t queue;
@property(strong) dispatch_queue_t audioQueue;
@property(weak) PDApp *app;
@property int width, height, fps;
@property uint64_t encodedFrames, encodedBytes;
@property uint64_t audioFrames;
- (BOOL)prepareEncoder;
- (void)stop;
- (void)encoded:(CMSampleBufferRef)sample status:(OSStatus)status;
- (void)sendAudio:(CMSampleBufferRef)sample;
@end

@interface PDApp : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(strong) NSWindow *window;
@property(strong) NSTextField *status, *detail;
@property(strong) NSTextField *connectionTitle, *connectionBadge, *settingsHint;
@property(strong) PDConnectionArtwork *connectionArtwork;
@property(strong) NSButton *permissionRepairButton;
@property(strong) NSTextField *penStatus;
@property BOOL penDown,penRight,penProximity;
@property CGPoint penPoint;
@property uint64_t penEvents,penEventNumber,lastPenDown;
@property NSInteger penClickCount;
@property BOOL touchDown;
@property CGPoint touchPoint,touchLastDownPoint;
@property uint64_t touchEvents,touchEventNumber,lastTouchDown;
@property NSInteger touchClickCount;
@property double touchScrollX,touchScrollY;
@property(strong) NSPopUpButton *mode, *resolution, *rate;
@property(strong) NSButton *startButton, *stopButton;
@property(strong) NSButton *updateButton;
@property(strong) PDUpdater *updater;
@property(strong) NSPopUpButton *audioDestination;
@property(strong) NSArray<NSMenuItem *> *audioMenuItems;
@property(strong) PDMacAudioOutput *macAudioOutput;
@property(strong) PDDisplayLayout *displayLayout;
@property(strong) PDForegroundSession *foregroundSession;
@property(copy) NSString *layoutDevice;
@property BOOL layoutReady;
@property(atomic) BOOL audioEnabled;
@property(strong) NSStatusItem *statusItem;
@property(strong) PDCapture *capture;
@property(strong) CGVirtualDisplay *virtualDisplay;
@property(atomic, strong) PDPeer *peer;
@property(atomic, strong) PDPeer *cursorPeer;
@property(atomic, strong) PDPeer *audioPeer;
@property(strong) dispatch_source_t cursorTimer;
@property(strong) NSTimer *cursorImageTimer;
@property(atomic, strong) NSData *cursorImagePayload;
@property(strong) NSData *lastCursorTIFF;
@property NSPoint lastCursorHotSpot;
@property(atomic) double cursorRTT;
@property(atomic) BOOL inputTrusted;
@property(copy) NSString *token, *serial, *adbPath;
@property int listener, cursorListener, audioListener;
@property BOOL starting, active, quitting, reconnecting, preparingCapture, screenCaptureDenied;
@property int reconnectTicks;
@property NSUInteger generation;
@property CGDirectDisplayID targetDisplay;
@property CGDirectDisplayID anchorDisplay;
@property(strong) NSTimer *timer;
- (void)updateStatus:(NSString *)text;
- (void)start:(id)sender;
- (void)stop:(id)sender;
- (void)stopCapture;
- (void)pauseForPeer:(PDPeer *)peer;
@end

static void PDEncoded(void *refcon, void *source, OSStatus status, VTEncodeInfoFlags flags, CMSampleBufferRef sample) {
    PDCapture *capture = (__bridge PDCapture *)refcon;
    [capture encoded:sample status:status];
    atomic_fetch_sub(&capture->pending, 1);
}
@implementation PDCapture
- (instancetype)init { if ((self = [super init])) { atomic_init(&pending, 0); atomic_init(&running, false); _queue = dispatch_queue_create("studio.prxs.paddisplay.capture", DISPATCH_QUEUE_SERIAL); _audioQueue=dispatch_queue_create("studio.prxs.paddisplay.audio",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_USER_INTERACTIVE,0)); } return self; }
- (BOOL)prepareEncoder {
    NSDictionary *spec = @{(__bridge NSString *)kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder:@YES,
        (__bridge NSString *)kVTVideoEncoderSpecification_EnableLowLatencyRateControl:@YES};
    OSStatus result = VTCompressionSessionCreate(NULL, _width, _height, kCMVideoCodecType_H264,
        (__bridge CFDictionaryRef)spec, NULL, NULL, PDEncoded, (__bridge void *)self, &encoder);
    if (result != noErr || !encoder) { PDLog([NSString stringWithFormat:@"Encoder creation failed: %d", (int)result]); return NO; }
    VTSessionSetProperty(encoder, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(encoder, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
    VTSessionSetProperty(encoder, kVTCompressionPropertyKey_MaxFrameDelayCount, (__bridge CFNumberRef)@1);
    VTSessionSetProperty(encoder, kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, kCFBooleanTrue);
    VTSessionSetProperty(encoder, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel);
    int bitrate = _width > 2000 ? 36000000 : (_fps == 60 ? 16000000 : 12000000);
    VTSessionSetProperty(encoder, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFNumberRef)@(bitrate));
    VTSessionSetProperty(encoder, kVTCompressionPropertyKey_ExpectedFrameRate, (__bridge CFNumberRef)@(_fps));
    VTSessionSetProperty(encoder, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFNumberRef)@(_fps));
    VTSessionSetProperty(encoder, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, (__bridge CFNumberRef)@1);
    result = VTCompressionSessionPrepareToEncodeFrames(encoder);
    atomic_store(&running, result == noErr);
    return result == noErr;
}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    if(type==SCStreamOutputTypeAudio){[self sendAudio:sample];return;}
    if (type != SCStreamOutputTypeScreen || !atomic_load(&running) || !_app.peer || !CMSampleBufferIsValid(sample)) return;
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sample, false);
    if (attachments && CFArrayGetCount(attachments)) {
        NSDictionary *info = (__bridge NSDictionary *)CFArrayGetValueAtIndex(attachments, 0);
        NSNumber *status = info[SCStreamFrameInfoStatus];
        if (status && status.integerValue != SCFrameStatusComplete) return;
    }
    CVPixelBufferRef pixel = CMSampleBufferGetImageBuffer(sample);
    if (!pixel || atomic_load(&pending) >= 2) return;
    BOOL keyframe = !_app.peer.configured || frameNumber % _fps == 0;
    NSDictionary *options = keyframe ? @{(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame:@YES} : nil;
    atomic_fetch_add(&pending, 1); frameNumber++;
    OSStatus result = VTCompressionSessionEncodeFrame(encoder, pixel, CMSampleBufferGetPresentationTimeStamp(sample),
        CMTimeMake(1, _fps), (__bridge CFDictionaryRef)options, NULL, NULL);
    if (result != noErr) { atomic_fetch_sub(&pending, 1); PDLog([NSString stringWithFormat:@"Encode failed: %d", (int)result]); }
}
- (void)encoded:(CMSampleBufferRef)sample status:(OSStatus)status {
    if (status || !sample || !atomic_load(&running)) return;
    PDPeer *peer = _app.peer; if (!peer) return;
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sample, false);
    BOOL key = YES;
    if (attachments && CFArrayGetCount(attachments)) {
        NSDictionary *a = (__bridge NSDictionary *)CFArrayGetValueAtIndex(attachments, 0);
        key = ![a[(__bridge NSString *)kCMSampleAttachmentKey_NotSync] boolValue];
    }
    NSMutableData *output = [NSMutableData data];
    const uint8_t prefix[] = {0, 0, 0, 1};
    CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sample);
    int headerLength = 4;
    if (key) {
        const uint8_t *sps, *pps; size_t sl = 0, pl = 0, count = 0;
        if (CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sps, &sl, &count, &headerLength) != noErr ||
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pps, &pl, NULL, NULL) != noErr) return;
        NSMutableData *spsData = [NSMutableData dataWithBytes:prefix length:4]; [spsData appendBytes:sps length:sl];
        NSMutableData *ppsData = [NSMutableData dataWithBytes:prefix length:4]; [ppsData appendBytes:pps length:pl];
        if (!peer.configured) {
            NSDictionary *config = @{@"width":@(_width), @"height":@(_height), @"fps":@(_fps),
                @"sps":[spsData base64EncodedStringWithOptions:0], @"pps":[ppsData base64EncodedStringWithOptions:0]};
            NSData *json = [NSJSONSerialization dataWithJSONObject:config options:0 error:nil];
            if (![peer packet:1 data:json]) { dispatch_async(dispatch_get_main_queue(), ^{ [self.app pauseForPeer:peer]; }); return; }
            peer.configured = YES;
        }
        [output appendData:spsData]; [output appendData:ppsData];
    }
    if (!peer.configured) return;
    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
    size_t size = CMBlockBufferGetDataLength(block);
    NSMutableData *buffer = [NSMutableData dataWithLength:size];
    if (CMBlockBufferCopyDataBytes(block, 0, size, buffer.mutableBytes) != noErr) return;
    const uint8_t *data = buffer.bytes; size_t offset = 0;
    while (offset + headerLength <= size) {
        uint32_t length = 0;
        for (int i = 0; i < headerLength; i++) length = (length << 8) | data[offset+i];
        offset += headerLength; if (!length || length > size-offset) return;
        [output appendBytes:prefix length:4]; [output appendBytes:data+offset length:length]; offset += length;
    }
    if ([peer packet:2 data:output]) { _encodedFrames++; _encodedBytes += output.length; }
    else { dispatch_async(dispatch_get_main_queue(), ^{ [self.app pauseForPeer:peer]; }); }
}
- (void)sendAudio:(CMSampleBufferRef)sample {
    PDPeer *peer=_app.audioPeer;
    if(!atomic_load(&running) || !_app.audioEnabled || !peer || !CMSampleBufferIsValid(sample))return;
    CMTime stamp=CMSampleBufferGetPresentationTimeStamp(sample);
    double age=CMTimeGetSeconds(CMTimeSubtract(CMClockGetTime(CMClockGetHostTimeClock()),stamp));
    if(isfinite(age) && age>.1)return;
    const AudioStreamBasicDescription *format=CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sample));
    struct {UInt32 count;AudioBuffer buffers[2];} storage={0};
    CMBlockBufferRef block=NULL;
    OSStatus status=CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample,NULL,(AudioBufferList *)&storage,sizeof(storage),NULL,NULL,kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,&block);
    if(status!=noErr){if(block)CFRelease(block);return;}
    NSData *pcm=PDAudioPCM16(format,(AudioBufferList *)&storage,CMSampleBufferGetNumSamples(sample));
    if(block)CFRelease(block);
    if(!pcm)return;
    if([peer packet:9 data:pcm]){
        if(!_audioFrames)PDLog(@"Audio streaming: 48000 Hz stereo PCM16 over dedicated USB channel");
        _audioFrames+=pcm.length/4;
    }else if(_app.audioPeer==peer)_app.audioPeer=nil;
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.app.capture != self) return;
        self.app.screenCaptureDenied=[error.domain isEqualToString:SCStreamErrorDomain] && error.code==SCStreamErrorUserDeclined;
        [self.app stop:nil]; [self.app updateStatus:[@"화면 전송 중단: " stringByAppendingString:error.localizedDescription]];
    });
}
- (void)stop {
    atomic_store(&running, false);
    SCStream *oldStream = _stream; _stream = nil;
    [oldStream stopCaptureWithCompletionHandler:^(NSError *error) { }];
    dispatch_sync(_queue, ^{
        if (self->encoder) { VTCompressionSessionCompleteFrames(self->encoder, kCMTimeInvalid); VTCompressionSessionInvalidate(self->encoder); CFRelease(self->encoder); self->encoder = NULL; }
    });
    dispatch_sync(_audioQueue,^{});
}
- (void)dealloc { if (encoder) { VTCompressionSessionInvalidate(encoder); CFRelease(encoder); } }
@end

@implementation PDApp
- (NSStackView *)field:(NSString *)title control:(NSPopUpButton *)control {
    NSTextField *label=PDText(title,12,NSFontWeightMedium); label.textColor=NSColor.secondaryLabelColor;
    control.translatesAutoresizingMaskIntoConstraints=NO; control.font=[NSFont systemFontOfSize:13];
    NSStackView *field=PDStack(@[label,control],NSUserInterfaceLayoutOrientationVertical,6);
    [control.leadingAnchor constraintEqualToAnchor:field.leadingAnchor].active=YES;
    [control.trailingAnchor constraintEqualToAnchor:field.trailingAnchor].active=YES;
    [control.heightAnchor constraintEqualToConstant:30].active=YES;
    return field;
}
- (void)buildDashboardWithAudioChoice:(NSInteger)audioChoice {
    _window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,760,660)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    _window.title=@"SidePad"; _window.delegate=self;
    _window.titlebarAppearsTransparent=YES; _window.titleVisibility=NSWindowTitleHidden;
    _window.backgroundColor=NSColor.windowBackgroundColor;
    _window.minSize=NSMakeSize(720,690); _window.maxSize=NSMakeSize(1100,950);
    [_window center];

    NSImageView *icon=[NSImageView imageViewWithImage:NSApp.applicationIconImage];
    icon.translatesAutoresizingMaskIntoConstraints=NO; icon.imageScaling=NSImageScaleProportionallyUpOrDown;
    [icon.widthAnchor constraintEqualToConstant:48].active=YES; [icon.heightAnchor constraintEqualToConstant:48].active=YES;
    NSString *version=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSTextField *versionLabel=PDText(version,11,NSFontWeightMedium); versionLabel.textColor=NSColor.secondaryLabelColor;
    NSStackView *brand=PDStack(@[PDText(@"SidePad",25,NSFontWeightSemibold),versionLabel],NSUserInterfaceLayoutOrientationHorizontal,9);
    NSTextField *subtitle=PDText(@"USB-C로 이어지는 두 번째 화면",12,NSFontWeightRegular); subtitle.textColor=NSColor.secondaryLabelColor;
    NSStackView *titles=PDStack(@[brand,subtitle],NSUserInterfaceLayoutOrientationVertical,3);
    _updateButton=PDAction(@"업데이트 확인",@"arrow.triangle.2.circlepath",self,@selector(checkUpdates:));
    NSStackView *header=PDStack(@[icon,titles,PDSpacer(),_updateButton],NSUserInterfaceLayoutOrientationHorizontal,12);

    PDCard *connection=[PDCard new]; connection.translatesAutoresizingMaskIntoConstraints=NO; connection.tinted=YES;
    _connectionArtwork=[PDConnectionArtwork new]; _connectionArtwork.translatesAutoresizingMaskIntoConstraints=NO;
    [_connectionArtwork.widthAnchor constraintEqualToConstant:218].active=YES;
    [_connectionArtwork.heightAnchor constraintEqualToConstant:164].active=YES;
    _connectionBadge=PDText(@"USB-C · 연결 준비",11,NSFontWeightSemibold); _connectionBadge.textColor=NSColor.controlAccentColor;
    _connectionTitle=PDText(@"패드를 연결하세요",24,NSFontWeightSemibold);
    _status=PDText(@"패드를 USB-C로 연결하고 연결 시작을 눌러 주세요.",12,NSFontWeightRegular);
    _status.textColor=NSColor.secondaryLabelColor;
    [_status.heightAnchor constraintEqualToConstant:46].active=YES;
    _detail=PDText(@"마지막 해상도와 모니터 배열을 기억합니다.",11,NSFontWeightRegular); _detail.textColor=NSColor.secondaryLabelColor;
    [_detail.heightAnchor constraintEqualToConstant:29].active=YES;
    _startButton=PDAction(@"연결 시작",@"play.fill",self,@selector(start:));
    _startButton.bezelColor=NSColor.controlAccentColor; _startButton.keyEquivalent=@"\r";
    [_startButton.widthAnchor constraintEqualToConstant:130].active=YES;
    _stopButton=PDAction(@"중지",@"stop.fill",self,@selector(stop:)); _stopButton.enabled=NO;
    NSButton *arrange=PDAction(@"배치 조정",@"rectangle.3.group",self,@selector(displays:));
    arrange.toolTip=@"시스템 설정에서 모니터 배열을 조정합니다. 배치는 다음 연결에 복원됩니다.";
    NSStackView *actions=PDStack(@[_startButton,_stopButton,PDSpacer(),arrange],NSUserInterfaceLayoutOrientationHorizontal,8);
    NSStackView *connectionText=PDStack(@[_connectionBadge,_connectionTitle,_status,_detail,actions],NSUserInterfaceLayoutOrientationVertical,6);
    for (NSView *view in @[_status,_detail,actions]) [view.widthAnchor constraintEqualToAnchor:connectionText.widthAnchor].active=YES;
    NSStackView *connectionRow=PDStack(@[_connectionArtwork,connectionText],NSUserInterfaceLayoutOrientationHorizontal,22);
    PDPin(connection,connectionRow,18);

    _mode=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_mode addItemsWithTitles:@[@"확장 모니터 · 서로 다른 화면",@"화면 복제 · Mac의 주 화면"]];
    _resolution=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_resolution addItemsWithTitles:@[@"1920 × 1200 · 균형",@"1472 × 920 · 가볍게",@"2944 × 1840 · Retina"]]; [_resolution selectItemAtIndex:2];
    _resolution.toolTip=@"Retina는 2944 × 1840 실제 픽셀에 1472 × 920 크기의 작업 공간을 표시합니다.";
    _rate=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [_rate addItemsWithTitles:@[@"60 fps · 부드럽게",@"30 fps · 가볍게"]];
    NSDictionary *options=@{@"PadDisplayMode":_mode,@"PadDisplayResolution":_resolution,@"PadDisplayRate":_rate};
    for (NSString *key in options) {
        NSPopUpButton *button=options[key]; id saved=[NSUserDefaults.standardUserDefaults objectForKey:key];
        if ([saved isKindOfClass:NSNumber.class] && [saved integerValue]>=0 && [saved integerValue]<button.numberOfItems) [button selectItemAtIndex:[saved integerValue]];
        button.target=self; button.action=@selector(rememberOptions:);
    }
    _audioDestination=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_audioDestination addItemsWithTitles:@[@"Mac + 패드 · 둘 다",@"패드만",@"Mac만"]]; [_audioDestination selectItemAtIndex:audioChoice];
    _audioDestination.target=self; _audioDestination.action=@selector(toggleAudio:);
    NSStackView *firstRow=PDStack(@[[self field:@"화면 모드" control:_mode],[self field:@"해상도" control:_resolution]],NSUserInterfaceLayoutOrientationHorizontal,20);
    NSStackView *secondRow=PDStack(@[[self field:@"영상 프레임" control:_rate],[self field:@"소리 출력" control:_audioDestination]],NSUserInterfaceLayoutOrientationHorizontal,20);
    firstRow.distribution=NSStackViewDistributionFillEqually; secondRow.distribution=NSStackViewDistributionFillEqually;
    _settingsHint=PDText(@"원하는 화면 환경으로 설정하세요.",11,NSFontWeightRegular); _settingsHint.textColor=NSColor.secondaryLabelColor;
    NSStackView *settingsHeader=PDStack(@[PDText(@"화면과 소리",14,NSFontWeightSemibold),PDSpacer(),_settingsHint],NSUserInterfaceLayoutOrientationHorizontal,12);
    NSStackView *settings=PDStack(@[settingsHeader,firstRow,secondRow],NSUserInterfaceLayoutOrientationVertical,12);
    for (NSView *row in settings.arrangedSubviews) [row.widthAnchor constraintEqualToAnchor:settings.widthAnchor].active=YES;
    PDCard *settingsCard=[PDCard new]; settingsCard.translatesAutoresizingMaskIntoConstraints=NO; PDPin(settingsCard,settings,18);

    _penStatus=PDText(@"펜·터치 권한을 확인하세요.",11,NSFontWeightRegular); _penStatus.textColor=NSColor.secondaryLabelColor;
    NSStackView *permissionText=PDStack(@[PDText(@"권한",14,NSFontWeightSemibold),_penStatus],NSUserInterfaceLayoutOrientationVertical,5);
    NSButton *screen=PDAction(@"화면 권한",@"record.circle",self,@selector(permission:));
    NSButton *input=PDAction(@"펜·터치 권한",@"hand.point.up.left",self,@selector(inputPermission:));
    _permissionRepairButton=PDAction(@"승인 복구",@"arrow.clockwise",self,@selector(repairScreenPermission:)); _permissionRepairButton.hidden=YES;
    NSStackView *permissions=PDStack(@[permissionText,PDSpacer(),screen,input,_permissionRepairButton],NSUserInterfaceLayoutOrientationHorizontal,10);
    PDCard *permissionCard=[PDCard new]; permissionCard.translatesAutoresizingMaskIntoConstraints=NO; PDPin(permissionCard,permissions,16);
    NSButton *support=PDAction(@"버그 신고 · 문의",@"envelope",self,@selector(support:)); support.bordered=NO;
    support.toolTip=@"studio.prxs@gmail.com";
    NSButton *guide=PDAction(@"설치·사용 안내",@"questionmark.circle",self,@selector(setupGuide:)); guide.bordered=NO;
    NSStackView *footer=PDStack(@[support,PDSpacer(),guide],NSUserInterfaceLayoutOrientationHorizontal,12);
    NSStackView *root=PDStack(@[header,connection,settingsCard,permissionCard,footer],NSUserInterfaceLayoutOrientationVertical,14);
    for (NSView *view in root.arrangedSubviews) [view.widthAnchor constraintEqualToAnchor:root.widthAnchor].active=YES;
    PDPin(_window.contentView,root,20);
}
- (void)updateDashboard {
    BOOL connected=_active && _peer && _peer.configured && _capture.encodedFrames>0;
    NSInteger state=_screenCaptureDenied ? 3 : (connected ? 2 : (_starting ? 1 : 0));
    _connectionArtwork.connectionState=state;
    _connectionTitle.stringValue=state==3 ? @"화면 권한을 확인하세요" : (connected ? @"패드와 연결됨" : (_starting ? @"패드에 연결하는 중" : (_foregroundSession.paired ? @"패드 연결 대기 중" : @"패드를 연결하세요")));
    _connectionBadge.stringValue=state==3 ? @"화면 기록 승인 필요" : (connected ? @"USB-C · 연결됨" : (_starting ? @"USB-C · 연결 중" : @"USB-C · 연결 대기"));
    _connectionBadge.textColor=state==3 ? NSColor.systemOrangeColor : (connected ? NSColor.systemGreenColor : NSColor.controlAccentColor);
    _permissionRepairButton.hidden=!_screenCaptureDenied;
    _settingsHint.stringValue=(_active || _starting) ? @"화면 설정은 연결을 중지한 뒤 변경하세요." : @"원하는 화면 환경으로 설정하세요.";
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _listener = -1; _cursorListener = -1; _audioListener=-1;
    _macAudioOutput=[PDMacAudioOutput new];
    _displayLayout=[[PDDisplayLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    _foregroundSession=[PDForegroundSession new];
    NSInteger audioChoice=[NSUserDefaults.standardUserDefaults integerForKey:@"PadAudioDestination"];
    if(audioChoice<0 || audioChoice>2)audioChoice=0;
    self.audioEnabled=audioChoice!=2;
    NSString *iconPath=[[NSBundle mainBundle] pathForResource:@"PadDisplayRounded" ofType:@"icns"];
    if(iconPath)NSApp.applicationIconImage=[[NSImage alloc] initWithContentsOfFile:iconPath];
    _token = [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    for (NSString *path in @[@"/opt/homebrew/bin/adb", @"/usr/local/bin/adb", [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Android/sdk/platform-tools/adb"]]) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) { _adbPath = path; break; }
    }
    [self buildDashboardWithAudioChoice:audioChoice];
    _updater=[PDUpdater new];
    __weak PDApp *weakSelf=self;
    _updater.stateChanged=^(NSString *title) { weakSelf.updateButton.title=title; weakSelf.updateButton.enabled=!weakSelf.updater.busy; };
    NSMenu *main = [NSMenu new], *application = [NSMenu new]; NSMenuItem *root = [NSMenuItem new]; root.submenu = application; [main addItem:root];
    [self addSetupItemsToMenu:application];
    [application addItem:[NSMenuItem separatorItem]];
    [application addItemWithTitle:@"SidePad 종료" action:@selector(terminate:) keyEquivalent:@"q"]; NSApp.mainMenu = main;
    _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength]; _statusItem.button.title = @"▣ SidePad";
    NSMenu *menu = [NSMenu new]; NSMenuItem *show = [menu addItemWithTitle:@"SidePad 열기" action:@selector(show:) keyEquivalent:@""]; show.target = self;
    NSMenuItem *stop = [menu addItemWithTitle:@"화면 전송 중지" action:@selector(stop:) keyEquivalent:@""]; stop.target = self;
    NSMenuItem *audioItem=[menu addItemWithTitle:@"소리 출력" action:nil keyEquivalent:@""];NSMenu *audioMenu=[NSMenu new];audioItem.submenu=audioMenu;
    NSMutableArray *audioItems=[NSMutableArray new];
    for(NSInteger i=0;i<3;i++){NSMenuItem *item=[audioMenu addItemWithTitle:@[@"Mac + 패드 · 둘 다",@"패드만",@"Mac만"][i] action:@selector(chooseAudio:) keyEquivalent:@""];item.target=self;item.tag=i;item.state=i==audioChoice?NSControlStateValueOn:NSControlStateValueOff;[audioItems addObject:item];}
    _audioMenuItems=audioItems;
    [menu addItem:[NSMenuItem separatorItem]];
    [self addSetupItemsToMenu:menu];
    [menu addItem:[NSMenuItem separatorItem]]; [menu addItemWithTitle:@"종료" action:@selector(terminate:) keyEquivalent:@"q"]; _statusItem.menu = menu;
    [_window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    [self listen];
    [self updateCursorImage:nil];
    _cursorImageTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/15 target:self selector:@selector(updateCursorImage:) userInfo:nil repeats:YES];
    [self startCursorSender];
    _timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    if (![[NSProcessInfo processInfo].arguments containsObject:@"--no-auto"]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self start:nil]; });
}
- (void)show:(id)sender { [_window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
- (BOOL)windowShouldClose:(NSWindow *)sender { [sender orderOut:nil]; return NO; }
- (void)updateStatus:(NSString *)text {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ [self updateStatus:text]; }); return; }
    _status.stringValue = text; [self updateDashboard]; PDLog(text);
}
- (void)addSetupItemsToMenu:(NSMenu *)menu {
    NSMenuItem *update=[menu addItemWithTitle:@"업데이트 확인…" action:@selector(checkUpdates:) keyEquivalent:@""];
    update.target=self;
    NSMenuItem *security = [menu addItemWithTitle:@"실행 승인 설정 열기…" action:@selector(securitySettings:) keyEquivalent:@""];
    security.target = self;
    NSMenuItem *guide = [menu addItemWithTitle:@"설치·권한 안내…" action:@selector(setupGuide:) keyEquivalent:@""];
    guide.target = self;
    NSMenuItem *support=[menu addItemWithTitle:@"버그 신고 및 문의…" action:@selector(support:) keyEquivalent:@""];
    support.target=self;
    NSMenuItem *repair=[menu addItemWithTitle:@"화면 기록 승인 복구…" action:@selector(repairScreenPermission:) keyEquivalent:@""];
    repair.target=self;
}
- (void)checkUpdates:(id)sender { [self show:nil]; [_updater check]; }
- (void)support:(id)sender {
    NSAlert *alert=[NSAlert new]; alert.messageText=@"버그 신고 및 문의";
    alert.informativeText=@"studio.prxs@gmail.com\n\n오류, 연결 문제, 기능 제안을 보내 주세요. Mac·패드의 SidePad 버전, 기종과 운영체제 버전, 증상과 재현 순서를 함께 알려 주시면 확인에 도움이 됩니다.";
    [alert addButtonWithTitle:@"메일 쓰기"]; [alert addButtonWithTitle:@"주소 복사"]; [alert addButtonWithTitle:@"닫기"];
    NSModalResponse result=[alert runModal];
    if (result==NSAlertFirstButtonReturn) {
        NSString *subject=[@"[SidePad] 버그 신고 및 문의" stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
        NSURL *url=[NSURL URLWithString:[@"mailto:studio.prxs@gmail.com?subject=" stringByAppendingString:subject]];
        if (![NSWorkspace.sharedWorkspace openURL:url]) [self updateStatus:@"메일 앱을 열지 못했습니다. studio.prxs@gmail.com으로 문의해 주세요."];
    } else if (result==NSAlertSecondButtonReturn) {
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard setString:@"studio.prxs@gmail.com" forType:NSPasteboardTypeString];
    }
}
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action==@selector(checkUpdates:)) return !_updater.busy;
    return YES;
}
- (void)securitySettings:(id)sender {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?General"];
    if (![[NSWorkspace sharedWorkspace] openURL:url]) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"시스템 설정에서 실행을 허용하세요";
        alert.informativeText = @"시스템 설정 → 개인정보 보호 및 보안 → 보안에서 SidePad의 ‘그래도 열기’를 선택하세요. 항목이 없으면 SidePad를 한 번 열어 경고를 확인한 뒤 다시 시도하세요.";
        [alert addButtonWithTitle:@"확인"];
        [alert beginSheetModalForWindow:_window completionHandler:nil];
    }
}
- (void)setupGuide:(id)sender {
    NSURL *guide = [[NSBundle mainBundle] URLForResource:@"StartHere-ko" withExtension:@"html"];
    if (!guide || ![[NSWorkspace sharedWorkspace] openURL:guide]) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://support.apple.com/ko-kr/102445"]];
    }
}
- (void)permission:(id)sender { [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"]]; }
- (void)repairScreenPermission:(id)sender {
    NSAlert *alert=[NSAlert new]; alert.messageText=@"SidePad 화면 기록 승인을 다시 등록할까요?";
    alert.informativeText=@"이전 버전의 서명으로 저장된 승인은 켜져 있어도 새 앱에 적용되지 않을 수 있습니다. SidePad의 화면 기록 승인만 초기화합니다. 새 요청을 허용하고 시스템 설정에서 SidePad를 켠 뒤 앱을 다시 실행해 주세요.";
    [alert addButtonWithTitle:@"승인 다시 등록"]; [alert addButtonWithTitle:@"취소"];
    if ([alert runModal]!=NSAlertFirstButtonReturn) return;
    [self stop:nil];
    NSTask *task=[NSTask new]; task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/tccutil"];
    task.arguments=@[@"reset",@"ScreenCapture",@"studio.prxs.paddisplay.mac"];
    NSError *error=nil;
    if (![task launchAndReturnError:&error]) { [self updateStatus:@"승인을 초기화하지 못했습니다. 시스템 설정에서 SidePad 항목을 제거한 뒤 다시 추가해 주세요."]; return; }
    [task waitUntilExit];
    if (task.terminationStatus!=0) { [self updateStatus:@"승인을 초기화하지 못했습니다. 시스템 설정에서 SidePad 항목을 제거한 뒤 다시 추가해 주세요."]; return; }
    self.screenCaptureDenied=YES;
    CGRequestScreenCaptureAccess(); // Only this explicit repair action requests permission.
    [self permission:nil];
    [self updateStatus:@"새 SidePad의 화면 기록을 허용한 뒤 앱을 종료했다가 다시 열어 주세요."];
}
- (void)displays:(id)sender { [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.Displays-Settings.extension"]]; }
- (void)inputPermission:(id)sender {
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}
- (void)sendAudioState {
    PDPeer *peer=self.audioPeer;if(!peer)return;uint8_t enabled=self.audioEnabled;
    if(![peer packet:10 data:[NSData dataWithBytes:&enabled length:1]] && self.audioPeer==peer)self.audioPeer=nil;
}
- (void)applyAudioOutput {
    if(self.audioPeer && ![self.audioPeer isConnected]){[self.audioPeer close];self.audioPeer=nil;}
    BOOL padOnly=_active && self.audioEnabled && _audioDestination.indexOfSelectedItem==1 && self.audioPeer && _capture.audioFrames>0;
    if(![_macAudioOutput setPadOnly:padOnly]){
        [_audioDestination selectItemAtIndex:0];[NSUserDefaults.standardUserDefaults setInteger:0 forKey:@"PadAudioDestination"];
        for(NSMenuItem *item in _audioMenuItems)item.state=item.tag==0?NSControlStateValueOn:NSControlStateValueOff;
        [self updateStatus:@"이 Mac 출력 장치는 음소거를 지원하지 않아 양쪽 소리를 유지합니다."];
    }
}
- (void)chooseAudio:(NSMenuItem *)item {[_audioDestination selectItemAtIndex:item.tag];[self toggleAudio:item];}
- (void)toggleAudio:(id)sender {
    NSInteger choice=_audioDestination.indexOfSelectedItem;
    self.audioEnabled=choice!=2;
    [NSUserDefaults.standardUserDefaults setInteger:choice forKey:@"PadAudioDestination"];
    for(NSMenuItem *item in _audioMenuItems)item.state=item.tag==choice?NSControlStateValueOn:NSControlStateValueOff;
    [self applyAudioOutput];
    PDCapture *capture=_capture;
    dispatch_async(capture?capture.audioQueue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[self sendAudioState];});
    if(!capture)return;
    capture.configuration.capturesAudio=self.audioEnabled;
    [capture.stream updateConfiguration:capture.configuration completionHandler:^(NSError *error){
        if(error)dispatch_async(dispatch_get_main_queue(),^{
            if(self.capture!=capture)return;self.audioEnabled=NO;[self.audioDestination selectItemAtIndex:2];
            [NSUserDefaults.standardUserDefaults setInteger:2 forKey:@"PadAudioDestination"];
            [self.macAudioOutput restore];for(NSMenuItem *item in self.audioMenuItems)item.state=item.tag==2?NSControlStateValueOn:NSControlStateValueOff;
            dispatch_async(capture.audioQueue,^{[self sendAudioState];});
            [self updateStatus:[@"소리 전송 설정 실패: " stringByAppendingString:error.localizedDescription]];
        });
    }];
}
- (void)rememberOptions:(id)sender {
    [NSUserDefaults.standardUserDefaults setInteger:_mode.indexOfSelectedItem forKey:@"PadDisplayMode"];
    [NSUserDefaults.standardUserDefaults setInteger:_resolution.indexOfSelectedItem forKey:@"PadDisplayResolution"];
    [NSUserDefaults.standardUserDefaults setInteger:_rate.indexOfSelectedItem forKey:@"PadDisplayRate"];
}
- (void)tick:(id)sender {
    [self applyAudioOutput];
    BOOL trusted=AXIsProcessTrusted();
    if(self.inputTrusted && !trusted){[self releasePen];[self releaseTouch];}
    self.inputTrusted=trusted;
    _penStatus.stringValue=trusted ? @"펜과 터치를 사용할 수 있습니다." : @"펜·터치 허용이 필요합니다.";
    [self updateDashboard];
    if (_active) {
        if (_layoutReady && _virtualDisplay) [_displayLayout saveForDevice:_layoutDevice display:_targetDisplay];
        if (_peer && ![_peer isConnected]) { [self pauseForPeer:_peer]; return; }
        BOOL connected = _peer != nil && _peer.configured && _capture.encodedFrames > 0;
        _status.stringValue = connected ? @"연결됨 · USB-C로 화면 전송 중" : (_peer ? @"USB 연결됨 · 첫 화면 전송 대기 중" : @"패드 연결 대기 중 · USB-C 케이블을 확인하세요.");
        NSString *timing = self.cursorRTT>0 ? [NSString stringWithFormat:@"USB 왕복 %.1f ms", self.cursorRTT] : @"커서 연결 측정 중";
        _detail.stringValue = [NSString stringWithFormat:@"%d × %d · 영상 최대 %d fps · 커서 최대 120 Hz · %@", _capture.width, _capture.height, _capture.fps, timing];
        _statusItem.button.title = connected ? @"▣ SidePad ●" : @"▣ SidePad ○";
    }
    // Transport maintenance must never launch an app, wake the tablet, or install an APK.
    // The foreground Android activity retries its own connection after cable recovery.
    if (_foregroundSession.paired && _serial && !_peer && !_starting && !_reconnecting && ++_reconnectTicks >= 5) {
        _reconnectTicks = 0; _reconnecting = YES; NSString *serial = [_serial copy];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
            [self repairUSBForSerial:serial];
            dispatch_async(dispatch_get_main_queue(), ^{ self.reconnecting = NO; });
        });
    }
    if (_peer) _reconnectTicks = 0;
}
- (NSString *)adb:(NSArray<NSString *> *)arguments error:(BOOL *)failed {
    if (!_adbPath) { if (failed) *failed = YES; return @"ADB를 찾을 수 없습니다."; }
    NSTask *task = [NSTask new]; task.executableURL = [NSURL fileURLWithPath:_adbPath]; task.arguments = arguments;
    NSPipe *pipe = [NSPipe pipe]; task.standardOutput = pipe; task.standardError = pipe;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) { if (failed) *failed = YES; return error.localizedDescription; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15*NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{ if (task.running) [task terminate]; });
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile]; [task waitUntilExit];
    if (failed) *failed = task.terminationStatus != 0;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}
- (void)repairUSBForSerial:(NSString *)serial {
    if (self.quitting) return;
    BOOL failed = NO;
    [self adb:@[@"-s",serial,@"get-state"] error:&failed];
    if (failed) return;
    for (int port=PDPort; port<=PDPort+2 && !self.quitting; port++) {
        NSString *endpoint=[NSString stringWithFormat:@"tcp:%d",port];
        [self adb:@[@"-s",serial,@"reverse",@"--no-rebind",endpoint,endpoint] error:nil];
    }
}
- (BOOL)connectUSBWithForeground:(NSString *)foreground generation:(NSUInteger)generation {
    BOOL failed = NO; NSString *devices = [self adb:@[@"devices"] error:&failed];
    NSMutableArray *serials = [NSMutableArray new];
    for (NSString *line in [devices componentsSeparatedByString:@"\n"]) {
        NSArray *parts = [line componentsSeparatedByString:@"\t"];
        if (parts.count == 2 && [parts[1] isEqualToString:@"device"]) [serials addObject:parts[0]];
    }
    if (failed || !serials.count) { [self updateStatus:@"USB 패드를 찾을 수 없습니다. 케이블과 USB 디버깅 허용을 확인하세요."]; return NO; }
    if (serials.count > 1 && ![serials containsObject:_serial ?: @""]) { [self updateStatus:@"안드로이드 기기가 여러 대입니다. 사용할 패드만 연결해 주세요."]; return NO; }
    NSString *selectedSerial = [serials containsObject:_serial ?: @""] ? _serial : serials[0];
    _serial = selectedSerial;
    [self adb:@[@"-s",_serial,@"reverse",@"tcp:28765",@"tcp:28765"] error:&failed];
    if (failed) { [self updateStatus:@"USB 화면 전송 경로를 연결하지 못했습니다."]; return NO; }
    [self adb:@[@"-s",_serial,@"reverse",@"tcp:28766",@"tcp:28766"] error:&failed];
    if (failed) { [self updateStatus:@"USB 커서 전송 경로를 연결하지 못했습니다."]; return NO; }
    [self adb:@[@"-s",_serial,@"reverse",@"tcp:28767",@"tcp:28767"] error:&failed];
    if(failed){[self updateStatus:@"USB 소리 전송 경로를 연결하지 못했습니다."];return NO;}
    NSString *installed = [self adb:@[@"-s",_serial,@"shell",@"pm",@"path",@"studio.prxs.paddisplay"] error:&failed];
    NSString *versions = [self adb:@[@"-s",_serial,@"shell",@"cmd",@"package",@"list",@"packages",@"--show-versioncode",@"studio.prxs.paddisplay"] error:nil];
    NSString *requiredVersion = [@"versionCode:" stringByAppendingString:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
    if (![installed containsString:@"package:"] || ![versions containsString:requiredVersion]) {
        NSString *apk = [[NSBundle mainBundle] pathForResource:@"SidePad" ofType:@"apk"];
        if (!apk) { [self updateStatus:@"패드 앱 설치 파일을 찾을 수 없습니다."]; return NO; }
        [self updateStatus:@"패드 앱을 설치하고 있습니다…"];
        [self adb:@[@"-s",_serial,@"install",@"--no-incremental",@"-r",apk] error:&failed];
        if (failed) { [self updateStatus:@"패드 앱 설치 실패. 패드의 설치 허용 화면을 확인하세요."]; return NO; }
    }
    if (self.quitting || generation != self.generation) return NO;
    [self adb:@[@"-s",_serial,@"shell",@"input",@"keyevent",@"KEYCODE_WAKEUP"] error:nil];
    if (self.quitting || generation != self.generation) return NO;
    [self adb:@[@"-s",_serial,@"shell",@"am",@"start",@"--activity-single-top",@"-n",@"studio.prxs.paddisplay/.MainActivity",@"--es",@"token",_token,@"--es",@"foreground",foreground] error:&failed];
    if (failed) { [self updateStatus:@"패드 앱을 실행하지 못했습니다."]; return NO; }
    return YES;
}
- (BOOL)createDisplayWidth:(int)width height:(int)height {
    if (!NSClassFromString(@"CGVirtualDisplay") || !NSClassFromString(@"CGVirtualDisplayDescriptor")) { [self updateStatus:@"이 macOS에서 확장 디스플레이를 만들 수 없습니다. 화면 복제를 선택하세요."]; return NO; }
    @try {
        _anchorDisplay = CGMainDisplayID();
        CGVirtualDisplayDescriptor *descriptor = [CGVirtualDisplayDescriptor new];
        descriptor.name = @"SidePad (USB-C)"; descriptor.vendorID = 0x505; descriptor.productID = 0x5044;
        descriptor.serialNum = 20261002; descriptor.serialNumber = 20261002;
        descriptor.maxPixelsWide = width; descriptor.maxPixelsHigh = height;
        descriptor.sizeInMillimeters = CGSizeMake(286,179);
        descriptor.redPrimary = CGPointMake(0.64,0.33); descriptor.greenPrimary = CGPointMake(0.30,0.60);
        descriptor.bluePrimary = CGPointMake(0.15,0.06); descriptor.whitePoint = CGPointMake(0.3127,0.3290);
        descriptor.queue = dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE,0);
        _virtualDisplay = [[CGVirtualDisplay alloc] initWithDescriptor:descriptor];
        BOOL retina=width>2000;
        CGVirtualDisplaySettings *settings = [CGVirtualDisplaySettings new]; settings.hiDPI = retina; settings.rotation = 0;
        settings.modes = @[[[CGVirtualDisplayMode alloc] initWithWidth:(retina ? width/2 : width) height:(retina ? height/2 : height) refreshRate:120]];
        if (!_virtualDisplay || ![_virtualDisplay applySettings:settings]) { _virtualDisplay = nil; [self updateStatus:@"확장 디스플레이 생성 실패. 화면 복제를 선택하세요."]; return NO; }
        _targetDisplay = _virtualDisplay.displayID;
        CGRect mainBounds = CGDisplayBounds(_anchorDisplay);
        CGDisplayConfigRef config = NULL;
        if (CGBeginDisplayConfiguration(&config) == kCGErrorSuccess) {
            CGConfigureDisplayMirrorOfDisplay(config, _targetDisplay, kCGNullDirectDisplay);
            CGConfigureDisplayOrigin(config, _targetDisplay, (int)CGRectGetMaxX(mainBounds), (int)CGRectGetMinY(mainBounds));
            CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
        }
        PDLog([NSString stringWithFormat:@"Virtual display ID=%u size=%dx%d", _targetDisplay,width,height]); return YES;
    } @catch (NSException *exception) { _virtualDisplay = nil; [self updateStatus:@"확장 디스플레이 API를 사용할 수 없습니다. 화면 복제를 선택하세요."]; return NO; }
}
- (BOOL)selectNativeWidth:(int)width height:(int)height {
    int logicalWidth=width>2000 ? width/2 : width, logicalHeight=width>2000 ? height/2 : height;
    CFArrayRef all = CGDisplayCopyAllDisplayModes(_targetDisplay, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes:@YES});
    CGDisplayModeRef selected = NULL;
    if (all) for (CFIndex i=0;i<CFArrayGetCount(all);i++) {
        CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(all,i);
        if (CGDisplayModeGetWidth(mode)==logicalWidth && CGDisplayModeGetHeight(mode)==logicalHeight && CGDisplayModeGetPixelWidth(mode)==width && CGDisplayModeGetPixelHeight(mode)==height) { selected=mode; break; }
    }
    CGError result = selected ? CGDisplaySetDisplayMode(_targetDisplay,selected,NULL) : kCGErrorFailure;
    if (all) CFRelease(all);
    CGDisplayModeRef current = CGDisplayCopyDisplayMode(_targetDisplay);
    BOOL verified = result==kCGErrorSuccess && current && CGDisplayModeGetPixelWidth(current)==width && CGDisplayModeGetPixelHeight(current)==height;
    if (current) CFRelease(current);
    if (!verified) return NO;
    if ([_displayLayout restoreForDevice:_layoutDevice display:_targetDisplay]) PDLog(@"Restored saved display arrangement");
    PDLog([NSString stringWithFormat:@"Verified display logical=%dx%d native pixels=%dx%d",logicalWidth,logicalHeight,width,height]); return YES;
}
- (void)start:(id)sender {
    if (_active || _starting) return;
    if (_screenCaptureDenied) {
        [self updateStatus:@"화면 기록 승인이 필요합니다. 켜져 있는데도 연결되지 않으면 SidePad 메뉴의 ‘화면 기록 승인 복구’를 누른 뒤 재실행해 주세요."];
        return;
    }
    if (_listener < 0 || _cursorListener < 0) { [self updateStatus:@"USB 수신 포트를 열 수 없습니다. 다른 SidePad 실행을 종료해 주세요."]; return; }
    _starting = YES; _startButton.enabled = NO;
    // ScreenCaptureKit is the authority for the capture we actually perform.
    // CGPreflightScreenCaptureAccess may retain a stale result after approval;
    // do not repeatedly request permission or force Settings open from it.
    [self updateStatus:@"USB-C 패드를 연결하고 있습니다…"];
    _stopButton.enabled = YES;
    NSString *foreground = [_foregroundSession prepareLaunch];
    NSUInteger connectionGeneration = ++_generation;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        BOOL connected = [self connectUSBWithForeground:foreground generation:connectionGeneration];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (connectionGeneration != self.generation) return;
            if (!connected || self.quitting) { self.starting = NO; self.startButton.enabled = YES; self.stopButton.enabled = NO; return; }
            // Capture starts only after the foreground receiver authenticates.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                if (connectionGeneration != self.generation || !self.starting) return;
                [self stop:nil]; [self updateStatus:@"패드 앱 연결 대기 시간이 지났습니다. 패드에서 SidePad를 다시 열어 주세요."];
            });
        });
    });
}
- (void)beginCapture {
    _preparingCapture = YES;
    [self rememberOptions:nil];
    _layoutReady = NO; _layoutDevice = [_serial copy];
    NSArray *sizes = @[@[@1920,@1200],@[@1472,@920],@[@2944,@1840]];
    NSArray *size = sizes[_resolution.indexOfSelectedItem]; int width = [size[0] intValue], height = [size[1] intValue];
    int fps = _rate.indexOfSelectedItem == 0 ? 60 : 30;
    if (_mode.indexOfSelectedItem == 0) { if (![self createDisplayWidth:width height:height]) { NSString *message=_status.stringValue; [self stop:nil]; [self updateStatus:message]; return; } }
    else {
        _targetDisplay = CGMainDisplayID();
        CGRect bounds = CGDisplayBounds(_targetDisplay);
        height = ((int)round(width * bounds.size.height / bounds.size.width)/2)*2;
    }
    NSUInteger generation = ++_generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 700*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (generation != self.generation || !self.starting) return;
        if (self.virtualDisplay && ![self selectNativeWidth:width height:height]) { [self stop:nil]; [self updateStatus:@"원본 디스플레이 모드를 적용하지 못했습니다. 다시 연결해 주세요."]; return; }
        [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:NO completionHandler:^(SCShareableContent *content, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self.generation || !self.starting) return;
                SCDisplay *selected = nil;
                for (SCDisplay *display in content.displays) if (display.displayID == self.targetDisplay) selected = display;
                if (error || !selected) {
                    BOOL declined = [error.domain isEqualToString:SCStreamErrorDomain] && error.code == SCStreamErrorUserDeclined;
                    self.screenCaptureDenied=declined;
                    [self stop:nil];
                    [self updateStatus:declined ? @"화면 기록 승인이 필요합니다. 이미 켜져 있다면 SidePad 메뉴의 ‘화면 기록 승인 복구’를 실행한 뒤 앱을 다시 여세요." : (error ? [@"화면 캡처 실패: " stringByAppendingString:error.localizedDescription] : @"확장 화면을 찾을 수 없습니다. 다시 연결해 주세요.")];
                    return;
                }
                PDCapture *capture = [PDCapture new]; capture.app = self; capture.width = width; capture.height = height; capture.fps = fps;
                if (![capture prepareEncoder]) { [self stop:nil]; [self updateStatus:@"H.264 영상 인코더를 시작하지 못했습니다."]; return; }
                SCStreamConfiguration *config = [SCStreamConfiguration new]; config.width = width; config.height = height;
                // ScreenCaptureKit needs at least three reusable surfaces; one stalls capture
                // while VideoToolbox retains the first surface. Encoding is still bounded to two.
                config.minimumFrameInterval = CMTimeMake(1,fps); config.queueDepth = 3; config.showsCursor = NO;
                config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
                config.colorSpaceName = kCGColorSpaceSRGB; config.capturesAudio = self.audioEnabled;
                config.sampleRate=48000;config.channelCount=2;config.excludesCurrentProcessAudio=YES;capture.configuration=config;
                SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:selected excludingWindows:@[]];
                capture.stream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:capture];
                NSError *outputError = nil;
                if (![capture.stream addStreamOutput:capture type:SCStreamOutputTypeScreen sampleHandlerQueue:capture.queue error:&outputError]) {
                    [capture stop]; [self stop:nil]; [self updateStatus:@"화면 전송 스트림 생성 실패"]; return;
                }
                if(![capture.stream addStreamOutput:capture type:SCStreamOutputTypeAudio sampleHandlerQueue:capture.audioQueue error:&outputError]){
                    [capture stop];[self stop:nil];[self updateStatus:@"소리 전송 스트림 생성 실패"];return;
                }
                self.capture = capture;
                [capture.stream startCaptureWithCompletionHandler:^(NSError *startError) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (generation != self.generation) return;
                        if (startError) {
                            self.screenCaptureDenied=[startError.domain isEqualToString:SCStreamErrorDomain] && startError.code==SCStreamErrorUserDeclined;
                            [self stop:nil]; [self updateStatus:[@"화면 전송 시작 실패: " stringByAppendingString:startError.localizedDescription]]; return;
                        }
                        self.active = YES; self.starting = NO; self.stopButton.enabled = YES; self.layoutReady = YES;
                        self.preparingCapture = NO;
                        self.mode.enabled = NO; self.resolution.enabled = NO; self.rate.enabled = NO;
                        [self updateStatus:@"USB 연결됨 · 첫 화면 전송 대기 중"];
                        PDLog(@"ScreenCaptureKit started");
                    });
                }];
            });
        }];
    });
}
- (void)stop:(id)sender {
    [_foregroundSession blockCurrent];
    [self stopCapture];
}
- (void)pauseForPeer:(PDPeer *)peer {
    if (!peer || _peer != peer || _quitting) return;
    [self stopCapture];
    PDLog(@"Tablet receiver closed; capture paused without relaunching Android");
    [self updateStatus:@"패드 연결 중지 · 패드에서 SidePad를 다시 열면 연결됩니다."];
}
- (void)stopCapture {
    if (_layoutReady && _virtualDisplay) [_displayLayout saveForDevice:_layoutDevice display:_targetDisplay];
    _layoutReady = NO;
    [_macAudioOutput restore];
    [self releasePen];
    [self releaseTouch];
    ++_generation; _starting = NO; _active = NO; _preparingCapture = NO;
    [_capture stop]; _capture = nil;
    [_peer close]; _peer = nil;
    [_cursorPeer close]; _cursorPeer = nil;
    [_audioPeer close];_audioPeer=nil;
    _virtualDisplay = nil; _targetDisplay = 0;
    _detail.stringValue=@"다시 연결하면 기존 설정과 모니터 배열을 복원합니다.";
    _startButton.enabled = YES; _stopButton.enabled = NO; _mode.enabled = YES; _resolution.enabled = YES; _rate.enabled = YES;
    _statusItem.button.title = @"▣ SidePad"; [self updateStatus:@"화면 전송을 중지했습니다."];
}
- (void)listen { [self listenPort:PDPort channel:0]; [self listenPort:PDPort+1 channel:1];[self listenPort:PDPort+2 channel:2]; }
- (void)listenPort:(uint16_t)port channel:(int)channel {
    int fd = socket(AF_INET, SOCK_STREAM, 0); int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in address = {0}; address.sin_family = AF_INET; address.sin_port = htons(port); address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (fd < 0 || bind(fd,(struct sockaddr *)&address,sizeof(address)) || listen(fd,4)) { if (fd >= 0) close(fd); return; }
    if(channel==1)_cursorListener=fd;else if(channel==2)_audioListener=fd;else _listener=fd;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        while (!self.quitting) {
            int client = accept(fd,NULL,NULL); if (client < 0) { if (errno == EINTR) continue; break; }
            int yes = 1; setsockopt(client,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
            setsockopt(client,IPPROTO_TCP,TCP_NODELAY,&yes,sizeof(yes));
            struct timeval timeout = {5,0}; setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
            timeout.tv_sec=channel==2?0:2;timeout.tv_usec=channel==2?100000:0;setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
            NSMutableData *hello = [NSMutableData new]; uint8_t byte=0;
            while (hello.length < 128 && recv(client,&byte,1,0) == 1 && byte != '\n') [hello appendBytes:&byte length:1];
            NSString *line = [[NSString alloc] initWithData:hello encoding:NSUTF8StringEncoding];
            NSString *foreground=channel==0 ? PDForegroundID(line,self.token) : nil;
            NSString *prefix=channel==1 ? @"PADCURSOR/1 " : @"PADAUDIO/1 ";
            BOOL authenticated=channel==0 ? foreground!=nil : [line isEqualToString:[prefix stringByAppendingString:self.token]];
            if (byte!='\n' || !authenticated) { close(client); continue; }
            PDPeer *peer = [PDPeer new]; peer.fd = client;
            // A duplicate descriptor keeps the EOF reader safe when a sender closes the peer.
            int readFD=channel==2 ? -1 : dup(client);
            if (channel!=2 && readFD<0) { [peer close]; continue; }
            if (channel==0) { timeout.tv_sec=0; timeout.tv_usec=0; setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout)); }
            __block BOOL accepted=NO;
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (self.quitting) return;
                if (channel==0) {
                    if (self.screenCaptureDenied) return;
                    if (![self.foregroundSession acceptID:foreground]) return;
                    [self.peer close]; self.peer=peer;
                    if (!self.active && !self.preparingCapture) {
                        self.starting=YES; self.startButton.enabled=NO; self.stopButton.enabled=YES;
                        [self beginCapture];
                    }
                } else {
                    if (!self.active && !self.starting) return;
                    if (channel==1) { [self.cursorPeer close]; self.cursorPeer=peer; }
                    else { [self.audioPeer close]; self.audioPeer=peer; }
                }
                accepted=YES;
            });
            if (!accepted) { [peer close]; if (readFD>=0) close(readFD); continue; }
            if(channel==2){
                uint8_t enabled=self.audioEnabled;
                if(![peer packet:10 data:[NSData dataWithBytes:&enabled length:1]])continue;
                PDLog(@"Authenticated dedicated USB audio connected");
            }
            else if (channel==0) {
                PDLog(@"Authenticated foreground USB video connected");
                // Android closes this socket in onPause. No timer launches it again.
                // A foreground receiver retries after a cable/decoder interruption.
                PDRead(readFD,&byte,1); close(readFD);
                dispatch_async(dispatch_get_main_queue(), ^{ [self pauseForPeer:peer]; });
            }
            else {
                PDLog(@"Authenticated dedicated USB cursor connected");
                uint8_t header[5]; double total=0; NSUInteger count=0;
                while (!self.quitting && PDRead(readFD,header,5)) {
                    uint32_t length; memcpy(&length,header+1,4); length=ntohl(length);
                    if(header[0]==7 && length==26) {
                        uint8_t data[26];if(!PDRead(readFD,data,26))break;
                        [self handlePen:[NSData dataWithBytes:data length:26]];continue;
                    }
                    if(header[0]==8 && length==17) {
                        uint8_t data[17];if(!PDRead(readFD,data,17))break;
                        [self handleTouch:[NSData dataWithBytes:data length:17]];continue;
                    }
                    if (header[0]!=5 || length!=17) break;
                    uint8_t data[17]; if (!PDRead(readFD,data,17)) break;
                    uint64_t sent; memcpy(&sent,data+9,8); sent=CFSwapInt64BigToHost(sent);
                    uint64_t now=PDClockNS(); if (sent>now) continue;
                    double rtt=(now-sent)/1000000.0; if (rtt>1000) continue;
                    total+=rtt; count++;
                    if (count==60) { self.cursorRTT=total/count; PDLog([NSString stringWithFormat:@"Cursor USB round-trip average %.2f ms",self.cursorRTT]); total=0;count=0; }
                }
                close(readFD); [peer close];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.cursorPeer==peer) { self.cursorPeer=nil;[self releasePen];[self releaseTouch]; }
                });
            }
        }
    });
}
- (void)penProximity:(BOOL)enter tool:(uint8_t)tool point:(CGPoint)point {
    CGEventRef event=CGEventCreate(NULL);if(!event)return;
    CGEventSetType(event,kCGEventTabletProximity);CGEventSetLocation(event,point);
    CGEventSetIntegerValueField(event,kCGTabletProximityEventVendorID,0x17ef);
    CGEventSetIntegerValueField(event,kCGTabletProximityEventTabletID,1);
    CGEventSetIntegerValueField(event,kCGTabletProximityEventPointerID,1);
    CGEventSetIntegerValueField(event,kCGTabletProximityEventDeviceID,1);
    CGEventSetIntegerValueField(event,kCGTabletProximityEventSystemTabletID,1);
    CGEventSetIntegerValueField(event,kCGTabletProximityEventVendorUniqueID,20261002);
    CGEventSetIntegerValueField(event,kCGTabletProximityEventCapabilityMask,0x05c7);
    CGEventSetIntegerValueField(event,kCGTabletProximityEventPointerType,tool==2?3:1);
    CGEventSetIntegerValueField(event,kCGTabletProximityEventEnterProximity,enter);
    CGEventPost(kCGHIDEventTap,event);CFRelease(event);_penProximity=enter;
}
- (void)releasePen {
    @synchronized(self) {
        if(_penDown) {
            PDPenInput input={0};CGMouseButton button=_penRight?kCGMouseButtonRight:kCGMouseButtonLeft;
            CGEventRef event=PDCreatePenEvent(input,_penRight?kCGEventRightMouseUp:kCGEventLeftMouseUp,_penPoint,button,NO);
            if(event){CGEventPost(kCGHIDEventTap,event);CFRelease(event);}_penDown=NO;
        }
        if(_penProximity)[self penProximity:NO tool:1 point:_penPoint];
    }
}
- (void)handlePen:(NSData *)data {
    PDPenInput input;if(!PDParsePen(data,&input) || !_active || !_targetDisplay || !self.inputTrusted)return;
    @synchronized(self) {
        [self releaseTouch];
        CGRect bounds=CGDisplayBounds(_targetDisplay);
        CGPoint point=CGPointMake(bounds.origin.x+input.x*(bounds.size.width-1),bounds.origin.y+input.y*(bounds.size.height-1));
        if(input.action==4 || input.action==5){[self releasePen];return;}
        if(!_penProximity)[self penProximity:YES tool:input.tool point:point];
        CGEventType type=kCGEventMouseMoved;
        if(input.action==2) {
            if(_penDown)[self releasePen];
            _penRight=(input.buttons&32)!=0;_penDown=YES;_penEventNumber++;
            uint64_t now=PDClockNS();
            BOOL near=hypot(point.x-_penPoint.x,point.y-_penPoint.y)<5;
            _penClickCount=near && now-_lastPenDown<NSEvent.doubleClickInterval*1e9 ? MIN(_penClickCount+1,3):1;_lastPenDown=now;
            type=_penRight?kCGEventRightMouseDown:kCGEventLeftMouseDown;
        } else if(input.action==3) {
            if(!_penDown)return;type=_penRight?kCGEventRightMouseUp:kCGEventLeftMouseUp;
        } else if(_penDown)type=_penRight?kCGEventRightMouseDragged:kCGEventLeftMouseDragged;
        CGMouseButton button=_penRight?kCGMouseButtonRight:kCGMouseButtonLeft;
        CGEventRef event=PDCreatePenEvent(input,type,point,button,_penDown && input.action!=3);
        if(event) {
            CGEventSetIntegerValueField(event,kCGMouseEventClickState,_penClickCount);
            CGEventSetIntegerValueField(event,kCGMouseEventNumber,_penEventNumber);
            CGEventPost(kCGHIDEventTap,event);CFRelease(event);_penEvents++;
            if(input.action==2 || input.action==3)PDLog([NSString stringWithFormat:@"Pen action=%d pressure=%.3f events=%llu",input.action,input.pressure,_penEvents]);
        }
        _penPoint=point;if(input.action==3)_penDown=NO;
    }
}
- (void)releaseTouch {
    @synchronized(self) {
        if(_touchDown){
            CGEventRef event=PDCreateTouchEvent(kCGEventLeftMouseUp,_touchPoint,_touchClickCount,_touchEventNumber);
            if(event){CGEventPost(kCGHIDEventTap,event);CFRelease(event);}_touchDown=NO;
        }
        _touchScrollX=0;_touchScrollY=0;
    }
}
- (void)handleTouch:(NSData *)data {
    PDTouchInput input;if(!PDParseTouch(data,&input) || !_active || !_targetDisplay || !self.inputTrusted)return;
    @synchronized(self) {
        if(_penDown)return;
        if(_penProximity)[self releasePen];
        if(input.action==4){[self releaseTouch];return;}
        CGRect bounds=CGDisplayBounds(_targetDisplay);
        CGPoint point=CGPointMake(bounds.origin.x+input.x*(bounds.size.width-1),bounds.origin.y+input.y*(bounds.size.height-1));
        if(input.action==6){
            if(_touchDown)[self releaseTouch];
            _touchScrollX+=input.dx*bounds.size.width;_touchScrollY+=input.dy*bounds.size.height;
            int dx=(int)lround(_touchScrollX),dy=(int)lround(_touchScrollY);
            _touchScrollX-=dx;_touchScrollY-=dy;
            if(dx || dy){
                CGEventRef event=CGEventCreateScrollWheelEvent(NULL,kCGScrollEventUnitPixel,2,dy,dx);
                if(event){CGEventSetLocation(event,point);CGEventPost(kCGHIDEventTap,event);CFRelease(event);_touchEvents++;}
            }
            return;
        }
        CGEventType type=kCGEventMouseMoved;
        if(input.action==2){
            if(_touchDown)[self releaseTouch];
            uint64_t now=PDClockNS();BOOL near=hypot(point.x-_touchLastDownPoint.x,point.y-_touchLastDownPoint.y)<5;
            _touchClickCount=near && now-_lastTouchDown<NSEvent.doubleClickInterval*1e9 ? MIN(_touchClickCount+1,3):1;
            _lastTouchDown=now;_touchLastDownPoint=point;_touchDown=YES;_touchEventNumber++;type=kCGEventLeftMouseDown;
        } else if(input.action==3){if(!_touchDown)return;type=kCGEventLeftMouseUp;}
        else if(input.action==1){if(!_touchDown)return;type=kCGEventLeftMouseDragged;}
        else {_touchScrollX=0;_touchScrollY=0;}
        CGEventRef event=PDCreateTouchEvent(type,point,_touchClickCount,_touchEventNumber);
        if(event){CGEventPost(kCGHIDEventTap,event);CFRelease(event);_touchEvents++;}
        _touchPoint=point;if(input.action==3)_touchDown=NO;
        if(input.action==2 || input.action==3)PDLog([NSString stringWithFormat:@"Touch action=%d events=%llu",input.action,_touchEvents]);
    }
}
- (void)updateCursorImage:(id)sender {
    // This global API is deprecated; retain the native arrow as a fallback.
    NSCursor *cursor=NSCursor.currentSystemCursor ?: NSCursor.arrowCursor;
    NSImage *image=cursor.image; NSSize size=image.size; NSPoint hot=cursor.hotSpot;
    if(size.width<=0 || size.height<=0 || size.width>256 || size.height>256)return;
    NSData *tiff=image.TIFFRepresentation;
    if([tiff isEqualToData:_lastCursorTIFF] && NSEqualPoints(hot,_lastCursorHotSpot))return;
    int w=(int)ceil(size.width*2),h=(int)ceil(size.height*2);
    NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    if(!bitmap)return;
    [NSGraphicsContext saveGraphicsState]; NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [image drawInRect:NSMakeRect(0,0,w,h) fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
    [NSGraphicsContext restoreGraphicsState];
    NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]; if(!png)return;
    float x=hot.x*2,y=hot.y*2; uint32_t xb,yb;memcpy(&xb,&x,4);memcpy(&yb,&y,4);xb=htonl(xb);yb=htonl(yb);
    NSMutableData *payload=[NSMutableData dataWithBytes:&xb length:4];[payload appendBytes:&yb length:4];[payload appendData:png];
    _lastCursorTIFF=tiff;_lastCursorHotSpot=hot;self.cursorImagePayload=payload;
}
- (void)startCursorSender {
    dispatch_queue_t queue=dispatch_queue_create("studio.prxs.paddisplay.cursor",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_USER_INTERACTIVE,0));
    _cursorTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,queue);
    dispatch_source_set_timer(_cursorTimer,dispatch_time(DISPATCH_TIME_NOW,0),NSEC_PER_SEC/120,NSEC_PER_MSEC/2);
    dispatch_source_set_event_handler(_cursorTimer,^{
        PDPeer *peer=self.cursorPeer; if (!self.active || !peer || !self.targetDisplay) return;
        NSData *image=self.cursorImagePayload;
        if(image && peer.cursorImagePayload!=image) {
            if(![peer packet:6 data:image]) { if(self.cursorPeer==peer)self.cursorPeer=nil;return; }
            peer.cursorImagePayload=image;
        }
        CGEventRef event=CGEventCreate(NULL); if (!event) return;
        CGPoint point=CGEventGetLocation(event); CFRelease(event);
        CGRect bounds=CGDisplayBounds(self.targetDisplay);
        BOOL visible=CGRectContainsPoint(bounds,point);
        float x=(point.x-bounds.origin.x)/bounds.size.width, y=(point.y-bounds.origin.y)/bounds.size.height;
        uint64_t now=PDClockNS();
        BOOL changed=!peer.hasCursorPosition || visible!=peer.cursorVisible || (visible && (x!=peer.cursorX || y!=peer.cursorY));
        // Moving cursors retain 120 Hz. An idle/hidden cursor only needs a 10 Hz heartbeat.
        if(!changed && now-peer.cursorSentAt<100*NSEC_PER_MSEC)return;
        uint32_t xb,yb; memcpy(&xb,&x,4);memcpy(&yb,&y,4);xb=htonl(xb);yb=htonl(yb);
        uint8_t data[17];data[0]=visible;memcpy(data+1,&xb,4);memcpy(data+5,&yb,4);
        uint64_t stamp=CFSwapInt64HostToBig(now);memcpy(data+9,&stamp,8);
        if (![peer packet:4 data:[NSData dataWithBytes:data length:17]]) { if (self.cursorPeer==peer) self.cursorPeer=nil; }
        else {peer.hasCursorPosition=YES;peer.cursorVisible=visible;peer.cursorX=x;peer.cursorY=y;peer.cursorSentAt=now;}
    });
    dispatch_resume(_cursorTimer);
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    _quitting = YES; [_timer invalidate]; [_cursorImageTimer invalidate]; [self stop:nil];
    if (_cursorTimer) { dispatch_source_cancel(_cursorTimer); _cursorTimer=nil; }
    if (_listener >= 0) { shutdown(_listener,SHUT_RDWR); close(_listener); _listener = -1; }
    if (_cursorListener >= 0) { shutdown(_cursorListener,SHUT_RDWR);close(_cursorListener);_cursorListener=-1; }
    if(_audioListener>=0){shutdown(_audioListener,SHUT_RDWR);close(_audioListener);_audioListener=-1;}
    if (_serial && _adbPath) [self adb:@[@"-s",_serial,@"reverse",@"--remove",@"tcp:28765"] error:nil];
    if (_serial && _adbPath) [self adb:@[@"-s",_serial,@"reverse",@"--remove",@"tcp:28766"] error:nil];
    if (_serial && _adbPath) [self adb:@[@"-s",_serial,@"reverse",@"--remove",@"tcp:28767"] error:nil];
    return NSTerminateNow;
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // A second copy must not compete for USB ports or change the tablet's session token.
        NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
        for (NSRunningApplication *other in [NSRunningApplication runningApplicationsWithBundleIdentifier:identifier]) {
            if (other.processIdentifier != NSProcessInfo.processInfo.processIdentifier && !other.terminated) {
                [other activateWithOptions:NSApplicationActivateAllWindows];
                return 0;
            }
        }
        NSApplication *application = NSApplication.sharedApplication; application.activationPolicy = NSApplicationActivationPolicyRegular;
        PDApp *delegate = [PDApp new]; application.delegate = delegate;
        [application run];
    }
    return 0;
}
