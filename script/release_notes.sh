#!/usr/bin/env bash
# Prints release notes: the CHANGELOG section for <version> (or "Unreleased"),
# followed by install instructions.
# usage: release_notes.sh <version>
set -euo pipefail

VERSION="${1:?usage: release_notes.sh <version>}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

section() {
  awk -v heading="## $1" '
    # "## 0.2.0" or "## 0.2.0 - 2026-09-25"
    !found && ($0 == heading || index($0, heading " ") == 1) { found = 1; next }
    found && /^## / { exit }
    found { print }
  ' "$ROOT_DIR/CHANGELOG.md"
}

NOTES="$(section "$VERSION")"
if [[ -z "${NOTES//[[:space:]]/}" ]]; then
  NOTES="$(section "Unreleased")"
fi

cat <<MD
${NOTES}

## 安装 / Install

1. 先安装 rclone / Install rclone first: \`brew install rclone\`
2. 下载 \`DiskFerry-${VERSION}.dmg\`，把 **Disk Ferry** 拖进“应用程序”。/ Download the .dmg and drag **Disk Ferry** to Applications.
3. 首次打开：在“应用程序”里**右键 → 打开**，再点“打开”。这个版本没有经过 Apple 公证，所以第一次需要这样确认一次。
   First launch: **right-click → Open** in Applications, then confirm. This build is not notarized by Apple, so macOS asks once.
   如果提示“已损坏” / If macOS says the app is damaged: \`xattr -dr com.apple.quarantine "/Applications/Disk Ferry.app"\`

通用版本，支持 Apple 芯片和 Intel，需要 macOS 13 或更高。/ Universal build for Apple silicon and Intel, macOS 13+.
校验和见 / Checksums: \`SHA256SUMS.txt\`
MD
