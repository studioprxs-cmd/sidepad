#import "DisplayLayout.h"

// Read-only by default. --remember DEVICE snapshots the live layout before an app update.
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        CGDirectDisplayID ids[32], pad=0; uint32_t count=0;
        CGGetActiveDisplayList(32,ids,&count);
        for(uint32_t i=0;i<count;i++) if(CGDisplayVendorNumber(ids[i])==0x505 && CGDisplayModelNumber(ids[i])==0x5044)pad=ids[i];
        NSArray *snapshot=PDLayoutSnapshot(pad); if(!snapshot)return 1;
        NSData *json=[NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:nil];
        fwrite(json.bytes,1,json.length,stdout);puts("");
        if(argc==3 && !strcmp(argv[1],"--remember")) {
            NSUserDefaults *defaults=[[NSUserDefaults alloc]initWithSuiteName:@"studio.prxs.paddisplay.mac"];
            PDDisplayLayout *layout=[[PDDisplayLayout alloc]initWithDefaults:defaults];
            if(![layout saveForDevice:[NSString stringWithUTF8String:argv[2]] display:pad])return 2;
            [defaults synchronize];puts("Remembered current layout.");
        }
    }
}
