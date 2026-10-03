#import <Foundation/Foundation.h>
#include <math.h>

static BOOL PDNumberInRange(id value, double low, double high) {
    return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]) &&
        [value doubleValue]>=low && [value doubleValue]<=high;
}

// Capabilities come from the authenticated receiver, never from a saved device guess.
static NSDictionary *PDReceiverInfo(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *json=value;
    if (![json[@"protocol"] isEqual:@3] ||
        !PDNumberInRange(json[@"nativeWidth"],320,8192) || !PDNumberInRange(json[@"nativeHeight"],240,8192) ||
        !PDNumberInRange(json[@"panelHz"],24,240) || ![json[@"modes"] isKindOfClass:NSArray.class] ||
        ![json[@"modes"] count] || [json[@"modes"] count]>32) return nil;
    NSMutableArray *modes=[NSMutableArray new];
    for (id mode in json[@"modes"]) {
        if (![mode isKindOfClass:NSDictionary.class]) return nil;
        if (!PDNumberInRange(mode[@"width"],320,4096) || !PDNumberInRange(mode[@"height"],240,4096) ||
            !([mode[@"maxFPS"] isEqual:@30] || [mode[@"maxFPS"] isEqual:@60])) return nil;
        int width=[mode[@"width"] intValue],height=[mode[@"height"] intValue];
        if (width%2 || height%2 || width!=[mode[@"width"] doubleValue] || height!=[mode[@"height"] doubleValue]) return nil;
        [modes addObject:@{@"width":@(width),@"height":@(height),@"maxFPS":mode[@"maxFPS"]}];
    }
    [modes sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [@([b[@"width"] integerValue]*[b[@"height"] integerValue])
            compare:@([a[@"width"] integerValue]*[a[@"height"] integerValue])];
    }];
    NSString *model=[json[@"model"] isKindOfClass:NSString.class] ? json[@"model"] : @"Android 패드";
    model=[[model componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet] componentsJoinedByString:@" "];
    if (model.length>60) model=[model substringToIndex:60];
    return @{@"protocol":@3,@"model":model.length ? model : @"Android 패드",@"nativeWidth":json[@"nativeWidth"],
             @"nativeHeight":json[@"nativeHeight"],@"panelHz":json[@"panelHz"],@"modes":modes};
}

// Choices: automatic, maximum detail, balanced, light. An unsupported rate is lowered.
static NSDictionary *PDStreamMode(NSDictionary *receiver, NSInteger choice, int requestedFPS) {
    NSArray *modes=receiver[@"modes"];
    if (!modes.count || choice<0 || choice>3 || (requestedFPS!=30 && requestedFPS!=60)) return nil;
    NSDictionary *selected=nil;
    for (NSDictionary *mode in modes) {
        if (choice==0 && [mode[@"maxFPS"] intValue]<requestedFPS) continue;
        if (choice==2 && [mode[@"width"] intValue]>1920) continue;
        if (choice==3 && [mode[@"width"] intValue]>1472) continue;
        selected=mode; break;
    }
    if (!selected) selected=choice<2 ? modes.firstObject : modes.lastObject;
    return @{@"width":selected[@"width"],@"height":selected[@"height"],
             @"fps":@(MIN(requestedFPS,[selected[@"maxFPS"] intValue]))};
}

static NSString *PDResolutionKey(NSDictionary *mode) {
    return [NSString stringWithFormat:@"%@x%@",mode[@"width"],mode[@"height"]];
}

// Keep a stable pixel key, rather than an index that changes with the connected pad.
static NSDictionary *PDSelectedStreamMode(NSDictionary *receiver,NSString *key,int requestedFPS) {
    NSArray *presets=@[@"auto",@"native",@"balanced",@"light"];
    NSUInteger preset=[presets indexOfObject:key ?: @"auto"];
    if(preset!=NSNotFound)return PDStreamMode(receiver,preset,requestedFPS);
    for(NSDictionary *mode in receiver[@"modes"])
        if([PDResolutionKey(mode) isEqual:key])return @{@"width":mode[@"width"],@"height":mode[@"height"],
            @"fps":@(MIN(requestedFPS,[mode[@"maxFPS"] intValue]))};
    return PDStreamMode(receiver,0,requestedFPS);
}

