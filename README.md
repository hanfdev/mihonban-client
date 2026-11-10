# Mihonban Client

[English](README.md) · [简体中文](README.zh.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Español](README.es.md)

This repository develops an independent iPhone/iPad client fork for people who listen to a Mihonban server, including ordinary listeners. It starts from the original client's verified Build 95 and retains the upstream source history and AGPL-3.0 license.

**My favorites** are device-local album and song bookmarks, stored separately for each server. **Admin picks** remain the server's shared, administrator-managed selection. Personal favorites work offline and do not change shared picks or download audio. The server currently identifies access roles rather than individual accounts, so personal favorites do not sync across devices or claim per-account isolation.

The app uses `org.mihonban.client.ios` and the display name **Mihonban Client**, so it can be installed alongside the original app. See [client scope, storage, and building](CLIENT-FORK.md) and [client build artifacts](https://github.com/hanfdev/mihonban-client/actions/workflows/mobile.yml). A successful CI run provides an unsigned IPA that needs signing before installation.

The inherited documentation below describes the wider [Mihonban server project](https://github.com/hanfdev/mihonban). Server, web, desktop and Android sources remain available as upstream context; the new fork's initial development scope is the iOS/iPadOS client.

Mihonban is a private, self-hosted music library with a responsive web player. Run it locally with Node and SQLite, use Wrangler's local D1 emulator, or deploy the same application to Cloudflare Workers and D1. Audio remains in storage you control.

## Highlights

- Responsive album, track, artist, favorites, import, and administration views
- Ordered multi-artist album credits plus per-track collaboration overrides, with per-artist pages, search, and player links
- Listener and administrator passwords, plus an optional passwordless read-only guest mode
- Persistent playback queue, complete mobile previous/play-pause/next controls, gesture-safe playback, shuffle/repeat, Range seeking, and Media Session controls
- Native Windows desktop client in `desktop/` (egui + Rodio), shipped as a portable exe on the [Releases page](https://github.com/hanfdev/mihonban/releases)
- Named OneDrive, WebDAV, Google Drive, and Node-only local-folder storage backends
- Optional self-healing R2 image mirror for covers, galleries, and artist avatars
- Discogs API imports and manual RYM HTML parsing without automated RYM requests
- Optional Python companion for inbox folders, single/nested archives, tag repair, and cloud synchronization
- English, Simplified Chinese, Traditional Chinese, Japanese, Korean, French, and Spanish interfaces
- SQLite/D1 migration tools and an optional signed audio proxy Worker

## Runtime choices

| Runtime | Metadata database | File backends | Typical use |
|---|---|---|---|
| Node | `<DATA_DIR>/mihonban.sqlite` | OneDrive, WebDAV, Google Drive, local folder | Local network, NAS, VPS |
| Wrangler local | Local D1/KV under `.wrangler/` | OneDrive, WebDAV, Google Drive | Cloudflare-compatible development |
| Cloudflare | D1 + KV, optional R2 | OneDrive, WebDAV, Google Drive | Always-online serverless deployment |

The Python companion is optional in every mode. Install it only when you need local inbox watching, archive extraction, tag organization, or local-to-cloud reconciliation.

## Quick start

Clone the canonical repository:

```bash
git clone https://github.com/hanfdev/mihonban.git
cd mihonban
```

### Local Wrangler app

On Windows, the helper stages build files outside OneDrive and starts Wrangler:

```powershell
tools\cloud-dev.cmd
```

Open `http://127.0.0.1:8787`; the dev server listens on loopback only by default. Set `MIHONBAN_DEV_LAN=1` and allow Node.js through the Windows firewall to test from a phone via `http://<computer-lan-ip>:8787`. The helper's first secrets file contains randomly generated listener and administrator passwords (see `.dev.vars` in the stage directory); change both in Admin before sharing the service.

For a manual Wrangler setup, see [Install and deploy](docs/install.md).

### Local Node + SQLite app

```bash
cd cloud/web
npm ci
npm run build
cd ../worker
npm ci
# Copy .env.example to .env, replace every placeholder, and set DEV_INSECURE_COOKIE=1 for local HTTP.
npm run node
```

Node listens on `0.0.0.0:8788` by default. Its database is `cloud/worker/data/mihonban.sqlite` unless `DATA_DIR` is set. There are no built-in Node passwords: `.env` must define `APP_PASSWORD`, `ADMIN_PASSWORD`, and a `SESSION_SECRET` of at least 32 characters.

### Cloudflare

Build the web app, create D1 and KV, set Worker secrets, apply `schema.sql`, and deploy. The manual path is canonical; the local Python companion is not required. Follow [Install and deploy](docs/install.md) and read [Database migration](docs/database-migration.md) before moving an existing local catalog.

### Optional Python companion

```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
# POSIX:   source .venv/bin/activate
pip install -e ./pipeline
mihonban setup
mihonban doctor
```

Keep `music_root`, `data_dir`, databases, and temporary files outside OneDrive, Dropbox, iCloud, or any other synchronized directory.

## Data and backups

| Data | Source of truth | Backup method |
|---|---|---|
| Albums, tracks, artists, favorites, notes | Node SQLite or D1 | SQLite-aware backup or logical SQL export |
| Named storage, R2, and module settings | Database settings | Admin settings JSON; store encrypted |
| Password bootstrap, session, companion, and proxy secrets | Runtime environment | Record separately in a password manager |
| Audio and original images | Configured storage backend | Independent storage-level backup |
| R2 image mirror and KV caches | Rebuildable cache | Same R2 bucket: migrate/reclaim its index; new bucket: prewarm; never migrate KV |

An Admin settings JSON is not a catalog backup, and a database backup is not an audio backup.

## Repository map

| Path | Purpose |
|---|---|
| `cloud/web/` | React player and administration UI |
| `cloud/worker/` | Hono API, D1 schema, Node compatibility runtime |
| `cloud/proxy-worker/` | Optional signed audio relay |
| `desktop/` | Native Windows desktop client (Rust, egui) |
| `pipeline/` | Python `mihonban` CLI and ingest/sync pipeline |
| `config/` | Safe configuration templates |
| `tools/` | Local development, deployment, watcher, and migration helpers |
| `tests/` | Python regression tests |

## Common commands

```text
mihonban setup                  create local companion config
mihonban doctor                 verify dependencies and paths
mihonban ingest --apply         process inbox archives or album folders
mihonban watch                  watch the inbox and reconcile cloud data
mihonban cloud sync             upload/register local albums
mihonban cloud pull             pull web imports back to the local library
mihonban rym parse|match|write  process manually saved RYM HTML

cd cloud/worker && npm test
cd cloud/proxy-worker && npm test
cd cloud/web && npm test && npm run build
python -m pytest -q
```

## Security

- Never commit `.dev.vars`, `.env`, `mihonban.toml`, `rclone.conf`, databases, settings exports, tokens, or audio.
- Local HTTP requires `DEV_INSECURE_COOKIE=1`; public deployments require HTTPS and must leave it unset.
- Password changes saved in Admin override bootstrap environment passwords and revoke existing sessions.
- Keep `STREAM_PROXY_SECRET` and `PROXY_SECRET` identical and private when the external proxy is enabled.
- RYM support only parses files saved manually by the user; this repository contains no RYM crawler.
- Keep at least one independent copy of irreplaceable audio.

## Documentation

| Guide | Languages |
|---|---|
| Install and deploy | [English](docs/install.md) · [简体中文](docs/install.zh.md) · [繁體中文](docs/install.zh-Hant.md) · [日本語](docs/install.ja.md) · [한국어](docs/install.ko.md) · [Français](docs/install.fr.md) · [Español](docs/install.es.md) |
| Architecture and runtime | [English](docs/cloud.md) · [简体中文](docs/cloud.zh.md) · [繁體中文](docs/cloud.zh-Hant.md) · [日本語](docs/cloud.ja.md) · [한국어](docs/cloud.ko.md) · [Français](docs/cloud.fr.md) · [Español](docs/cloud.es.md) |
| Daily operation | [English](docs/manual.md) · [简体中文](docs/manual.zh.md) · [繁體中文](docs/manual.zh-Hant.md) · [日本語](docs/manual.ja.md) · [한국어](docs/manual.ko.md) · [Français](docs/manual.fr.md) · [Español](docs/manual.es.md) |
| Database migration | [English](docs/database-migration.md) · [简体中文](docs/database-migration.zh.md) · [繁體中文](docs/database-migration.zh-Hant.md) · [日本語](docs/database-migration.ja.md) · [한국어](docs/database-migration.ko.md) · [Français](docs/database-migration.fr.md) · [Español](docs/database-migration.es.md) |
| Storage and file migration | [English](docs/storage.md) · [简体中文](docs/storage.zh.md) · [繁體中文](docs/storage.zh-Hant.md) · [日本語](docs/storage.ja.md) · [한국어](docs/storage.ko.md) · [Français](docs/storage.fr.md) · [Español](docs/storage.es.md) |
| Serverless hosting | [English](docs/serverless-hosting.md) · [简体中文](docs/serverless-hosting.zh.md) · [繁體中文](docs/serverless-hosting.zh-Hant.md) · [日本語](docs/serverless-hosting.ja.md) · [한국어](docs/serverless-hosting.ko.md) · [Français](docs/serverless-hosting.fr.md) · [Español](docs/serverless-hosting.es.md) |
| Optional audio proxy | [English](docs/audio-proxy.md) · [简体中文](docs/audio-proxy.zh.md) · [繁體中文](docs/audio-proxy.zh-Hant.md) · [日本語](docs/audio-proxy.ja.md) · [한국어](docs/audio-proxy.ko.md) · [Français](docs/audio-proxy.fr.md) · [Español](docs/audio-proxy.es.md) |
| Publishing safely | [English](docs/github-publish.md) · [简体中文](docs/github-publish.zh.md) · [繁體中文](docs/github-publish.zh-Hant.md) · [日本語](docs/github-publish.ja.md) · [한국어](docs/github-publish.ko.md) · [Français](docs/github-publish.fr.md) · [Español](docs/github-publish.es.md) |

## License

Mihonban is licensed under the [GNU Affero General Public License v3.0](LICENSE) (`AGPL-3.0-only`). If you modify the software and make it available over a network, the AGPL requires you to offer the corresponding source code of that version.

The license covers this repository's code and safe templates only. It does not grant rights to distribute music or third-party metadata.
