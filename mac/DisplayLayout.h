#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

// Persistent identities replace session-local CGDirectDisplayIDs. The pad is
// identified by its Android device key outside the snapshot.
static NSArray<NSDictionary *> *PDLayoutSnapshot(CGDirectDisplayID pad) {
    CGDirectDisplayID ids[32]; uint32_t count = 0;
    if (!pad || CGGetActiveDisplayList(32, ids, &count) != kCGErrorSuccess || count == 32) return nil;
    NSMutableArray *rows = [NSMutableArray new]; BOOL foundPad = NO;
    for (uint32_t i = 0; i < count; i++) {
        CGDirectDisplayID display = ids[i];
        if (CGDisplayIsInMirrorSet(display)) return nil;
        NSString *key = @"pad";
        if (display != pad) {
            CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(display);
            if (!uuid) return nil;
            key = CFBridgingRelease(CFUUIDCreateString(NULL, uuid)); CFRelease(uuid);
        } else foundPad = YES;
        CGRect bounds = CGDisplayBounds(display);
        [rows addObject:@{@"key":key, @"id":@(display), @"x":@(bounds.origin.x), @"y":@(bounds.origin.y),
                          @"width":@(bounds.size.width), @"height":@(bounds.size.height),
                          @"rotation":@(CGDisplayRotation(display)), @"main":@(CGDisplayIsMain(display))}];
    }
    return foundPad && rows.count > 1 ? rows : nil;
}

static BOOL PDLayoutValidRows(NSArray *rows) {
    if (![rows isKindOfClass:NSArray.class] || rows.count < 2 || rows.count > 31) return NO;
    NSMutableSet *keys = [NSMutableSet new]; NSUInteger mainCount = 0;
    for (id row in rows) {
        if (![row isKindOfClass:NSDictionary.class]) return NO;
        NSString *key = row[@"key"];
        if (![key isKindOfClass:NSString.class] || !key.length || [keys containsObject:key]) return NO;
        [keys addObject:key];
        for (NSString *field in @[@"x", @"y", @"width", @"height", @"rotation", @"main"]) {
            if (![row[field] isKindOfClass:NSNumber.class] || !isfinite([row[field] doubleValue])) return NO;
        }
        if (fabs([row[@"x"] doubleValue]) > 100000 || fabs([row[@"y"] doubleValue]) > 100000 ||
            [row[@"width"] doubleValue] < 1 || [row[@"width"] doubleValue] > 32768 ||
            [row[@"height"] doubleValue] < 1 || [row[@"height"] doubleValue] > 32768) return NO;
        if ([row[@"main"] boolValue]) {
            mainCount++;
            if ([row[@"x"] doubleValue] != 0 || [row[@"y"] doubleValue] != 0) return NO;
        }
    }
    return mainCount == 1 && [keys containsObject:@"pad"];
}

static NSString *PDLayoutTopologyKey(NSArray *rows) {
    if (!PDLayoutValidRows(rows)) return nil;
    NSMutableArray *parts = [NSMutableArray new];
    for (NSDictionary *row in rows) {
        [parts addObject:[NSString stringWithFormat:@"%@:%g:%g:%g", row[@"key"], [row[@"width"] doubleValue],
                          [row[@"height"] doubleValue], [row[@"rotation"] doubleValue]]];
    }
    [parts sortUsingSelector:@selector(compare:)];
    return [parts componentsJoinedByString:@"|"];
}

// Returns destinations using CURRENT display IDs, even after hotplug/restart.
// A different monitor set, scale, or rotation gets a separate saved profile.
static NSArray<NSDictionary *> *PDLayoutRestorePlan(NSArray *saved, NSArray *current) {
    NSString *key = PDLayoutTopologyKey(saved);
    if (!key || ![key isEqual:PDLayoutTopologyKey(current)]) return nil;
    NSMutableDictionary *byKey = [NSMutableDictionary new];
    for (NSDictionary *row in current) {
        if (![row[@"id"] isKindOfClass:NSNumber.class] || ![row[@"id"] unsignedIntValue]) return nil;
        byKey[row[@"key"]] = row;
    }
    NSMutableArray *plan = [NSMutableArray new];
    for (NSDictionary *row in saved) {
        [plan addObject:@{@"id":byKey[row[@"key"]][@"id"], @"key":row[@"key"],
                          @"x":row[@"x"], @"y":row[@"y"], @"main":row[@"main"]}];
    }
    [plan sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"main"] compare:a[@"main"]];
    }];
    return plan;
}

@interface PDDisplayLayout : NSObject
@property(strong) NSUserDefaults *defaults;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (BOOL)saveForDevice:(NSString *)device display:(CGDirectDisplayID)pad;
- (BOOL)restoreForDevice:(NSString *)device display:(CGDirectDisplayID)pad;
@end

@implementation PDDisplayLayout
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) _defaults = defaults;
    return self;
}
- (BOOL)saveForDevice:(NSString *)device display:(CGDirectDisplayID)pad {
    NSArray *current = PDLayoutSnapshot(pad); NSString *topology = PDLayoutTopologyKey(current);
    if (!device.length || !topology) return NO;
    // IDs change after a restart and must never be persisted as identities.
    NSMutableArray *saved = [NSMutableArray new];
    for (NSDictionary *row in current) { NSMutableDictionary *entry = [row mutableCopy]; [entry removeObjectForKey:@"id"]; [saved addObject:entry]; }
    [saved sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"key"] compare:b[@"key"]]; }];
    NSMutableDictionary *devices = [[_defaults dictionaryForKey:@"SidePadDisplayLayoutsV1"] mutableCopy] ?: [NSMutableDictionary new];
    NSDictionary *existing = [devices[device] isKindOfClass:NSDictionary.class] ? devices[device] : nil;
    if ([existing[topology] isEqual:saved]) return YES;
    NSMutableDictionary *profiles = [existing mutableCopy] ?: [NSMutableDictionary new];
    profiles[topology] = saved; devices[device] = profiles;
    [_defaults setObject:devices forKey:@"SidePadDisplayLayoutsV1"];
    return YES;
}
- (BOOL)restoreForDevice:(NSString *)device display:(CGDirectDisplayID)pad {
    NSArray *current = PDLayoutSnapshot(pad); NSString *topology = PDLayoutTopologyKey(current);
    if (!device.length || !topology) return NO;
    NSDictionary *devices = [_defaults dictionaryForKey:@"SidePadDisplayLayoutsV1"];
    NSDictionary *profiles = [devices[device] isKindOfClass:NSDictionary.class] ? devices[device] : nil;
    NSArray *plan = PDLayoutRestorePlan(profiles[topology], current);
    if (!plan) return NO;
    CGDisplayConfigRef config = NULL;
    if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess) return NO;
    for (NSDictionary *row in plan) {
        if (CGConfigureDisplayOrigin(config, [row[@"id"] unsignedIntValue], [row[@"x"] intValue], [row[@"y"] intValue]) != kCGErrorSuccess) {
            CGCancelDisplayConfiguration(config); return NO;
        }
    }
    if (CGCompleteDisplayConfiguration(config, kCGConfigureForSession) != kCGErrorSuccess) return NO;
    for (NSDictionary *row in plan) {
        CGRect actual = CGDisplayBounds([row[@"id"] unsignedIntValue]);
        if (actual.origin.x != [row[@"x"] doubleValue] || actual.origin.y != [row[@"y"] doubleValue]) return NO;
    }
    return YES;
}
@end
