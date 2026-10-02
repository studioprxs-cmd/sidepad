#import "UpdateInfo.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        NSMutableDictionary *asset=[@{@"name":@"SidePad-macOS.zip",@"state":@"uploaded",@"size":@3,
            @"browser_download_url":@"https://github.com/studioprxs-cmd/sidepad/releases/download/v1.9/SidePad-macOS.zip",
            @"digest":@"sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"} mutableCopy];
        NSMutableDictionary *release=[@{@"tag_name":@"v1.9",@"draft":@NO,@"prerelease":@NO,@"assets":@[asset]} mutableCopy];
        NSDictionary *info=PDUpdateInfo(release);
        assert(info && [info[@"version"] isEqual:@"1.9"]);
        assert(PDVerifyUpdateData([@"abc" dataUsingEncoding:NSUTF8StringEncoding],info));
        assert(!PDVerifyUpdateData([@"abd" dataUsingEncoding:NSUTF8StringEncoding],info));
        assert(!PDVerifyUpdateData([@"ab" dataUsingEncoding:NSUTF8StringEncoding],info));
        assert(PDIsNewerVersion(@"1.10",@"1.9"));
        assert(PDIsNewerVersion(@"1.9",@"1.8.1"));
        assert(!PDIsNewerVersion(@"1.9",@"1.9"));
        assert(!PDIsNewerVersion(@"1.8",@"1.9"));
        assert(!PDIsNewerVersion(@"1.9-beta",@"1.8"));
        release[@"draft"]=@YES; assert(!PDUpdateInfo(release)); release[@"draft"]=@NO;
        release[@"prerelease"]=@YES; assert(!PDUpdateInfo(release)); release[@"prerelease"]=@NO;
        asset[@"browser_download_url"]=@"https://example.com/SidePad-macOS.zip"; assert(!PDUpdateInfo(release));
        asset[@"browser_download_url"]=@"https://github.com/studioprxs-cmd/sidepad/releases/download/v1.9/SidePad-macOS.zip";
        asset[@"digest"]=NSNull.null; assert(!PDUpdateInfo(release));
        assert(!PDUpdateInfo(NSNull.null)); assert(!PDUpdateInfo(@{}));
        puts("Update tests passed (version order, origin, complete release, SHA-256, corruption)");
    }
}
