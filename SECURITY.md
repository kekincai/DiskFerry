# Security Policy

Disk Ferry is a local macOS utility that launches the installed `rclone` binary. It writes nothing to the destination besides the copied files.

## Supported Versions

The current `main` branch is the supported development line.

## Reporting A Vulnerability

Please open a private security advisory on GitHub if available, or contact the maintainer through GitHub.

Do not include private file paths, SMB credentials, or full rclone output in public issues.

## Notes

- Disk Ferry never sees SMB credentials. When you enter an `smb://` or `\\server\share` address for a share that is not mounted, it asks macOS (NetFS) to mount it, and macOS shows its own login sheet and Keychain handling.
- Each rclone process runs its remote-control server on `127.0.0.1` only, on a random free port, with basic auth and a random per-run password. Disk Ferry only calls `core/stats`.
- Before copying, the destination path is checked for symbolic links and for escaping the selected folder, and it is re-validated right before rclone starts.
