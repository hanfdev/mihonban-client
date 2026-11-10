# Mihonban Client

[English](CLIENT-FORK.md) · [简体中文](CLIENT-FORK.zh.md) · [繁體中文](CLIENT-FORK.zh-Hant.md) · [日本語](CLIENT-FORK.ja.md) · [한국어](CLIENT-FORK.ko.md) · [Français](CLIENT-FORK.fr.md) · [Español](CLIENT-FORK.es.md)

An independent iPhone/iPad client fork of [Mihonban](https://github.com/hanfdev/mihonban), intended for ordinary listeners as well as administrators. The first client revision is based on original Build 95 (`9128f034d3ea52f2eb2e2f01527d6e63b8293126`). The repository retains the upstream history, [AGPL-3.0 license](LICENSE), fonts and third-party notices.

## Personal favorites and shared picks

| | My favorites | Admin picks |
|---|---|---|
| Symbol | Heart | Sparkles |
| Who can change it | Anyone connected to a server | Server administrators |
| Storage | This app installation, separately per server | The server's shared selection |
| Changes sent to the server | None | Existing admin favorites API |
| Offline changes | Supported for locally available library items | Requires the server |

Use the heart in the player or album toolbar, or **Add to my favorites** in an album/song menu. The **Favorites** tab opens **My favorites**; its **Admin picks** link opens the shared list. Administrators use the explicitly labeled **Add to admin picks** / **Remove from admin picks** menu actions. Personal lists support albums, songs, playback, removal and manual ordering.

Favorites are bookmarks, not audio downloads. Offline playback still requires downloaded or cached audio. Local favorites survive app restarts, disconnect/reconnect and clearing the audio cache. They belong to this installation, not to the server. Removing the app removes its local data; no export, cross-device sync or migration from the original app is included in this first version.

The current server protocol supplies roles and shared passwords, not stable personal account IDs. People using the same app installation and server share this installation's local favorites. Different server origins and base paths have independent collections. Switching roles does not create an account; saved entries are displayed only when available in the currently authorized catalog. Temporarily unavailable entries keep their saved IDs without bypassing server permissions.

Personal metadata is written atomically under Application Support, outside the evictable media cache. File operations run off the UI executor. A failed save retains the prior state and reports the failure; a corrupt or unsupported saved file is preserved rather than silently replaced.

## Independent app and builds

- Display name: **Mihonban Client**
- Bundle identifier: `org.mihonban.client.ios`
- Initial marketing version: `0.3.0`; build numbers start independently in this repository.
- Deployment target: iOS/iPadOS 17; native SwiftUI interface and pinned SFBAudioEngine.

The separate bundle identifier allows both apps to be installed together. Their passwords, settings, downloads and favorites are separate. No automatic migration is performed.

The [iOS workflow](.github/workflows/mobile.yml) runs on `main`, builds an unsigned device IPA, and executes iPhone and iPad simulator tests. Download the IPA artifact from a successful run and sign it using your existing installation tool. An unsigned IPA is not an App Store or TestFlight release. Simulator results do not establish physical-device frame rates, real lock-screen routing or future iPadOS behavior.

For a local macOS build, use Xcode with the Swift language features required by the sources; the workflow records the exact CI version (currently Xcode 26.6). Run these commands from the repository root:

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

Keep `-clonedSourcePackagesDirPath .spm` on later build and test commands so they use the patched engine. If a reviewed `ios/Package.resolved` is supplied, copy it into `ios/Mihonban.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/` before resolving packages, as the workflow does. For simulator tests, start `python3 -I ios/tools/fixture-server.py ios/TestFixtures` in another terminal and use an available iPhone or iPad destination.

Keep the checked-in shared font assets and license notices. Regenerate localization with `node ios/tools/export-locales.mjs`; personal client translations are maintained in `ios/tools/personal-locales.json`. Run `python3 ios/tools/check-l10n.py` and `python3 ios/tools/check-fonts.py` before building.

## Scope

This first fork adds device-local personal favorites while keeping the server API and administrator permissions unchanged. Future improvements focus on ordinary listening, reliable playback and offline use, accessibility, and measured performance. Server/web/Android redesigns and unrelated working changes are outside this initial client release.
