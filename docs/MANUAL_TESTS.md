# Desktop acceptance checklist

Automated checks do not replace these steps. Use invented data, not passwords or actual clipboard history. Record OS, CPU, app version and input source alongside results.

## Both platforms

- Copy two distinct texts, repeat the first, confirm deduplication and newest-first order.
- Search by content and source; switch favorites and an empty search result.
- Navigate cards, copy selected item, verify panel closes only on successful copy; paste manually into a different editor.
- Select search-field text and copy; confirm text selection takes precedence over card copying.
- Hold/release the number modifier; numbering remains stable, and visible-number selection matches the shown card.
- Copy HTML/RTF, an image and multiple files. Paste into apps that accept each format. Move/delete a referenced file and check failure handling.
- Confirm a favorite survives age/count cleanup. Clear history and verify favorites remain.
- Pause capture, copy test data, resume. Test excluded apps and clipboard privacy markers.
- Test sleep/wake, a second launch, full screen and multiple monitors.

## macOS

- Fresh accessibility authorization and authorization after an ad-hoc rebuild; deny Keychain access and confirm the app fails closed.
- `;;t`, `；；t`, mixed punctuation; prefix-conflicting abbreviations; English and Chinese input sources.
- IME composition, secure-input fields and very fast typing. Watch for incorrect deletion.
- Long snippet expansion followed immediately by a new clipboard copy (known restore race still open).

## Windows

- First launch tray icon, Ctrl+Shift+V; occupy the hotkey in another application and verify tray access still works.
- Ctrl+C, Enter, Shift+Enter, Ctrl+D, Ctrl+Delete, Ctrl+visible-number in Notepad, a browser and an editor.
- Ordinary vs elevated target applications: failed input injection leaves content available for manual paste.
- Hold the paste shortcut longer than one second; ensure no keystrokes are sent to an unintended window.
- Simulate a locked clipboard and a read-only storage directory. Confirm retry or explicit error and no false success.
- Restart and verify encrypted history. Copy history.dat to another Windows account: decryption must fail without overwriting the file.
- Record responsiveness near 500 records and the 64 MiB cap. Favorites occupying the entire budget must cause an explicit rejection of new captures.

Windows automatic text expansion is not implemented in this preview and is not part of a passing checklist.
