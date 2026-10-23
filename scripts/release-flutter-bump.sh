#!/usr/bin/env bash
# [SMV-1723] 기준 트리의 "현재 버전" 자리를 <V> 로 바꾸고 각 패키지 CHANGELOG 에 <V> 절을 넣는다.
# 작업 디렉토리 = 리포 루트(버튼은 기준 브랜치의 git worktree 에서 부른다). 커밋·push 는 하지 않는다.
#
#   scripts/release-flutter-bump.sh --to 3.0.4 --ios-checksums sums.txt [--since 3.0.3]
#   scripts/release-flutter-bump.sh --to 1.9.1 [--since 1.9.0]
#
#   --ios-checksums  3.x 필수. 한 줄에 "<XCFramework 이름> <sha256>" — shoplive-sdk-ios <V> 의 Package.swift checksum.
#   --since          CHANGELOG 에 넣을 커밋 범위의 시작 태그(직전 발행). 없으면 CHANGELOG 를 건드리지 않는다.
# stdout = PR 본문에 넣을 마크다운(바꾼 자리 · 남은 옛 버전 문자열). 진행 로그는 stderr.
#
# 자리 표는 두 종류다.
#   구조 자리 — 정확히 N곳이어야 한다. 파일 모양이 바뀌어 수가 다르면 멈춘다(태그를 자른 뒤 빌드에서 알면 늦다).
#   문서 자리 — README 의 "현재 버전" 표현(설치 예시 · 다운로드 주소). 0곳이어도 된다. "SDK 3.0.3+" 같은 이력 표현은 건드리지 않는다.
# 정규식은 perl 이고, 일치하는 부분(\K 뒤 · 전방탐색 앞)이 정확히 옛 버전(또는 옛 sha256)이 되게 쓴다 — 그 부분만 바뀐다.
set -euo pipefail
# shellcheck source=scripts/release-flutter-lib.sh
. "$(cd "$(dirname "$0")" && pwd)/release-flutter-lib.sh"

TO=""; SUMS=""; SINCE=""
while (( $# )); do
  case "$1" in
    --to) TO=${2:-}; shift 2 ;;
    --ios-checksums) SUMS=${2:-}; shift 2 ;;
    --since) SINCE=${2:-}; shift 2 ;;
    *) die "모르는 인자: $1" ;;
  esac
done
is_semver "$TO" || die "--to 는 x.y.z 여야 합니다: '${TO}'"
MAJOR=${TO%%.*}
line_base "$MAJOR" > /dev/null || die "${TO}: 지원하는 라인은 1.x · 3.x 입니다."
[[ -f "${LINE_PRIMARY_DIR}/pubspec.yaml" ]] || die "리포 루트에서 실행하세요(${LINE_PRIMARY_DIR}/pubspec.yaml 이 없음)."
FROM=$(pubspec_version < "${LINE_PRIMARY_DIR}/pubspec.yaml")
is_semver "$FROM" || die "${LINE_PRIMARY_DIR}/pubspec.yaml 의 version 을 읽지 못했습니다: '${FROM}'"
[[ "${FROM%%.*}" == "$MAJOR" ]] || die "기준 트리는 ${FROM} 입니다 — ${TO} 와 라인(major)이 다릅니다."
semver_gt "$TO" "$FROM" || die "${TO} 는 기준 트리의 현재 버전 ${FROM} 보다 높아야 합니다."
O=$(re_ver "$FROM")