static NSArray<NSDictionary *> *PDResolutionOptions(NSDictionary *receiver,BOOL mirrored) {
    NSMutableArray *options=[NSMutableArray arrayWithObject:@{@"key":@"auto",@"title":@"자동 · 패드에 맞게 (권장)"}];
    if(!receiver){
        [options addObjectsFromArray:@[@{@"key":@"native",@"title":@"원본 우선 · 선명하게"},
            @{@"key":@"balanced",@"title":@"균형 · 최대 1920"},@{@"key":@"light",@"title":@"가볍게 · 최대 1472"}]];
        return options;
    }
    NSMutableSet *widths=[NSMutableSet new];
    for(NSDictionary *mode in receiver[@"modes"]){
        if([widths containsObject:mode[@"width"]])continue;
        [widths addObject:mode[@"width"]];
        BOOL native=[mode[@"width"] isEqual:receiver[@"nativeWidth"]] && [mode[@"height"] isEqual:receiver[@"nativeHeight"]];
        NSString *kind=!mirrored && [mode[@"width"] intValue]>2000 ? @"Retina" : @"일반";
        NSString *title=[NSString stringWithFormat:@"%@ × %@ · %@%@",mode[@"width"],mode[@"height"],kind,native ? @" · 원본" : @""];
        [options addObject:@{@"key":PDResolutionKey(mode),@"title":title}];
    }
    return options;
}

static NSString *PDResolutionDescription(NSDictionary *mode,BOOL mirrored) {
    if(!mode)return @"패드를 한 번 연결하면 지원 해상도가 메뉴에 표시됩니다.\nRetina는 글자 크기를 유지하면서 가로·세로 2배의 픽셀로 표시합니다.";
    int width=[mode[@"width"] intValue],height=[mode[@"height"] intValue],fps=[mode[@"fps"] intValue];
    if(mirrored)return [NSString stringWithFormat:@"화면 복제 · 전송 %d × %d · 최대 %d fps\n글자와 작업 공간 크기는 Mac 주 화면의 디스플레이 설정을 따릅니다.",width,height,fps];
    if(width>2000)return [NSString stringWithFormat:@"Retina (2×) · 실제 픽셀 %d × %d / 화면 크기 %d × %d\n글자·버튼은 2배 크기로 편안하게, 세부 표현은 촘촘하게 표시합니다. 최대 %d fps.",width,height,width/2,height/2,fps];
    return [NSString stringWithFormat:@"일반 (1×) · 전송 %d × %d / 화면 크기 %d × %d\n낮은 해상도는 전송 부담을 줄입니다. 패드 화면 크기에 맞춰 확대됩니다. 최대 %d fps.",width,height,width,height,fps];
}

static NSDictionary *PDReceiverFeedback(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *json=value;
    for (NSString *key in @[@"rendered",@"received",@"submitted",@"dropped"])
        if (!PDNumberInRange(json[key],0,1e12) || [json[key] doubleValue] != [json[key] unsignedLongLongValue]) return nil;
    if (!PDNumberInRange(json[@"fps"],0,240) || !PDNumberInRange(json[@"decodeMs"],-1,5000) ||
        !PDNumberInRange(json[@"panelHz"],24,240)) return nil;
    return json;
}

static BOOL PDReceiverDisplaying(NSDictionary *feedback,uint64_t receivedAt,uint64_t now) {
    return [feedback[@"rendered"] unsignedLongLongValue]>0 && receivedAt>0 && now>=receivedAt && now-receivedAt<4000000000ULL;
}
