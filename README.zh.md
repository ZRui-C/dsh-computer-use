<p align="center">
  <img src="docs/assets/app-icon.png" width="112" height="112" alt="DSH Computer Use 图标">
</p>

<h1 align="center">DSH Computer Use</h1>

<p align="center">
  面向 DSH 的文本优先浏览器与 macOS 后台控制。<br>
  锁定正确的进程和窗口，不抢前台，也不移动用户的鼠标。
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="documentation/architecture.md">架构</a> ·
  <a href="documentation/distribution.zh.md">分发</a> ·
  <a href="SECURITY.md">安全</a>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-202329?style=flat-square&logo=apple&logoColor=white">
  <img alt="Universal 2" src="https://img.shields.io/badge/Universal%202-arm64%20%7C%20x86__64-4DBD88?style=flat-square">
  <img alt="Apache 2.0" src="https://img.shields.io/badge/license-Apache--2.0-F06A5B?style=flat-square">
  <img alt="GitHub stars" src="https://img.shields.io/github/stars/ZRui-C/dsh-computer-use?style=flat-square&logo=github&logoColor=white">
  <img alt="GitHub release" src="https://img.shields.io/github/v/release/ZRui-C/dsh-computer-use?style=flat-square&logo=github&logoColor=white">
</p>

## 安装

### Homebrew

```bash
brew tap zrui-c/tap
brew trust zrui-c/tap
brew install --cask dsh-computer-use
open -a "DSH Computer Use"
```

### DMG

1. 从 [Releases](https://github.com/ZRui-C/dsh-computer-use/releases/latest) 下载最新版 `DSH-Computer-Use-*-universal.dmg`。
2. 将 **DSH Computer Use** 拖入“应用程序”并打开。

两种方式都需要按设置中心引导授权“辅助功能”和“屏幕录制”，在“DSH 插件”一行点击“安装”，然后重启正在运行的 DSH Host。

Homebrew Cask 与官方 DMG 安装的是同一份 Universal 2 App，均经过 Developer ID 签名和 Apple 公证。普通用户不需要安装 Xcode、Swift，也不需要下载源码；系统中需要已有 DSH 和 Google Chrome。

<p align="center">
  <img src="docs/assets/setup-center.png" width="760" alt="DSH Computer Use 设置中心">
</p>

## 能做什么

| 控制面 | 感知 | 输入 |
| --- | --- | --- |
| Chromium | Playwright、CDP Accessibility/DOM、frame、标签页、可选 OCR | 基于 ref 的导航、鼠标、键盘、表单、滚动、拖拽、上传 |
| macOS | Accessibility 树优先，Vision OCR 补语义，独立窗口捕获 | AX 语义动作、定向 SkyLight/CoreGraphics，无目标时才用全局 HID |

每次动作都会返回新的、有预算上限的文本观察。模型读取 role、name、value、状态、几何和稳定 snapshot ref，不会假装自己能看懂截图。页面文字与 OCR 内容统一视为不可信 UI 数据。

### macOS 后台控制

- 每个动作贯通 PID、WindowServer window ID、AX 窗口 frame 和元素身份。
- 坐标输入前优先尝试 AX 语义动作。
- 支持时把鼠标和键盘事件直接投递到目标进程/窗口。
- 使用可穿透的软件光标；定向动作不移动物理鼠标。
- 即使其他 App 保持前台，动作后观察仍锁定上一个目标窗口。
- 私有能力不可用时回退公开 CoreGraphics，或明确失败关闭。

## 平台边界

ScreenCaptureKit 是公开 API。可选的后台输入路径会动态加载 SkyLight 私有符号，适合 Developer ID 分发，不适合 Mac App Store。私有 API 不受 Apple 支持，macOS 升级后可能变化。

在 macOS 26 上，Stage Manager 可能只向 WindowServer 暴露架上窗口的缩略图；为这种表示创建捕获 filter 甚至可能在 SkyLight 内直接 abort。DSH Computer Use 会先比较 AX 与 WindowServer 几何，避开崩溃路径，保留 AX 观察并返回明确 warning，绝不会把缩略图拉伸成伪造的全窗口截图。

## DSH 集成

App 内嵌包已在 `package.json` 声明 DSH bundle。设置中心执行的官方命令等价于：

```bash
dsh plugin --profile web add --save-exact file:/path/to/DSH\ Computer\ Use.app/Contents/Resources/Plugin
```

`cordis.patch.yml` 会安装 Host runtime，并将 `computer_observe` / `computer_action` 注册到 DSH 的 global tool layer，由所有 agent preset 继承。不要求用户手改 profile YAML 或复制 preset。设置中心会识别旧版“只有 dependency、没有启用 bundle”的状态并提供修复。安装、修复或升级后需要重启正在运行的 DSH Host。

## 从源码构建

要求：macOS 14+、Xcode/Swift 5.9+、Node.js 22+、pnpm 11+、DSH 和 Google Chrome。

```bash
pnpm install
pnpm run typecheck
pnpm run test
pnpm run test:native
pnpm run build
```

`pnpm run build` 生成：

```text
native/macos-helper/dist/DSH Computer Use.app
```

默认构建 Universal 2。本地快速迭代可只编译当前架构：

```bash
COMPUTER_USE_ARCHS=arm64 pnpm run build
```

生成本地拖拽安装 DMG：

```bash
pnpm run package:dmg
```

公开发布需要 `Developer ID Application` 证书和 Apple 公证。完整的本地与 GitHub Actions 流程见 [documentation/distribution.zh.md](documentation/distribution.zh.md)。

## 工具协议

`computer_observe` 返回 `browser` 或 `desktop` 的 `interactive`、`full`、`changes` 文本快照，支持 query 过滤和 `auto | always | never` OCR。

`computer_action` 每次只执行一个浏览器或桌面动作，并返回动作后的语义状态。ref/坐标动作必须携带最新 `snapshot_id`；过期目标会失败关闭并要求重新观察。上传文件严格限制在当前 DSH Session workspace 内。

## 项目资料

- [架构与信任边界](documentation/architecture.md)
- [签名、公证与 DMG](documentation/distribution.zh.md)
- [安全策略](SECURITY.md)
- [贡献指南](CONTRIBUTING.md)
- [更新记录](CHANGELOG.md)
- [第三方归属](THIRD_PARTY_NOTICES.md)

## 社区

- [GitHub Discussions](https://github.com/ZRui-C/dsh-computer-use/discussions) — 提问、分享用法、反馈想法
- [DeepSeek Harness Discord](https://discord.gg/Ycq5dCaS4) — 更大的 DSH 生态
- 觉得好用就点个 Star ⭐，让更多人发现它

项目采用 [Apache-2.0](LICENSE) 许可证。本项目不受 Apple 背书；“DeepSeek”等名称归各自权利人所有，本文仅用于说明与 DeepSeek Harness/DSH 的兼容关系。
