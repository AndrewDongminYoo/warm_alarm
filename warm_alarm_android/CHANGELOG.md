# 0.1.2

- Give a wake-check retrigger its own `PendingIntent` identity. It shared the regular alarm's, so arming a retrigger re-targeted the pending next occurrence and dismissing a wake check cancelled it.
- Keep a recurring alarm's stored schedule when a wake check finishes. Only a one-shot alarm's schedule is removed.
- Cancel both alarm identities from `cancelAlarm` and `cancelAllAlarms`.

# 0.1.1

- Add notification authorization and supported readiness-settings remediation.
- Report `unsupported` when notification authorization is requested below Android 13.

# 0.1.0+1

- Initial release of this plugin.
