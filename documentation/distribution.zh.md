# macOS 签名与分发

正式版本通过 Mac App Store 之外的渠道分发，产物是 Developer ID 签名、Apple 公证并包含 `arm64` 与 `x86_64` 的 Universal 2 DMG。

## 本地安装包

```bash
pnpm install
pnpm run build
pnpm run package:dmg
```

输出位于 `release/`。未配置 Developer ID 时会生成 ad-hoc 或 Apple Development 签名的本地验证包，不可作为公开下载版本。

本地快速迭代可以只构建当前架构：

```bash
COMPUTER_USE_ARCHS=arm64 pnpm run build
```

`package:dmg` 会拒绝非 Universal 2 App，避免误发布单架构版本。

## 安装 Developer ID Application 证书

需要使用准备发布 App 的 Apple Developer Program Team 创建 `Developer ID Application` 证书。Account Holder 或 Admin 可以直接创建；其他角色需要 Team 为其开启 **Access to Certificates, Identifiers & Profiles** 权限。

### 方式一：通过 Xcode，推荐

1. 打开 **Xcode > Settings > Accounts**。
2. 添加已加入 Apple Developer Program Team 的 Apple ID。
3. 选中对应 Team，打开 **Manage Certificates**。
4. 点击左下角 `+`，选择 **Developer ID Application**。
5. Xcode 会在“登录”钥匙串中生成私钥并安装对应证书。

这是最省事的方式，因为证书和私钥会在同一台 Mac 上正确配对。

### 方式二：通过 Apple Developer 网站

Xcode 无法创建时，可以手工生成 CSR：

1. 打开“钥匙串访问”。
2. 选择 **钥匙串访问 > 证书助理 > 从证书颁发机构请求证书**。
3. 填写 Apple ID 邮箱和容易识别的常用名称，选择“存储到磁盘”，保存 CSR。
4. 打开 [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/add)。
5. 选择 **Developer ID Application**，上传刚生成的 CSR。
6. 下载 `.cer`，双击导入“登录”钥匙串。
7. 在“钥匙串访问 > 我的证书”中展开该证书，确认下面存在一把私钥。

`.cer` 只包含公开证书，不包含私钥。若证书下面没有私钥，通常表示 CSR 在另一台 Mac 上生成，或本机私钥已经丢失。这种情况下应重新生成 CSR 和证书，单独导入 `.cer` 无法恢复签名能力。

在终端确认身份：

```bash
security find-identity -v -p codesigning
```

输出中必须出现有效的：

```text
Developer ID Application: 名称 (TEAMID)
```

项目构建时把这一整行传给 `COMPUTER_USE_CODESIGN_IDENTITY`。

## 配置本机公证凭据

在 [appleid.apple.com](https://appleid.apple.com/) 创建 App 专用密码，然后存入系统钥匙串：

```bash
xcrun notarytool store-credentials dsh-computer-use-notary \
  --apple-id 'release@example.com' \
  --team-id 'TEAMID' \
  --password 'app-specific-password'
```

构建并生成正式 DMG：

```bash
COMPUTER_USE_CODESIGN_IDENTITY='Developer ID Application: 名称 (TEAMID)' \
  pnpm run build

COMPUTER_USE_CODESIGN_IDENTITY='Developer ID Application: 名称 (TEAMID)' \
NOTARYTOOL_PROFILE='dsh-computer-use-notary' \
  pnpm run release:macos
```

发布脚本会依次：

1. 检查 App 嵌套签名和两种架构；
2. 提交 ZIP 公证并 staple App；
3. 生成带“应用程序”链接的 DMG；
4. 签名、公证并 staple DMG；
5. 运行 Gatekeeper 检查；
6. 生成 SHA-256 校验和。

完整产品使用 SkyLight 私有 API 实现后台定向输入，因此不启用 App Sandbox，也不适合 Mac App Store 审核。

## 导出 P12 给 GitHub Actions

1. 打开“钥匙串访问 > 我的证书”。
2. 找到并展开 Developer ID Application，确认私钥在其下方。
3. 右键证书，选择“导出”，格式选择 `.p12`，设置一个强临时密码。
4. 将 P12 编码为 GitHub Secret：

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

剪贴板内容写入 `MACOS_CERTIFICATE_P12`，P12 密码写入 `MACOS_CERTIFICATE_PASSWORD`。不要把 P12、密码、私钥或编码结果提交到仓库。

CI 公证建议使用 App Store Connect Team API Key：

1. 打开 **App Store Connect > Users and Access > Integrations > App Store Connect API**。
2. 创建 Team API Key，记录 Issuer ID 和 Key ID。
3. 下载 `.p8`。Apple 只允许下载一次，需安全保存。

Release workflow 需要：

| Secret | 用途 |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64 编码的 Developer ID 证书与私钥 |
| `MACOS_CERTIFICATE_PASSWORD` | P12 密码 |
| `MACOS_KEYCHAIN_PASSWORD` | CI 临时钥匙串密码 |
| `MACOS_CODESIGN_IDENTITY` | 完整的 `Developer ID Application: ...` 身份 |
| `APPLE_API_KEY_ID` | App Store Connect API Key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect Issuer ID |
| `APPLE_API_KEY_P8` | P8 私钥文件内容 |

这些值只能放在 GitHub Actions Secrets，不应出现在仓库变量、源码、日志、Issue 或 Release 附件中。

## 用户升级

用新版本替换 `/Applications` 中的 App，会保留 bundle ID 和 designated requirement。同一 Team ID 签发的升级通常能延续现有 TCC 授权。升级后打开设置中心点击“重新安装”以刷新 DSH file dependency，然后重启 DSH Host。

## 发布插件包到 npm

当 App 已安装在 `/Applications` 时（运行时回退到 `/Applications/DSH Computer Use.app`），TS 插件包可以脱离 DMG 单独安装：

```bash
npm login
npm publish
```

`prepare` 会在打包前从 TypeScript 重新构建 `dist/`，因此 tarball 始终包含最新构建产物。`dsh-computer-use` 这个包名已预留，发布后用户可这样安装：

```bash
dsh plugin --profile web add dsh-computer-use
```

原生 helper **不在** npm 包内，运行时从 `/Applications` 中的 App 解析。请以 DMG 作为主要安装路径，npm 作为 bundle 层的便捷路径。
