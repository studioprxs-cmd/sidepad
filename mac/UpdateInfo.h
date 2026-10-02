#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

static BOOL PDMatches(NSString *text, NSString *pattern) {
    return [text isKindOfClass:NSString.class] &&
        [text rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}

// Only complete, stable releases from this repository are installable.
static NSDictionary *PDUpdateInfo(id json) {
    if (![json isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *release=json;
    NSString *tag=release[@"tag_name"];
    if (!PDMatches(tag,@"^v[0-9]+(\\.[0-9]+){1,2}$") ||
        ![release[@"draft"] isEqual:@NO] || ![release[@"prerelease"] isEqual:@NO] ||
        ![release[@"assets"] isKindOfClass:NSArray.class]) return nil;
    NSString *expected=[NSString stringWithFormat:@"https://github.com/studioprxs-cmd/sidepad/releases/download/%@/SidePad-macOS.zip",tag];
    for (id value in release[@"assets"]) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *asset=value;
        if (![asset[@"name"] isEqual:@"SidePad-macOS.zip"] || ![asset[@"state"] isEqual:@"uploaded"] ||
            ![asset[@"browser_download_url"] isEqual:expected] ||
            !PDMatches(asset[@"digest"],@"^sha256:[0-9a-f]{64}$") ||
            ![asset[@"size"] isKindOfClass:NSNumber.class] ||
            [asset[@"size"] longLongValue]<=0 || [asset[@"size"] longLongValue]>100*1024*1024) continue;
        return @{@"version":[tag substringFromIndex:1],@"url":expected,
                 @"sha256":[asset[@"digest"] substringFromIndex:7],@"size":asset[@"size"]};
    }
    return nil;
}

static BOOL PDIsNewerVersion(NSString *available, NSString *installed) {
    if (!PDMatches(available,@"^[0-9]+(\\.[0-9]+){1,2}$") ||
        !PDMatches(installed,@"^[0-9]+(\\.[0-9]+){1,2}$")) return NO;
    return [available compare:installed options:NSNumericSearch]==NSOrderedDescending;
}

static BOOL PDVerifyUpdateData(NSData *data, NSDictionary *info) {
    if (!data || data.length!=[info[@"size"] unsignedLongLongValue]) return NO;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *hex=[NSMutableString new];
    for (NSUInteger i=0;i<sizeof(digest);i++) [hex appendFormat:@"%02x",digest[i]];
    return [hex isEqualToString:info[@"sha256"]];
}
