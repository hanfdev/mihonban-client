# Mihonban Client

[English](CLIENT-FORK.md) · [简体中文](CLIENT-FORK.zh.md) · [繁體中文](CLIENT-FORK.zh-Hant.md) · [日本語](CLIENT-FORK.ja.md) · [한국어](CLIENT-FORK.ko.md) · [Français](CLIENT-FORK.fr.md) · [Español](CLIENT-FORK.es.md)

这是 [Mihonban](https://github.com/hanfdev/mihonban) 的独立 iPhone/iPad 客户端分支，面向普通听众和管理员。首个客户端版本基于原项目 Build 95（`9128f034d3ea52f2eb2e2f01527d6e63b8293126`），保留上游历史、[AGPL-3.0 许可证](LICENSE)、字体及第三方声明。

## 个人收藏与共享精选

| | 我的收藏 | 管理员精选 |
|---|---|---|
| 图标 | 爱心 | 闪光 |
| 谁可以修改 | 任何已连接服务器的用户 | 服务器管理员 |
| 存储位置 | 当前应用安装，按服务器分别保存 | 服务器的共享精选 |
| 是否向服务器发送更改 | 否 | 使用现有管理员精选 API |
| 离线修改 | 支持本地曲库中可用的条目 | 需要连接服务器 |

点击播放页或专辑工具栏中的爱心，也可在专辑或歌曲菜单中选择**添加到我的收藏**。**收藏**标签打开**我的收藏**，其中的**管理员精选**链接打开共享列表。管理员通过明确标注的**添加到管理员精选**／**从管理员精选移除**菜单操作管理共享内容。个人列表支持专辑、歌曲、播放、移除和手动排序。

收藏保存的是书签，不会下载音频。离线播放仍需已下载或缓存的音频。个人收藏在应用重启、断开后重新连接、清理音频缓存后保留。它属于当前应用安装，而非服务器。卸载应用会删除本地数据；首个版本不包含导出、跨设备同步或从原应用迁移。

当前服务器协议提供访问角色和共享密码，而非稳定的个人账户 ID。同一应用安装中使用同一服务器的人共享本机收藏。不同服务器来源和基础路径拥有独立收藏。切换角色不会创建账户；收藏条目只在当前授权曲库允许访问时显示。暂时不可用的条目保留已保存的 ID，不会绕过服务器权限。

个人元数据以原子方式写入 Application Support，位于可清理的媒体缓存之外。文件操作在界面执行器之外运行。保存失败会保留原状态并报告错误；损坏或版本不受支持的文件会被保留，不会被静默替换。

## 独立应用与构建

- 显示名称：**Mihonban Client**
- Bundle 标识符：`org.mihonban.client.ios`
- 初始版本号：`0.3.0`；构建号在本仓库独立计数。
- 最低系统：iOS/iPadOS 17；使用原生 SwiftUI 界面及固定版本的 SFBAudioEngine。

独立的 Bundle 标识符允许两个应用同时安装。密码、设置、下载和收藏相互独立，不执行自动迁移。

[iOS 工作流](.github/workflows/mobile.yml)在 `main` 分支运行，构建未签名的设备 IPA，并执行 iPhone 和 iPad 模拟器测试。从成功的运行中下载 IPA 产物，使用现有安装工具签名。未签名 IPA 并不是 App Store 或 TestFlight 发布版本。模拟器结果不能证明真机帧率、真实锁屏路由或未来 iPadOS 的行为。

在 macOS 本地构建时，需要使用支持源代码所需 Swift 语言特性的 Xcode；工作流记录了 CI 使用的确切版本（目前为 Xcode 26.6）。从仓库根目录执行：

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

后续构建和测试命令保留 `-clonedSourcePackagesDirPath .spm`，确保使用已修补的音频引擎。如果提供了已审查的 `ios/Package.resolved`，请按工作流的方式，在解析依赖前复制到 `ios/Mihonban.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`。运行模拟器测试前，在另一终端启动 `python3 -I ios/tools/fixture-server.py ios/TestFixtures`，并选择可用的 iPhone 或 iPad 目标。

保留仓库中的共享字体资源和许可证声明。使用 `node ios/tools/export-locales.mjs` 重新生成本地化；个人客户端译文维护在 `ios/tools/personal-locales.json`。构建前运行 `python3 ios/tools/check-l10n.py` 和 `python3 ios/tools/check-fonts.py`。

## 范围

首个分支版本增加设备本地个人收藏，保持服务器 API 和管理员权限不变。后续改进聚焦日常听歌、可靠播放与离线使用、无障碍及有测量依据的性能优化。服务器、网页或 Android 的重新设计，以及其他无关的工作区改动，不属于首次客户端发布范围。
