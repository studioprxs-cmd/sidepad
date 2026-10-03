#import <Foundation/Foundation.h>

// A foreground ID lasts for one Android onResume interval, including USB retries.
// Only a new foreground interval or an explicit Mac start can undo a manual stop.
static NSString *PDForegroundID(NSString *hello, NSString *token) {
    NSArray<NSString *> *parts = [hello componentsSeparatedByString:@" "];
    if (parts.count != 3 || ![parts[0] isEqualToString:@"PADDISPLAY/3"] ||
        !token.length || ![parts[1] isEqualToString:token]) return nil;
    return [[NSUUID alloc] initWithUUIDString:parts[2]].UUIDString;
}

@interface PDForegroundSession : NSObject
@property(nonatomic, readonly) BOOL paired;
@property(nonatomic, copy, readonly) NSString *currentID;
- (NSString *)prepareLaunch;
- (BOOL)acceptID:(NSString *)identifier;
- (BOOL)canAcceptID:(NSString *)identifier;
- (void)blockCurrent;
@end

@implementation PDForegroundSession {
    NSMutableSet<NSString *> *_blockedIDs;
}
- (instancetype)init {
    if ((self = [super init])) _blockedIDs = [NSMutableSet new];
    return self;
}
- (NSString *)prepareLaunch {
    _paired = YES;
    _currentID = NSUUID.UUID.UUIDString;
    return _currentID;
}
- (BOOL)acceptID:(NSString *)identifier {
    if(![self canAcceptID:identifier])return NO;
    NSString *normalized = [[NSUUID alloc] initWithUUIDString:identifier].UUIDString;
    _currentID = normalized;
    return YES;
}
- (BOOL)canAcceptID:(NSString *)identifier {
    NSString *normalized=[[NSUUID alloc] initWithUUIDString:identifier].UUIDString;
    return _paired && normalized && ![_blockedIDs containsObject:normalized];
}
- (void)blockCurrent {
    if (_currentID) [_blockedIDs addObject:_currentID];
}
@end
