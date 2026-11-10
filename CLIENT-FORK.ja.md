# Mihonban Client

[English](CLIENT-FORK.md) · [简体中文](CLIENT-FORK.zh.md) · [繁體中文](CLIENT-FORK.zh-Hant.md) · [日本語](CLIENT-FORK.ja.md) · [한국어](CLIENT-FORK.ko.md) · [Français](CLIENT-FORK.fr.md) · [Español](CLIENT-FORK.es.md)

一般リスナーと管理者のための、[Mihonban](https://github.com/hanfdev/mihonban) から独立した iPhone/iPad クライアントのフォークです。初版は元の Build 95（`9128f034d3ea52f2eb2e2f01527d6e63b8293126`）を基盤とし、上流の履歴、[AGPL-3.0 ライセンス](LICENSE)、フォント、第三者の権利表示を継承します。

## 個人のお気に入りと共有のおすすめ

| | 自分のお気に入り | 管理者のおすすめ |
|---|---|---|
| 記号 | ハート | きらめき |
| 編集できる人 | サーバーに接続しているすべての人 | サーバー管理者 |
| 保存先 | このアプリのインストール内、サーバーごと | サーバーの共有選曲 |
| サーバーへの変更送信 | なし | 既存の管理者用お気に入り API |
| オフラインでの変更 | ローカルライブラリで利用可能な項目に対応 | サーバー接続が必要 |

プレーヤーやアルバムのツールバーにあるハート、またはアルバム・曲のメニューの**自分のお気に入りに追加**を使います。**お気に入り**タブは**自分のお気に入り**を開き、その中の**管理者のおすすめ**リンクで共有リストを開けます。管理者は、明示された**管理者のおすすめに追加**／**管理者のおすすめから削除**のメニューで共有内容を編集します。個人リストはアルバム、曲、再生、削除、手動並べ替えに対応します。

お気に入りはブックマークであり、音声のダウンロードではありません。オフライン再生には、ダウンロード済みまたはキャッシュ済みの音声が必要です。アプリの再起動、切断と再接続、音声キャッシュの消去後も個人のお気に入りは残ります。保存先はサーバーではなく、このアプリのインストールです。アプリを削除するとローカルデータも失われます。初版にはエクスポート、端末間同期、元のアプリからの移行は含まれません。

現在のサーバープロトコルは権限と共有パスワードを提供し、安定した個人アカウント ID は提供しません。同じアプリのインストールで同じサーバーを利用する人は、端末内のお気に入りを共有します。サーバーのオリジンやベースパスが異なれば、保存先も分かれます。権限の切り替えでアカウントが作られることはありません。保存した項目は、現在許可されているライブラリで利用可能な場合のみ表示します。一時的に利用できない項目の ID は保持しますが、サーバーの権限を回避しません。

個人メタデータは、削除可能なメディアキャッシュの外にある Application Support にアトミックに保存します。ファイル操作は UI の実行系の外で行います。保存に失敗した場合は以前の状態を保持してエラーを通知します。破損したファイルや非対応バージョンのファイルは、無断で置き換えず保存します。

## 独立したアプリとビルド

- 表示名：**Mihonban Client**
- Bundle 識別子：`org.mihonban.client.ios`
- 初期バージョン：`0.3.0`。ビルド番号はこのリポジトリで独立して付けます。
- 対応 OS：iOS/iPadOS 17 以降。ネイティブ SwiftUI と固定版 SFBAudioEngine を使用します。

別の Bundle 識別子により、両方のアプリを同時にインストールできます。パスワード、設定、ダウンロード、お気に入りはそれぞれ独立し、自動移行は行いません。

[iOS ワークフロー](.github/workflows/mobile.yml)は `main` で実行し、実機用の未署名 IPA をビルドして、iPhone と iPad のシミュレーターテストを行います。成功した実行の IPA 成果物を取得し、普段のインストールツールで署名してください。未署名 IPA は App Store や TestFlight のリリースではありません。シミュレーターの結果は、実機のフレームレート、実際のロック画面ルーティング、将来の iPadOS の動作を保証しません。

macOS でローカルビルドする場合は、ソースが必要とする Swift の言語機能に対応した Xcode を使用してください。CI の正確なバージョンはワークフローに記録されています（現在は Xcode 26.6）。リポジトリのルートで次を実行します。

```sh
brew install xcodegen ffmpeg
python3 -I ios/tools/check-l10n.py
python3 -I ios/tools/check-fonts.py
mkdir -p ios/TestFixtures ios/Resources/ThirdParty
ffmpeg -v error -f lavfi -i 'sine=frequency=440:duration=8:sample_rate=44100' -ac 2 -c:a libmp3lame -q:a 3 ios/TestFixtures/tone.mp3
ffmpeg -v error -f lavfi -i 'sine=frequency=440:duration=8:sample_rate=44100' -ac 2 -c:a flac ios/TestFixtures/tone.flac
ffmpeg -v error -f lavfi -i 'sine=frequency=440:duration=8:sample_rate=44100' -ac 2 -c:a vorbis -strict experimental -q:a 4 ios/TestFixtures/tone.ogg
xcodegen generate --spec ios/project.yml
xcodebuild -resolvePackageDependencies -project ios/Mihonban.xcodeproj -scheme Mihonban -clonedSourcePackagesDirPath .spm
python3 -I ios/tools/apply-audio-engine-fixes.py .spm/checkouts/SFBAudioEngine
python3 -I ios/tools/acknowledgements.py .spm/checkouts ios/Resources/ThirdParty/Acknowledgements.txt
xcodegen generate --spec ios/project.yml
xcodebuild build -project ios/Mihonban.xcodeproj -scheme Mihonban -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/Simulator -clonedSourcePackagesDirPath .spm \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
```

以降のビルドとテストでも `-clonedSourcePackagesDirPath .spm` を指定し、修正済みのエンジンを使用してください。確認済みの `ios/Package.resolved` がある場合は、ワークフローと同様に依存関係の解決前に `ios/Mihonban.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/` へコピーします。シミュレーターテストでは、別の端末で `python3 -I ios/tools/fixture-server.py ios/TestFixtures` を起動し、利用可能な iPhone または iPad を実行先に選びます。

リポジトリの共有フォントとライセンス表示を保持します。翻訳データの再生成には `node ios/tools/export-locales.mjs` を使います。個人クライアントの翻訳は `ios/tools/personal-locales.json` で管理します。ビルド前に `python3 ios/tools/check-l10n.py` と `python3 ios/tools/check-fonts.py` を実行してください。

## 対象範囲

初版は、サーバー API と管理者権限を維持しながら、端末内の個人のお気に入りを追加します。今後は日常の音楽再生、安定した再生とオフライン利用、アクセシビリティ、測定に基づく性能改善に取り組みます。サーバー・Web・Android の再設計や、無関係な作業中の変更は、最初のクライアントリリースの対象外です。
