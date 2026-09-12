#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        // На Catalina NSApplication.delegate не обязан удерживать delegate.
        // Поэтому держим AppDelegate живым до полного завершения run loop.
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];

        [app run];

        [app setDelegate:nil];
        [delegate release];
    }

    return 0;
}
