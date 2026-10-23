# Voice alarm example validation

## Delivered behavior

The example now demonstrates recording a voice message, previewing it, and passing that file to an alarm request.
Recording is capped at about 15 seconds during normal operation.
The example adds `record`, `audioplayers`, and `path_provider`, with native microphone declarations for Android, iOS, and macOS.
No plugin public API or native scheduling implementation was changed.

The macOS host starts with a 1280×720 content area.
At widths of at least 1100 and heights of at least 640 logical pixels, with text scaling at most 1.3, three columns show voice/events, alarm controls/results, and permissions/capabilities.
Long event lists and scheduling diagnostics scroll inside their own areas.
Smaller windows and larger text retain the scrolling fallback.

Permission exceptions show a short recovery message instead of a native stack trace.
The message is scrolled into view.
Recorder shutdown failures retain the stop control until cleanup succeeds, and playback stream errors restore preview controls.
Recordings are saved in app-private storage; previous files are retained to protect already pending alarms.

## Checks and their scope

Run from `warm_alarm/example` unless stated otherwise.

| Check                                                                                                 | Evidence                    | What it reads                                                                                                       |
| ----------------------------------------------------------------------------------------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `dart format lib/main.dart lib/voice_audio.dart test/inspection_test.dart test/voice_audio_test.dart` | Scoped formatting performed | Dart syntax/style                                                                                                   |
| `flutter analyze --no-pub`                                                                            | No issues found             | Static Dart analysis                                                                                                |
| `flutter test --no-pub --concurrency 1`                                                               | 27 tests passed             | Fake platform/audio UI behavior, schedule arguments, remediation selection, and mock-channel file/shutdown behavior |
| Opt-in rendered fixtures                                                                              | Exported PNGs inspected     | Rasterized Flutter widgets with real font files and synthetic state                                                 |
| Native macOS build                                                                                    | See completion status below | Example host, native audio plugins, microphone entitlements, and Dart compilation                                   |
| `plutil -lint` on the two usage-description plists and both macOS entitlements                        | All valid                   | Property-list syntax                                                                                                |
| Python XML parser on Android manifest                                                                 | Valid XML                   | Manifest syntax                                                                                                     |
| `git diff --check` from repository root                                                               | Passed                      | Diff whitespace                                                                                                     |

The 1280×720 UI test measures the viewport positions of recording, scheduling, preview, cancel, permission actions, event heading, and all six capability values.
An additional test injects 30 synthetic events, verifies the retained 20-event range, scrolls that pane, and confirms a permission error becomes visible without moving alarm controls.
The rendered macOS-style fixture includes blocked readiness and an unsupported wake-check warning; these are test inputs, not a runtime claim about the installed app.
The normal-font rendered fixture also checks that its short scheduling result fits its inner viewport.

### Mutation checks

Removing native disposal from the stop-failure path made `stop failure awaits native disposal before clearing active state` fail: the observed calls ended at `stop` instead of including `dispose`.
Restoring cleanup passed the full suite.
Removing error scrolling made the permission error visibility test fail with its title at y=-380.
Restoring scrolling passed the full suite.
The initial 16:9 arrangement also failed its capability viewport check with the final item ending at y=768; the compact panel passed after correction.

The invariant is that permission failures remain visible and failed recorder shutdown cannot silently enable scheduling.
Callers and siblings were inspected in `lib/main.dart`, `lib/voice_audio.dart`, and the example tests.
Actual native capture and audible delivery remain outside these mocked tests.

### Reproduce rendered fixtures

Use the material-font directory from the Flutter SDK actually running these tests.
The paths below match this Mac's SDK and output directory.

```bash
flutter test --no-pub test/inspection_test.dart \
  --plain-name 'export rendered demo fixtures' \
  --dart-define=DEMO_PREVIEW_DIR=/Users/dongminyu/Desktop/warm-alarm-example-review-20261023 \
  --dart-define=DEMO_FONT_DIR=/Users/dongminyu/Development/flutter/bin/cache/artifacts/material_fonts
```

