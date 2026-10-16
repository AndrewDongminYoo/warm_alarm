# iOS fallback replacement rollback implementation

## Scope

Implement issue #88 in the existing iOS plugin, store, and RunnerTests source.
Update the iOS README contract in the same PR.
Oracle retrieval for personal project `warm_alarm`, topics `fallback rollback` and `sound ownership`, returned no relevant precedent.

## Steps

1. Add a notification-adder injection seam with unchanged production defaults and plugin-level regression tests.
   Verify: draft PR iOS RunnerTests reports the expected replacement failure assertions before the fix.
2. Snapshot old fallback requests and schedule, defer previous sound cleanup, and recover all prior requests before an explicit error reply.
   Verify: the same native tests pass, including partial recovery and queued mutation coverage.
3. Check affected README, AGENTS, and CLAUDE claims and run scoped local formatting, Flutter analysis/tests, and Trunk.
   Verify: record command results and distinguish Dart/static checks from native execution.
4. Review the complete candidate, fix findings within the bounded review budget, and complete hosted code/security review and CI.
   Verify: current-head evidence is clean before requesting operator merge.

## Constraints

Use the assigned main workspace and preserve unrelated branches and control records.
Do not run a local heavy mobile job while the Data volume is near capacity.
Keep existing CI gates and hooks active; the initial draft PR is for regression-first execution, not merge readiness.
Merge remains an operator action.
