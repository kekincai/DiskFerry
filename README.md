# Disk Ferry

![Disk Ferry icon](Assets/DiskFerry-icon.png)

Disk Ferry is a small native macOS app that wraps `rclone` for cautious, low-cache folder transfers from a Mac-attached drive to an SMB-mounted Windows drive or another mounted destination.

It is built for the boring but important job: move large photo, video, and backup folders without turning Finder, Photos, Spotlight, thumbnails, or media indexing into part of the workflow.

## What It Does

- **Routes, not forms.** Every source → destination pair you copy is saved in the sidebar with its last result. Pin the ones you use weekly and re-sync with one click.
- **Set locations the way you already have them.** Drag a folder from Finder, paste a folder you copied with ⌘C, or paste an address: `/Volumes/...`, `smb://server/share/folder`, `\\server\share\folder`. Shares that are not mounted yet are connected automatically with the standard macOS login sheet.
- **See where files will land.** Choose "put into a `<source>` folder" (like dragging in Finder) or "merge into the destination"; the exact write path is always shown.
- **Accurate, cheap live progress.** Percent, bytes, files, current and average speed, ETA, skipped files and the files currently in flight come straight from rclone's own stats, refreshed once per second without redrawing the rest of the window.
- **Resume by running again.** Files already on the destination are skipped.
- **Nothing extra on disk.** No log files, no summaries, no thumbnails, previews or caches. If a run fails, rclone's errors are shown in the window.
- Optional `size-only` verification after copying.
- Keeps the Mac awake while copying, shows progress in the Dock, and notifies you when a long copy finishes.

## Requirements

- macOS 13 or later
- Swift 5.9 or later for building from source
- [`rclone`](https://rclone.org/) installed locally

Install `rclone` with Homebrew:

```bash
brew install rclone
```

Disk Ferry searches common Homebrew locations such as `/opt/homebrew/bin/rclone` and `/usr/local/bin/rclone`, and also lets you provide a custom path.

## Build And Run

From the repository root:

```bash
./script/build_and_run.sh
```

The script builds the Swift package, creates `dist/DiskFerry.app`, adds the app icon, and launches it as a normal macOS app bundle.

You can also verify launch:

```bash
./script/build_and_run.sh --verify
```

## Copy Command

The "Advanced" popover shows the exact command for the current route. With default settings it is:

```bash
rclone copy "$SOURCE" "$TARGET" \
  --check-first \
  --local-no-clone \
  --transfers 1 \
  --checkers 2 \
  --retries 10 \
  --low-level-retries 20 \
  --exclude ".DS_Store" --exclude "._*" \
  --exclude ".Spotlight-V100/**" --exclude ".Trashes/**" \
  --exclude ".fseventsd/**" --exclude ".TemporaryItems/**" \
  --stats 0 --log-level NOTICE \
  --rc --rc-addr 127.0.0.1:<random port> --rc-user diskferry --rc-pass <random>
```

- `--check-first` compares everything before the first byte moves, so totals and ETA are exact from the start. It can be turned off ("先统计再复制").
- `--local-no-clone` (added when the installed rclone supports it) makes rclone stream the data itself instead of handing each file to the OS, so progress is counted per byte rather than per finished file.
- The rc server listens on loopback only with a random password; Disk Ferry polls `core/stats` once per second for live progress.

`$TARGET` is either the selected destination or `<destination>/<source folder name>`, depending on the chosen layout. Routes saved by earlier versions keep their previous behavior.

## Verification

Post-copy verification is optional and off by default. When enabled, Disk Ferry runs:

```bash
rclone check "$SOURCE" "$TARGET" --size-only --one-way  # plus the same excludes
```

This is intentionally not a full hash check. Full hash verification can be slow and may read a large amount of data from both drives.

## Scripting

```bash
open -a DiskFerry --args -source /Volumes/PhotoDisk/Photos -target /Volumes/nas -autostart YES
```

## Privacy And Cache Policy

Disk Ferry does not:

- Generate thumbnails
- Preview photos or videos
- Read EXIF metadata
- Build a media database
- Hash every file by default
- Cache file contents
- Stage data in a local temporary directory
- Write log or summary files

Local app state is limited to small settings and saved routes (`~/Library/Application Support/DiskFerry/recent_tasks.json`). rclone output is held in memory and shown only when a run fails.

## Project Layout

```text
Sources/DiskFerry/App       App entry point
Sources/DiskFerry/Models    Transfer, progress, and status models
Sources/DiskFerry/Services  rclone, precheck, parsing, and scanner services
Sources/DiskFerry/Stores    App state and recent task persistence
Sources/DiskFerry/Support   Small platform and formatting helpers
Sources/DiskFerry/Views     SwiftUI views
script/                     Build/run and icon generation scripts
Assets/                     Project icon assets
```

## Roadmap

- Queue several routes to run one after another
- More explicit SMB disconnect warnings
- Optional full verification with clear warnings

## Contributing

Contributions are welcome. Please keep the central design constraint intact: Disk Ferry should remain a low-cache transfer controller, not a photo manager or file browser.

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

MIT. See [LICENSE](LICENSE).
