# Mihonban Client

[English](CLIENT-FORK.md) · [简体中文](CLIENT-FORK.zh.md) · [繁體中文](CLIENT-FORK.zh-Hant.md) · [日本語](CLIENT-FORK.ja.md) · [한국어](CLIENT-FORK.ko.md) · [Français](CLIENT-FORK.fr.md) · [Español](CLIENT-FORK.es.md)

일반 청취자와 관리자를 위한 [Mihonban](https://github.com/hanfdev/mihonban)의 독립 iPhone/iPad 클라이언트 포크입니다. 첫 클라이언트 버전은 원본 Build 95(`9128f034d3ea52f2eb2e2f01527d6e63b8293126`)를 기반으로 합니다. 업스트림 이력, [AGPL-3.0 라이선스](LICENSE), 글꼴 및 제삼자 고지를 유지합니다.

## 개인 즐겨찾기와 공유 추천

| | 내 즐겨찾기 | 관리자 추천 |
|---|---|---|
| 기호 | 하트 | 반짝임 |
| 변경할 수 있는 사람 | 서버에 연결된 모든 사용자 | 서버 관리자 |
| 저장 위치 | 이 앱 설치의 로컬 데이터, 서버별 구분 | 서버의 공유 선곡 |
| 서버에 전송하는 변경 | 없음 | 기존 관리자 즐겨찾기 API |
| 오프라인 변경 | 로컬 라이브러리에서 이용 가능한 항목 지원 | 서버 연결 필요 |

플레이어 또는 앨범 도구 모음의 하트나 앨범·곡 메뉴의 **내 즐겨찾기에 추가**를 사용하세요. **즐겨찾기** 탭은 **내 즐겨찾기**를 열며, 그 안의 **관리자 추천** 링크로 공유 목록을 볼 수 있습니다. 관리자는 명확히 표시된 **관리자 추천에 추가** / **관리자 추천에서 제거** 메뉴로 공유 선곡을 관리합니다. 개인 목록은 앨범, 곡, 재생, 제거 및 수동 정렬을 지원합니다.

즐겨찾기는 북마크이며 오디오 다운로드가 아닙니다. 오프라인 재생에는 다운로드하거나 캐시한 오디오가 필요합니다. 개인 즐겨찾기는 앱 재시작, 연결 해제 후 재연결, 오디오 캐시 삭제 후에도 유지됩니다. 서버가 아닌 이 앱 설치에 속합니다. 앱을 삭제하면 로컬 데이터도 삭제됩니다. 첫 버전은 내보내기, 기기 간 동기화 또는 원본 앱에서의 이전을 제공하지 않습니다.

현재 서버 프로토콜은 역할과 공유 비밀번호를 제공하며, 고정된 개인 계정 ID는 제공하지 않습니다. 같은 앱 설치에서 같은 서버를 사용하는 사람은 해당 설치의 로컬 즐겨찾기를 공유합니다. 서버 출처나 기본 경로가 다르면 별도의 모음을 사용합니다. 역할 전환은 계정을 생성하지 않습니다. 저장한 항목은 현재 권한이 허용하는 라이브러리에서 이용할 수 있을 때만 표시됩니다. 일시적으로 이용할 수 없는 항목의 ID는 보존하지만 서버 권한을 우회하지 않습니다.

개인 메타데이터는 삭제 가능한 미디어 캐시 바깥의 Application Support에 원자적으로 기록합니다. 파일 작업은 UI 실행기 밖에서 수행합니다. 저장에 실패하면 이전 상태를 유지하고 오류를 알립니다. 손상되었거나 지원하지 않는 버전의 파일은 알림 없이 덮어쓰지 않고 보존합니다.

## 독립 앱과 빌드

- 표시 이름: **Mihonban Client**
- 번들 식별자: `org.mihonban.client.ios`
- 초기 버전: `0.3.0`. 빌드 번호는 이 저장소에서 독립적으로 시작합니다.
- 지원 대상: iOS/iPadOS 17 이상. 네이티브 SwiftUI 인터페이스와 고정된 버전의 SFBAudioEngine을 사용합니다.

별도의 번들 식별자 덕분에 두 앱을 함께 설치할 수 있습니다. 비밀번호, 설정, 다운로드 및 즐겨찾기는 서로 분리되며 자동 이전은 수행하지 않습니다.

[iOS 워크플로](.github/workflows/mobile.yml)는 `main`에서 실행되어 서명되지 않은 기기용 IPA를 빌드하고 iPhone 및 iPad 시뮬레이터 테스트를 수행합니다. 성공한 실행에서 IPA 결과물을 내려받아 기존 설치 도구로 서명하세요. 서명되지 않은 IPA는 App Store나 TestFlight 출시물이 아닙니다. 시뮬레이터 결과만으로 실제 기기의 프레임 속도, 실제 잠금 화면 라우팅 또는 향후 iPadOS의 동작을 입증할 수 없습니다.

macOS에서 로컬로 빌드하려면 소스에 필요한 Swift 언어 기능을 지원하는 Xcode를 사용하세요. CI의 정확한 버전은 워크플로에 기록되어 있습니다(현재 Xcode 26.6). 저장소 루트에서 다음을 실행하세요.

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

후속 빌드와 테스트 명령에도 `-clonedSourcePackagesDirPath .spm`을 유지해 패치된 엔진을 사용하세요. 검토된 `ios/Package.resolved`가 있다면 워크플로처럼 의존성을 확인하기 전에 `ios/Mihonban.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`에 복사하세요. 시뮬레이터 테스트는 다른 터미널에서 `python3 -I ios/tools/fixture-server.py ios/TestFixtures`를 시작하고 사용 가능한 iPhone 또는 iPad 대상을 선택해 실행합니다.

저장소의 공유 글꼴과 라이선스 고지를 유지해야 합니다. `node ios/tools/export-locales.mjs`로 번역 리소스를 다시 생성하며, 개인 클라이언트 번역은 `ios/tools/personal-locales.json`에서 관리합니다. 빌드 전에 `python3 ios/tools/check-l10n.py`와 `python3 ios/tools/check-fonts.py`를 실행하세요.

## 범위

첫 포크 버전은 서버 API와 관리자 권한을 유지하면서 기기 로컬 개인 즐겨찾기를 추가합니다. 이후 개선은 일상적인 음악 감상, 안정적인 재생과 오프라인 사용, 접근성 및 측정에 기반한 성능에 집중합니다. 서버·웹·Android 재설계와 관련 없는 작업 중 변경 사항은 첫 클라이언트 릴리스의 범위에 포함되지 않습니다.
