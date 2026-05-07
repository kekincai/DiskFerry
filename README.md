# Disk Ferry

![Disk Ferry icon](Assets/DiskFerry-icon.png)

Disk Ferry is a small native macOS app that wraps `rclone` for cautious, low-cache folder transfers from a Mac-attached drive to an SMB-mounted Windows drive or another mounted destination.

It is built for the boring but important job: move large photo, video, and backup folders without turning Finder, Photos, Spotlight, thumbnails, or media indexing into part of the workflow.

## What It Does

- Select a source folder and a destination folder with native macOS folder pickers.
- Run `rclone copy` with conservative defaults.
- Write full logs to the destination under `_transfer_logs`.
- Show live transfer output without keeping large local logs.
- Avoid thumbnails, previews, EXIF parsing, media databases, and file-content caches.
- Resume interrupted transfers by running the same task again.
- Optionally run a `size-only` check after copying.

## Why This Exists

Finder is convenient, but it is not ideal for multi-terabyte transfers across external disks and SMB mounts. Disk Ferry intentionally stays simple:

```text
source drive -> rclone -> SMB / external destination
```

No temporary staging on the Mac. No photo library import. No preview generation.

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

## Default Copy Command

Disk Ferry generates an `rclone copy` command with defaults tuned for external disks and SMB:

```bash
rclone copy "$SOURCE" "$TARGET" \
  --stats 1s \
  --stats-log-level NOTICE \
  --transfers 1 \
  --checkers 2 \
  --retries 10 \
  --low-level-retries 20 \
  --exclude ".DS_Store" \
  --exclude "._*" \
  --exclude ".Spotlight-V100/**" \
  --exclude ".Trashes/**" \
  --exclude ".fseventsd/**" \
  --exclude ".TemporaryItems/**" \
  --log-file "$TARGET/_transfer_logs/YYYYMMDD-HHMMSS.log" \
  --log-level INFO
```

When the destination is a mounted volume root, such as `/Volumes/minipc`, Disk Ferry copies into a child folder named after the source folder. For example:

```text
source:      /Volumes/PhotoDisk/Photos
destination: /Volumes/minipc
actual path: /Volumes/minipc/Photos
```

This avoids scattering thousands of files directly into the drive root.

## Verification

Post-copy verification is optional and off by default. When enabled, Disk Ferry runs:

```bash
rclone check "$SOURCE" "$TARGET" --size-only --one-way
```

This is intentionally not a full hash check. Full hash verification can be slow and may read a large amount of data from both drives.

## Privacy And Cache Policy

Disk Ferry does not:

- Generate thumbnails
- Preview photos or videos
- Read EXIF metadata
- Build a media database
- Hash every file by default
- Cache file contents
- Stage data in a local temporary directory

Local app state is limited to small settings and recent task metadata. Transfer logs are written to the destination by default.

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

- Better progress parsing for more `rclone` output variants
- Optional report generation for failed or missing files
- Saved task templates
- More explicit SMB disconnect warnings
- Optional full verification with clear warnings

## Contributing

Contributions are welcome. Please keep the central design constraint intact: Disk Ferry should remain a low-cache transfer controller, not a photo manager or file browser.

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

MIT. See [LICENSE](LICENSE).
