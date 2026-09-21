# Live Activity host example

This example configures the optional custom alarm-status Live Activity on iOS 16.2 or later.
It uses local ActivityKit updates only and does not use an ActivityKit push token or a push server.

## Add the files to the host

1. Create a Widget Extension with the **Include Live Activity** option and an iOS 16.2 or later deployment target.
2. Add `WarmAlarmLiveActivityAttributes.swift` to both the app target and the Widget Extension target.
3. Add `WarmAlarmLiveActivityWidget.swift` to the Widget Extension target only.
4. Add `WarmAlarmActivityKitAdapter.swift` to the app target only.
5. If the Widget Extension already has an `@main` `WidgetBundle`, remove the sample `WarmAlarmWidgetBundle` and add `WarmAlarmLiveActivityWidget()` to the existing bundle.

The attributes file is host-owned and has no Flutter dependency.
Compiling that file into both targets gives ActivityKit and WidgetKit the same state schema without linking the Flutter plugin into the extension.

## Configure the app target

Add both keys to the app target's `Info.plist`.

```xml
<key>NSSupportsLiveActivities</key>
<true/>
<key>WarmAlarmLiveActivityEnabled</key>
<true/>
```

The plugin reports custom Live Activity support as unsupported when either key is absent or false.
`WarmAlarmAlarmKitLiveActivityEnabled` is a separate opt-in for AlarmKit Snooze countdown presentation and does not enable this API.

Register the adapter during app startup.

```swift
import Flutter
import UIKit
import warm_alarm_ios

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        WarmAlarmLiveActivityRegistration.register()
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
```

Registration can occur before the first capability query or Live Activity operation.
The adapter checks `ActivityAuthorizationInfo.areActivitiesEnabled` each time, so a user setting change takes effect without rebuilding the adapter.

## Accessibility

The sample provides accessibility labels for the Lock Screen, expanded Dynamic Island, compact Dynamic Island, and minimal Dynamic Island presentations.
The labels include the current title and status, and include the next alarm time when one is present.
Keep these labels synchronized when the visual status changes, preserve readable color contrast, and test each presentation with VoiceOver and larger text sizes.

## Runtime behavior

Starting returns an ActivityKit activity identifier.
Persist that identifier if updates can occur after an app restart.
The adapter resolves update and end requests against `Activity<WarmAlarmActivityAttributes>.activities`, so a valid identifier continues to work after process recreation.
A recovered update also verifies that the immutable ActivityKit `alarmId` matches the requested state before it changes visible content.
A missing identifier returns the public `notFound` result.

ActivityKit allows an app to start a Live Activity only while the app is in the foreground unless the host adopts a separate system mechanism such as a `LiveActivityIntent`.
This first version intentionally omits App Intents, interactive controls, remote push updates, frequent-update configuration, and custom dismissal policies.
