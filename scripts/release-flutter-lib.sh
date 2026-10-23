#!/usr/bin/env bash
# [SMV-1723] Flutter SDK 배포 스크립트들이 같이 쓰는 표와 함수. source 해서 쓴다(직접 실행하지 않음).
#
#   release-flutter-prepare.sh   버튼(Release Flutter SDK) — 버전 올리는 PR 을 연다
#   release-flutter-bump.sh      버전 자리 · podspec sha256 · CHANGELOG 를 바꾼다(로컬에서도 돌릴 수 있음)
#   release-flutter-on-merge.sh  그 PR 머지 → 머지 커밋에 태그 <V> → 발행 워크플로 호출
#   release-flutter-publish.sh   발행 워크플로(태그 ref) — pub.dev 발행 · GitHub Release
#
# 원칙: 원격 조회가 실패하면 "없음" 으로 읽지 않는다 — 판정할 수 없으면 멈춘다(200=있음 · 404=없음 · 그 밖=멈춤).
# shellcheck disable=SC2034  # 표·좌표 상수는 이 파일을 source 하는 스크립트가 쓴다.
# 호환: macOS 기본 bash 3.2 에서도 돈다(로컬 실행·하네스). 연관 배열 · mapfile · ${v,,} · set -u 하 빈 배열 전개를 쓰지 않는다.
# 주의: bash 는 명령 치환 $(…) 안에서 set -e 를 끈다. x=$(f) 로 부르는 함수 안의 y=$(…) 실패는 그냥 지나가므로
#       그런 자리는 반드시 `|| exit 1` 을 붙인다(조회 실패가 "없음" 으로 새는 길 — 하네스 remote-fail 이 잡은 것).

# ---------------------------------------------------------------------------
# 라인 표 — 버전의 major 가 라인을 정한다. 이 표 하나만 고친다.
#   3.x  main 에서, 패키지 3개(같은 버전). shoplive_core 를 먼저 발행한다(player·streamer 가 같은 버전으로 의존).
#   1.x  release/v1 에서, shoplive_player 하나. main 은 3.x 구조라 1.x 유지보수는 release/v1 에서 한다.
# 패키지 = "<폴더>:<pub 이름>", 발행 순서대로.
# ---------------------------------------------------------------------------
line_base() {
  case "$1" in
    3) echo "main" ;;
    1) echo "release/v1" ;;
    *) return 1 ;;
  esac
}
line_packages() {
  case "$1" in
    3) echo "shoplive_core:shoplive_core shoplive_flutter_sample:shoplive_player shoplive_streamer:shoplive_streamer" ;;
    1) echo "shoplive_flutter_sample:shoplive_player" ;;
    *) return 1 ;;
  esac
}
# 다른 패키지보다 먼저 발행돼 pub.dev 에 보여야 하는 패키지(없으면 빈 값).
line_core() {
  case "$1" in
    3) echo "shoplive_core" ;;
    *) echo "" ;;
  esac
}
# 라인의 대표 pubspec — 기준 브랜치의 "현재 버전" 을 읽는 곳.
LINE_PRIMARY_DIR="shoplive_flutter_sample"
# 트리가 고정한 네이티브 SDK 버전(Flutter 버전과 다를 수 있다 — 버튼 입력 native_version).
#   3.x: podspec 의 shoplive_ios_sdk_version (Android 좌표 버전과 같아야 한다 — bump 가 같은 값으로 센다)
#   1.x: android/build.gradle 의 def shoplive_sdk_version
tree_native_version() {  # tree_native_version <major> [<리포 루트>]
  local root=${2:-.}
  case "$1" in
    3) sed -n "s/^shoplive_ios_sdk_version = '\([^']*\)'.*/\1/p" "${root}/${LINE_PRIMARY_DIR}/ios/shoplive_player.podspec" | head -n 1 ;;
    1) sed -n 's/^def shoplive_sdk_version = "\([^"]*\)".*/\1/p' "${root}/${LINE_PRIMARY_DIR}/android/build.gradle" | head -n 1 ;;
    *) return 1 ;;
  esac
}
# 1.x iOS 는 shoplive/pod-specs 의 pod 두 개를 V 로 고정한다(podspec 의 s.dependency).
LINE1_IOS_PODS="ShopLive ShopliveSDKCommon"

# release/v1 이 갖고 있어야 하는 배포 자동화 — 머지·발행은 그 커밋(태그)의 파일로 돈다.
# 버튼은 main 의 것과 같은지만 본다. GITHUB_TOKEN 은 .github/workflows 를 push 할 수 없어 동기화는 사람이 한다(RELEASING.md).
# TODO(SDP-VERIFY): 요확인 — GITHUB_TOKEN 의 워크플로 파일 push 거부(workflows 권한 없음)는 문서·경험 기반, 이 리포 실측 아님 · 근거 SMV-1723
RELEASE_MACHINERY=".github/workflows/release-flutter-on-merge.yml .github/workflows/publish-flutter-sdk.yml scripts/release-flutter-lib.sh scripts/release-flutter-on-merge.sh scripts/release-flutter-publish.sh"

PR_BRANCH_PREFIX="release-flutter/"
PUBLISH_WORKFLOW="publish-flutter-sdk.yml"
PR_BUILD_WORKFLOW="pr-build.yml"

