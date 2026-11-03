# ClipKeep open-source preparation plan

**Goal:** Publish an honest, reproducibly buildable source baseline to flyingcow-niu/clipkeep, and identify the work needed for Windows.

**Architecture:** Keep the existing native macOS application and storage identity intact. The owner confirmed no Windows source exists and requested a new implementation; build the WPF preview described in docs/WINDOWS_DESIGN.md.

**Tech stack:** Swift 5.10+, SwiftUI, AppKit, SQLite, CryptoKit, macOS 14+. Windows: C# / .NET 10, WPF, DPAPI.

## Constraints
- Never include clipboard databases, credentials, signing keys, build caches, or installed application data.
- Do not reinstall the user's running application during publication preparation.
- Distinguish compilation, automated checks, and actual desktop acceptance testing.
- Preserve storage/keychain identifiers to avoid losing access to existing encrypted history.

## Tasks
- [x] Inspect and test macOS source; verify the documented build path rather than a one-off compiler invocation.
- [ ] Build Windows preview from scratch, test core rules and DPAPI/WPF construction, and document verified build commands.
- [x] Add project documentation, MIT license, contributing/security guidance, ignores, and native macOS/Windows CI.
- [x] Inspect the exact publication file list and scan source for private data and secrets.
- [ ] Commit and push to the authorized empty GitHub repository without overwriting remote history.
- [ ] Inspect CI results and report remaining platform/signing/runtime limitations.

## Review focus
- Ad-hoc updates can invalidate macOS accessibility authorization.
- Clipboard capture can contain secrets not marked as sensitive by the source application.
- Input-method composition is not covered by string normalization tests.
- File clipboard entries store references, not backups of file contents.
- Windows cannot be built by substituting an OS flag into this AppKit-based package.
