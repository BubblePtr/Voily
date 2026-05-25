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

- `VOILY_SPARKLE_PUBLIC_ED_KEY` 已配置为发布机生成的公钥。只要构建产物里的 `SUPublicEDKey` 为空或仍是未解析的 `$(...)`，应用会显示“应用内更新尚未配置”，不会启动 Sparkle。
- appcast 生成和上传已经接进 GitHub Actions release workflow。发布机仍需要把 Sparkle 私钥放进专用 release keychain 的 generic password item。

## 不要做的事

- 不要把 Sparkle 私钥、私钥导出文件、Keychain 导出、Apple notary 凭据、API token 提交到仓库。
- 不要把 Sparkle EdDSA key 和 Apple Developer ID / notarytool 凭据混在一起管理。Sparkle 私钥只用于签 appcast，Apple 凭据只用于签名和公证。
- 不要改 appcast URL，除非同时更新 `project.yml`、`Resources/VoilyApp/Info.plist` 和相关文档。
- 不要把 Sparkle dependency 改回远程包，除非先确认发布机和 CI 不会卡在 SwiftPM binary artifact 下载。

## 发布机前置检查

发布机需要满足：

- 当前 checkout 包含 Sparkle 接入改动。
- `Developer ID Application` 证书和 `VOILY_NOTARY_PROFILE` 已能完成现有发布流程。
- `dmgbuild --help` 可用，用于生成不依赖 Finder GUI 自动化的 DMG 安装窗口布局。
- GitHub CLI 已登录，并且有上传 release asset 的权限。
- 发布操作使用的 macOS 用户可以解锁 `$HOME/Library/Keychains/voily-release.keychain-db`，并能从其中读取 Sparkle generic password。

如果 `dmgbuild` 还没安装，先在发布用户下安装：

```bash
pipx install "dmgbuild==1.6.7"
```

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

这个命令会把私钥写入当前 macOS 用户的默认 Keychain，并打印公钥。保存打印出的公钥；私钥不要导出到仓库路径。

GitHub Actions self-hosted runner 是 headless 环境，不能可靠让 Sparkle 工具自己弹 Keychain 授权。把同一个私钥复制到专用 release keychain 的 generic password item 里，让 workflow 在解锁 release keychain 后通过 `/usr/bin/security` 读取：

```bash
VOILY_RELEASE_KEYCHAIN="$HOME/Library/Keychains/voily-release.keychain-db"
VOILY_SPARKLE_KEYCHAIN_ACCOUNT="ed25519"
VOILY_SPARKLE_KEYCHAIN_SERVICE="dev.voily.sparkle.ed25519-private-key"

SPARKLE_PRIVATE_KEY="$(
  security find-generic-password \
    -a "$VOILY_SPARKLE_KEYCHAIN_ACCOUNT" \
    -s "Private key for signing Sparkle updates" \
    -w "$HOME/Library/Keychains/login.keychain-db"
)"

security add-generic-password -U \
  -a "$VOILY_SPARKLE_KEYCHAIN_ACCOUNT" \
  -s "$VOILY_SPARKLE_KEYCHAIN_SERVICE" \
  -l "Voily Sparkle EdDSA private key" \
  -T /usr/bin/security \
  -w "$SPARKLE_PRIVATE_KEY" \
  "$VOILY_RELEASE_KEYCHAIN"

unset SPARKLE_PRIVATE_KEY

security set-generic-password-partition-list \
  -a "$VOILY_SPARKLE_KEYCHAIN_ACCOUNT" \
  -s "$VOILY_SPARKLE_KEYCHAIN_SERVICE" \
  -S apple-tool:,apple: \
  "$VOILY_RELEASE_KEYCHAIN"
```

如果 `security find-generic-password` 找不到默认 Sparkle item，就在“钥匙串访问”里查找 `Private key for signing Sparkle updates`，显示密码后把值导入上面的 release keychain generic password。不要把 Sparkle 私钥长期保存为文本文件。

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
VERSION=0.1.3
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
VERSION=0.1.3
RELEASE_TAG="v${VERSION}"
DOWNLOAD_URL_PREFIX="https://github.com/BubblePtr/Voily/releases/download/${RELEASE_TAG}/"
```

先把仓库里的 release notes 复制成 dmg 同名文件。Sparkle 的 `generate_appcast` 会读取这个文件，并把它写进更新说明：

```bash
cp "docs/releases/${RELEASE_TAG}.md" "build/release/artifacts/Voily-${VERSION}.md"
```

在包含 notarized dmg 和同名 release notes 的 artifacts 目录上运行：

```bash
security find-generic-password \
  -a ed25519 \
  -s dev.voily.sparkle.ed25519-private-key \
  -w "$HOME/Library/Keychains/voily-release.keychain-db" |
