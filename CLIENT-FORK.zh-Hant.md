# Mihonban Client

[English](CLIENT-FORK.md) · [简体中文](CLIENT-FORK.zh.md) · [繁體中文](CLIENT-FORK.zh-Hant.md) · [日本語](CLIENT-FORK.ja.md) · [한국어](CLIENT-FORK.ko.md) · [Français](CLIENT-FORK.fr.md) · [Español](CLIENT-FORK.es.md)

這是 [Mihonban](https://github.com/hanfdev/mihonban) 的獨立 iPhone/iPad 用戶端分支，面向一般聽眾和管理員。首個用戶端版本基於原專案 Build 95（`9128f034d3ea52f2eb2e2f01527d6e63b8293126`），保留上游歷史、[AGPL-3.0 授權條款](LICENSE)、字型及第三方聲明。

## 個人收藏與共享精選

| | 我的收藏 | 管理員精選 |
|---|---|---|
| 圖示 | 愛心 | 閃光 |
| 誰可以修改 | 任何已連接伺服器的使用者 | 伺服器管理員 |
| 儲存位置 | 目前應用程式安裝，依伺服器分別儲存 | 伺服器的共享精選 |
| 是否向伺服器傳送變更 | 否 | 使用現有管理員精選 API |
| 離線修改 | 支援本機曲庫中可用的項目 | 需要連接伺服器 |

點選播放頁或專輯工具列中的愛心，也可在專輯或歌曲選單中選擇**加入我的收藏**。**收藏**分頁開啟**我的收藏**，其中的**管理員精選**連結開啟共享清單。管理員透過明確標示的**加入管理員精選**／**從管理員精選移除**選單操作管理共享內容。個人清單支援專輯、歌曲、播放、移除和手動排序。

收藏儲存的是書籤，不會下載音訊。離線播放仍需已下載或快取的音訊。個人收藏在應用程式重啟、中斷後重新連接、清除音訊快取後保留。它屬於目前應用程式安裝，而非伺服器。移除應用程式會刪除本機資料；首個版本不包含匯出、跨裝置同步或從原應用程式移轉。

目前伺服器協定提供存取角色和共用密碼，而非穩定的個人帳戶 ID。同一應用程式安裝中使用同一伺服器的人共用本機收藏。不同伺服器來源和基礎路徑擁有獨立收藏。切換角色不會建立帳戶；收藏項目只在目前授權曲庫允許存取時顯示。暫時不可用的項目保留已儲存的 ID，不會繞過伺服器權限。

個人中繼資料以不可分割的寫入方式儲存於 Application Support，位於可清除的媒體快取之外。檔案操作在介面執行器之外執行。儲存失敗會保留原狀態並回報錯誤；損壞或版本不受支援的檔案會被保留，不會被無聲取代。

## 獨立應用程式與建置

- 顯示名稱：**Mihonban Client**
- Bundle 識別碼：`org.mihonban.client.ios`
- 初始版本號：`0.3.0`；建置號在本儲存庫獨立計數。
- 最低系統：iOS/iPadOS 17；使用原生 SwiftUI 介面及固定版本的 SFBAudioEngine。

獨立的 Bundle 識別碼允許兩個應用程式同時安裝。密碼、設定、下載和收藏相互獨立，不執行自動移轉。

[iOS 工作流程](.github/workflows/mobile.yml)在 `main` 分支執行，建置未簽署的裝置 IPA，並執行 iPhone 和 iPad 模擬器測試。從成功的執行中下載 IPA 產物，使用現有安裝工具簽署。未簽署 IPA 並不是 App Store 或 TestFlight 發行版本。模擬器結果不能證明實機影格率、真實鎖定畫面路由或未來 iPadOS 的行為。

在 macOS 本機建置時，需要使用支援原始碼所需 Swift 語言功能的 Xcode；工作流程記錄了 CI 使用的確切版本（目前為 Xcode 26.6）。從儲存庫根目錄執行：

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

後續建置和測試命令保留 `-clonedSourcePackagesDirPath .spm`，確保使用已修補的音訊引擎。如果提供了已審查的 `ios/Package.resolved`，請依工作流程的方式，在解析相依套件前複製到 `ios/Mihonban.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`。執行模擬器測試前，在另一終端啟動 `python3 -I ios/tools/fixture-server.py ios/TestFixtures`，並選擇可用的 iPhone 或 iPad 目標。

保留儲存庫中的共用字型資源和授權聲明。使用 `node ios/tools/export-locales.mjs` 重新產生在地化；個人用戶端譯文維護於 `ios/tools/personal-locales.json`。建置前執行 `python3 ios/tools/check-l10n.py` 和 `python3 ios/tools/check-fonts.py`。

## 範圍

首個分支版本增加裝置本機個人收藏，保持伺服器 API 和管理員權限不變。後續改進聚焦日常聆聽、可靠播放與離線使用、輔助使用及有測量依據的效能最佳化。伺服器、網頁或 Android 的重新設計，以及其他無關的工作區變更，不屬於首次用戶端發行範圍。
