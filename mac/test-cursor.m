#import "CursorImage.h"
#include <assert.h>
static NSImage *shape(NSColor *color) {
    return [NSImage imageWithSize:NSMakeSize(16,16) flipped:NO drawingHandler:^BOOL(NSRect rect){
        [color setFill];NSRectFill(rect);return YES;
    }];
}
int main(void){
    @autoreleasepool {
        PDCursorImageEncoder *encoder=[PDCursorImageEncoder new];
        NSData *first=[encoder payloadForImage:shape(NSColor.blackColor) hotspot:NSMakePoint(2,3)];
        assert(first.length>8);
        for(int i=0;i<30;i++)assert([encoder payloadForImage:shape(NSColor.blackColor) hotspot:NSMakePoint(2,3)]==first);
        NSData *hot=[encoder payloadForImage:shape(NSColor.blackColor) hotspot:NSMakePoint(3,3)];
        assert(hot!=first && ![hot isEqualToData:first]);
        NSData *white=[encoder payloadForImage:shape(NSColor.whiteColor) hotspot:NSMakePoint(3,3)];
        assert(![white isEqualToData:hot]);
        NSImage *decoded=[[NSImage alloc] initWithData:[white subdataWithRange:NSMakeRange(8,white.length-8)]];
        assert(decoded && decoded.size.width==32 && decoded.size.height==32);
        assert(![encoder payloadForImage:shape(NSColor.blackColor) hotspot:NSMakePoint(NAN,0)]);
        puts("Cursor tests passed (identical pixels reuse payload, shape and hotspot changes, valid PNG)");
    }
}
