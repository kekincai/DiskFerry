# Contributing

Thanks for helping improve Disk Ferry.

The project has one strong product boundary: it is a low-cache `rclone` controller. Please avoid features that turn it into a media library, photo browser, Finder replacement, or indexing system.

## Development

Build and launch:

```bash
./script/build_and_run.sh
```

Verify:

```bash
swift build
./script/build_and_run.sh --verify
```

## Design Rules

- Do not generate thumbnails.
- Do not preview image or video contents.
- Do not parse EXIF metadata.
- Do not create file-content caches or large manifests.
- Keep full transfer logs on the destination disk by default.
- Prefer `rclone` for transfer and verification behavior.
- Keep SMB and external-drive operations conservative.

## Pull Requests

Good pull requests include:

- A clear description of the user-facing change.
- Notes about cache or disk I/O impact.
- The commands used for validation.
- Screenshots for visible UI changes when useful.

## Issue Reports

For bugs, include:

- macOS version
- rclone version
- Source and target type, for example external APFS drive to SMB mount
- Whether the target path is under `/Volumes`
- Relevant log excerpts, with private paths redacted
