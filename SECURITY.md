# Security Policy

Disk Ferry is a local macOS utility that launches the installed `rclone` binary. Besides the copied files, a real copy writes only two things to the destination: the destination folder itself (with the "into a folder of the same name" layout), and one empty `.disk-ferry-write-test-*` file that is written and immediately deleted to confirm the share is writable. A dry run writes nothing.

## Supported Versions

The current `main` branch is the supported development line.

## Reporting A Vulnerability

Please open a private security advisory on GitHub if available, or contact the maintainer through GitHub.

Do not include private file paths, SMB credentials, or full rclone output in public issues.

## Notes

- Disk Ferry never sees SMB credentials. When you enter an `smb://` or `\\server\share` address for a share that is not mounted, it asks macOS (NetFS) to mount it, and macOS shows its own login sheet and Keychain handling.
- Each rclone process runs its remote-control server on `127.0.0.1` only, on a random free port, with basic auth and a random per-run password. The password is passed in the `RCLONE_RC_PASS` environment variable rather than on the command line, so other local users cannot see it in `ps`. Disk Ferry only calls `core/stats`.
- Before copying, the destination path is checked for symbolic links and for escaping the selected folder, and it is re-validated right before rclone starts.
- A destination inside the source is rejected, including when it is reached through a symbolic link or a differently cased path on a case-insensitive volume.
