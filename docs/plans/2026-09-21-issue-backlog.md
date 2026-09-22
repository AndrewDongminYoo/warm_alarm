# Issue backlog implementation

## Success criteria

1. Assess #14 and #19 against current implementations → verify existing Dart and native tests plus documented device evidence.
2. Repair #16, #18, and Android #20 → verify `./gradlew :warm_alarm_android:testDebugUnitTest --console=plain` from the example Android host.
3. Validate #17 and document #20 → verify `flutter test` in the facade package and scoped `dart format --line-length 120`.
4. Deliver #15 across all platforms → verify native FIFO and retry tests plus platform Dart tests.
5. Implement #21 → verify public unsupported defaults, iOS ActivityKit behavior, generated bindings, and Apple build results.
6. Integrate and review → verify `flutter analyze`, package tests, native tests, scoped Trunk checks, and independent review findings.

## Ownership

- Root: integration, shared documentation, readiness assessment, generated bindings, Xcode test membership, final checks, Git state.
- Sol Android worker: schedule store, foreground service, vibration/audio policy, corresponding tests and Android documentation.
- Terra validation worker: facade validation, facade tests, audio model documentation, facade documentation and changelogs.
- Sol event worker: native queues and event dispatch hooks, platform Dart event setup and tests.
- Sol Apple assessment: read-only AlarmKit and ActivityKit gap analysis before bounded implementation assignment.

Workers share the verified main workspace and do not stage or commit.
Native builds run one at a time under root coordination.
No new dependency or broad rewrite is planned.

## Integration order

Complete independent Android and validation fixes while the event worker updates dispatch.
Define the smallest Live Activity contract from Apple SDK evidence, then add public methods and generated bindings.
Integrate ActivityKit hooks only after the event worker releases the Apple plugin files.
Review the complete diff for ownership, replay acknowledgements, fallback behavior, and release constraints.

## Boundaries

Do not mark device-dependent acceptance complete from source inspection or mocks.
Do not close an issue until its stated acceptance is supported by evidence.
Preserve the staged release order for future publication: interface, platform packages, facade.

## Facade release stage

PR #57 published interface 0.1.4, and PR #58 merged as `af9a950117f6de0016092eb38975b0ff7efa7279` before publishing Android 0.1.3, iOS 0.1.10, and macOS 0.1.3.
Merge that main commit into the existing PR #56 branch without rewriting remote history.
Keep all platform packages, generated bindings, example fixtures, and workflows identical to that main commit.
Retain the facade forwarding, validation, and contract documentation from this approved plan.
Release the facade as 0.1.5 with dependency floors matching those published versions.

1. Preserve the platform integration → verify no diff against the platform merge in platform packages, generated outputs, example fixtures, and workflows.
2. Verify facade behavior → run facade and example Dart tests, Flutter analysis, and scoped formatting.
3. Verify published dependency floors → resolve the facade outside the workspace with `flutter pub downgrade` and inspect the hosted package versions; run the hosted Pana check.
4. Complete the facade PR → run independent review, current-head CI, and the remaining bounded hosted review rounds.

The prior Live Activity visual approval carries through this nonvisual facade change.
Final physical iPhone acceptance for issue #19 remains pending and does not become verified through facade tests.
Facade merge, facade publication, issue closure, cleanup, and durable memory retain their separate authorization boundaries.
