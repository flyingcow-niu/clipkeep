# Windows initial implementation

The owner requested a new Windows implementation on 2026-11-03; no previous Windows source exists.

- Native WPF on .NET 10, Windows 11 x64 first. Preserve the existing macOS implementation separately in the same repository.
- System-tray lifetime, Ctrl+Shift+V panel, horizontal cards, search, favorites, Ctrl+C copy-and-close, Enter paste, Shift+Enter plain text, persistent visible quick-pick numbers.
- Capture Unicode text, HTML/RTF alongside text, bitmap images and file references. Skip clipboard history exclusion markers and excluded foreground processes. Reject payloads larger than 8 MiB.
- Protect the complete stored snapshot with Windows DPAPI CurrentUser; write atomically and fail closed on corruption/decryption errors. Initial storage cap: 64 MiB payload, 500 non-favorites by default, 30 days. Favorites survive automatic purging.
- Keep business rules in a platform-independent library with executable regression checks, and desktop integration in the Windows app. Build both Windows target and portable core tests in CI.
- Do not claim feature parity: automatic text expansion, editable snippets, autostart, custom/global number shortcuts, installer signing and IME acceptance are follow-up work. They require real Windows desktop validation, beyond compilation.
