# Changelog

## Unreleased

### Removed
- The folder comparison tab. It scanned only the first level of each folder and compared allocated size, so its percentages were unreliable; all numbers now come from rclone.
- The precheck warning shown for every destination under `/Volumes/`.

### Fixed
- Dry runs no longer create the destination folder or a write-test file.
- With "verify after copying", the copy's numbers stay visible after verification instead of dropping to 0.
- A verification that could not run (share gone, folder missing) is no longer reported as "differences found".
- Editing a pinned route's paths no longer leaves the star and the old name attached to the new route.
- The app reopens the route that ran last, pinned or not.
- Filesystem checks before a copy, before verification, when opening a folder picker and when revealing the destination no longer run on the main thread.
- A destination inside the source is also rejected when reached through a symlink or a differently cased path.

### Changed
- The rc password is passed to rclone through `RCLONE_RC_PASS` instead of the command line.
- The precheck runs once per start instead of preparing the destination twice.
- The rclone path in Settings is saved and checked when you press Return, not on every keystroke.
- The command preview only includes `--local-no-clone` when the installed rclone supports it.
- `script/build_and_run.sh` refuses to quit the app while it is copying, and its `--telemetry` mode is gone.
- The app bundle uses the committed `Assets/DiskFerry.icns` instead of regenerating it on every build.

## 0.2.0 - 2026-09-25

### Changed
- Rebuilt the interface for daily use: saved routes in the sidebar (pin, rename, last result), source/destination cards with drag-and-drop, paste, typed paths and one-click mounted volumes, an explicit destination layout with a preview of the real write path, and a single run panel.
- Live progress now comes from rclone's rc `core/stats` (polled once per second) instead of parsing console output, which never arrived because rclone wrote it to the log file. Totals are exact up front with `--check-first`, and `--local-no-clone` keeps progress per byte.
- Progress updates only redraw the progress views.
- No log files or `summary.json` are written anymore; rclone errors are shown in the window when a run fails.
- New minimal app icon.
- Follows the system light/dark appearance.

### Added
- `smb://` and `\\server\share` addresses, with automatic mounting through the macOS login sheet.
- Current speed, per-file progress, skipped-file count, Dock badge, sleep prevention while copying, and a notification when a copy finishes in the background.
- "Fast" (4 parallel transfers) speed preset; custom allows up to 8.
- Confirmation before quitting during a copy; closing the window keeps copying.
- `-source`, `-target`, `-autostart` launch arguments.

### Fixed
- A destination inside the source is rejected before any folder is created.
- Verification applies the same excludes as the copy, so skipped `.DS_Store` files no longer fail it.

## 0.1.0

- Initial SwiftUI macOS app.
- rclone copy controller with conservative SMB-friendly defaults.
- Native source and destination folder selection.
- Optional post-copy `size-only` verification.
- Folder heatmap.
