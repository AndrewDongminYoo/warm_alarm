#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Carbon/Carbon.h>
int main(void) {
  @autoreleasepool {
    const char *bundle = "com.apple.systemevents";
    AEAddressDesc target = {typeNull, NULL};
    OSStatus status = AECreateDesc(typeApplicationBundleID, bundle, strlen(bundle), &target);
    if (status == noErr) {
      status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false);
      AEDisposeDesc(&target);
    }
    printf("Accessibility (this caller): %s\n", AXIsProcessTrusted() ? "granted" : "not granted");
    printf("Screen Recording (this caller): %s\n", CGPreflightScreenCaptureAccess() ? "granted" : "not granted");
    printf("Automation -> System Events (no prompt): %d\n", (int)status);
    puts("Automation: 0=granted, -1744=consent required, -1743=denied. Other codes=unknown/error.");
    puts("Permissions depend on the launching host; recheck from the Terminal used for rehearsal.");
    BOOL found = NO;
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
      if ([app.bundleIdentifier isEqualToString:@"com.example.myplugin.example"]) {
        found = YES;
        printf("Example running: %s (pid %d)\n", app.localizedName.UTF8String, app.processIdentifier);
      }
    }
    if (!found) puts("Example running: not found by source bundle ID (identity still needs runtime verification).");
  }
  return 0;
}
