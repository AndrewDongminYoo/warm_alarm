# macOS replacement rollback implementation

## Scope

The operator authorized the next issue through `pr-loop`.
Implement #74 in the main workspace on `fix/macos-replacement-rollback` from `e4b185639fed241d7c2adbf20c0ea48a51522d30`.
The root owns macOS `WarmAlarmPlugin.swift`, `WarmAlarmReplacementTests.swift`, `README.md`, and these spec and plan files.
Oracle returned no applicable project precedent for replacement or rollback.
Advisor confirmed snapshot restoration with explicit pending removal before store restoration and all-request restoration attempts.

## Steps

1. Add injectable notification addition and authorization-status boundaries with production defaults → compile native regression fixtures and observe the old loss behavior fail.
2. Snapshot previous requests and stored data, restore after registration failure, and surface explicit errors → run the replacement tests, including partial and rollback failures and queue ordering.
3. Document the contract and inspect root README, CLAUDE.md, and applicable AGENTS.md for drift → update affected documentation in this PR.
4. Run all macOS SwiftPM tests with the real FlutterMacOS framework, macOS Dart tests, Flutter analysis, explicit Dart formatting, and scoped Trunk → record each gate's actual coverage.
5. Perform the repository-calibrated adversarial review and repairs → commit by concern, push, create a PR closing #74, and observe current-head CI and hosted reviews.

## Boundary

Merge remains the operator's action.
Cleanup and memory recording for this PR were not requested.
Use at most two local repair rounds and five hosted review rounds within five hours.
Run heavy mobile jobs sequentially after checking machine load.
