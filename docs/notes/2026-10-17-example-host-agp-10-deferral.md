# Example host AGP 10 migration deferral

**Date:** 2026-10-17
**Decision owner:** operator
**Issues:** [#112](https://github.com/AndrewDongminYoo/warm_alarm/issues/112) (decision), [#113](https://github.com/AndrewDongminYoo/warm_alarm/issues/113) (deferred migration)

## Current state

The example Android host uses AGP 9.0.1 and Kotlin 2.3.20 since [#95](https://github.com/AndrewDongminYoo/warm_alarm/pull/95).
`warm_alarm/example/android/gradle.properties` keeps `android.newDsl=false` and `android.builtInKotlin=false`, and the host still applies the external Kotlin plugin and Jetifier.
AGP 9 reports these settings as deprecated for AGP 10.
The builds, the Android native unit job, and the API 19/22/29 instrumented matrix pass with these settings.

## Decision

Defer the migration to built-in Kotlin, the new Flutter Gradle DSL, and the removal of Jetifier.
The deprecation notices are warnings, not build failures, and the published plugin does not depend on the example host configuration.

## Trigger

Start #113 when one of these conditions becomes true:

- Flutter requires AGP 10 for its Android tooling.
- The default Flutter app template moves to built-in Kotlin and the new DSL.

When #113 starts, it must pass the native unit suite, both example APK builds, and the API 19/22/29 instrumented matrix without AGP 10 deprecation notices for these settings.

## Update 2026-10-25: template sync, trigger not met

A fresh `flutter create` on Flutter 3.47.8 still writes `android.newDsl=false` and `android.builtInKotlin=false`, so neither trigger above has fired and those two settings stay deferred.
The template no longer sets Jetifier and uses AGP 9.1.0, Kotlin 2.4.0 and Gradle 9.3.1, so the example host follows it: Jetifier is removed and the three versions moved (operator decision on #113).
#113 stays open for the two flags under the same trigger.
