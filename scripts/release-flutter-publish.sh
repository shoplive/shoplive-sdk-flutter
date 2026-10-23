#!/usr/bin/env bash
# [SMV-1723] Publish Flutter SDK 의 단계들. 워크플로가 태그 <V> 를 체크아웃한 클론(리포 루트)에서 부른다.
#
#   plan                 태그·트리 검사 → 발행할 패키지 결정(pub.dev 에 이미 있으면 건너뜀) → GITHUB_OUTPUT
#   publish <폴더>        pub.dev 에 없으면 flutter pub publish --force (setup-dart 가 만든 OIDC 토큰으로)
#   wait [<패키지>]       pub.dev API 에 <V> 가 보일 때까지(기본: 라인의 core) 기다린다(상한 RELEASE_POLL_ATTEMPTS × RELEASE_POLL_INTERVAL 초)
#   release              모든 패키지가 pub.dev 에 있으면 GitHub Release <V>(노트 = 각 CHANGELOG 의 <V> 절)
#
# 다시 실행해도 된다 — 이미 pub.dev 에 있는 패키지는 건너뛰고, Release 가 이미 있으면 만들지 않는다.
# 그래서 중간에 실패하면 같은 태그로 이 워크플로를 다시 실행하는 것이 복구다(RELEASING.md).
set -euo pipefail
# shellcheck source=scripts/release-flutter-lib.sh
. "$(cd "$(dirname "$0")" && pwd)/release-flutter-lib.sh"

