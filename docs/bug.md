# KeePassY Bug Log

This file tracks user-reported bugs that need follow-up investigation.

## Open

### BUG-001: Packaged Linux app copy buttons do nothing

Status: open.

Reported: 2026-05-01.

Environment:

- Linux desktop packaged build from `dist/linux/KeePassY/keepassy_flutter`.
- Exact display server and desktop environment not yet confirmed.

Observed behavior:

- Clicking copy buttons in the packaged app has no visible effect.
- The user reports no success feedback and no failure feedback.
- The issue still happens after changing the copy path to await
  `Clipboard.setData`, add a 2-second timeout, and show a failure `SnackBar`.

Expected behavior:

- Clicking a copy button writes the selected value to the system clipboard.
- The app shows a success message such as `Password copied to clipboard`.
- If the system clipboard is unavailable, the app shows an actionable failure
  message.

Known affected actions:

- Entry detail copy buttons, including password/custom-field copy actions.

What has already been tried:

- Unified password shortcut and button copy paths through `_onCopyToClipboard`.
- Awaited `Clipboard.setData`.
- Added timeout/error feedback around clipboard writes.
- Rebuilt the Linux release bundle with `scripts/build_linux_release.sh`.
- `flutter analyze` and `flutter test` pass after the change.

Notes:

- Because neither success nor failure feedback appears in the packaged app, the
  next investigation should first verify whether the button callback is being
  invoked at all in release mode.
- If callbacks are invoked, inspect Flutter Linux clipboard behavior under the
  user's display server (`X11` vs `Wayland`) and test a lower-level GTK clipboard
  path or a dedicated clipboard plugin.

Next debugging steps:

- Add temporary release-visible diagnostics around copy button callbacks.
- Run the packaged app from a terminal and capture stdout/stderr while clicking
  copy.
- Confirm `echo $XDG_SESSION_TYPE`, desktop environment, and whether the app is
  launched from terminal or file manager.
- Test copying from both the header password action and field-row copy actions.
- If Flutter's built-in clipboard channel is unreliable, evaluate replacing it
  with a Linux desktop clipboard plugin or a small platform channel implemented
  in the GTK runner.
