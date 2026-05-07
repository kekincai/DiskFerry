# Security Policy

Disk Ferry is a local macOS utility that launches the installed `rclone` binary and writes logs to the selected destination.

## Supported Versions

The current `main` branch is the supported development line.

## Reporting A Vulnerability

Please open a private security advisory on GitHub if available, or contact the maintainer through GitHub.

Do not include private file paths, SMB credentials, or full transfer logs in public issues.

## Notes

Disk Ferry does not ask for SMB credentials directly. Mount SMB shares through macOS first, then select the mounted destination folder.