Artifacts are in `/Users/dongminyu/Desktop/warm-alarm-example-review-20261023/`.
`dashboard.png` and `dashboard-scheduled.png` are synthetic 16:9 previews.
Other captures cover the smaller desktop window, phone layout, dark theme, permission error, and large-text error.
They contain no real microphone recording or desktop capture.

## Runtime limits and manual check

The agent did not request microphone access, grant any OS permission, record personal audio, launch a recording, or write to a physical phone.
Android and iOS native builds/runs for this change were not performed.
Native microphone capture, preview sound, foreground/background alarm playback, and platform permission transitions still need a manual device check.
An earlier System Events request from the agent host was denied with -25211; it was not retried without new permission evidence.
Accessibility permission held by the user's Terminal does not establish permission for this host.

Fully quit the macOS example and run it again so the native initial window size takes effect:

```bash
flutter run --no-pub -d macos
```

Record a short message only after reviewing the OS microphone prompt yourself.
Save, preview, choose **My voice**, schedule a 15-second alarm, observe actual audio and events, and cancel alarm 42 afterward.
If native shutdown cannot be confirmed, retry **Save recording** or close the app before continuing.
A permission error still requires inspecting OS settings; compact error UI does not grant permission or repair the OS authorization state.
See the example README for storage, cleanup, and the existing platform comparison demos.

## Review precedent

The personal `warm_alarm` Oracle retrieval found general Flutter UI review guidance indexed from `.claude/skills/flutter-ui-ux-review/references/review-criteria.md` through `wiki/entities/flutter-ui-ux-review.md`.
That precedent confirmed testing narrow widths, large text, long errors, and explicit recovery controls.
The companion indexed source `.claude/skills/flutter-ui-ux-review/references/evidence-and-runtime.md` confirmed separating rendered fixture evidence from native permission and audio evidence.
No project-specific precedent for this voice-demo redesign or macOS compact error treatment was found: [no precedent found].

Two bounded read-only code reviews initially found offscreen errors, initial-load races, recorder cleanup, and playback-stream error handling issues.
Those issues were repaired and the reviewers reported no remaining blockers in their source checks.
The final dashboard source review also reported no confirmed layout/state blockers.
These reviews did not perform native runtime verification.

## Completion status

`flutter build macos --debug --no-pub` passed for the final source and produced `warm_alarm/example/build/macos/Build/Products/Debug/example.app`.
The built bundle includes the microphone usage description and the signed `com.apple.security.device.audio-input` entitlement.
The scoped Trunk check passed for 15 UI, native declaration, and directly affected documentation files after registering the legitimate terms `mirae`, `osascript`, and `libx264`.

An earlier full `trunk check --no-fix` reported 19 spelling findings and two formatting findings in `scripts/demo`.
Before committing, the legitimate tool names were registered, ephemeral macOS temporary paths were excluded by a narrow spelling pattern, and the two identified files were formatted.
The full gate then passed, and a unique injected spelling canary was detected before restoring the original README byte for byte.
The unmeasured archived zoom templates now reject rendering until their framing is reviewed; synthetic verification uses temporary fixture copies.
The five demo-script unit tests and the synthetic zoom/audio/overwrite checks passed.
No merge, publication, global tool installation, microphone approval, or physical-device write was performed.

### Supplied simulator recordings

The later user-supplied Android and iOS recordings were converted to individual MP4s and a 73.02-second stage-aligned comparison in `/Users/dongminyu/Desktop/warm-alarm-voice-demo-edits-20261023/`.
Original source hashes were preserved, every output fully decoded, and the iOS AAC payload matched its source.
The comparison retains original playback speed and separates Android/iOS audio into left/right channels.
It is an edited comparison, not simultaneous footage or a latency measurement.
iOS preview audio around source seconds 53–64 measured nearly silent; no replacement sound was added.
The supplied footage is separate evidence from the agent's mocked UI and native build checks.
