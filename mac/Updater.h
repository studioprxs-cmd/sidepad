#import <Cocoa/Cocoa.h>
#import "UpdateInfo.h"

@interface PDUpdater : NSObject
@property(nonatomic, readonly) BOOL busy;
@property(nonatomic, copy) void (^stateChanged)(NSString *title);
- (void)check;
@end

@implementation PDUpdater {
    NSURLSession *_session;
}
- (instancetype)init {
    if ((self=[super init])) {
        NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.timeoutIntervalForRequest=30; config.timeoutIntervalForResource=180;
        config.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
        config.HTTPAdditionalHeaders=@{@"User-Agent":@"SidePad-macOS",@"Accept":@"application/vnd.github+json"};
        _session=[NSURLSession sessionWithConfiguration:config];
    }
    return self;
}
- (void)finishWithTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_busy=NO;
        if (self.stateChanged) self.stateChanged(@"업데이트 확인");
        NSAlert *alert=[NSAlert new]; alert.messageText=title; alert.informativeText=message;
        [alert addButtonWithTitle:@"확인"]; [alert runModal];
    });
}
- (void)check {
    if (_busy) return;
    _busy=YES; if (_stateChanged) _stateChanged(@"버전 확인 중…");
    NSURL *url=[NSURL URLWithString:@"https://api.github.com/repos/studioprxs-cmd/sidepad/releases/latest"];
    [[_session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || [(NSHTTPURLResponse *)response statusCode]!=200 || data.length>1024*1024) {
            [self finishWithTitle:@"업데이트를 확인하지 못했습니다" message:error.localizedDescription ?: @"인터넷 연결을 확인한 뒤 다시 눌러 주세요. 잠시 뒤 다시 시도해야 할 수도 있습니다."]; return;
        }
        NSDictionary *info=PDUpdateInfo([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
        if (!info) { [self finishWithTitle:@"업데이트 정보를 확인하지 못했습니다" message:@"공식 배포 파일이 준비되지 않았습니다. 잠시 뒤 다시 시도해 주세요."]; return; }
        NSString *current=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        if (!PDIsNewerVersion(info[@"version"],current)) {
            [self finishWithTitle:@"최신 버전입니다" message:[NSString stringWithFormat:@"현재 SidePad %@을 사용하고 있습니다.",current]]; return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert *alert=[NSAlert new]; alert.messageText=[NSString stringWithFormat:@"SidePad %@ 업데이트",info[@"version"]];
            alert.informativeText=[NSString stringWithFormat:@"현재 버전 %@\n\n설정은 유지됩니다. 설치가 끝나면 Mac 앱을 다시 열고, 연결된 패드 앱도 업데이트합니다. 화면 연결은 잠시 중지됩니다.",current];
            [alert addButtonWithTitle:@"업데이트 설치"]; [alert addButtonWithTitle:@"나중에"];
            if ([alert runModal]!=NSAlertFirstButtonReturn) { self->_busy=NO; if (self.stateChanged) self.stateChanged(@"업데이트 확인"); return; }
            [self install:info];
        });
    }] resume];
}
- (BOOL)run:(NSString *)executable arguments:(NSArray<NSString *> *)arguments error:(NSError **)error {
    NSTask *task=[NSTask new]; task.executableURL=[NSURL fileURLWithPath:executable]; task.arguments=arguments;
    task.standardOutput=NSFileHandle.fileHandleWithNullDevice; task.standardError=NSFileHandle.fileHandleWithNullDevice;
    if (![task launchAndReturnError:error]) return NO;
    [task waitUntilExit]; return task.terminationStatus==0;
}
- (void)install:(NSDictionary *)info {
    NSString *destination=NSBundle.mainBundle.bundlePath.stringByResolvingSymlinksInPath;
    NSFileManager *fm=NSFileManager.defaultManager;
    if (![fm isWritableFileAtPath:destination] || ![fm isWritableFileAtPath:destination.stringByDeletingLastPathComponent] ||
        [destination containsString:@"/AppTranslocation/"]) {
        [self finishWithTitle:@"앱을 응용 프로그램 폴더로 옮겨 주세요" message:@"SidePad를 종료하고 SidePad.app을 쓰기 가능한 응용 프로그램 폴더로 옮긴 뒤 업데이트를 다시 눌러 주세요."]; return;
    }
    if (_stateChanged) _stateChanged(@"업데이트 받는 중…");
    [[_session downloadTaskWithURL:[NSURL URLWithString:info[@"url"]] completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error || [(NSHTTPURLResponse *)response statusCode]!=200) {
            [self finishWithTitle:@"업데이트 다운로드 실패" message:error.localizedDescription ?: @"인터넷 연결을 확인한 뒤 다시 시도해 주세요."]; return;
        }
        NSData *data=[NSData dataWithContentsOfURL:location options:NSDataReadingMappedIfSafe error:&error];
        if (!PDVerifyUpdateData(data,info)) { [self finishWithTitle:@"업데이트 파일 검증 실패" message:@"배포 파일의 크기 또는 SHA-256이 일치하지 않습니다. 기존 앱은 그대로 유지했습니다. 다시 시도해 주세요."]; return; }
        NSString *work=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"SidePad-update-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        if (![fm createDirectoryAtPath:work withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]) {
            [self finishWithTitle:@"업데이트 준비 실패" message:error.localizedDescription]; return;
        }
        NSString *unpacked=[work stringByAppendingPathComponent:@"unpacked"];
        NSString *staged=[unpacked stringByAppendingPathComponent:@"SidePad/SidePad.app"];
        BOOL valid=[self run:@"/usr/bin/ditto" arguments:@[@"-x",@"-k",location.path,unpacked] error:&error];
        NSDictionary *plist=[NSDictionary dictionaryWithContentsOfFile:[staged stringByAppendingPathComponent:@"Contents/Info.plist"]];
        valid=valid && [plist[@"CFBundleIdentifier"] isEqual:@"studio.prxs.paddisplay.mac"] &&
            [plist[@"CFBundleShortVersionString"] isEqual:info[@"version"]] &&
            [self run:@"/usr/bin/codesign" arguments:@[@"--verify",@"--strict",@"-R",@"=identifier \"studio.prxs.paddisplay.mac\"",staged] error:&error];
        if (!valid) {
            [fm removeItemAtPath:work error:nil];
            [self finishWithTitle:@"업데이트 앱 검증 실패" message:@"새 앱의 버전 또는 서명을 확인할 수 없습니다. 기존 앱은 그대로 유지했습니다."]; return;
        }
        NSString *helper=[work stringByAppendingPathComponent:@"install-update.sh"];
        if (![fm copyItemAtPath:[NSBundle.mainBundle pathForResource:@"install-update" ofType:@"sh"] toPath:helper error:&error]) {
            [fm removeItemAtPath:work error:nil]; [self finishWithTitle:@"업데이트 준비 실패" message:error.localizedDescription]; return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.stateChanged) self.stateChanged(@"설치 후 다시 여는 중…");
            NSTask *installer=[NSTask new]; installer.executableURL=[NSURL fileURLWithPath:@"/bin/bash"];
            installer.arguments=@[helper,[NSString stringWithFormat:@"%d",NSProcessInfo.processInfo.processIdentifier],destination,staged,work];
            NSString *log=[work stringByAppendingPathComponent:@"install.log"]; [fm createFileAtPath:log contents:nil attributes:nil];
            NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:log]; installer.standardOutput=handle; installer.standardError=handle;
            NSError *launchError=nil;
            if (![installer launchAndReturnError:&launchError]) {
                [handle closeFile]; [self finishWithTitle:@"업데이트 설치 실패" message:launchError.localizedDescription]; return;
            }
            [handle closeFile]; [NSApp terminate:nil];
        });
    }] resume];
}
@end
