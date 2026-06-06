# Voily 官网部署：Cloudflare Pages

## 结论

Voily 官网首版部署到 Cloudflare Pages。现在不需要购买独立域名，先使用 Pages 默认的 `*.pages.dev` 域名；后续如果项目有更明确的传播需求，再接入自定义域名。

选择 Cloudflare Pages 的原因：

- 官网是静态 landing page，适合 Pages 的静态站托管模型。
- 默认提供 HTTPS 和 Cloudflare CDN。
- 推荐用 Git 集成自动部署；必要时也可以用 Wrangler 本地直接上传 `dist`。
- 后续接入自定义域名时，不需要改应用代码。

## 推荐配置

在 Cloudflare Pages 创建项目时使用以下配置：

| 配置项 | 值 |
| --- | --- |
| Project name | `voily` |
| Production branch | `main` |
| Root directory | `website` |
| Build command | `bun run build` |
| Build output directory | `dist` |
| Environment variables | `BUN_VERSION=1.3.12` |

如果 `voily.pages.dev` 已被占用，可以把项目名改成 `voily-app` 或 `voily-website`。项目名变化只影响 Pages 默认域名和本地 CLI 部署时的 `--project-name` 参数。

## Git 集成部署

Cloudflare Dashboard 的 Git 集成仍然是最完整的 Git 部署模式，但当前 `voily` 项目是通过 Wrangler Direct Upload 创建的。Direct Upload 项目不能直接切换为 Git 集成项目，因此当前仓库先用 GitHub Actions + Wrangler 自动部署。

## GitHub Actions 自动部署

当前仓库使用 `.github/workflows/deploy-website.yml` 自动部署官网：

- 触发分支：`main`
- 触发路径：`website/**` 和 `.github/workflows/deploy-website.yml`
- 构建命令：`bun install --frozen-lockfile` 后执行 `bun run build`
- 部署命令：`wrangler pages deploy dist --project-name=voily --branch=main`

需要在 GitHub 仓库的 Actions secrets 中配置：

| Secret | 说明 |
| --- | --- |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account ID |
| `CLOUDFLARE_API_TOKEN` | 有 `Account > Cloudflare Pages > Edit` 权限的 API token |

本地已有 token，但不要直接写入仓库文件。需要通过 GitHub Secrets 配置，或在确认后用 `gh secret set` 写入仓库 secrets。

## 本地直接上传

直接上传适合临时发布或没有配置 Git 集成时使用。注意：如果首次创建项目时选择 Direct Upload，Cloudflare 文档说明该项目不能再切换为 Git 集成项目。因此如果希望长期自动部署，先用 Dashboard 创建 Git 集成项目，再考虑本地直接上传。

首次部署前需要登录 Cloudflare：

```bash
cd website
bunx wrangler login
```

确认登录状态：

```bash
bunx wrangler whoami
```

构建并部署：

```bash
cd website
bun run pages:deploy:direct
```

本地用 Cloudflare Pages runtime 预览：

```bash
cd website
bun run pages:dev
```

## 相关文件

- `website/wrangler.jsonc`：Cloudflare Pages 项目名和构建输出目录。
- `website/package.json`：`pages:deploy:direct` 和 `pages:dev` 脚本。

## 当前状态

已用 `CLOUDFLARE_API_TOKEN` 通过 Wrangler Direct Upload 创建并发布 `voily` Pages 项目。

- 生产地址：`https://voily.pages.dev`
- 最新部署：`32b5c657-8114-40f2-ac2b-bc4da1d5d42c`
- 部署分支：`main`

已验证生产地址返回 `200 OK`，React 页面可正常渲染，`Star on GitHub` 和两个下载按钮可见。
