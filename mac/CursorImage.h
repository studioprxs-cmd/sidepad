#import <Cocoa/Cocoa.h>
#include <arpa/inet.h>
#include <math.h>

@interface PDCursorImageEncoder : NSObject
- (NSData *)payloadForImage:(NSImage *)image hotspot:(NSPoint)hot;
@end
@implementation PDCursorImageEncoder {
    NSData *_pixels,*_payload;
    NSSize _size;
    NSPoint _hot;
}
- (NSData *)payloadForImage:(NSImage *)image hotspot:(NSPoint)hot {
    NSSize size=image.size;
    if(!isfinite(size.width) || !isfinite(size.height) || size.width<=0 || size.height<=0 ||
        size.width>256 || size.height>256 || !isfinite(hot.x) || !isfinite(hot.y))return nil;
    int w=(int)ceil(size.width*2),h=(int)ceil(size.height*2);
    NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:w*4 bitsPerPixel:32];
    if(!bitmap)return nil;
    memset(bitmap.bitmapData,0,bitmap.bytesPerRow*h);
    [NSGraphicsContext saveGraphicsState];NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [image drawInRect:NSMakeRect(0,0,w,h) fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
    [NSGraphicsContext restoreGraphicsState];
    NSData *pixels=[NSData dataWithBytes:bitmap.bitmapData length:bitmap.bytesPerRow*h];
    NSSize dimensions=NSMakeSize(w,h);
    // TIFF metadata can change while the cursor pixels stay identical. Compare the pixels
    // before encoding, preserving payload identity so the transport sends real changes only.
    if(NSEqualSizes(dimensions,_size) && NSEqualPoints(hot,_hot) && [pixels isEqualToData:_pixels])return _payload;
    NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];if(!png)return nil;
    float x=hot.x*2,y=hot.y*2;uint32_t xb,yb;memcpy(&xb,&x,4);memcpy(&yb,&y,4);xb=htonl(xb);yb=htonl(yb);
    NSMutableData *payload=[NSMutableData dataWithBytes:&xb length:4];[payload appendBytes:&yb length:4];[payload appendData:png];
    _pixels=pixels;_size=dimensions;_hot=hot;_payload=payload;return _payload;
}
@end
