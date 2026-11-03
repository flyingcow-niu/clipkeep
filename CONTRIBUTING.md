# Contributing

ClipKeep is an early native clipboard utility. Small, focused fixes with a reproduction are welcome.

## macOS development

Requirements: macOS 14+, Xcode Command Line Tools providing Swift 5.10+.

```sh
cd macos
./test.sh
./build.sh
```

Tests use synthetic data and do not read your clipboard database or Keychain. The build produces `dist/ClipKeep.app` without installing it. Only `./build.sh --install` changes your installed app.

Before a pull request, describe the observed behavior, expected behavior, operating system and input source. Add regression checks for changed matching, storage or interaction rules. For GUI changes, also report manual testing; compiling is not GUI verification.

Never attach real clipboard history, passwords, tokens, database files, signing credentials or private application content. Use invented examples and redact screenshots.

## Compatibility

The `com.luojilab.clipkeep` identifiers are retained for existing Keychain and settings compatibility. Changing them requires a migration plan. Do not change the bundle ID solely to rebrand a fork while expecting existing encrypted history to remain accessible.

## Windows development

On Windows 11 with .NET 10 SDK and PowerShell 7:

```powershell
cd windows
pwsh ./test.ps1
pwsh ./build.ps1 -Runtime win-x64
```

Portable core checks also run on macOS/Linux: `dotnet run --project windows/ClipKeep.Core.Tests -c Release`.
The Windows self-test uses a temporary store with synthetic data, verifies DPAPI and atomic replacement, and constructs WPF windows without starting capture or reading user history. Do not equate it with cross-application keyboard/paste testing.

See [platform status](docs/PLATFORM_STATUS.md) and [Windows documentation](windows/README.md) for remaining work.
