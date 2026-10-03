#import "ForegroundSession.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        PDForegroundSession *session = [PDForegroundSession new];
        NSString *first = NSUUID.UUID.UUIDString;
        assert(![session acceptID:first]); // A tablet cannot start before pairing.
        NSString *launch = [session prepareLaunch];
        assert([session acceptID:launch]);
        assert([session acceptID:launch]); // A cable retry in the foreground can recover.
        [session blockCurrent];
        assert(![session acceptID:launch]); // Retries cannot undo the Mac Stop button.
        assert([session acceptID:first]); // Leaving and reopening the app can resume.
        assert(![session acceptID:launch]); // A delayed older retry stays blocked.
        [session blockCurrent];
        NSString *nextLaunch = [session prepareLaunch];
        assert([session acceptID:nextLaunch]); // Explicit Mac start resumes as well.
        [session blockCurrent];
        assert(![session acceptID:nextLaunch]); // Stop while launch is in flight.
        assert(![session acceptID:@"not-a-uuid"]);
        assert(![session acceptID:nil]);
        NSString *hello = [NSString stringWithFormat:@"PADDISPLAY/3 secret %@", first.lowercaseString];
        assert([PDForegroundID(hello, @"secret") isEqualToString:first]);
        assert(!PDForegroundID(hello, @"wrong-secret"));
        assert(!PDForegroundID(@"PADDISPLAY/1 secret", @"secret"));
        assert(!PDForegroundID([hello stringByReplacingOccurrencesOfString:@"/3" withString:@"/2"],@"secret"));
        assert(![session canAcceptID:nextLaunch]);
        assert(!PDForegroundID([hello stringByAppendingString:@" extra"], @"secret"));
        assert(!PDForegroundID(@"PADDISPLAY/3 secret invalid", @"secret"));
        assert(!PDForegroundID(nil, @"secret"));
        puts("Foreground session tests passed");
    }
}
