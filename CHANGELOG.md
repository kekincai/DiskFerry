# Changelog

## Unreleased

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
