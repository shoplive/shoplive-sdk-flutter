#!/usr/bin/env bash
# [SMV-1723] 기준 트리의 버전 자리를 바꾸고 각 패키지 CHANGELOG 에 <V> 절을 넣는다.
# 작업 디렉토리 = 리포 루트(버튼은 기준 브랜치의 git worktree 에서 부른다). 커밋·push 는 하지 않는다.
#
#   scripts/release-flutter-bump.sh --to 3.0.4 [--native 3.0.4] --ios-checksums sums.txt
#   scripts/release-flutter-bump.sh --to 1.9.1 --native 1.9.0
#
#   --to             Flutter 패키지 버전(pubspec · 태그 · Release)
#   --native         네이티브 SDK 버전(Android 좌표 · podspec SDK 버전·sha256 · CHANGELOG 링크). 생략 = --to.
#                    트리의 네이티브 버전과 같으면 네이티브 자리는 그대로 둔다(Flutter 만 고친 릴리스).
#   --ios-checksums  3.x 에서 네이티브 버전이 바뀔 때 필수. 한 줄에 "<XCFramework 이름> <sha256>" — shoplive-sdk-ios <native> 의 Package.swift.
# stdout = PR 본문에 넣을 마크다운(바꾼 자리 · 남은 옛 버전 문자열). 진행 로그는 stderr.
#
# 자리 표는 두 종류다.
#   구조 자리 — 정확히 N곳이어야 한다. 파일 모양이 바뀌어 수가 다르면 멈춘다(태그를 자른 뒤 빌드에서 알면 늦다).
#   문서 자리 — README 의 "현재 버전" 표현(설치 예시 · SDK 버전 · 다운로드 주소). 0곳이어도 된다. "SDK 3.0.3+" 같은 이력 표현은 건드리지 않는다.
# 각 자리는 Flutter 버전 자리(F)와 네이티브 버전 자리(N)로 나뉜다.
# 정규식은 perl 이고, 일치하는 부분(\K 뒤 · 전방탐색 앞)이 정확히 옛 값이 되게 쓴다 — 그 부분만 바뀐다.
set -euo pipefail
# shellcheck source=scripts/release-flutter-lib.sh
. "$(cd "$(dirname "$0")" && pwd)/release-flutter-lib.sh"

TO=""; NATIVE=""; SUMS=""
while (( $# )); do
  case "$1" in
    --to) TO=${2:-}; shift 2 ;;
    --native) NATIVE=${2:-}; shift 2 ;;
    --ios-checksums) SUMS=${2:-}; shift 2 ;;
    *) die "모르는 인자: $1" ;;
  esac
done
is_semver "$TO" || die "--to 는 x.y.z 여야 합니다: '${TO}'"
NATIVE=${NATIVE:-$TO}
is_semver "$NATIVE" || die "--native 는 x.y.z 여야 합니다: '${NATIVE}'"
MAJOR=${TO%%.*}
line_base "$MAJOR" > /dev/null || die "${TO}: 지원하는 라인은 1.x · 3.x 입니다."
[[ "${NATIVE%%.*}" == "$MAJOR" ]] || die "네이티브 ${NATIVE} 의 메이저가 Flutter ${TO} 와 다릅니다."
[[ -f "${LINE_PRIMARY_DIR}/pubspec.yaml" ]] || die "리포 루트에서 실행하세요(${LINE_PRIMARY_DIR}/pubspec.yaml 이 없음)."
FROM=$(pubspec_version < "${LINE_PRIMARY_DIR}/pubspec.yaml")
is_semver "$FROM" || die "${LINE_PRIMARY_DIR}/pubspec.yaml 의 version 을 읽지 못했습니다: '${FROM}'"
[[ "${FROM%%.*}" == "$MAJOR" ]] || die "기준 트리는 ${FROM} 입니다 — ${TO} 와 라인(major)이 다릅니다."
semver_gt "$TO" "$FROM" || die "${TO} 는 기준 트리의 현재 버전 ${FROM} 보다 높아야 합니다."
NFROM=$(tree_native_version "$MAJOR") || die "기준 트리의 네이티브 버전을 읽지 못했습니다."
is_semver "$NFROM" || die "기준 트리의 네이티브 버전을 읽지 못했습니다: '${NFROM}'"
O=$(re_ver "$FROM"); NO=$(re_ver "$NFROM")
NATIVE_CHANGES=true
if [[ "$NFROM" == "$NATIVE" ]]; then NATIVE_CHANGES=false; fi

