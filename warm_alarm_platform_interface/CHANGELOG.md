# 0.1.4

- Add opt-in Live Activity content and operation result models.
- Add inherited unsupported defaults for start, update, and end so existing platform subclasses remain compatible.

# 0.1.3

- Expose granular notification authorization and delivery settings through the optional readiness snapshot.

# 0.1.2

- Add optional system-sound preparation and an AlarmKit sound-file override without changing legacy audio inputs.
- Add actual system audio ownership to alarm snapshots, with a default of false for existing backends.

# 0.1.1

- Add the readiness remediation contract and result model.
  Both methods default to `unsupported`; the endorsed platform packages implement them in a
  release that depends on this version.

# 0.1.0+1

- Initial release.
