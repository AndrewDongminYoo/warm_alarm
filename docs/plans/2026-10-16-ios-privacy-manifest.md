# iOS privacy manifest implementation

## Scope and ownership

The operator requested the implementation and PR loop for issue #77.
Use the main workspace on `fix/ios-privacy-manifest`; the root owns all edits, commits, and verification.
Modify the iOS manifest, SwiftPM resource list, podspec resource bundle, iOS README and package instructions, the package-local bundle verifier, a dedicated iOS privacy CI workflow, and these documents.
Use standard-library validation and existing Flutter, CocoaPods, and Xcode tools without adding dependencies.

## Steps and checks

1. Inventory production required-reason APIs against current Apple documentation → retain the two category mappings in the spec.
2. Add a source and built-bundle verifier → observe the missing-manifest failure before adding the resource.
3. Add the shared manifest and both package resource declarations → parse the plist, inspect resolved package metadata, and run the verifier.
4. Build SwiftPM and CocoaPods hosts on separate macOS CI runners → run the verifier against each actual archived app bundle and prove missing or altered resources fail.
5. Archive a host and generate the Xcode privacy report → inspect the archive resources and report, preserving the distinction between required-reason APIs and collected-data reporting.
6. Add a dual-packaging archive CI workflow with built-bundle checks, update the README and package instructions → run package tests, Flutter analysis, explicit formatting, scoped Trunk, and diff review.
7. Review the final change according to its actual scope, commit by concern, push, open a PR closing #77, and observe hosted reviews and CI → require the current-head gates before requesting operator merge.

## Verification constraints

Check available disk space and load before native builds; run at most one heavy mobile job at a time.
Reuse existing build outputs where possible and avoid deleting unrelated caches or changing global Flutter settings.
Local preflight found 97% Data-volume capacity and no reusable iOS host outputs, so native builds run on CI and archives are downloaded for report inspection.
Packaging fixtures may live outside the repository; record their inputs and output paths in Git-local state.
Preserve generated Flutter files and avoid committing fixture or archive artifacts.
Allow two local repair rounds and five hosted rounds within five hours of the first hosted trigger.
Merge remains the operator's action; cleanup and memory recording for the new PR require their own request.