REPO=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY 가 필요합니다}
# 버전은 태그 이름이다. 브랜치에서 부르면 pub.dev 가 거절하므로(refType tag 만 받음) 여기서 먼저 멈춘다.
[[ "${GITHUB_REF:-}" == refs/tags/* ]] || die "태그에서 실행하세요(지금 '${GITHUB_REF:-}') — Actions → Publish Flutter SDK → 'Use workflow from' 에서 태그 <V> 를 고릅니다."
VERSION=${GITHUB_REF#refs/tags/}
is_semver "$VERSION" || die "태그 ${VERSION} 는 x.y.z 가 아닙니다."
MAJOR=${VERSION%%.*}
BASE=$(line_base "$MAJOR") || die "${VERSION}: 1.x · 3.x 만 발행합니다."
PACKAGES=$(line_packages "$MAJOR")
CORE=$(line_core "$MAJOR")

pkg_name() {  # pkg_name <폴더> → pub 이름(라인 표에 없는 폴더면 멈춘다)
  local e
  for e in $PACKAGES; do
    if [[ "${e%%:*}" == "$1" ]]; then echo "${e#*:}"; return 0; fi
  done
  die "$1 은 ${MAJOR}.x 라인의 패키지 폴더가 아닙니다."
}

cmd_plan() {
  local sha entry dir name v st core_flag=false core_dir="" deps="" pending=""
  sha=$(git rev-parse HEAD)
  # 태그가 기준 브랜치에 들어 있어야 한다 — 머지되지 않은 커밋에 붙은 태그로는 발행하지 않는다.
  git fetch -q --no-tags origin "+refs/heads/${BASE}:refs/remotes/origin/${BASE}" || die "${BASE} 를 받지 못했습니다 — 다시 실행하세요."
  git merge-base --is-ancestor "$sha" "refs/remotes/origin/${BASE}" \
    || die "태그 ${VERSION} (${sha:0:9}) 가 ${BASE} 에 없습니다 — release PR 이 머지된 커밋의 태그여야 합니다."
  for entry in $PACKAGES; do
    dir=${entry%%:*}; name=${entry#*:}
    v=$(pubspec_version < "${dir}/pubspec.yaml")
    [[ "$v" == "$VERSION" ]] || die "태그 ${VERSION} 의 ${dir}/pubspec.yaml 버전이 ${v} 입니다 — 발행하지 않습니다."
    st=$(pub_state "$name" "$VERSION")
    if [[ "$st" == published ]]; then
      notice "${name} ${VERSION} 은 이미 pub.dev 에 있습니다 — 건너뜁니다."
      continue
    fi
    pending="${pending} ${name}"
    if [[ "$name" == "$CORE" ]]; then
      core_flag=true; core_dir=$dir
    else
      deps="${deps:+${deps},}{\"dir\":\"${dir}\",\"name\":\"${name}\"}"
    fi
  done
  log "태그 ${VERSION} @ ${sha:0:9} · 발행할 것:${pending:- 없음(Release 만 확인)}"
  {
    echo "version=${VERSION}"
    echo "line=${MAJOR}"
    echo "core=${core_flag}"
    echo "core_dir=${core_dir}"
    echo "dependents=[${deps}]"
  } >> "${GITHUB_OUTPUT:-/dev/stdout}"
  summary "### Publish Flutter SDK ${VERSION}" "" "- 발행할 것:${pending:- 없음}"
}

cmd_publish() {
  local dir=${1:-} name v st
  [[ -n "$dir" ]] || die "publish <폴더>"
  name=$(pkg_name "$dir")
  v=$(pubspec_version < "${dir}/pubspec.yaml")
  [[ "$v" == "$VERSION" ]] || die "${dir}/pubspec.yaml 버전 ${v} ≠ 태그 ${VERSION}"
  st=$(pub_state "$name" "$VERSION")
  if [[ "$st" == published ]]; then
    notice "${name} ${VERSION} 은 이미 pub.dev 에 있습니다 — 건너뜁니다."; return 0
  fi
  # setup-dart 가 이 job 의 OIDC 토큰(audience https://pub.dev)을 PUB_TOKEN 에 넣는다. 없으면 id-token: write 가 빠진 것이다.
  [[ -n "${PUB_TOKEN:-}" ]] || die "PUB_TOKEN 이 없습니다 — 이 job 에 permissions: id-token: write 와 dart-lang/setup-dart 가 있어야 합니다."
  # setup-dart 는 자기 dart 로 'dart pub token add https://pub.dev --env-var PUB_TOKEN' 을 한다. 발행은 flutter(고정 버전)의 pub 로
  # 하므로 같은 등록을 그 pub 에도 한다(토큰은 같은 PUB_TOKEN — 새로 만들지 않는다).
  # TODO(SDP-VERIFY): 요확인 — Flutter 3.22.1 의 pub 가 이 등록으로 pub.dev 에 인증되는지(로컬에선 명령 동작만 확인) 첫 실발행에서 확인 · 근거 SMV-1723
  flutter pub token add https://pub.dev --env-var PUB_TOKEN > /dev/null || die "flutter pub token add 실패"
  # --force: 경고(예: shoplive_core 를 같은 버전으로 고정)는 넘기고, 오류는 멈춘다.
  (cd "$dir" && flutter pub publish --force) || die "${name} ${VERSION} 발행 실패 — 원인을 고친 뒤 이 워크플로를 같은 태그로 다시 실행하면 남은 패키지만 발행합니다."
  notice "${name} ${VERSION} 발행"
  summary "- ${name} ${VERSION} → https://pub.dev/packages/${name}/versions/${VERSION}"
}

cmd_wait() {  # 인자가 없으면 라인의 core(3.x shoplive_core). 라인에 core 가 없으면(1.x) 바로 끝난다.
  local name=${1:-$CORE} i st
  if [[ -z "$name" ]]; then log "${MAJOR}.x 는 먼저 보여야 할 패키지가 없습니다."; return 0; fi
  for (( i = 1; i <= RELEASE_POLL_ATTEMPTS; i++ )); do
    st=$(pub_state "$name" "$VERSION")
    if [[ "$st" == published ]]; then log "${name} ${VERSION} 이 pub.dev 에 보입니다(${i}회째)."; return 0; fi
    if (( i < RELEASE_POLL_ATTEMPTS )); then sleep "$RELEASE_POLL_INTERVAL"; fi
  done
  die "${name} ${VERSION} 이 $(( RELEASE_POLL_ATTEMPTS * RELEASE_POLL_INTERVAL ))초 안에 pub.dev 에 보이지 않습니다 — 이 워크플로를 같은 태그로 다시 실행하세요."
}

# changelog_body <폴더> → CHANGELOG 의 "## <V>" 절 본문(다음 "## " 전까지)
changelog_body() {
  awk -v h="## ${VERSION}" '
    $0 == h || index($0, h " ") == 1 { on = 1; next }
    on && /^## / { exit }
    on { print }' "$1/CHANGELOG.md"
}

cmd_release() {
  local code entry dir name st missing="" notes body
  code=$(http_get "${GH_API}/repos/${REPO}/releases/tags/${VERSION}" /dev/null)
  if [[ "$code" == 200 ]]; then notice "GitHub Release ${VERSION} 가 이미 있습니다 — 건너뜁니다."; return 0; fi
  for entry in $PACKAGES; do
    name=${entry#*:}
    st=$(pub_state "$name" "$VERSION")
    [[ "$st" == published ]] || missing="${missing} ${name}"
  done
  [[ -z "$missing" ]] || die "pub.dev 에 아직 없는 패키지가 있어 Release 를 만들지 않습니다:${missing} — 이 워크플로를 같은 태그로 다시 실행하세요."
  notes=$(mktemp)
  for entry in $PACKAGES; do
    dir=${entry%%:*}; name=${entry#*:}
    body=$(changelog_body "$dir")
    [[ -n "${body//[[:space:]]/}" ]] || die "${dir}/CHANGELOG.md 에 ## ${VERSION} 절이 없습니다."
    if [[ "$MAJOR" == 3 ]]; then printf '## %s %s\n' "$name" "$VERSION" >> "$notes"; fi
    printf '%s\n\n' "$body" >> "$notes"
  done
  # 3.x 만 Latest. 1.x 는 유지보수 라인이라 Latest 를 빼앗지 않는다.
  local latest=--latest=false
  if [[ "$MAJOR" == 3 ]]; then latest=--latest; fi
  gh release create "$VERSION" --repo "$REPO" --verify-tag --title "$VERSION" --notes-file "$notes" "$latest" > /dev/null \
    || die "GitHub Release ${VERSION} 를 만들지 못했습니다 — 이 워크플로를 같은 태그로 다시 실행하세요(pub.dev 발행은 건너뜁니다)."
  rm -f "$notes"
  notice "GitHub Release ${VERSION} (${latest#--})"
  summary "- GitHub Release https://github.com/${REPO}/releases/tag/${VERSION}"
}

case "${1:-}" in
  plan) cmd_plan ;;
  publish) shift; cmd_publish "$@" ;;
  wait) shift; cmd_wait "$@" ;;
  release) cmd_release ;;
  *) die "사용법: $0 plan | publish <폴더> | wait [<패키지>] | release" ;;
esac