CHANGED=""   # "파일 n곳" 줄들(보고용)

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
  local entry dir name pod a sum arts
  for entry in $(line_packages 3); do
    dir=${entry%%:*}; name=${entry#*:}; pod="${dir}/ios/${name}.podspec"
    subst "${dir}/pubspec.yaml" 1 "(?m)^version: \\K${O}\$" "$TO"
    if [[ "$name" != "$(line_core 3)" ]]; then
      subst "${dir}/pubspec.yaml" 1 "(?m)^  shoplive_core: \\K${O}\$" "$TO"
    fi
    subst "${dir}/android/build.gradle" 1 "(?m)^version = \"\\K${O}(?=\"\$)" "$TO"
    subst "${dir}/android/build.gradle" 1 "implementation\\(\"cloud\\.shoplive:[a-z0-9-]+:\\K${O}(?=\"\\))" "$TO"
    subst "$pod" 1 "(?m)^shoplive_ios_sdk_version = '\\K${O}(?='\$)" "$TO"
    subst "$pod" 1 "shoplive-sdk-ios/blob/\\K${O}(?=/Package\\.swift)" "$TO"
    arts=$(podspec_artifacts "$pod") || die "${pod} 를 읽지 못했습니다."
    [[ -n "$arts" ]] || die "${pod} 에서 sha256 을 가진 XCFramework 줄을 찾지 못했습니다 — 파일 모양이 바뀌었습니다."
    for a in $arts; do
      sum=$(awk -v n="$a" '$1 == n { print $2 }' "$SUMS")
      [[ "$sum" =~ ^[0-9a-f]{64}$ ]] || die "--ios-checksums 에 ${a} 의 sha256 이 없습니다(${pod} 가 내려받는 XCFramework)."
      subst "$pod" 1 "'${a}' => '\\K[0-9a-f]{64}(?=')" "$sum"
    done
  done
  # 플러그인 자체 버전 상수(getPluginVersion) — test/plugin_version_test.dart 가 pubspec 과 같은지 본다.
  subst shoplive_flutter_sample/lib/src/shoplive_player.dart 1 "static const String pluginVersion = '\\K${O}(?=';)" "$TO"
  # 테스트가 고정한 SDK 버전(세 podspec 이 같은 값인지 · 기기 계약 테스트의 getSdkVersion)
  subst shoplive_flutter_sample/test/ios_sdk_podspec_sync_test.dart 1 "\\{'\\K${O}(?='\\})" "$TO"
  subst shoplive_flutter_sample/example/integration_test/ios_contract_test.dart 1 "getSdkVersion\\(\\), '\\K${O}(?='\\))" "$TO"
  # pub.dev 의 발행본을 받는 샘플 앱(path 가 아님) — 발행 뒤에 이 버전을 받는다.
  subst shoplive_flutter_sample/flutter_sample/pubspec.yaml 2 "(?m)^  shoplive_(?:player|streamer): \\K${O}\$" "$TO"
  subst shoplive_flutter_sample/flutter_sample/pubspec.yaml any "published (?:shoplive_player / shoplive_streamer )?\\K${O}(?= )" "$TO"
  # 문서 자리 — "현재 버전" 표현만
  local f
  for f in README.md shoplive_core/README.md shoplive_flutter_sample/README.md shoplive_streamer/README.md; do
    [[ -f "$f" ]] || continue
    subst "$f" any "(?m)^[ \\t]*#?[ \\t]*shoplive_(?:player|streamer|core): \\K${O}(?![0-9.])" "$TO"
    subst "$f" any "SDK \\*\\*\\K${O}(?=\\*\\*)" "$TO"
    subst "$f" any "SDK \\K${O}(?= XCFrameworks)" "$TO"
    subst "$f" any "Android SDK \\K${O}(?= is not published)" "$TO"
    subst "$f" any "shoplive-sdk-ios/releases/tag/\\K${O}(?![0-9.])" "$TO"
    subst "$f" any "<base>/\\K${O}(?=/)" "$TO"
  done
}

bump_1x() {
  local dir=$LINE_PRIMARY_DIR pod p pods=""
  subst "${dir}/pubspec.yaml" 1 "(?m)^version: \\K${O}\$" "$TO"
  subst "${dir}/android/build.gradle" 1 "(?m)^def shoplive_sdk_version = \"\\K${O}(?=\"\$)" "$TO"
  # pubspec 을 못 읽을 때 쓰는 기본값(BuildConfig.PLUGIN_VERSION)
  subst "${dir}/android/build.gradle" 1 "versionMatch\\[0\\]\\[1\\]\\.trim\\(\\) : \"\\K${O}(?=\")" "$TO"
  pod="${dir}/ios/shoplive_player.podspec"
  for p in $LINE1_IOS_PODS; do pods="${pods:+${pods}|}${p}"; done
  subst "$pod" 2 "(?m)^[ \\t]*s\\.dependency '(?:${pods})', '\\K${O}(?='\$)" "$TO"
}

