#import "Updater.h"
#include <assert.h>

static NSDictionary *release;
static NSInteger responseCode=200;
static int requests=0;
@interface UpdateProtocol : NSURLProtocol @end
@implementation UpdateProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    requests++;
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:responseCode HTTPVersion:@"HTTP/1.1" headerFields:nil];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:[NSJSONSerialization dataWithJSONObject:release options:0 error:nil]];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end
@interface ObservedUpdater : PDUpdater
@property int alerts;
@end
@implementation ObservedUpdater
- (void)finishWithTitle:(NSString *)title message:(NSString *)message { self.alerts++; }
@end
static NSDictionary *fixture(NSString *version) {
    return @{@"tag_name":[@"v" stringByAppendingString:version],@"draft":@NO,@"prerelease":@NO,
        @"assets":@[@{@"name":@"SidePad-macOS.zip",@"state":@"uploaded",@"size":@3,
          @"browser_download_url":[NSString stringWithFormat:@"https://github.com/studioprxs-cmd/sidepad/releases/download/v%@/SidePad-macOS.zip",version],
          @"digest":@"sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"}]};
}
static void waitForCheck(PDUpdater *updater) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];
    while(updater.busy && deadline.timeIntervalSinceNow>0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    assert(!updater.busy);
}
int main(void) {
    @autoreleasepool {
        NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.protocolClasses=@[UpdateProtocol.class];
        NSURLSession *session=[NSURLSession sessionWithConfiguration:config];
        ObservedUpdater *updater=[[ObservedUpdater alloc] initWithSession:session currentVersion:@"1.11"];
        __block NSString *title=nil;
        updater.stateChanged=^(NSString *value){assert(NSThread.isMainThread);title=value;};
        release=fixture(@"1.12");[updater checkInBackground];waitForCheck(updater);
        assert([updater.availableVersion isEqual:@"1.12"] && [title isEqual:@"업데이트 가능 · 1.12"]);
        assert(updater.alerts==0 && requests==1);
        [updater checkInBackground];assert(requests==1 && !updater.busy); // Six-hour throttle.
        responseCode=503;[updater checkPresentingResult:NO];waitForCheck(updater);
        assert([updater.availableVersion isEqual:@"1.12"] && updater.alerts==0); // Offline retains badge.
        responseCode=200;release=fixture(@"1.11");[updater checkPresentingResult:NO];waitForCheck(updater);
        assert(updater.availableVersion==nil && [title isEqual:@"업데이트 확인"] && updater.alerts==0);
        release=@{@"tag_name":@"v1.13",@"draft":@NO,@"prerelease":@NO,@"assets":@[]};
        [updater checkPresentingResult:NO];waitForCheck(updater);
        assert(updater.availableVersion==nil && updater.alerts==0); // Incomplete release is never advertised.
        [session invalidateAndCancel];
        puts("Automatic update tests passed (new version badge, quiet checks, throttle, offline retention, complete release)");
    }
}
