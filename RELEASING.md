# Flutter SDK 배포 (메인테이너용)

[SMV-1723] 네이티브(Android·iOS) SDK 와 같은 손 구조다 — **버튼 1번, PR 머지 1번.** 나머지(태그·pub.dev 발행·GitHub Release)는 워크플로가 한다.

```
Actions → Release Flutter SDK (version[, native_version]) ─▶ PR: release-flutter/<V> → main | release/v1  (+ PR build)
(사람) PR 머지 ─▶ Release Flutter SDK on merge: 머지 커밋에 태그 <V> ─▶ Publish Flutter SDK (ref = 태그 <V>)
                                                                      pub.dev 발행 → GitHub Release <V>
```

| 라인 | 기준 브랜치 | 패키지(발행 순서) | GitHub Release |
|---|---|---|---|
| 3.x | `main` | `shoplive_core` → `shoplive_player` · `shoplive_streamer` (세 패키지 같은 버전) | Latest |
| 1.x | `release/v1` | `shoplive_player` | Latest 아님 |

태그·Release 이름은 `v` 없이 `<V>`(예: `3.0.4`). 보통 Flutter 버전 = 네이티브 SDK 버전이고, Flutter 만 고친 릴리스는
`native_version` 으로 바탕 SDK 를 따로 준다(예: version `1.9.1` · native_version `1.9.0`, 메이저는 같아야 함).
pubspec·태그·Release 는 `version`, Android 좌표·podspec SDK 버전·sha256·CHANGELOG 링크는 `native_version` 을 따른다.

## 릴리스하기

1. 바탕 네이티브 SDK(`native_version`, 비우면 `<V>`) 배포가 끝났는지 본다 — 버튼이 다시 확인한다(Android `sdk.shoplive.cloud/maven-repo` POM · iOS `shoplive-sdk-ios` Release `<V>` 의 zip 과 `Package.swift` checksum(3.x) 또는 `shoplive/pod-specs`(1.x) · 두 네이티브 리포의 Release `<V>` 노트).
2. **Actions → Release Flutter SDK → Run workflow**(Use workflow from: `main`), version 에 `<V>`(필요하면 native_version).
3. 열린 PR 을 본다.
   - 버전 자리(pubspec · Android `build.gradle` · iOS podspec 버전과 sha256 · 테스트 고정값 · README 설치 예시)가 바뀌었는지. 본문 끝의 "남은 옛 버전 문자열" 은 대부분 이력 설명이다 — "현재 버전" 을 말하는 곳만 고친다.
   - CHANGELOG(각 패키지, pub.dev 에 나감): 영어 고정 문구 + 네이티브 `native_version` Release 링크(Android·iOS)만. GitHub Release 노트도 이것을 그대로 쓴다. 직전 태그 이후 커밋 제목은 PR 본문에만 있다 — 고객에게 알릴 변경이 있으면 이 PR 에서 CHANGELOG 에 영어로 더한다.
   - 3.x 는 PR build(Dart · Android APK · iOS 시뮬레이터)가 그 브랜치로 돈다 — 통과를 보고 머지. 1.x 는 PR build 가 없다 — example 빌드를 손으로 확인.
4. 머지한다. 이후는 자동이다 — Actions 의 Release Flutter SDK on merge → Publish Flutter SDK 가 끝나면 pub.dev 와 Release `<V>` 를 확인.

**pub.dev 는 같은 버전을 다시 올릴 수 없다**(재발행 기능 없음). 고칠 것이 있으면 다음 버전으로 낸다.

## 실패했을 때

