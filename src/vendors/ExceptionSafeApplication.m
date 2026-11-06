@import Cocoa;
#import "ExceptionSafeApplication.h"

/// Catches Objective-C exceptions thrown while dispatching an event, so a bad event logs instead of aborting the app.
@implementation ExceptionSafeApplication

- (void)sendEvent:(NSEvent *)theEvent {
    @try {
        [super sendEvent:theEvent];
    } @catch (NSException *exception) {
        [self reportException:exception];
    }
}

@end
