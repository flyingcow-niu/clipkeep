# Security and privacy

ClipKeep runs locally and observes clipboard changes while enabled. Clipboard content, previews and thumbnails are encrypted using AES-GCM; the key is stored in the macOS login Keychain. This is not full-database encryption: metadata such as source application, timestamps, type, size, favorites and abbreviations is stored in plaintext.

Known sensitive pasteboard markers and excluded applications are skipped. These are best-effort safeguards, not a guarantee that all passwords or secrets will be detected. Pause recording before copying sensitive information from an application that does not supply a sensitive marker.

Text expansion requires keyboard-event/accessibility access. Secure-input mode is skipped. Input methods and synthetic key delivery still need application-specific testing.

Do not publish real clipboard data in issues. For a vulnerability, use GitHub's **Report a vulnerability** feature if enabled by the maintainer. If it is unavailable, open an issue requesting a private contact without including exploit details, secrets or affected clipboard contents. Private vulnerability reporting is not assumed to be enabled.

On Windows, the entire history/settings snapshot is protected with DPAPI for the current user. A changed account/machine or lost profile keys may make it unreadable; there is no portable recovery scheme. Password-manager process exclusions and clipboard opt-out formats are best effort. No automatic text-expansion keyboard hook is installed by the Windows preview.

There is currently no security audit, formal support lifetime, signed update channel or guaranteed response time. This is an early source release.
