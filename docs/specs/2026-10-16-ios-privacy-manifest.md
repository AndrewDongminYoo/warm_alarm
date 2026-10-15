# iOS privacy manifest packaging

## Problem and contract

[Issue #77](https://github.com/AndrewDongminYoo/warm_alarm/issues/77) identifies required-reason API use without a bundled privacy manifest.
Ship one `PrivacyInfo.xcprivacy` from the iOS source tree through both SwiftPM and CocoaPods.
The plugin's runtime behavior, public API, dependencies, and host entitlements stay unchanged.

## API inventory and reasons

| Category                                    | Production use                                                                                                                                                                                                       | Approved reason                             |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| `NSPrivacyAccessedAPICategoryUserDefaults`  | `WarmAlarmStore` persists schedules; `WarmAlarmConsumedOccurrenceStore` persists handled occurrences; `WarmAlarmPlugin` persists process-termination warning configuration, all in app-local `UserDefaults.standard` | `CA92.1`: app-only information              |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `WarmAlarmSoundFiles.removeUnreferenced` reads `contentModificationDateKey` for generated audio in the app's `Library/Sounds` directory                                                                              | `C617.1`: metadata inside the app container |

The production Swift source inventory found no direct disk-capacity, system-uptime, or active-keyboard API use.
The plugin does not implement network collection or tracking; declare no collected data types or tracking domains and set tracking to false.
These declarations describe this plugin, not the consuming app or other SDKs.
Do not use the wrapper-only reasons: persistence and cleanup also run during plugin lifecycle handling rather than only through a generic wrapper called by the app.

Reason definitions and covered APIs were checked against [Apple's API category reference](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
Resource placement follows [Apple's privacy manifest guidance](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files).
Oracle returned `[no precedent found]` for this project's privacy-manifest and UserDefaults topics.

## Acceptance and limits

1. The manifest declares exactly the inventoried API categories and reasons and parses as a property list.
2. SwiftPM processes the manifest as a target resource; CocoaPods includes the same source in a named resource bundle.
3. A built host app from each packaging path contains the plugin manifest with the expected declarations.
4. The bundle check fails when the manifest is absent or its reasons differ; the initial source check fails before implementation.
5. Generate and inspect an Xcode archive privacy report using [Apple's documented workflow](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests).
   Inspect the archive manifest directly for required-reason details because the report summarizes collected data and tracking.
6. Flutter analysis, package Dart tests, scoped formatting and Trunk, local review, and current-head CI pass.

No App Store submission or rejection is reproduced or claimed.
Builds and report generation do not require a physical-device install or a publication.
No product visual output changes, so operator visual approval is not applicable.
