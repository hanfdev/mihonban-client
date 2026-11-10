# Mihonban Client

[English](README.md) · [简体中文](README.zh.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Español](README.es.md)

本儲存庫開發獨立的 iPhone/iPad 用戶端分支，面向連接 Mihonban 伺服器聽音樂的使用者，也包括一般聽眾。它以原用戶端已驗證的 Build 95 為起點，保留上游原始碼歷史及 AGPL-3.0 授權條款。

**我的收藏**是在裝置本機儲存的專輯與歌曲書籤，依伺服器分別儲存。**管理員精選**仍是由管理員管理的伺服器共享內容。個人收藏可離線修改，不會改變共享精選，也不會下載音訊。目前伺服器只區分存取角色，不提供個人帳戶識別，因此個人收藏不會跨裝置同步，也不承諾依帳戶隔離。

應用程式使用 `org.mihonban.client.ios` 和顯示名稱 **Mihonban Client**，可與原應用程式同時安裝。參閱[用戶端範圍、儲存與建置說明](CLIENT-FORK.zh-Hant.md)及[用戶端建置產物](https://github.com/hanfdev/mihonban-client/actions/workflows/mobile.yml)。成功的 CI 執行會提供未簽署 IPA，安裝前需要簽署。

下方保留的原文件介紹更完整的 [Mihonban 伺服器專案](https://github.com/hanfdev/mihonban)。伺服器、網頁、桌面和 Android 原始碼保留作為上游背景；本分支最初的開發範圍是 iOS/iPadOS 用戶端。

Mihonban 是一套私有、自託管音樂曲庫和響應式網頁播放器。它可以使用 Node + SQLite 在本地執行，也可以使用 Wrangler 本地 D1，或部署到 Cloudflare Workers + D1；音訊始終儲存在你控制的儲存中。

## 主要能力

- 完整適配桌面與手機的專輯、歌曲、藝人、精選、匯入和管理頁面
- 原生支援有順序的專輯多藝人署名與單曲合作藝人覆寫，每位藝人均可獨立搜尋、進入主頁並從播放器跳轉
- 聽眾與管理員雙口令，以及可選的免密只讀訪客模式
- 播放佇列、行動端上一首/播放暫停/下一首完整控制、手勢安全首播、隨機/迴圈、Range 拖動和系統媒體控制
- `desktop/` 目錄下的原生 Windows 桌面客戶端（egui + Rodio），以免安裝可攜 exe 形式發佈於 [Releases 頁面](https://github.com/hanfdev/mihonban/releases)
- 命名 OneDrive、WebDAV、Google Drive，以及僅 Node 支援的本地資料夾後端
- 可自動回源修復的 R2 圖片映象，用於封面、內頁和藝人頭像
- Discogs 官方 API 匯入；手動儲存 RYM HTML 後解析，不自動請求 RYM
- 可選 Python 本機伴侶：處理資料夾及單層/巢狀壓縮包、修復標籤並同步
- 英語、簡體中文、繁體中文、日語、韓語、法語和西班牙語介面
- SQLite/D1 遷移工具和可選的簽名音源代理 Worker

## 執行方式

| 執行時 | 後設資料資料庫 | 檔案後端 | 適用場景 |
|---|---|---|---|
| Node | `<DATA_DIR>/mihonban.sqlite` | OneDrive、WebDAV、Google Drive、本地資料夾 | 區域網、NAS、VPS |
| Wrangler 本地 | `.wrangler/` 下的本地 D1/KV | OneDrive、WebDAV、Google Drive | 相容 Cloudflare 的本地開發 |
| Cloudflare | D1 + KV，可選 R2 | OneDrive、WebDAV、Google Drive | 全天線上的 Serverless 部署 |

Python 伴侶在所有模式下都是可選項。只有需要本地收件箱守望、解壓、標籤整理或本地與雲端對賬時才安裝。

## 快速開始

克隆正式倉庫：

```bash
git clone https://github.com/hanfdev/mihonban.git
cd mihonban
```

### 本地 Wrangler 應用

Windows 可使用輔助指令碼，把構建目錄放到 OneDrive 外並啟動 Wrangler：

```powershell
tools\cloud-dev.cmd
```

電腦開啟 `http://127.0.0.1:8787`；開發伺服器預設只監聽回環位址。設定 `MIHONBAN_DEV_LAN=1` 並在 Windows 防火牆允許 Node.js 後，同一區域網的手機可開啟 `http://<電腦內網 IP>:8787` 測試。輔助指令碼首次生成的金鑰檔案包含隨機生成的聽眾口令和管理員口令（見暫存目錄中的 `.dev.vars`）；對外分享前必須在管理後臺修改。

手動配置 Wrangler 見[安裝與部署](docs/install.zh-Hant.md)。

### 本地 Node + SQLite 應用

```bash
cd cloud/web
npm ci
npm run build
cd ../worker
npm ci
# 將 .env.example 複製為 .env，替換全部佔位值；本地 HTTP 設定 DEV_INSECURE_COOKIE=1。
npm run node
```

Node 預設監聽 `0.0.0.0:8788`。未設定 `DATA_DIR` 時，資料庫是 `cloud/worker/data/mihonban.sqlite`。Node 模式沒有內建口令：`.env` 必須提供 `APP_PASSWORD`、`ADMIN_PASSWORD` 和至少 32 個字元的 `SESSION_SECRET`。

### Cloudflare

構建網頁後建立 D1/KV、設定 Worker secrets、應用 `schema.sql` 並部署。手動部署是標準流程，不要求安裝本機 Python 伴侶。操作前閱讀[安裝與部署](docs/install.zh-Hant.md)；已有本地曲庫先閱讀[資料庫遷移](docs/database-migration.zh-Hant.md)。

### 可選 Python 本機伴侶

```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
# POSIX:   source .venv/bin/activate
pip install -e ./pipeline
mihonban setup
mihonban doctor
```

`music_root`、`data_dir`、資料庫和臨時目錄不能位於 OneDrive、Dropbox、iCloud 或其他同步目錄中。

## 資料與備份

| 資料 | 權威來源 | 備份方式 |
|---|---|---|
| 專輯、曲目、藝人、收藏、備註 | Node SQLite 或 D1 | SQLite 感知備份或邏輯 SQL 匯出 |
| 命名儲存、R2 和模組設定 | 資料庫 settings | 管理後臺設定 JSON，必須加密儲存 |
| 初始口令、會話、伴侶和代理金鑰 | 執行環境 | 單獨記錄在密碼管理器 |
| 音訊和原始圖片 | 配置的儲存後端 | 儲存層獨立備份 |
| R2 圖片映象和 KV 快取 | 可重建快取 | 複用同一 R2 桶時遷移/認領索引；新桶重新預熱；KV 不遷移 |

管理後臺設定 JSON 不是曲庫備份，資料庫備份也不是音訊備份。

## 倉庫結構

| 路徑 | 用途 |
|---|---|
| `cloud/web/` | React 播放器與管理介面 |
| `cloud/worker/` | Hono API、D1 schema、Node 相容執行時 |
| `cloud/proxy-worker/` | 可選簽名音源中轉 |
| `desktop/` | 原生 Windows 桌面客戶端（Rust、egui） |
| `pipeline/` | Python `mihonban` CLI 與整理/同步管線 |
| `config/` | 不含金鑰的配置模板 |
| `tools/` | 本地開發、部署、守望和遷移工具 |
| `tests/` | Python 迴歸測試 |

## 常用命令

```text
mihonban setup                  建立本機伴侶配置
mihonban doctor                 檢查依賴與路徑
mihonban ingest --apply         處理收件箱壓縮包或專輯資料夾
mihonban watch                  守望收件箱並對賬雲端資料
mihonban cloud sync             上傳並登記本機專輯
mihonban cloud pull             把網頁匯入拉回本機
mihonban rym parse|match|write  處理手動儲存的 RYM HTML

cd cloud/worker && npm test
cd cloud/proxy-worker && npm test
cd cloud/web && npm test && npm run build
python -m pytest -q
```

## 安全

- 不要提交 `.dev.vars`、`.env`、`mihonban.toml`、`rclone.conf`、資料庫、設定匯出、token 或音訊。
- 本地 HTTP 需要 `DEV_INSECURE_COOKIE=1`；公開環境必須使用 HTTPS，並且不能設定它。
- 在管理後臺儲存的新口令會覆蓋環境變數中的初始口令，並讓舊會話失效。
- 使用外部代理時，`STREAM_PROXY_SECRET` 與 `PROXY_SECRET` 必須完全相同並保持私密。
- RYM 功能只解析使用者手動儲存的檔案，本倉庫不包含 RYM 爬蟲。
- 無法替代的音訊至少保留一份獨立副本。

## 文件

| 指南 | 語言版本 |
|---|---|
| 安裝與部署 | [English](docs/install.md) · [簡體中文](docs/install.zh.md) · [繁體中文](docs/install.zh-Hant.md) · [日本語](docs/install.ja.md) · [한국어](docs/install.ko.md) · [Français](docs/install.fr.md) · [Español](docs/install.es.md) |
| 架構與執行模型 | [English](docs/cloud.md) · [簡體中文](docs/cloud.zh.md) · [繁體中文](docs/cloud.zh-Hant.md) · [日本語](docs/cloud.ja.md) · [한국어](docs/cloud.ko.md) · [Français](docs/cloud.fr.md) · [Español](docs/cloud.es.md) |
| 日常使用手冊 | [English](docs/manual.md) · [簡體中文](docs/manual.zh.md) · [繁體中文](docs/manual.zh-Hant.md) · [日本語](docs/manual.ja.md) · [한국어](docs/manual.ko.md) · [Français](docs/manual.fr.md) · [Español](docs/manual.es.md) |
| 資料庫遷移 | [English](docs/database-migration.md) · [簡體中文](docs/database-migration.zh.md) · [繁體中文](docs/database-migration.zh-Hant.md) · [日本語](docs/database-migration.ja.md) · [한국어](docs/database-migration.ko.md) · [Français](docs/database-migration.fr.md) · [Español](docs/database-migration.es.md) |
| 多儲存與檔案遷移 | [English](docs/storage.md) · [簡體中文](docs/storage.zh.md) · [繁體中文](docs/storage.zh-Hant.md) · [日本語](docs/storage.ja.md) · [한국어](docs/storage.ko.md) · [Français](docs/storage.fr.md) · [Español](docs/storage.es.md) |
| 純 Cloudflare 託管 | [English](docs/serverless-hosting.md) · [簡體中文](docs/serverless-hosting.zh.md) · [繁體中文](docs/serverless-hosting.zh-Hant.md) · [日本語](docs/serverless-hosting.ja.md) · [한국어](docs/serverless-hosting.ko.md) · [Français](docs/serverless-hosting.fr.md) · [Español](docs/serverless-hosting.es.md) |
| 可選音源代理 | [English](docs/audio-proxy.md) · [簡體中文](docs/audio-proxy.zh.md) · [繁體中文](docs/audio-proxy.zh-Hant.md) · [日本語](docs/audio-proxy.ja.md) · [한국어](docs/audio-proxy.ko.md) · [Français](docs/audio-proxy.fr.md) · [Español](docs/audio-proxy.es.md) |
| 安全釋出程式碼 | [English](docs/github-publish.md) · [簡體中文](docs/github-publish.zh.md) · [繁體中文](docs/github-publish.zh-Hant.md) · [日本語](docs/github-publish.ja.md) · [한국어](docs/github-publish.ko.md) · [Français](docs/github-publish.fr.md) · [Español](docs/github-publish.es.md) |

## 許可證

Mihonban 使用 [GNU Affero 通用公共許可證第三版](LICENSE)（`AGPL-3.0-only`）。如果修改本軟體並透過網路向他人提供服務，AGPL 要求向這些使用者提供對應版本的原始碼。

許可證只覆蓋本倉庫中的程式碼和安全模板，不授予傳播音樂或第三方後設資料的權利。
