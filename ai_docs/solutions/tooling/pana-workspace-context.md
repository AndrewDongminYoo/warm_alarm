---
title: Preserve workspace context during Pana analysis
date: 2026-08-13
work_type: bugfix
tags: [flutter, pana, github-actions]
confidence: high
references:
  [
    .github/workflows/pana.yaml,
    .github/workflows/warm_alarm_android.yaml,
    .github/workflows/warm_alarm_ios.yaml,
    .github/workflows/warm_alarm_macos.yaml,
    https://github.com/AndrewDongminYoo/warm_alarm/pull/10,
  ]
---

## Summary

The Android, iOS, and macOS Pana jobs scored below the CI threshold because Pana copied each target package into a temporary directory without its sibling `warm_alarm_platform_interface` path dependency.
The fix keeps the package as the analysis target while passing the repository root through Pana's `--project-root` option, so the temporary analysis tree contains the complete pub workspace.

## Reusable Insights

- A Git checkout alone does not preserve workspace context inside Pana because local analysis copies its input into a temporary directory.
- For a package below a pub workspace root, run `pana <package> --project-root .` from the repository root.
- Do not replace legitimate sibling path dependencies or lower the score threshold to hide a dependency-resolution failure.
- Route path-dependent packages through one local reusable workflow, and include that workflow in each caller's path filters so changes exercise every affected package.
- Verify tool claims against the installed version and completed CI logs.
  Pana 0.23.18 exposes `--project-root`, and the three platform jobs each scored `130/160` with it.

## Validation

```bash
pana warm_alarm_android --project-root . --no-warning
pana warm_alarm_ios --project-root . --no-warning
pana warm_alarm_macos --project-root . --no-warning
trunk check .github/workflows/pana.yaml .github/workflows/warm_alarm_android.yaml .github/workflows/warm_alarm_ios.yaml .github/workflows/warm_alarm_macos.yaml
git diff --check
```

The PR reached eight passing checks with no failures or pending jobs on commit `c624864817c8cac6d574e81f4759c6cd4c151c05` before this note was added.
