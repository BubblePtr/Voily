# Sparkle 发布机交接

这份文档给发布机上的 Agent 使用。目标不是重新接入 Sparkle，而是在发布机上完成 Sparkle 私钥、公钥注入、appcast 生成和 GitHub Release 资产上传，让 Voily 的“检查更新...”菜单能从真实 appcast 检测更新。

通用发布流程仍以 [releasing.md](releasing.md) 为准；本文只覆盖发布机上剩余的 Sparkle 收尾工作。

## 当前仓库状态

- Voily 已接入 Sparkle 2.9.2，依赖通过 `Vendor/Sparkle/` 的本地 binary Swift package 提供。
- 应用内已经有手动“检查更新...”菜单项，自动检查暂时关闭。
- Sparkle feed URL 已固定为：

```text
https://github.com/BubblePtr/Voily/releases/latest/download/appcast.xml
```

- `VOILY_SPARKLE_PUBLIC_ED_KEY` 目前仍为空。只要构建产物里的 `SUPublicEDKey` 为空或仍是未解析的 `$(...)`，应用会显示“应用内更新尚未配置”，不会启动 Sparkle。
- appcast 生成和上传还没有接进 GitHub Actions release workflow，需要先在发布机手工跑通。

## 不要做的事

- 不要把 Sparkle 私钥、私钥导出文件、Keychain 导出、Apple notary 凭据、API token 提交到仓库。
- 不要把 Sparkle EdDSA key 和 Apple Developer ID / notarytool 凭据混在一起管理。Sparkle 私钥只用于签 appcast，Apple 凭据只用于签名和公证。
- 不要改 appcast URL，除非同时更新 `project.yml`、`Resources/VoilyApp/Info.plist` 和相关文档。
- 不要把 Sparkle dependency 改回远程包，除非先确认发布机和 CI 不会卡在 SwiftPM binary artifact 下载。

## 发布机前置检查

发布机需要满足：

- 当前 checkout 包含 Sparkle 接入改动。
- `Developer ID Application` 证书和 `VOILY_NOTARY_PROFILE` 已能完成现有发布流程。
- GitHub CLI 已登录，并且有上传 release asset 的权限。
- 发布操作使用的 macOS 用户与后续运行 `generate_appcast` 的用户一致。

先确认 vendored Sparkle 包没有变：

```bash
shasum -a 256 Vendor/Sparkle/Sparkle-for-Swift-Package-Manager.zip
```

期望值：

```text
b83e37436774556ed055e0244b297ef2c790e0737393bf65bf495fcbba6eed65
```

建议先跑一次基础验证：

```bash
make generate
swift test
make build
```

## 1. 生成 Sparkle EdDSA key

在发布机上解压 Sparkle 工具：

```bash
rm -rf /tmp/voily-sparkle
unzip -q Vendor/Sparkle/Sparkle-for-Swift-Package-Manager.zip -d /tmp/voily-sparkle
```

用发布用户生成 key：

```bash
/tmp/voily-sparkle/bin/generate_keys
```

这个命令会把私钥写入当前 macOS 用户的 Keychain，并打印公钥。保存打印出的公钥；私钥留在 Keychain，不要导出到仓库路径。

如果必须从另一台机器迁移 Sparkle 私钥，只能使用 Sparkle 官方工具导入导出，并在导入后删除临时文件：

在源机器运行：

```bash
/tmp/voily-sparkle/bin/generate_keys -x /tmp/voily-sparkle-private-key.txt
```

把临时文件安全传到发布机后，在发布机运行：

```bash
/tmp/voily-sparkle/bin/generate_keys -f /tmp/voily-sparkle-private-key.txt
rm -f /tmp/voily-sparkle-private-key.txt
```

## 2. 注入公钥

推荐把公钥提交到 `project.yml` 的 build setting 里：

```yaml
VOILY_SPARKLE_PUBLIC_ED_KEY: "<generate_keys 打印出的公钥>"
```

Sparkle 公钥不是 secret，提交它比依赖发布机环境变量更稳。修改后重新生成工程：

```bash
make generate
```

然后确认构建产物里真的带了公钥：

```bash
make build
/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' .xcodebuild/Build/Products/Debug/Voily.app/Contents/Info.plist
```

输出必须是实际公钥，不能是空字符串，也不能是 `$(VOILY_SPARKLE_PUBLIC_ED_KEY)`。

如果不想把公钥提交到仓库，也可以改 release workflow 或 release 脚本，在 `xcodebuild` 命令行传入 `VOILY_SPARKLE_PUBLIC_ED_KEY=<public key>`。这种方式更容易漏配，必须保留上面的 `PlistBuddy` 校验。

## 3. 构建并公证发布资产

确认版本号遵循 `docs/releasing.md`：

- `MARKETING_VERSION` 是 `MAJOR.MINOR.PATCH`。
- tag 是 `vMAJOR.MINOR.PATCH`。
- `CURRENT_PROJECT_VERSION` 必须递增，Sparkle 用它判断机器可比版本。

示例命令：

```bash
VERSION=0.1.2
make clean-release
make release
make package-dmg
ARTIFACT="build/release/artifacts/Voily-${VERSION}.dmg" make notarize
ARTIFACT="build/release/artifacts/Voily-${VERSION}.dmg" make staple
ARTIFACT="build/release/artifacts/Voily-${VERSION}.dmg" make verify-release
```

把 `VERSION` 替换为本次发布版本。

