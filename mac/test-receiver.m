#import "ReceiverInfo.h"
#import "ControlPacket.h"
#include <assert.h>
#include <unistd.h>

static NSDictionary *profile(NSArray *modes) {
    return PDReceiverInfo(@{@"protocol":@3,@"model":@"Test Pad",@"nativeWidth":@2944,@"nativeHeight":@1840,@"panelHz":@120,@"modes":modes});
}
static NSDictionary *mode(int w,int h,int fps) {return @{@"width":@(w),@"height":@(h),@"maxFPS":@(fps)};}
static void packet(int fd,uint8_t type,NSData *body) {
    uint8_t header[5]={type};uint32_t length=htonl((uint32_t)body.length);memcpy(header+1,&length,4);
    assert(write(fd,header,5)==5);assert(write(fd,body.bytes,body.length)==body.length);
}
int main(void) {
    @autoreleasepool {
        NSDictionary *pad=profile(@[mode(1920,1200,60),mode(2944,1840,60),mode(1472,920,60)]);
        assert(pad && [PDStreamMode(pad,0,60)[@"width"] intValue]==2944);
        assert([PDStreamMode(pad,2,60)[@"width"] intValue]==1920);
        assert([PDStreamMode(pad,3,60)[@"width"] intValue]==1472);
        assert([PDStreamMode(pad,0,30)[@"fps"] intValue]==30);
        NSDictionary *slower=profile(@[mode(2944,1840,30),mode(1920,1200,60)]);
        assert([PDStreamMode(slower,0,60)[@"width"] intValue]==1920);
        assert([PDStreamMode(slower,1,60)[@"width"] intValue]==2944);
        assert([PDStreamMode(slower,1,60)[@"fps"] intValue]==30);
        NSDictionary *small=profile(@[mode(1280,800,30)]);
        assert([PDStreamMode(small,0,60)[@"fps"] intValue]==30);
        assert([PDStreamMode(small,2,60)[@"width"] intValue]==1280);
        assert(!profile(@[]) && !profile(@[mode(9000,1200,60)]) && !profile(@[mode(1921,1200,60)]));
        assert(!profile(@[mode(1920,1200,120)]) && !PDReceiverInfo(@[]) && !PDStreamMode(pad,99,60));
        assert([PDReceiverInfo(pad) isEqual:pad]); // Persisted capabilities still pass validation.
        assert([PDSelectedStreamMode(pad,@"1920x1200",60)[@"width"] intValue]==1920);
        assert([PDSelectedStreamMode(slower,@"2944x1840",60)[@"fps"] intValue]==30);
        assert([PDSelectedStreamMode(small,@"2944x1840",60)[@"width"] intValue]==1280);
        assert([PDSelectedStreamMode(pad,@"balanced",60)[@"width"] intValue]==1920);
        NSDictionary *aligned=profile(@[mode(2944,1840,60),mode(1472,920,60),mode(1472,912,60)]);
        NSArray *options=PDResolutionOptions(aligned,NO);
        assert(options.count==3 && [options[1][@"key"] isEqual:@"2944x1840"]);
        assert([options[1][@"title"] containsString:@"Retina"] && [options[1][@"title"] containsString:@"원본"]);
        assert(![PDResolutionOptions(aligned,YES)[1][@"title"] containsString:@"Retina"]);
        assert([PDResolutionDescription(PDSelectedStreamMode(pad,@"auto",60),NO) containsString:@"화면 크기 1472 × 920"]);
        assert(![PDResolutionDescription(PDSelectedStreamMode(pad,@"auto",60),YES) containsString:@"Retina"]);
        assert([PDResolutionDescription(nil,NO) containsString:@"한 번 연결"]);
        NSDictionary *waiting=@{@"rendered":@0,@"received":@60,@"submitted":@60,@"dropped":@0,@"fps":@0,@"decodeMs":@-1,@"panelHz":@120};
        assert(PDReceiverFeedback(waiting));
        assert(!PDReceiverDisplaying(waiting,100,200)); // Sending frames is not proof of display.
        NSMutableDictionary *shown=[waiting mutableCopy];shown[@"rendered"]=@1;
        assert(PDReceiverDisplaying(shown,100,200));
        assert(!PDReceiverDisplaying(shown,100,4000000100ULL));
        shown[@"fps"]=@(-1);assert(!PDReceiverFeedback(shown));
        shown[@"fps"]=@60;shown[@"rendered"]=@"1";assert(!PDReceiverFeedback(shown));

        int fds[2];assert(socketpair(AF_UNIX,SOCK_STREAM,0,fds)==0);
        NSData *body=[NSJSONSerialization dataWithJSONObject:waiting options:0 error:nil];
        int writer=fds[1];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{
            uint8_t header[5]={12};uint32_t length=htonl((uint32_t)body.length);memcpy(header+1,&length,4);
            for(int i=0;i<5;i++)assert(write(writer,header+i,1)==1);
            for(NSUInteger i=0;i<body.length;i++)assert(write(writer,(const char *)body.bytes+i,1)==1);
            close(writer);
        });
        assert([PDReadControl(fds[0],12) isEqual:waiting]);close(fds[0]);
        assert(socketpair(AF_UNIX,SOCK_STREAM,0,fds)==0);
        packet(fds[1],11,[NSData dataWithBytes:"[]" length:2]);assert(!PDReadControl(fds[0],11));close(fds[0]);close(fds[1]);
        assert(socketpair(AF_UNIX,SOCK_STREAM,0,fds)==0);
        uint8_t excessive[]={11,0,1,0,0};assert(write(fds[1],excessive,5)==5);
        assert(!PDReadControl(fds[0],11));close(fds[0]);close(fds[1]);
        assert(socketpair(AF_UNIX,SOCK_STREAM,0,fds)==0);
        uint8_t truncated[]={11,0,0,0,9,'{'};assert(write(fds[1],truncated,6)==6);close(fds[1]);
        assert(!PDReadControl(fds[0],11));close(fds[0]);
        puts("Receiver negotiation, display acknowledgement and fragmented control packet tests passed");
    }
}
