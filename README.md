<div align="center">

<img src="Assets/DiskFerry-icon.png" width="128" alt="Disk Ferry 图标">

# Disk Ferry

**把大文件夹稳稳地搬过去 —— 外置硬盘、NAS、Windows 共享之间的原生 macOS 复制工具**

[![CI](https://github.com/kekincai/DiskFerry/actions/workflows/ci.yml/badge.svg)](https://github.com/kekincai/DiskFerry/actions/workflows/ci.yml)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
![rclone](https://img.shields.io/badge/powered%20by-rclone-3F79AD)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

简体中文 · [English](README.en.md)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/copying-dark.png">
  <img src="docs/screenshots/copying-light.png" alt="Disk Ferry 正在复制照片到 NAS" width="820">
</picture>

</div>

## 为什么需要它

用 Finder 往 SMB 共享拷几百 GB 的照片和视频，经常会遇到：进度条不准、中途断了不知道从哪继续、缩略图和 Spotlight 在后台拼命读盘。

Disk Ferry 把这件事交给 [rclone](https://rclone.org/)，自己只做一件事：**让你每天都能轻松、放心地把文件夹从 A 复制到 B**。

```text
外置硬盘 / 本机文件夹  ──rclone──▶  SMB 共享 / NAS / 另一块硬盘
```

## 功能亮点

- **路线，而不是表单** —— 每次复制都会保存成左侧的一条“路线”，带上次结果。常用的收藏起来，下次点一下“再次同步”。
- **怎么方便怎么设** —— 从 Finder 拖文件夹进来；在 Finder 里 ⌘C 后点“粘贴”；或者直接输入 `smb://电脑名/共享/文件夹`、`\\电脑名\共享\文件夹`。共享还没连接时会自动弹出 macOS 登录框帮你连上。
- **写到哪里一目了然** —— “放进同名文件夹”（和 Finder 拖拽一样）或“直接合并到目标”，下面始终显示真实写入路径。
- **准确又不卡的实时进度** —— 百分比、数据量、文件数、当前 / 平均速度、剩余时间、已跳过文件、正在传输的文件，全部来自 rclone 自身的统计，每秒刷新一次，只重绘进度区域。
- **断了就再点一次** —— 目标已有的文件自动跳过，从断点继续。
- **不留垃圾** —— 除了复制的文件，不写日志、不写摘要、不生成缩略图和缓存。失败时才在窗口里显示 rclone 的错误信息。
- **贴心的小事** —— 复制时防止 Mac 睡眠、Dock 图标显示进度、后台完成时发通知、复制中退出会先确认。
- 可选：复制后按文件大小校验（`rclone check --size-only`）。

## 安装

需要 macOS 13 或更高版本（Apple 芯片和 Intel 都支持），以及 rclone：

```bash
brew install rclone
```

### 下载（推荐）

1. 到 [Releases](https://github.com/kekincai/DiskFerry/releases/latest) 下载最新的 `DiskFerry-x.y.z.dmg`。
2. 打开后把 **Disk Ferry** 拖进“应用程序”。
3. 第一次打开时，在“应用程序”里 **右键 → 打开**，再点“打开”。目前的版本没有经过 Apple 公证，macOS 只会在第一次这样确认。
   如果提示“已损坏，无法打开”，在终端执行：`xattr -dr com.apple.quarantine "/Applications/Disk Ferry.app"`

### 从源码构建

需要 Xcode 命令行工具（Swift 5.9+）：

```bash
git clone https://github.com/kekincai/DiskFerry.git
cd DiskFerry
./script/build_and_run.sh              # 调试构建并启动
./script/package_release.sh 0.0.0      # 打包通用版 .dmg / .zip 到 dist/release/
```

## 使用

1. **设置“从”**：把要复制的文件夹拖到左边卡片上，或点“选择…”/“粘贴”/“输入地址…”。
2. **设置“复制到”**：右边卡片同理。点 **⋯** 可以一键选择已连接的硬盘和共享、最近用过的位置，或“连接服务器…”。
3. **确认写入位置**：卡片下方的“写入到”就是文件最终所在的文件夹。
4. **开始复制**（⌘R）。不确定时先点 **预演**（⇧⌘R），只统计要复制多少，不写入任何文件。
5. 复制完成后，这条路线会出现在左侧。点 ☆ 收藏，下次直接选中它再点“再次同步”。

| 选项 | 说明 |
| --- | --- |
| 速度 | 稳妥（1 个并行）/ 标准（2）/ 快速（4）/ 自定义。机械硬盘和弱 Wi‑Fi 用稳妥，千兆有线 + SSD 用快速。 |
| 先统计再复制 | 默认开启。先比对完所有文件再开始传输，总量和剩余时间从一开始就准确。 |
| 复制后校验 | 按文件大小再核对一遍，不读取文件内容。 |

## 实时进度是怎么做到的

rclone 启动时会在 `127.0.0.1` 上开一个只供本机访问、带随机密码的统计接口，Disk Ferry 每秒读取一次 `core/stats`，拿到的是 rclone 自己记录的精确数字，而不是扫描目录猜出来的。

默认命令（“高级”面板里可以看到并拷贝当前路线的完整命令）：

```bash
rclone copy "$SOURCE" "$TARGET" \
  --check-first --local-no-clone \
  --transfers 1 --checkers 2 --retries 10 --low-level-retries 20 \
  --exclude ".DS_Store" --exclude "._*" --exclude ".Spotlight-V100/**" \
  --exclude ".Trashes/**" --exclude ".fseventsd/**" --exclude ".TemporaryItems/**" \
  --stats 0 --log-level NOTICE \
  --rc --rc-addr 127.0.0.1:<随机端口> --rc-user diskferry --rc-pass <随机密码>
```

- `--check-first`：先比对再传输，进度和剩余时间从头就准。
- `--local-no-clone`：让 rclone 自己逐字节传输，而不是把整个文件交给系统复制，这样大视频也能看到平滑的进度。（仅在已安装的 rclone 支持时添加。）

## 隐私与缓存

Disk Ferry 不会：生成缩略图、预览照片或视频、读取 EXIF、建立媒体库、默认对每个文件做哈希、缓存文件内容、在本机中转数据、写日志文件。

本机只保存少量设置和路线列表（`~/Library/Application Support/DiskFerry/recent_tasks.json`）。rclone 的输出只保存在内存里，仅在失败时显示。

## 脚本调用

```bash
open -a DiskFerry --args -source /Volumes/PhotoDisk/Photos -target /Volumes/NAS -autostart YES
```

## 开发

```bash
swift build
swift test          # 装了 rclone 时还会跑一个端到端的真实复制测试
./script/build_and_run.sh --verify
```

```text
Sources/DiskFerry/App       入口、菜单、退出确认
Sources/DiskFerry/Models    路线、进度、状态模型
Sources/DiskFerry/Services  rclone 运行 / 统计、路径解析与挂载、预检查、安全策略
Sources/DiskFerry/Stores    应用状态、实时进度、路线存储
Sources/DiskFerry/Support   格式化与系统小工具
Sources/DiskFerry/Views     SwiftUI 界面
script/                     构建、启动与图标生成脚本
```

欢迎贡献，请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。核心原则：Disk Ferry 是一个低缓存的复制控制器，不是相册、文件浏览器或索引工具。

## 许可证

MIT，见 [LICENSE](LICENSE)。