# 원격 좌표
PUB_API="https://pub.dev/api/packages"
MAVEN_REPO="https://sdk.shoplive.cloud/maven-repo"
GH_API="${GITHUB_API_URL:-https://api.github.com}"
ANDROID_REPO="shoplive/shoplive-sdk-android"
IOS_REPO="shoplive/shoplive-sdk-ios"
PODSPECS_REPO="shoplive/pod-specs"

# pub.dev 에 core 가 보일 때까지 기다리는 상한(대기 = 간격 × 횟수, 기본 10초 × 30 = 5분).
RELEASE_POLL_ATTEMPTS="${RELEASE_POLL_ATTEMPTS:-30}"
RELEASE_POLL_INTERVAL="${RELEASE_POLL_INTERVAL:-10}"

# ---------------------------------------------------------------------------
# 출력
# ---------------------------------------------------------------------------
log()    { printf '%s\n' "$*" >&2; }
notice() { printf '::notice::%s\n' "$*" >&2; }
warn()   { printf '::warning::%s\n' "$*" >&2; }
die()    { printf '::error::%s\n' "$*" >&2; exit 1; }
# GitHub 실행 요약(로컬에서는 버린다).
summary() { if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then printf '%s\n' "$@" >> "$GITHUB_STEP_SUMMARY"; fi; }

# ---------------------------------------------------------------------------
# 버전
# ---------------------------------------------------------------------------
# 앞자리 0(3.0.04 · 03.0.4)은 받지 않는다 — 태그·pub.dev 의 정규형과 어긋난 채 태그가 먼저 생길 수 있다.
is_semver() { [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; }
# a > b (둘 다 x.y.z)
semver_gt() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<< "$1"
  IFS=. read -r b1 b2 b3 <<< "$2"
  if (( 10#$a1 != 10#$b1 )); then (( 10#$a1 > 10#$b1 )); return; fi
  if (( 10#$a2 != 10#$b2 )); then (( 10#$a2 > 10#$b2 )); return; fi
  (( 10#$a3 > 10#$b3 ))
}
# 정규식에 넣을 버전(점만 이스케이프 — 버전은 숫자와 점뿐이다).
re_ver() { printf '%s' "$1" | sed 's/\./\\./g'; }
# pubspec 텍스트(stdin)의 version 값.
pubspec_version() { sed -n 's/^version:[[:space:]]*\([^[:space:]#]*\).*$/\1/p' | head -n 1; }
# line_tag_max <major> [<V>] → 그 major 의 x.y.z 태그 중 가장 높은 것(<V> 를 주면 <V> 보다 낮은 것 중). 없으면 빈 값.
# 로컬 태그를 본다 — 부르기 전에 git fetch --tags.
line_tag_max() {
  local major=$1 below=${2:-} best="" t tags
  tags=$(git tag -l "${major}.*") || exit 1
  for t in $tags; do
    is_semver "$t" || continue
    if [[ -n "$below" ]] && ! semver_gt "$below" "$t"; then continue; fi
    if [[ -z "$best" ]] || semver_gt "$t" "$best"; then best=$t; fi
  done
  printf '%s' "$best"
}

# ---------------------------------------------------------------------------
# 원격 조회
# ---------------------------------------------------------------------------
# http_get <url> <out-file> [accept] → stdout 에 200 또는 404. 그 밖의 응답·네트워크 실패는 멈춘다.
# curl 의 --retry 는 타임아웃·408·429·5xx 를 3번까지 다시 시도한다.
http_get() {
  local url=$1 out=$2 accept=${3:-application/vnd.github+json} code
  local -a hdr=()
  case "$url" in
    "$GH_API"/*)
      hdr=(-H "Accept: ${accept}" -H "X-GitHub-Api-Version: 2022-11-28")
      if [[ -n "${GH_TOKEN:-}" ]]; then hdr=("${hdr[@]}" -H "Authorization: Bearer ${GH_TOKEN}"); fi
      ;;
  esac
  code=$(curl -sS -L --max-time 30 --retry 3 --retry-delay 2 --retry-connrefused \
    ${hdr[@]+"${hdr[@]}"} -o "$out" -w '%{http_code}' "$url") \
    || die "조회 실패(네트워크): ${url} — 있는지 없는지 판정할 수 없어 멈춥니다. 다시 실행하세요."
  case "$code" in
    200|404) printf '%s' "$code" ;;
    *) die "조회 실패(HTTP ${code}): ${url} — 판정할 수 없어 멈춥니다. 다시 실행하세요." ;;
  esac
}
# pub_state <package> <version> → published | absent
pub_state() {
  local code
  code=$(http_get "${PUB_API}/$1/versions/$2" /dev/null) || exit 1
  if [[ "$code" == 200 ]]; then echo published; else echo absent; fi
}
# remote_ref <full ref> → 그 ref 가 가리키는 커밋 SHA(주석 태그는 벗긴 커밋), 없으면 빈 값. 조회 실패는 멈춘다.
remote_ref() {
  local out sha
  out=$(git ls-remote origin "$1" "$1^{}") || die "원격 ref ${1} 를 조회하지 못했습니다 — 판정할 수 없어 멈춥니다. 다시 실행하세요."
  sha=$(printf '%s\n' "$out" | awk -v r="$1^{}" '$2 == r { print $1 }')
  if [[ -z "$sha" ]]; then sha=$(printf '%s\n' "$out" | awk -v r="$1" '$2 == r { print $1 }'); fi
  printf '%s' "$sha"
}