# changelog_section <dir> → <V> 절(직전 태그 이후 그 패키지 폴더를 바꾼 커밋 제목). 머지 커밋은 뺀다(같은 변경의 PR 제목).
changelog_section() {
  local dir=$1 subjects
  subjects=$(git log --no-merges --format='%s' "${SINCE}..HEAD" -- "$dir" ":(exclude)${dir}/flutter_sample") \
    || die "git log ${SINCE}..HEAD 실패 — 직전 태그 ${SINCE} 가 이 클론에 있는지 확인하세요(git fetch --tags)."
  printf '## %s\n\n' "$TO"
  printf 'Built on Shoplive SDK %s (Android and iOS). Native SDK release notes: [Android](https://github.com/%s/releases/tag/%s) · [iOS](https://github.com/%s/releases/tag/%s).\n' \
    "$TO" "$ANDROID_REPO" "$TO" "$IOS_REPO" "$TO"
  if [[ -n "$subjects" ]]; then
    printf '\n### Changes since %s\n\n' "$SINCE"
    printf '%s\n' "$subjects" | sed 's/^/* /'
  fi
  printf '\n'
}

write_changelogs() {
  local entry dir file tmp
  git rev-parse -q --verify "${SINCE}^{commit}" > /dev/null || die "직전 태그 ${SINCE} 가 이 클론에 없습니다(git fetch --tags)."
  for entry in $(line_packages "$MAJOR"); do
    dir=${entry%%:*}; file="${dir}/CHANGELOG.md"
    [[ -f "$file" ]] || die "${file} 이 없습니다."
    if grep -qE "^## $(re_ver "$TO")([[:space:]]|\$)" "$file"; then die "${file} 에 이미 ## ${TO} 절이 있습니다."; fi
    tmp=$(mktemp)
    { changelog_section "$dir"; cat "$file"; } > "$tmp"
    cat "$tmp" > "$file"; rm -f "$tmp"
    CHANGED="${CHANGED}${file} 1"$'\n'
  done
}

if [[ "$MAJOR" == 3 ]]; then
  [[ -n "$SUMS" && -f "$SUMS" ]] || die "3.x 는 --ios-checksums 파일이 필요합니다(podspec sha256)."
  bump_3x
else
  bump_1x
fi
if [[ -n "$SINCE" ]]; then write_changelogs; fi

# 파일별 합계("- `파일` n곳")
CHANGED=$(printf '%s' "$CHANGED" | awk 'NF == 2 { if (!($1 in n)) o[++k] = $1; n[$1] += $2 } END { for (i = 1; i <= k; i++) printf "- `%s` %d곳\n", o[i], n[o[i]] }')
log "${FROM} → ${TO}: 바꾼 자리"
log "$CHANGED"

# 남은 옛 버전 문자열 — 이력 설명·주석·테스트 목 값일 수 있다. 리뷰어가 PR 에서 본다(CHANGELOG 의 옛 절은 뺀다).
LEFT=$(git grep -n -E "(^|[^0-9.])${O}([^0-9]|\$)" -- . ':(exclude)*CHANGELOG.md' ':(exclude)*.lock' || true)
printf '### 바꾼 자리 (%s → %s)\n\n%s\n' "$FROM" "$TO" "$CHANGED"
# shellcheck disable=SC2016  # 마크다운의 백틱이다(셸 확장 아님).
if [[ -n "$LEFT" ]]; then
  printf '### 남은 `%s` 문자열 %s곳 — 이력 설명·주석·테스트 목 값이면 그대로 두고, "현재 버전" 을 말하는 곳이면 이 PR 에서 고치세요\n\n' \
    "$FROM" "$(printf '%s\n' "$LEFT" | wc -l | tr -d ' ')"
  printf '<details><summary>목록</summary>\n\n```\n%s\n```\n</details>\n' "$(printf '%s\n' "$LEFT" | head -n 80)"
else
  printf '### 남은 `%s` 문자열 없음\n' "$FROM"
fi
