# Mihonban Client

[English](README.md) · [简体中文](README.zh.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Español](README.es.md)

이 저장소는 일반 청취자를 포함해 Mihonban 서버에서 음악을 듣는 사용자를 위한 독립 iPhone/iPad 클라이언트 포크를 개발합니다. 원본 클라이언트에서 검증한 Build 95를 기반으로 하며, 업스트림 소스 이력과 AGPL-3.0 라이선스를 유지합니다.

**내 즐겨찾기**는 기기에 저장하는 앨범과 곡의 북마크이며 서버별로 구분됩니다. **관리자 추천**은 관리자가 관리하는 서버의 공유 선곡으로 유지됩니다. 개인 즐겨찾기는 오프라인에서도 변경할 수 있고, 공유 추천을 바꾸거나 오디오를 다운로드하지 않습니다. 현재 서버는 개인 계정이 아닌 접근 역할만 식별하므로 기기 간 동기화나 계정별 분리를 제공하지 않습니다.

앱 식별자는 `org.mihonban.client.ios`, 표시 이름은 **Mihonban Client**이며 원본 앱과 함께 설치할 수 있습니다. [클라이언트 범위, 저장 및 빌드 안내](CLIENT-FORK.ko.md)와 [클라이언트 빌드 결과물](https://github.com/hanfdev/mihonban-client/actions/workflows/mobile.yml)을 참고하세요. 성공한 CI 실행은 서명되지 않은 IPA를 제공하며, 설치 전에 서명이 필요합니다.

아래에 유지된 기존 문서는 더 넓은 [Mihonban 서버 프로젝트](https://github.com/hanfdev/mihonban)를 설명합니다. 서버, 웹, 데스크톱 및 Android 소스는 업스트림 참고 자료로 남겨 두며, 이 포크의 초기 개발 범위는 iOS/iPadOS 클라이언트입니다.

Mihonban은 반응형 웹 플레이어를 제공하는 개인용 셀프 호스팅 음악 라이브러리입니다. Node와 SQLite로 로컬에서 실행하거나, Wrangler의 로컬 D1 에뮬레이터를 사용하거나, 같은 애플리케이션을 Cloudflare Workers와 D1에 배포할 수 있습니다. 오디오 파일은 사용자가 직접 관리하는 저장소에 그대로 보관됩니다.

## 주요 기능

- 앨범, 트랙, 아티스트, 즐겨찾기, 가져오기, 관리 화면을 위한 반응형 UI
- 순서가 유지되는 앨범 다중 아티스트 크레딧과 트랙별 협업 아티스트 재정의, 아티스트별 검색·페이지·플레이어 링크
- 청취자 및 관리자 비밀번호와 선택적으로 사용할 수 있는 비밀번호 없는 읽기 전용 게스트 모드
- 영구 재생 대기열, 모바일 이전 곡／재생·일시 정지／다음 곡 전체 제어, 사용자 동작 안에서 시작되는 재생, 셔플／반복, Range 탐색, Media Session 제어
- `desktop/`의 네이티브 Windows 데스크톱 클라이언트(egui + Rodio), 설치가 필요 없는 포터블 exe로 [Releases 페이지](https://github.com/hanfdev/mihonban/releases)에서 배포
- OneDrive, WebDAV, Google Drive와 Node 전용 로컬 폴더를 이름 있는 저장소로 관리
- 표지, 갤러리, 아티스트 이미지를 위한 자동 복구 R2 이미지 미러
- Discogs API 가져오기와 자동 RYM 요청 없이 수동 저장된 RYM HTML 분석
- 받은편지함 폴더, 단일／중첩 압축 파일, 태그 복구, 클라우드 동기화를 처리하는 선택적 Python 컴패니언
- 영어, 중국어 간체, 중국어 번체, 일본어, 한국어, 프랑스어, 스페인어 UI
- SQLite／D1 마이그레이션 도구와 선택적 서명 오디오 프록시 Worker

## 실행 환경

| 실행 환경 | 메타데이터 DB | 파일 저장소 | 일반적인 용도 |
|---|---|---|---|
| Node | `<DATA_DIR>/mihonban.sqlite` | OneDrive, WebDAV, Google Drive, 로컬 폴더 | 로컬 네트워크, NAS, VPS |
| 로컬 Wrangler | `.wrangler/`의 로컬 D1／KV | OneDrive, WebDAV, Google Drive | Cloudflare 호환 개발 환경 |
| Cloudflare | D1 + KV, 선택적 R2 | OneDrive, WebDAV, Google Drive | 상시 온라인 서버리스 배포 |

Python 컴패니언은 모든 실행 환경에서 선택 사항입니다. 로컬 받은편지함 감시, 압축 파일 해제, 태그 정리, 로컬과 클라우드 간 동기화가 필요할 때만 설치하세요.

## 빠른 시작

공식 저장소를 복제합니다.

```bash
git clone https://github.com/hanfdev/mihonban.git
cd mihonban
```

### 로컬 Wrangler 앱

Windows에서는 도우미가 OneDrive 외부에 빌드 파일을 준비하고 Wrangler를 시작합니다.

```powershell
tools\cloud-dev.cmd
```

`http://127.0.0.1:8787`을 여세요. 개발 서버는 기본적으로 `http://127.0.0.1:8787`(루프백)에서만 수신합니다. `MIHONBAN_DEV_LAN=1`을 설정하고 Windows 방화벽에서 Node.js를 허용하면 같은 LAN의 휴대폰에서 `http://<computer-lan-ip>:8787`로 테스트할 수 있습니다. 도우미가 처음 생성하는 시크릿 파일에는 무작위로 생성된 청취자 비밀번호와 관리자 비밀번호가 들어 있습니다(스테이지 디렉터리의 `.dev.vars` 참조). 서비스를 공유하기 전에 관리 화면에서 두 비밀번호를 모두 변경하세요.

Wrangler를 수동으로 설정하려면 [설치 및 배포](docs/install.ko.md)를 참고하세요.

### 로컬 Node + SQLite 앱

```bash
cd cloud/web
npm ci
npm run build
cd ../worker
npm ci
# .env.example을 .env로 복사하고 모든 자리 표시자를 바꿉니다. 로컬 HTTP에서는 DEV_INSECURE_COOKIE=1을 설정합니다.
npm run node
```

Node는 기본적으로 `0.0.0.0:8788`에서 수신합니다. `DATA_DIR`을 설정하지 않으면 데이터베이스는 `cloud/worker/data/mihonban.sqlite`에 생성됩니다. Node에는 기본 비밀번호가 없으므로 `.env`에 `APP_PASSWORD`, `ADMIN_PASSWORD`, 32자 이상의 `SESSION_SECRET`을 정의해야 합니다.

### Cloudflare

웹 앱을 빌드하고 D1과 KV를 만든 다음 Worker 시크릿을 설정하고 `schema.sql`을 적용해 배포합니다. 수동 절차가 표준이며 로컬 Python 컴패니언은 필수가 아닙니다. 기존 로컬 카탈로그를 옮기기 전에 [설치 및 배포](docs/install.ko.md)와 [데이터베이스 마이그레이션](docs/database-migration.ko.md)을 읽어보세요.

### 선택적 Python 컴패니언

```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
# POSIX:   source .venv/bin/activate
pip install -e ./pipeline
mihonban setup
mihonban doctor
```

`music_root`, `data_dir`, 데이터베이스, 임시 파일은 OneDrive, Dropbox, iCloud 등 동기화되는 디렉터리 밖에 보관하세요.

## 데이터와 백업

| 데이터 | 원본 | 백업 방법 |
|---|---|---|
| 앨범, 트랙, 아티스트, 즐겨찾기, 메모 | Node SQLite 또는 D1 | SQLite 인식 백업 또는 논리 SQL 내보내기 |
| 이름 있는 저장소, R2, 모듈 설정 | 데이터베이스 설정 | 관리 화면의 설정 JSON을 암호화해 보관 |
| 초기 비밀번호, 세션, 컴패니언, 프록시 시크릿 | 실행 환경 | 비밀번호 관리자에 별도로 기록 |
| 오디오와 원본 이미지 | 구성된 저장소 백엔드 | 저장소 수준에서 별도로 백업 |
| R2 이미지 미러와 KV 캐시 | 재구성 가능한 캐시 | 같은 R2 버킷이면 인덱스를 이전／재확보하고, 새 버킷이면 다시 예열합니다. KV는 이전하지 않습니다 |

관리 화면의 설정 JSON은 카탈로그 백업이 아니며, 데이터베이스 백업에도 오디오 파일은 포함되지 않습니다.

## 저장소 구조

| 경로 | 용도 |
|---|---|
| `cloud/web/` | React 플레이어와 관리 UI |
| `cloud/worker/` | Hono API, D1 스키마, Node 호환 런타임 |
| `cloud/proxy-worker/` | 선택적 서명 오디오 릴레이 |
| `desktop/` | 네이티브 Windows 데스크톱 클라이언트(Rust, egui) |
| `pipeline/` | Python `mihonban` CLI와 가져오기／동기화 파이프라인 |
| `config/` | 안전한 구성 템플릿 |
| `tools/` | 로컬 개발, 배포, 감시, 마이그레이션 도우미 |
| `tests/` | Python 회귀 테스트 |

## 자주 사용하는 명령

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

## 보안

- `.dev.vars`, `.env`, `mihonban.toml`, `rclone.conf`, 데이터베이스, 설정 내보내기, 토큰, 오디오 파일을 커밋하지 마세요.
- 로컬 HTTP에서는 `DEV_INSECURE_COOKIE=1`이 필요합니다. 공개 배포에서는 HTTPS를 사용하고 이 변수는 설정하지 마세요.
- 관리 화면에서 저장한 비밀번호는 실행 환경의 초기 비밀번호보다 우선하며 기존 세션을 해제합니다.
- 외부 프록시를 사용할 때는 `STREAM_PROXY_SECRET`과 `PROXY_SECRET`을 같은 값으로 설정하고 비공개로 보관하세요.
- RYM 기능은 사용자가 직접 저장한 파일만 분석합니다. 이 저장소에는 RYM 크롤러가 포함되어 있지 않습니다.
- 대체할 수 없는 오디오는 반드시 한 벌 이상 별도의 장소에도 보관하세요.

## 문서

| 가이드 | 언어 |
|---|---|
| 설치 및 배포 | [English](docs/install.md) · [简体中文](docs/install.zh.md) · [繁體中文](docs/install.zh-Hant.md) · [日本語](docs/install.ja.md) · [한국어](docs/install.ko.md) · [Français](docs/install.fr.md) · [Español](docs/install.es.md) |
| 아키텍처와 실행 환경 | [English](docs/cloud.md) · [简体中文](docs/cloud.zh.md) · [繁體中文](docs/cloud.zh-Hant.md) · [日本語](docs/cloud.ja.md) · [한국어](docs/cloud.ko.md) · [Français](docs/cloud.fr.md) · [Español](docs/cloud.es.md) |
| 일상 운영 | [English](docs/manual.md) · [简体中文](docs/manual.zh.md) · [繁體中文](docs/manual.zh-Hant.md) · [日本語](docs/manual.ja.md) · [한국어](docs/manual.ko.md) · [Français](docs/manual.fr.md) · [Español](docs/manual.es.md) |
| 데이터베이스 마이그레이션 | [English](docs/database-migration.md) · [简体中文](docs/database-migration.zh.md) · [繁體中文](docs/database-migration.zh-Hant.md) · [日本語](docs/database-migration.ja.md) · [한국어](docs/database-migration.ko.md) · [Français](docs/database-migration.fr.md) · [Español](docs/database-migration.es.md) |
| 저장소와 파일 마이그레이션 | [English](docs/storage.md) · [简体中文](docs/storage.zh.md) · [繁體中文](docs/storage.zh-Hant.md) · [日本語](docs/storage.ja.md) · [한국어](docs/storage.ko.md) · [Français](docs/storage.fr.md) · [Español](docs/storage.es.md) |
| 서버리스 호스팅 | [English](docs/serverless-hosting.md) · [简体中文](docs/serverless-hosting.zh.md) · [繁體中文](docs/serverless-hosting.zh-Hant.md) · [日本語](docs/serverless-hosting.ja.md) · [한국어](docs/serverless-hosting.ko.md) · [Français](docs/serverless-hosting.fr.md) · [Español](docs/serverless-hosting.es.md) |
| 선택적 오디오 프록시 | [English](docs/audio-proxy.md) · [简体中文](docs/audio-proxy.zh.md) · [繁體中文](docs/audio-proxy.zh-Hant.md) · [日本語](docs/audio-proxy.ja.md) · [한국어](docs/audio-proxy.ko.md) · [Français](docs/audio-proxy.fr.md) · [Español](docs/audio-proxy.es.md) |
| 안전한 공개 절차 | [English](docs/github-publish.md) · [简体中文](docs/github-publish.zh.md) · [繁體中文](docs/github-publish.zh-Hant.md) · [日本語](docs/github-publish.ja.md) · [한국어](docs/github-publish.ko.md) · [Français](docs/github-publish.fr.md) · [Español](docs/github-publish.es.md) |

## 라이선스

Mihonban은 [GNU Affero General Public License v3.0](LICENSE)(`AGPL-3.0-only`)에 따라 배포됩니다. 소프트웨어를 수정해 네트워크를 통해 제공하는 경우, AGPL에 따라 해당 버전의 소스 코드를 함께 제공해야 합니다.

이 라이선스는 이 저장소의 코드와 안전한 템플릿에만 적용됩니다. 음악이나 제3자 메타데이터를 배포할 권리를 부여하지 않습니다.