| 어디서 | 증상 | 할 일 |
|---|---|---|
| 버튼 | 멈춤(이유가 오류 줄에 나옴) | 이유를 해소하고 다시 누른다. 버튼은 읽기 검사를 다 통과한 뒤에만 쓴다(브랜치·PR). 원격 조회 실패도 멈춘다 — 다시 누른다 |
| 버튼 | 같은 버전 PR 이 이미 열려 있음 | 새로 만들지 않고 PR build 만 다시 부른다(정상 종료) |
| 버튼 | "브랜치가 남아 있는데 열린 PR 이 없습니다" | 닫은 PR 의 `release-flutter/<V>` 브랜치를 지우고 다시 누른다 |
| 머지 뒤 | 태그가 안 생김 · 발행이 안 불림 | Release Flutter SDK on merge 실행을 **Re-run**, 또는 Run workflow(Use workflow from = 그 PR 의 기준 브랜치, pr = PR 번호). 태그가 이미 머지 커밋에 있으면 발행만 다시 부른다 |
| 발행 | 패키지 하나가 실패 · Release 실패 | 원인을 고친 뒤 **Publish Flutter SDK → Run workflow, Use workflow from = 태그 `<V>`**. pub.dev 에 이미 있는 패키지는 건너뛰고 남은 것만 발행, Release 가 있으면 만들지 않는다 |
| 발행 | 발행 워크플로·스크립트 자체의 결함 | 발행은 태그 커밋의 파일로 돌아 같은 태그로 다시 실행해도 결함이 그대로다. 고친 커밋을 기준 브랜치에 머지하고 태그 `<V>` 를 그 커밋으로 옮긴 뒤 발행을 수동 실행한다 — 사람이 판단한다(이미 나간 패키지가 있으면 남은 패키지가 같은 코드로 나가는지 확인) |

태그를 손으로 만들지 않는다 — 태그는 release PR 의 머지 커밋에만 붙는다(발행 워크플로가 태그가 기준 브랜치에 있는지, pubspec 버전이 태그와 같은지 확인한다).

## 1.x: `release/v1` 맞추기

`main` 은 3.x 구조라 1.x 유지보수는 `release/v1` 에서 한다. 1.x 버튼을 처음 누르면 `release/v1` 이 없을 때 마지막 1.x 태그(지금 `1.9.0`)에서 만든다.
머지·발행은 **`release/v1` 의 커밋에 있는 워크플로·스크립트로** 돈다(pull_request 이벤트는 머지 커밋의 파일, 발행은 태그 커밋의 파일). 그래서 `release/v1` 에 배포 자동화가 main 과 같게 있어야 하고, 다르면 버튼이 멈춘다. GITHUB_TOKEN 은 `.github/workflows` 를 push 할 수 없어 이 동기화는 사람이 한다(`release/v1` 은 룰셋이 없어 직접 push 가능). 처음 한 번, 그리고 main 의 배포 자동화가 바뀌었을 때:

```sh
git fetch origin
git switch release/v1            # 없으면: 버튼을 한 번 누르면 만들어진다(그리고 이 단계에서 멈춘다)
git checkout origin/main -- \
  .github/workflows/release-flutter-on-merge.yml .github/workflows/publish-flutter-sdk.yml \
  scripts/release-flutter-lib.sh scripts/release-flutter-on-merge.sh scripts/release-flutter-publish.sh
git commit -m "Sync release automation from main"
git push origin release/v1
```

그다음 버튼을 다시 누른다. (`pr-build.yml` 은 3.x 전용이라 옮기지 않는다.)

## 전제(설정)

- **pub.dev**(세 패키지 각각 Admin → Automated publishing): GitHub Actions 사용, repository `shoplive/shoplive-sdk-flutter`, tag pattern `{{version}}`, **push 와 workflow_dispatch 이벤트 허용**, environment 요구 없음. 발행은 `workflow_dispatch` + 태그 ref 로 하므로 workflow_dispatch 허용이 필요하다.
- **리포**: Settings → Actions → General — Workflow permissions 에서 "Allow GitHub Actions to create and approve pull requests" 켜짐(버튼이 PR 을 연다). 새 시크릿은 없다(GITHUB_TOKEN 과 pub.dev OIDC 뿐).
- `main` 룰셋은 PR 승인 1명을 요구한다 — 버튼이 연 PR 은 사람이 승인해 머지한다.

## 파일

| 파일 | 역할 |
|---|---|
| `.github/workflows/release-flutter-sdk.yml` · `scripts/release-flutter-prepare.sh` | 버튼 — 검사 · 버전 올리기 PR · PR build 호출 |
| `scripts/release-flutter-bump.sh` | 버전 자리 표(Flutter 자리 · 네이티브 자리) · podspec sha256 · CHANGELOG (로컬: `scripts/release-flutter-bump.sh --to <V> [--native <SDK>] [--ios-checksums f]`) |
| `.github/workflows/release-flutter-on-merge.yml` · `scripts/release-flutter-on-merge.sh` | 머지 → 태그 → 발행 호출 |
| `.github/workflows/publish-flutter-sdk.yml` · `scripts/release-flutter-publish.sh` | pub.dev 발행(OIDC) · GitHub Release |
| `scripts/release-flutter-lib.sh` | 라인 표(major → 기준 브랜치·패키지) · 원격 조회 |
