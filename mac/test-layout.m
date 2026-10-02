#import "DisplayLayout.h"
#include <assert.h>

static NSDictionary *row(NSString *key, int id, int x, int y, int w, int h, BOOL main) {
    return @{@"key":key,@"id":@(id),@"x":@(x),@"y":@(y),@"width":@(w),@"height":@(h),@"rotation":@0,@"main":@(main)};
}
int main(void) {
    @autoreleasepool {
        NSArray *saved = @[row(@"main-screen",1,0,0,2560,1440,YES), row(@"portrait",2,-1080,0,1080,1920,NO), row(@"pad",20,1330,1440,1472,920,NO)];
        NSArray *current = @[row(@"pad",77,2560,0,1472,920,NO), row(@"main-screen",8,0,0,2560,1440,YES), row(@"portrait",9,-1080,0,1080,1920,NO)];
        NSArray *plan = PDLayoutRestorePlan(saved,current);
        assert(plan.count==3 && [plan[0][@"id"] intValue]==8);
        NSDictionary *pad = [plan filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"key == 'pad'"]].firstObject;
        assert([pad[@"id"] intValue]==77 && [pad[@"x"] intValue]==1330 && [pad[@"y"] intValue]==1440);
        // Another panel, missing monitor, or changed scaling must not move physical screens.
        assert(!PDLayoutRestorePlan(saved,@[current[0],current[1]]));
        assert(!PDLayoutRestorePlan(saved,@[current[0],current[1],row(@"different",9,-1080,0,1080,1920,NO)]));
        assert(!PDLayoutRestorePlan(saved,@[row(@"pad",77,2560,0,1920,1200,NO),current[1],current[2]]));
        // The pad can be the primary display; negative coordinates survive restoration.
        NSArray *padMain = @[row(@"pad",20,0,0,1472,920,YES),row(@"main-screen",1,-1330,-1440,2560,1440,NO),row(@"portrait",2,-2410,-1440,1080,1920,NO)];
        plan=PDLayoutRestorePlan(padMain,current);
        assert([plan[0][@"key"] isEqual:@"pad"] && [plan[0][@"id"] intValue]==77);
        assert(!PDLayoutRestorePlan(@[@"invalid"],current));
        assert(!PDLayoutRestorePlan(@[saved[0],saved[0],saved[2]],current));
        NSMutableDictionary *bad=[saved[2] mutableCopy];bad[@"x"]=@(NAN);
        assert(!PDLayoutRestorePlan(@[saved[0],saved[1],bad],current));
        puts("Display layout tests passed (ID changes, topology/scaling changes, primary display, invalid profiles).");
    }
}
