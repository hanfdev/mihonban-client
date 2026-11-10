# Mihonban Client

[English](README.md) · [简体中文](README.zh.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Español](README.es.md)

本仓库开发独立的 iPhone/iPad 客户端分支，面向连接 Mihonban 服务器听音乐的用户，也包括普通听众。它以原客户端已验证的 Build 95 为起点，保留上游源代码历史及 AGPL-3.0 许可证。

**我的收藏**是在设备本地保存的专辑和歌曲书签，按服务器分别存储。**管理员精选**仍是由管理员管理的服务器共享内容。个人收藏可离线修改，不会改变共享精选，也不会下载音频。目前服务器只区分访问角色，不提供个人账户标识，因此个人收藏不会跨设备同步，也不承诺按账户隔离。

应用使用 `org.mihonban.client.ios` 和显示名称 **Mihonban Client**，可与原应用同时安装。参阅[客户端范围、存储与构建说明](CLIENT-FORK.zh.md)及[客户端构建产物](https://github.com/hanfdev/mihonban-client/actions/workflows/mobile.yml)。成功的 CI 运行会提供未签名 IPA，安装前需要签名。

下方保留的原文档介绍更完整的 [Mihonban 服务器项目](https://github.com/hanfdev/mihonban)。服务器、网页、桌面和 Android 源代码保留作为上游背景；本分支最初的开发范围是 iOS/iPadOS 客户端。

Mihonban 是一套私有、自托管音乐曲库和响应式网页播放器。它可以使用 Node + SQLite 在本地运行，也可以使用 Wrangler 本地 D1，或部署到 Cloudflare Workers + D1；音频始终保存在你控制的存储中。

## 主要能力

- 完整适配桌面与手机的专辑、歌曲、艺人、精选、导入和管理页面
- 原生支持有顺序的专辑多艺人署名与单曲合作艺人覆盖，每位艺人均可独立搜索、进入主页并从播放器跳转
- 听众与管理员双口令，以及可选的免密只读访客模式
- 播放队列、移动端上一首/播放暂停/下一首完整控制、手势安全首播、随机/循环、Range 拖动和系统媒体控制
- `desktop/` 目录下的原生 Windows 桌面客户端（egui + Rodio），以免安装便携 exe 发布于 [Releases 页面](https://github.com/hanfdev/mihonban/releases)
- 命名 OneDrive、WebDAV、Google Drive，以及仅 Node 支持的本地文件夹后端
- 可自动回源修复的 R2 图片镜像，用于封面、内页和艺人头像
- Discogs 官方 API 导入；手动保存 RYM HTML 后解析，不自动请求 RYM
- 可选 Python 本机伴侣：处理文件夹及单层/嵌套压缩包、修复标签并同步
- 英语、简体中文、繁体中文、日语、韩语、法语和西班牙语界面
- SQLite/D1 迁移工具和可选的签名音源代理 Worker

## 运行方式

| 运行时 | 元数据数据库 | 文件后端 | 适用场景 |
|---|---|---|---|
| Node | `<DATA_DIR>/mihonban.sqlite` | OneDrive、WebDAV、Google Drive、本地文件夹 | 局域网、NAS、VPS |
| Wrangler 本地 | `.wrangler/` 下的本地 D1/KV | OneDrive、WebDAV、Google Drive | 兼容 Cloudflare 的本地开发 |
| Cloudflare | D1 + KV，可选 R2 | OneDrive、WebDAV、Google Drive | 全天在线的 Serverless 部署 |

Python 伴侣在所有模式下都是可选项。只有需要本地收件箱守望、解压、标签整理或本地与云端对账时才安装。

## 快速开始

克隆正式仓库：

```bash
git clone https://github.com/hanfdev/mihonban.git
cd mihonban
```

### 本地 Wrangler 应用

Windows 可使用辅助脚本，把构建目录放到 OneDrive 外并启动 Wrangler：

```powershell
tools\cloud-dev.cmd
```

电脑打开 `http://127.0.0.1:8787`；开发服务器默认只监听回环地址。设置 `MIHONBAN_DEV_LAN=1` 并在 Windows 防火墙允许 Node.js 后，同一局域网的手机可打开 `http://<电脑内网 IP>:8787` 测试。辅助脚本首次生成的密钥文件包含随机生成的听众口令和管理员口令（见暂存目录中的 `.dev.vars`）；对外分享前必须在管理后台修改。

手动配置 Wrangler 见[安装与部署](docs/install.zh.md)。

### 本地 Node + SQLite 应用

```bash
cd cloud/web
npm ci
npm run build
cd ../worker
npm ci
# 将 .env.example 复制为 .env，替换全部占位值；本地 HTTP 设置 DEV_INSECURE_COOKIE=1。
npm run node
```

Node 默认监听 `0.0.0.0:8788`。未设置 `DATA_DIR` 时，数据库是 `cloud/worker/data/mihonban.sqlite`。Node 模式没有内置口令：`.env` 必须提供 `APP_PASSWORD`、`ADMIN_PASSWORD` 和至少 32 个字符的 `SESSION_SECRET`。

### Cloudflare

构建网页后创建 D1/KV、设置 Worker secrets、应用 `schema.sql` 并部署。手动部署是标准流程，不要求安装本机 Python 伴侣。操作前阅读[安装与部署](docs/install.zh.md)；已有本地曲库先阅读[数据库迁移](docs/database-migration.zh.md)。

### 可选 Python 本机伴侣

```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
# POSIX:   source .venv/bin/activate
pip install -e ./pipeline
mihonban setup
mihonban doctor
```

`music_root`、`data_dir`、数据库和临时目录不能位于 OneDrive、Dropbox、iCloud 或其他同步目录中。

## 数据与备份

| 数据 | 权威来源 | 备份方式 |
|---|---|---|
| 专辑、曲目、艺人、收藏、备注 | Node SQLite 或 D1 | SQLite 感知备份或逻辑 SQL 导出 |
| 命名存储、R2 和模块设置 | 数据库 settings | 管理后台设置 JSON，必须加密保存 |
| 初始口令、会话、伴侣和代理密钥 | 运行环境 | 单独记录在密码管理器 |
| 音频和原始图片 | 配置的存储后端 | 存储层独立备份 |
| R2 图片镜像和 KV 缓存 | 可重建缓存 | 复用同一 R2 桶时迁移/认领索引；新桶重新预热；KV 不迁移 |

管理后台设置 JSON 不是曲库备份，数据库备份也不是音频备份。

## 仓库结构

| 路径 | 用途 |
|---|---|
| `cloud/web/` | React 播放器与管理界面 |
| `cloud/worker/` | Hono API、D1 schema、Node 兼容运行时 |
| `cloud/proxy-worker/` | 可选签名音源中转 |
| `desktop/` | 原生 Windows 桌面客户端（Rust、egui） |
| `pipeline/` | Python `mihonban` CLI 与整理/同步管线 |
| `config/` | 不含密钥的配置模板 |
| `tools/` | 本地开发、部署、守望和迁移工具 |
| `tests/` | Python 回归测试 |

## 常用命令

```text
mihonban setup                  创建本机伴侣配置
mihonban doctor                 检查依赖与路径
mihonban ingest --apply         处理收件箱压缩包或专辑文件夹
mihonban watch                  守望收件箱并对账云端数据
mihonban cloud sync             上传并登记本机专辑
mihonban cloud pull             把网页导入拉回本机
mihonban rym parse|match|write  处理手动保存的 RYM HTML

cd cloud/worker && npm test
cd cloud/proxy-worker && npm test
cd cloud/web && npm test && npm run build
python -m pytest -q
```

## 安全

- 不要提交 `.dev.vars`、`.env`、`mihonban.toml`、`rclone.conf`、数据库、设置导出、token 或音频。
- 本地 HTTP 需要 `DEV_INSECURE_COOKIE=1`；公开环境必须使用 HTTPS，并且不能设置它。
- 在管理后台保存的新口令会覆盖环境变量中的初始口令，并让旧会话失效。
- 使用外部代理时，`STREAM_PROXY_SECRET` 与 `PROXY_SECRET` 必须完全相同并保持私密。
- RYM 功能只解析用户手动保存的文件，本仓库不包含 RYM 爬虫。
- 无法替代的音频至少保留一份独立副本。

## 文档

| 指南 | 语言版本 |
|---|---|
| 安装与部署 | [English](docs/install.md) · [简体中文](docs/install.zh.md) · [繁體中文](docs/install.zh-Hant.md) · [日本語](docs/install.ja.md) · [한국어](docs/install.ko.md) · [Français](docs/install.fr.md) · [Español](docs/install.es.md) |
| 架构与运行模型 | [English](docs/cloud.md) · [简体中文](docs/cloud.zh.md) · [繁體中文](docs/cloud.zh-Hant.md) · [日本語](docs/cloud.ja.md) · [한국어](docs/cloud.ko.md) · [Français](docs/cloud.fr.md) · [Español](docs/cloud.es.md) |
| 日常使用手册 | [English](docs/manual.md) · [简体中文](docs/manual.zh.md) · [繁體中文](docs/manual.zh-Hant.md) · [日本語](docs/manual.ja.md) · [한국어](docs/manual.ko.md) · [Français](docs/manual.fr.md) · [Español](docs/manual.es.md) |
| 数据库迁移 | [English](docs/database-migration.md) · [简体中文](docs/database-migration.zh.md) · [繁體中文](docs/database-migration.zh-Hant.md) · [日本語](docs/database-migration.ja.md) · [한국어](docs/database-migration.ko.md) · [Français](docs/database-migration.fr.md) · [Español](docs/database-migration.es.md) |
| 多存储与文件迁移 | [English](docs/storage.md) · [简体中文](docs/storage.zh.md) · [繁體中文](docs/storage.zh-Hant.md) · [日本語](docs/storage.ja.md) · [한국어](docs/storage.ko.md) · [Français](docs/storage.fr.md) · [Español](docs/storage.es.md) |
| 纯 Cloudflare 托管 | [English](docs/serverless-hosting.md) · [简体中文](docs/serverless-hosting.zh.md) · [繁體中文](docs/serverless-hosting.zh-Hant.md) · [日本語](docs/serverless-hosting.ja.md) · [한국어](docs/serverless-hosting.ko.md) · [Français](docs/serverless-hosting.fr.md) · [Español](docs/serverless-hosting.es.md) |
| 可选音源代理 | [English](docs/audio-proxy.md) · [简体中文](docs/audio-proxy.zh.md) · [繁體中文](docs/audio-proxy.zh-Hant.md) · [日本語](docs/audio-proxy.ja.md) · [한국어](docs/audio-proxy.ko.md) · [Français](docs/audio-proxy.fr.md) · [Español](docs/audio-proxy.es.md) |
| 安全发布代码 | [English](docs/github-publish.md) · [简体中文](docs/github-publish.zh.md) · [繁體中文](docs/github-publish.zh-Hant.md) · [日本語](docs/github-publish.ja.md) · [한국어](docs/github-publish.ko.md) · [Français](docs/github-publish.fr.md) · [Español](docs/github-publish.es.md) |

## 许可证

Mihonban 使用 [GNU Affero 通用公共许可证第三版](LICENSE)（`AGPL-3.0-only`）。如果修改本软件并通过网络向他人提供服务，AGPL 要求向这些用户提供对应版本的源代码。

许可证只覆盖本仓库中的代码和安全模板，不授予传播音乐或第三方元数据的权利。