## 4. 生成 appcast

先准备 release tag 和下载前缀：

```bash
VERSION=0.1.2
RELEASE_TAG="v${VERSION}"
DOWNLOAD_URL_PREFIX="https://github.com/BubblePtr/Voily/releases/download/${RELEASE_TAG}/"
```

在包含 notarized dmg 的 artifacts 目录上运行：

```bash
/tmp/voily-sparkle/bin/generate_appcast \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  build/release/artifacts
```

这会在 `build/release/artifacts/` 下生成或更新：

- `appcast.xml`
- 可能的 `.delta` 增量更新文件
- 可能的 `old_updates/` 归档目录

如果要给 Sparkle 更新弹窗显示 release notes，可以在运行 `generate_appcast` 前，把同名 `.md`、`.html` 或 `.txt` 放到 artifacts 目录。例如：

```text
build/release/artifacts/Voily-0.1.2.dmg
build/release/artifacts/Voily-0.1.2.md
```

生成后检查 appcast 至少包含 `sparkle:edSignature` 和 GitHub Release 下载 URL：

```bash
rg 'sparkle:edSignature|https://github.com/BubblePtr/Voily/releases/download' build/release/artifacts/appcast.xml
```

## 5. 上传 GitHub Release 资产

如果 release workflow 已经创建了 GitHub Release 并上传 dmg，只需要补传 `appcast.xml` 和 delta 文件：

```bash
shopt -s nullglob
gh release upload "$RELEASE_TAG" build/release/artifacts/appcast.xml build/release/artifacts/*.delta --clobber
```

如果是完全手工发布，则同时上传 dmg：

```bash
shopt -s nullglob
gh release upload "$RELEASE_TAG" "build/release/artifacts/Voily-${VERSION}.dmg" build/release/artifacts/appcast.xml build/release/artifacts/*.delta --clobber
```

上传后确认 feed URL 能访问：

```bash
curl -fsSL https://github.com/BubblePtr/Voily/releases/latest/download/appcast.xml | head
```

## 6. 真实升级验证

至少做一次从旧版本到新版本的真实验证：

1. 安装一个 `CURRENT_PROJECT_VERSION` 更低的 Voily 到 `/Applications` 或 `~/Applications`。
2. 启动旧版本。
3. 点击菜单里的“检查更新...”。
4. 确认 Sparkle 弹出可更新提示，并能下载、安装、重启到新版本。
5. 再次检查新版本的 `Voily.app/Contents/Info.plist`，确认 `CFBundleShortVersionString` 和 `CFBundleVersion` 是本次发布值。

注意：从 dmg 里直接运行 app 不适合验证自更新；应先把 app 拖到 Applications 目录。

## 验收清单

- `SUPublicEDKey` 在最终 release app 里非空，且不是未解析的 build setting。
- Sparkle 私钥只存在于发布用户 Keychain 或临时迁移文件中；临时文件已删除。
- `appcast.xml` 已上传到 latest release asset URL。
- `appcast.xml` 包含 `sparkle:edSignature`。
- appcast 中的下载 URL 指向本次 release tag 下的 dmg。
- dmg 已完成 notarize、staple 和 `make verify-release`。
- `CURRENT_PROJECT_VERSION` 比上一版递增。
- 旧版本 Voily 可以通过“检查更新...”升级到新版本。
- `git status --short` 没有私钥、token、Keychain 导出或临时发布产物。

## 常见问题

### 菜单显示“应用内更新尚未配置”

构建产物里的 `SUPublicEDKey` 为空或未解析。先用 `PlistBuddy` 查最终 app 的 Info.plist，不要只看 `project.yml`。

### `generate_appcast` 没有签名或找不到 key

通常是运行命令的 macOS 用户和生成 key 的用户不一致，或者 Keychain 弹窗没有允许访问。用同一个发布用户运行：

```bash
/tmp/voily-sparkle/bin/generate_keys -p
```

这个命令应该能打印已有公钥。

### 应用提示没有可用更新

优先检查：

- `curl -fsSL https://github.com/BubblePtr/Voily/releases/latest/download/appcast.xml` 能否拿到最新 appcast。
- appcast 的 enclosure URL 是否指向真实存在的 dmg。
- 新版本的 `CURRENT_PROJECT_VERSION` 是否大于已安装旧版本。
- GitHub `latest` 是否指向本次 release。当前 feed URL 依赖 `releases/latest`，不适合只发 prerelease 做验证。

### 下载失败

检查 `--download-url-prefix`。它应该是：

```text
https://github.com/BubblePtr/Voily/releases/download/v0.1.2/
```

不要用 `releases/latest/download` 作为 enclosure 下载前缀；feed 可以走 latest，但单个 dmg 的 enclosure 最好固定到具体 tag。

## 后续自动化

第一版手工跑通后，可以再把 appcast 步骤接进 `.github/workflows/release.yml`：

1. release runner 解锁包含 Sparkle 私钥的 Keychain。
2. `make verify-release` 通过后运行 `generate_appcast --download-url-prefix ... build/release/artifacts`。
3. 上传 dmg、`appcast.xml` 和 delta 文件。
4. 在 workflow 里保留 `PlistBuddy` 校验，防止公钥漏注入。

不要把 Sparkle 私钥放进 GitHub secret 再通过 `--ed-key-file -` 传给工具，除非明确决定把私钥托管到 GitHub。当前更简单的方案是让私钥留在自托管发布机的 Keychain。