/tmp/voily-sparkle/bin/generate_appcast \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --embed-release-notes \
  --ed-key-file - \
  build/release/artifacts
```

这会在 `build/release/artifacts/` 下生成或更新：

- `appcast.xml`
- 可能的 `.delta` 增量更新文件
- 可能的 `old_updates/` 归档目录

要给 Sparkle 更新弹窗显示 release notes，运行 `generate_appcast` 前必须把同名 `.md`、`.html` 或 `.txt` 放到 artifacts 目录。例如：

```text
build/release/artifacts/Voily-0.1.3.dmg
build/release/artifacts/Voily-0.1.3.md
```

自动 release workflow 已经从 `docs/releases/${RELEASE_TAG}.md` 执行这一步，并强制 `--embed-release-notes`，所以 GitHub Release 页面和 Sparkle 弹窗会使用同一份说明。生成后检查 appcast 至少包含 `sparkle:edSignature`、GitHub Release 下载 URL 和非空 `<description>`：

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

1. 安装一个 `CURRENT_PROJECT_VERSION` 更低的 Voily 到 `/Applications`。
2. 启动旧版本。
3. 点击菜单里的“检查更新...”。
4. 确认 Sparkle 弹出可更新提示，并能下载、安装、重启到新版本。
5. 再次检查新版本的 `Voily.app/Contents/Info.plist`，确认 `CFBundleShortVersionString` 和 `CFBundleVersion` 是本次发布值。

注意：从 dmg 里直接运行 app 不适合验证自更新；应先把 app 拖到 Applications 目录。

## 验收清单

- `SUPublicEDKey` 在最终 release app 里非空，且不是未解析的 build setting。
- Sparkle 私钥只存在于发布用户默认 Keychain、专用 release keychain 的 generic password item 或临时迁移文件中；临时文件已删除。
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

本地手工生成时，通常是运行命令的 macOS 用户和生成 key 的用户不一致，或者 release keychain 里还没有 generic password item。先确认默认 Sparkle key 存在：

```bash
/tmp/voily-sparkle/bin/generate_keys -p
```

这个命令应该能打印已有公钥。再确认 release keychain 里的 workflow item 能被读取：

```bash
security find-generic-password \
  -a ed25519 \
  -s dev.voily.sparkle.ed25519-private-key \
  -w "$HOME/Library/Keychains/voily-release.keychain-db" >/dev/null
```

如果交互式终端能读，但 GitHub Actions 仍然读不到，通常是这个 generic password item 的访问控制还没允许命令行工具访问。workflow 会用 release keychain 密码自动设置 partition list；手工排查时也可以运行：

```bash
security set-generic-password-partition-list \
  -a ed25519 \
  -s dev.voily.sparkle.ed25519-private-key \
  -S apple-tool:,apple: \
  "$HOME/Library/Keychains/voily-release.keychain-db"
```

GitHub Actions workflow 里如果看到 Keychain blocked 或 SSH/headless 相关错误，不要让 Sparkle 工具自己读默认 Keychain。workflow 应该从已解锁的 release keychain 读取 generic password，并通过 `--ed-key-file -` 传给 `generate_appcast`。

### 应用提示没有可用更新

优先检查：

- `curl -fsSL https://github.com/BubblePtr/Voily/releases/latest/download/appcast.xml` 能否拿到最新 appcast。
- appcast 的 enclosure URL 是否指向真实存在的 dmg。
- 新版本的 `CURRENT_PROJECT_VERSION` 是否大于已安装旧版本。
- GitHub `latest` 是否指向本次 release。当前 feed URL 依赖 `releases/latest`，不适合只发 prerelease 做验证。

### 下载失败

检查 `--download-url-prefix`。它应该是：

```text
https://github.com/BubblePtr/Voily/releases/download/v0.1.3/
```

不要用 `releases/latest/download` 作为 enclosure 下载前缀；feed 可以走 latest，但单个 dmg 的 enclosure 最好固定到具体 tag。

## 后续自动化

当前 `.github/workflows/release.yml` 已经执行 appcast 步骤：

1. release runner 解锁 Apple 发布 keychain。
2. `make verify-release` 通过后从 release keychain 读取 Sparkle generic password，并运行 `generate_appcast --download-url-prefix ... --ed-key-file - build/release/artifacts`。
3. 上传 dmg、`appcast.xml` 和 delta 文件。
4. 在 workflow 里保留 `PlistBuddy` 校验，防止公钥漏注入。

不要把 Sparkle 私钥放进 GitHub secret 再通过 `--ed-key-file -` 传给工具，除非明确决定把私钥托管到 GitHub。当前方案是让 Sparkle 私钥和 Developer ID 发布材料一样归 release keychain 管理。