CHANGED=""   # "파일 n" 줄들(보고용)

# subst <file> <곳 수 | any> <perl 정규식> <새 값>
subst() {
  local file=$1 want=$2 re=$3 new=$4 n
  [[ -f "$file" ]] || die "${file} 이 없습니다 — 버전 자리 표(scripts/release-flutter-bump.sh)가 이 트리와 맞지 않습니다."
  n=$(RE="$re" NEW="$new" WANT="$want" perl -e '
    my $f = shift;
    open(my $in, "<", $f) or die "$f: $!"; local $/; my $s = <$in>; close $in;
    my $n = () = $s =~ /$ENV{RE}/g;
    if ($ENV{WANT} eq "any" || $n == $ENV{WANT}) {
      if ($n > 0) {
        $s =~ s/$ENV{RE}/$ENV{NEW}/g;
        open(my $out, ">", $f) or die "$f: $!"; print $out $s; close $out;
      }
    }
    print $n;' "$file") || die "${file}: 치환 실패"
  if [[ "$want" != any && "$n" != "$want" ]]; then
    die "${file}: 바꿀 자리가 ${want}곳이어야 하는데 ${n}곳입니다 — 파일 모양이 바뀌었습니다. scripts/release-flutter-bump.sh 의 자리 표를 고치세요. (패턴: ${re})"
  fi
  if [[ "$n" != 0 ]]; then CHANGED="${CHANGED}${file} ${n}"$'\n'; fi
}

# podspec 이 내려받는 XCFramework 이름(sha256 을 가진 줄).
podspec_artifacts() { perl -ne "print \"\$1\n\" if /^\s*'(\w+)' => '[0-9a-f]{64}',?\s*\$/" "$1"; }

bump_3x() {
  local entry dir name pod a sum arts f
  for entry in $(line_packages 3); do
    dir=${entry%%:*}; name=${entry#*:}; pod="${dir}/ios/${name}.podspec"
    # F: 패키지 버전 · 같은 버전 core 의존 · 플러그인 모듈의 Gradle version
    subst "${dir}/pubspec.yaml" 1 "(?m)^version: \\K${O}\$" "$TO"
    if [[ "$name" != "$(line_core 3)" ]]; then
      subst "${dir}/pubspec.yaml" 1 "(?m)^  shoplive_core: \\K${O}\$" "$TO"
    fi
    subst "${dir}/android/build.gradle" 1 "(?m)^version = \"\\K${O}(?=\"\$)" "$TO"
    [[ "$NATIVE_CHANGES" == true ]] || continue
    # N: Android 좌표 · iOS SDK 버전 · Package.swift 주소 · sha256
    subst "${dir}/android/build.gradle" 1 "implementation\\(\"cloud\\.shoplive:[a-z0-9-]+:\\K${NO}(?=\"\\))" "$NATIVE"
    subst "$pod" 1 "(?m)^shoplive_ios_sdk_version = '\\K${NO}(?='\$)" "$NATIVE"
    subst "$pod" 1 "shoplive-sdk-ios/blob/\\K${NO}(?=/Package\\.swift)" "$NATIVE"
    arts=$(podspec_artifacts "$pod") || die "${pod} 를 읽지 못했습니다."
    [[ -n "$arts" ]] || die "${pod} 에서 sha256 을 가진 XCFramework 줄을 찾지 못했습니다 — 파일 모양이 바뀌었습니다."
    for a in $arts; do
      sum=$(awk -v n="$a" '$1 == n { print $2 }' "$SUMS")
      [[ "$sum" =~ ^[0-9a-f]{64}$ ]] || die "--ios-checksums 에 ${a} 의 sha256 이 없습니다(${pod} 가 내려받는 XCFramework)."
      subst "$pod" 1 "'${a}' => '\\K[0-9a-f]{64}(?=')" "$sum"
    done
  done
  # F: 플러그인 자체 버전 상수(getPluginVersion) — test/plugin_version_test.dart 가 pubspec 과 같은지 본다.
  subst shoplive_flutter_sample/lib/src/shoplive_player.dart 1 "static const String pluginVersion = '\\K${O}(?=';)" "$TO"
  # F: pub.dev 의 발행본을 받는 샘플 앱(path 가 아님) — 발행 뒤에 이 버전을 받는다.
  subst shoplive_flutter_sample/flutter_sample/pubspec.yaml 2 "(?m)^  shoplive_(?:player|streamer): \\K${O}\$" "$TO"
  subst shoplive_flutter_sample/flutter_sample/pubspec.yaml any "published (?:shoplive_player / shoplive_streamer )?\\K${O}(?= )" "$TO"
  for f in README.md shoplive_core/README.md shoplive_flutter_sample/README.md shoplive_streamer/README.md; do
    [[ -f "$f" ]] || continue
    subst "$f" any "(?m)^[ \\t]*#?[ \\t]*shoplive_(?:player|streamer|core): \\K${O}(?![0-9.])" "$TO"   # F: 설치 예시
  done
  [[ "$NATIVE_CHANGES" == true ]] || return 0
  # N: 테스트가 고정한 SDK 버전(세 podspec 이 같은 값인지 · 기기 계약 테스트의 getSdkVersion)
  subst shoplive_flutter_sample/test/ios_sdk_podspec_sync_test.dart 1 "\\{'\\K${NO}(?='\\})" "$NATIVE"
  subst shoplive_flutter_sample/example/integration_test/ios_contract_test.dart 1 "getSdkVersion\\(\\), '\\K${NO}(?='\\))" "$NATIVE"
  # N: 문서의 "현재 SDK 버전" 표현
  for f in README.md shoplive_core/README.md shoplive_flutter_sample/README.md shoplive_streamer/README.md; do
    [[ -f "$f" ]] || continue
    subst "$f" any "SDK \\*\\*\\K${NO}(?=\\*\\*)" "$NATIVE"
    subst "$f" any "SDK \\K${NO}(?= XCFrameworks)" "$NATIVE"
    subst "$f" any "Android SDK \\K${NO}(?= is not published)" "$NATIVE"
    subst "$f" any "shoplive-sdk-ios/releases/tag/\\K${NO}(?![0-9.])" "$NATIVE"
    subst "$f" any "<base>/\\K${NO}(?=/)" "$NATIVE"
  done
}

bump_1x() {
  local dir=$LINE_PRIMARY_DIR p pods=""
  # F: 패키지 버전 · pubspec 을 못 읽을 때의 BuildConfig.PLUGIN_VERSION 기본값
  subst "${dir}/pubspec.yaml" 1 "(?m)^version: \\K${O}\$" "$TO"
  subst "${dir}/android/build.gradle" 1 "versionMatch\\[0\\]\\[1\\]\\.trim\\(\\) : \"\\K${O}(?=\")" "$TO"
  [[ "$NATIVE_CHANGES" == true ]] || return 0
  # N: Android SDK 버전 · iOS pod 버전
  subst "${dir}/android/build.gradle" 1 "(?m)^def shoplive_sdk_version = \"\\K${NO}(?=\"\$)" "$NATIVE"
  for p in $LINE1_IOS_PODS; do pods="${pods:+${pods}|}${p}"; done
  subst "${dir}/ios/shoplive_player.podspec" 2 "(?m)^[ \\t]*s\\.dependency '(?:${pods})', '\\K${NO}(?='\$)" "$NATIVE"
}

# CHANGELOG(pub.dev 에 나간다) — 영어 고정 문구 + 네이티브 Release 링크만. 커밋 목록은 PR 본문에만 둔다.
write_changelogs() {
  local entry dir file tmp
  for entry in $(line_packages "$MAJOR"); do
    dir=${entry%%:*}; file="${dir}/CHANGELOG.md"
    [[ -f "$file" ]] || die "${file} 이 없습니다."
    if grep -qE "^## $(re_ver "$TO")([[:space:]]|\$)" "$file"; then die "${file} 에 이미 ## ${TO} 절이 있습니다."; fi
    tmp=$(mktemp)
    {
      printf '## %s\n\n' "$TO"
      printf 'Built on Shoplive SDK %s (Android and iOS). Native SDK release notes: [Android](https://github.com/%s/releases/tag/%s) · [iOS](https://github.com/%s/releases/tag/%s).\n\n' \
        "$NATIVE" "$ANDROID_REPO" "$NATIVE" "$IOS_REPO" "$NATIVE"
      cat "$file"
    } > "$tmp"
    cat "$tmp" > "$file"; rm -f "$tmp"
    CHANGED="${CHANGED}${file} 1"$'\n'
  done
}

if [[ "$MAJOR" == 3 ]]; then
  if [[ "$NATIVE_CHANGES" == true ]]; then
    [[ -n "$SUMS" && -f "$SUMS" ]] || die "3.x 에서 네이티브 버전을 바꾸려면 --ios-checksums 파일이 필요합니다(podspec sha256)."
  fi
  bump_3x
else
  bump_1x
fi
write_changelogs

# 파일별 합계("- `파일` n곳")
CHANGED=$(printf '%s' "$CHANGED" | awk 'NF == 2 { if (!($1 in n)) o[++k] = $1; n[$1] += $2 } END { for (i = 1; i <= k; i++) printf "- `%s` %d곳\n", o[i], n[o[i]] }')
log "Flutter ${FROM} → ${TO} · 네이티브 ${NFROM} → ${NATIVE}: 바꾼 자리"
log "$CHANGED"

# 남은 옛 버전 문자열 — 이력 설명·주석·테스트 목 값일 수 있다. 리뷰어가 PR 에서 본다(CHANGELOG 의 옛 절은 뺀다).
# 네이티브 버전이 그대로면 그 값은 "남은" 것이 아니라 맞는 값이므로 Flutter 옛 버전만 찾는다.
PAT="$O"
if [[ "$NATIVE_CHANGES" == true && "$NO" != "$O" ]]; then PAT="${O}|${NO}"; fi
if [[ "$NATIVE_CHANGES" == false && "$NO" == "$O" ]]; then PAT=""; fi
LEFT=""
if [[ -n "$PAT" ]]; then
  LEFT=$(git grep -n -E "(^|[^0-9.])(${PAT})([^0-9]|\$)" -- . ':(exclude)*CHANGELOG.md' ':(exclude)*.lock' || true)
fi
printf '### 바꾼 자리 (Flutter %s → %s · 네이티브 %s → %s)\n\n%s\n' "$FROM" "$TO" "$NFROM" "$NATIVE" "$CHANGED"
# shellcheck disable=SC2016  # 마크다운의 백틱이다(셸 확장 아님).
if [[ -n "$LEFT" ]]; then
  printf '### 남은 옛 버전 문자열 %s곳 — 이력 설명·주석·테스트 목 값이면 그대로 두고, "현재 버전" 을 말하는 곳이면 이 PR 에서 고치세요\n\n' \
    "$(printf '%s\n' "$LEFT" | wc -l | tr -d ' ')"
  printf '<details><summary>목록</summary>\n\n```\n%s\n```\n</details>\n' "$(printf '%s\n' "$LEFT" | head -n 80)"
elif [[ -n "$PAT" ]]; then
  printf '### 남은 옛 버전 문자열 없음\n'
else
  printf '### 네이티브 버전 그대로(%s) — 옛 Flutter 버전과 같은 문자열은 네이티브 자리라 목록을 만들지 않습니다\n' "$NFROM"
fi
