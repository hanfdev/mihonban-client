# Mihonban Client

[English](README.md) · [简体中文](README.zh.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Español](README.es.md)

このリポジトリでは、一般リスナーを含む Mihonban サーバーの利用者向けに、独立した iPhone/iPad クライアントのフォークを開発しています。元のクライアントで検証済みの Build 95 を出発点とし、上流のソース履歴と AGPL-3.0 ライセンスを継承します。

**自分のお気に入り**は端末内に保存するアルバムと曲のブックマークで、サーバーごとに管理します。**管理者のおすすめ**は引き続き管理者が編集するサーバー共有の選曲です。個人のお気に入りはオフラインでも変更でき、共有の選曲を変更したり音声をダウンロードしたりしません。現在のサーバーは個人アカウントではなくアクセス権限を識別するため、端末間の同期やアカウント単位の分離は提供しません。

アプリの識別子は `org.mihonban.client.ios`、表示名は **Mihonban Client** で、元のアプリと同時にインストールできます。[対象範囲・保存・ビルドの説明](CLIENT-FORK.ja.md)と[クライアントのビルド成果物](https://github.com/hanfdev/mihonban-client/actions/workflows/mobile.yml)を参照してください。成功した CI 実行から未署名 IPA を取得できます。インストール前に署名が必要です。

以下の継承ドキュメントは、より広い [Mihonban サーバープロジェクト](https://github.com/hanfdev/mihonban)を説明しています。サーバー、Web、デスクトップ、Android のソースは上流の背景資料として残します。このフォークの初期開発対象は iOS/iPadOS クライアントです。

Mihonban は、レスポンシブな Web プレーヤーを備えた、個人向けのセルフホスト型音楽ライブラリです。Node と SQLite を使ったローカル実行、Wrangler のローカル D1 エミュレーター、Cloudflare Workers と D1 へのデプロイに対応しています。音声ファイルは、常に自分で管理するストレージに保管されます。

## 主な機能

- アルバム、トラック、アーティスト、お気に入り、インポート、管理画面に対応したレスポンシブ UI
- アルバムの順序付き複数アーティスト表記と曲ごとのコラボレーション表記に対応し、各アーティストを個別に検索・表示・プレーヤーから移動可能
- リスナー用・管理者用パスワードと、任意で有効にできるパスワード不要の読み取り専用ゲストモード
- 永続的な再生キュー、モバイルの前の曲／再生・一時停止／次の曲の完全な操作、ユーザー操作内で開始する再生、シャッフル／リピート、Range シーク、Media Session
- `desktop/` にあるネイティブ Windows デスクトップクライアント（egui + Rodio）。インストール不要のポータブル exe として [Releases ページ](https://github.com/hanfdev/mihonban/releases) で配布
- OneDrive、WebDAV、Google Drive、Node 専用ローカルフォルダーを名前付きストレージとして管理
- カバー、ギャラリー、アーティスト画像を配信し、自動復旧できる任意の R2 イメージミラー
- Discogs API からのインポートと、自動アクセスを行わない手動保存 RYM HTML の解析
- 受信トレイ、単一／多重圧縮アーカイブ、タグ修復、クラウド同期に対応する任意の Python コンパニオン
- 英語、簡体字中国語、繁体字中国語、日本語、韓国語、フランス語、スペイン語の UI
- SQLite／D1 移行ツールと、任意で利用できる署名付き音声プロキシ Worker

## 実行環境

| 実行環境 | メタデータ DB | ファイルストレージ | 主な用途 |
|---|---|---|---|
| Node | `<DATA_DIR>/mihonban.sqlite` | OneDrive、WebDAV、Google Drive、ローカルフォルダー | LAN、NAS、VPS |
| ローカル Wrangler | `.wrangler/` 内のローカル D1／KV | OneDrive、WebDAV、Google Drive | Cloudflare 互換の開発環境 |
| Cloudflare | D1 + KV、任意で R2 | OneDrive、WebDAV、Google Drive | 常時稼働のサーバーレス環境 |

Python コンパニオンは、どの実行環境でも任意です。ローカル受信トレイの監視、アーカイブ展開、タグ整理、ローカルとクラウドの同期が必要な場合にだけインストールしてください。

## クイックスタート

公式リポジトリをクローンします。

```bash
git clone https://github.com/hanfdev/mihonban.git
cd mihonban
```

### ローカル Wrangler アプリ

Windows では、補助スクリプトが OneDrive の外へビルドファイルを配置し、Wrangler を起動します。

```powershell
tools\cloud-dev.cmd
```

`http://127.0.0.1:8787` を開きます。開発サーバーはデフォルトでは `http://127.0.0.1:8787`（ループバック）のみで待ち受けます。`MIHONBAN_DEV_LAN=1` を設定し、Windows ファイアウォールで Node.js を許可すると、同じ LAN 内のスマートフォンから `http://<computer-lan-ip>:8787` でテストできます。補助スクリプトが最初に生成するシークレットファイルには、ランダムに生成されたリスナーパスワードと管理者パスワードが含まれます（ステージディレクトリの `.dev.vars` を参照）。サービスを共有する前に、管理画面で両方を変更してください。

手動で Wrangler を設定する場合は、[インストールとデプロイ](docs/install.ja.md)を参照してください。

### ローカル Node + SQLite アプリ

```bash
cd cloud/web
npm ci
npm run build
cd ../worker
npm ci
# .env.example を .env にコピーし、すべてのプレースホルダーを置き換えます。ローカル HTTP では DEV_INSECURE_COOKIE=1 を設定します。
npm run node
```

Node は既定で `0.0.0.0:8788` をリッスンします。`DATA_DIR` を設定しない場合、データベースは `cloud/worker/data/mihonban.sqlite` に作成されます。Node には組み込みパスワードがないため、`.env` で `APP_PASSWORD`、`ADMIN_PASSWORD`、32 文字以上の `SESSION_SECRET` を設定する必要があります。

### Cloudflare

Web アプリをビルドし、D1 と KV を作成して Worker のシークレットを設定し、`schema.sql` を適用してデプロイします。標準手順は手動デプロイであり、ローカルの Python コンパニオンは必須ではありません。既存のローカルカタログを移行する前に、[インストールとデプロイ](docs/install.ja.md)および[データベース移行](docs/database-migration.ja.md)を確認してください。

### 任意の Python コンパニオン

```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
# POSIX:   source .venv/bin/activate
pip install -e ./pipeline
mihonban setup
mihonban doctor
```

`music_root`、`data_dir`、データベース、一時ファイルは、OneDrive、Dropbox、iCloud などの同期フォルダーの外に置いてください。

## データとバックアップ

| データ | 正本 | バックアップ方法 |
|---|---|---|
| アルバム、トラック、アーティスト、お気に入り、ノート | Node SQLite または D1 | SQLite 対応バックアップまたは論理 SQL エクスポート |
| 名前付きストレージ、R2、モジュール設定 | データベース内の設定 | 管理画面の設定 JSON。暗号化して保管 |
| 初期パスワード、セッション、コンパニオン、プロキシのシークレット | 実行環境 | パスワードマネージャーへ別途記録 |
| 音声とオリジナル画像 | 設定したストレージバックエンド | ストレージ側で独立してバックアップ |
| R2 イメージミラーと KV キャッシュ | 再構築可能なキャッシュ | 同じ R2 バケットならインデックスを移行／再取得。新しいバケットなら再度プリウォーム。KV は移行しない |

管理画面の設定 JSON はカタログのバックアップではなく、データベースのバックアップにも音声ファイルは含まれません。

## リポジトリ構成

| パス | 用途 |
|---|---|
| `cloud/web/` | React プレーヤーと管理 UI |
| `cloud/worker/` | Hono API、D1 スキーマ、Node 互換ランタイム |
| `cloud/proxy-worker/` | 任意の署名付き音声リレー |
| `desktop/` | ネイティブ Windows デスクトップクライアント（Rust、egui） |
| `pipeline/` | Python の `mihonban` CLI と取り込み／同期パイプライン |
| `config/` | 安全な設定テンプレート |
| `tools/` | ローカル開発、デプロイ、監視、移行用の補助ツール |
| `tests/` | Python 回帰テスト |

## よく使うコマンド

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

## セキュリティ

- `.dev.vars`、`.env`、`mihonban.toml`、`rclone.conf`、データベース、設定エクスポート、トークン、音声ファイルをコミットしないでください。
- ローカル HTTP では `DEV_INSECURE_COOKIE=1` が必要です。公開環境では HTTPS を使用し、この変数は設定しないでください。
- 管理画面で保存したパスワードは、実行環境の初期パスワードより優先され、既存のセッションを無効にします。
- 外部プロキシを有効にする場合は、`STREAM_PROXY_SECRET` と `PROXY_SECRET` を同一の値にし、非公開で保管してください。
- RYM 機能は、利用者が手動保存したファイルだけを解析します。このリポジトリに RYM クローラーは含まれません。
- 失うことのできない音声は、必ず少なくとも 1 つ別の場所にも保管してください。

## ドキュメント

| ガイド | 言語 |
|---|---|
| インストールとデプロイ | [English](docs/install.md) · [简体中文](docs/install.zh.md) · [繁體中文](docs/install.zh-Hant.md) · [日本語](docs/install.ja.md) · [한국어](docs/install.ko.md) · [Français](docs/install.fr.md) · [Español](docs/install.es.md) |
| アーキテクチャと実行環境 | [English](docs/cloud.md) · [简体中文](docs/cloud.zh.md) · [繁體中文](docs/cloud.zh-Hant.md) · [日本語](docs/cloud.ja.md) · [한국어](docs/cloud.ko.md) · [Français](docs/cloud.fr.md) · [Español](docs/cloud.es.md) |
| 日常運用 | [English](docs/manual.md) · [简体中文](docs/manual.zh.md) · [繁體中文](docs/manual.zh-Hant.md) · [日本語](docs/manual.ja.md) · [한국어](docs/manual.ko.md) · [Français](docs/manual.fr.md) · [Español](docs/manual.es.md) |
| データベース移行 | [English](docs/database-migration.md) · [简体中文](docs/database-migration.zh.md) · [繁體中文](docs/database-migration.zh-Hant.md) · [日本語](docs/database-migration.ja.md) · [한국어](docs/database-migration.ko.md) · [Français](docs/database-migration.fr.md) · [Español](docs/database-migration.es.md) |
| ストレージとファイル移行 | [English](docs/storage.md) · [简体中文](docs/storage.zh.md) · [繁體中文](docs/storage.zh-Hant.md) · [日本語](docs/storage.ja.md) · [한국어](docs/storage.ko.md) · [Français](docs/storage.fr.md) · [Español](docs/storage.es.md) |
| サーバーレスホスティング | [English](docs/serverless-hosting.md) · [简体中文](docs/serverless-hosting.zh.md) · [繁體中文](docs/serverless-hosting.zh-Hant.md) · [日本語](docs/serverless-hosting.ja.md) · [한국어](docs/serverless-hosting.ko.md) · [Français](docs/serverless-hosting.fr.md) · [Español](docs/serverless-hosting.es.md) |
| 任意の音声プロキシ | [English](docs/audio-proxy.md) · [简体中文](docs/audio-proxy.zh.md) · [繁體中文](docs/audio-proxy.zh-Hant.md) · [日本語](docs/audio-proxy.ja.md) · [한국어](docs/audio-proxy.ko.md) · [Français](docs/audio-proxy.fr.md) · [Español](docs/audio-proxy.es.md) |
| 安全な公開手順 | [English](docs/github-publish.md) · [简体中文](docs/github-publish.zh.md) · [繁體中文](docs/github-publish.zh-Hant.md) · [日本語](docs/github-publish.ja.md) · [한국어](docs/github-publish.ko.md) · [Français](docs/github-publish.fr.md) · [Español](docs/github-publish.es.md) |

## ライセンス

Mihonban は [GNU Affero General Public License v3.0](LICENSE)（`AGPL-3.0-only`）の下でライセンスされています。ソフトウェアを変更し、ネットワーク経由で利用可能にした場合、AGPL により、そのバージョンに対応するソースコードの提供が求められます。

このライセンスが対象とするのは、このリポジトリのコードと安全なテンプレートだけです。音楽や第三者のメタデータを配布する権利は付与されません。
