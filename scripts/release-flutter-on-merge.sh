#!/usr/bin/env bash
# [SMV-1723] release PR 머지 → 머지 커밋에 태그 <V> → Publish Flutter SDK 를 태그 ref 로 부른다.
#
#   scripts/release-flutter-on-merge.sh <PR 번호>      (GITHUB_REPOSITORY · GH_TOKEN · origin 이 있는 클론에서)
#
# release PR = 이 리포의 release-flutter/<V> 브랜치에서 그 라인의 기준 브랜치(3.x main · 1.x release/v1)로 머지된 PR.
# 그 밖(닫기만 함 · 다른 브랜치 · 포크)은 아무것도 하지 않고 정상 종료한다.
# 다시 실행해도 된다: 태그가 이미 머지 커밋에 있으면 발행만 다시 부르고, 다른 커밋에 있으면 멈춘다.
#
# 태그는 GITHUB_TOKEN 으로 만든다 — GITHUB_TOKEN 의 태그는 push 이벤트 워크플로를 깨우지 않으므로 발행은 workflow_dispatch(--ref <V>)로 부른다.
# pub.dev 는 workflow_dispatch 의 태그 ref(refs/tags/<V>)를 받는다(패키지 설정: tag pattern {{version}}, workflow_dispatch 허용).
set -euo pipefail
# shellcheck source=scripts/release-flutter-lib.sh
. "$(cd "$(dirname "$0")" && pwd)/release-flutter-lib.sh"

PR=${1:-}
[[ "$PR" =~ ^[0-9]+$ ]] || die "PR 번호가 필요합니다: '${PR}'"
REPO=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY 가 필요합니다}

JSON=$(gh api "repos/${REPO}/pulls/${PR}") || die "PR #${PR} 를 조회하지 못했습니다 — 판정할 수 없어 멈춥니다. 다시 실행하세요."
# 읽지 못한 응답을 "머지 안 됨" 으로 넘기지 않는다.
jq -e 'type == "object" and (.merged | type == "boolean") and (.head.ref | type == "string") and (.base.ref | type == "string")' \
  <<< "$JSON" > /dev/null 2>&1 || die "PR #${PR} 응답을 읽지 못했습니다 — 판정할 수 없어 멈춥니다. 다시 실행하세요."
field() { jq -r "$1" <<< "$JSON" || exit 1; }
MERGED=$(field '.merged')
HEAD_REPO=$(field '.head.repo.full_name // ""')
HEAD_REF=$(field '.head.ref')
BASE_REF=$(field '.base.ref')
SHA=$(field '.merge_commit_sha // ""')

if [[ "$MERGED" != true ]]; then
  log "PR #${PR} 는 머지되지 않았습니다 — 할 일 없음."; exit 0
fi
if [[ "$HEAD_REF" != "${PR_BRANCH_PREFIX}"* ]]; then
  log "PR #${PR} (${HEAD_REF} → ${BASE_REF}) 는 release PR 이 아닙니다 — 할 일 없음."; exit 0
fi
# 포크의 release-flutter/ 브랜치는 버튼이 연 것이 아니다.
if [[ "$HEAD_REPO" != "$REPO" ]]; then
  warn "PR #${PR} 는 다른 리포(${HEAD_REPO:-삭제된 포크})의 ${HEAD_REF} 입니다 — release PR 로 보지 않습니다."; exit 0
fi
VERSION=${HEAD_REF#"${PR_BRANCH_PREFIX}"}
is_semver "$VERSION" || die "브랜치 ${HEAD_REF} 의 버전이 x.y.z 가 아닙니다."
MAJOR=${VERSION%%.*}
BASE=$(line_base "$MAJOR") || die "${VERSION}: 1.x · 3.x 만 발행합니다."
[[ "$BASE_REF" == "$BASE" ]] || die "release PR ${HEAD_REF} 가 ${BASE_REF} 에 머지됐습니다 — ${VERSION} 의 기준 브랜치는 ${BASE} 입니다. 태그를 만들지 않습니다."
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || die "PR #${PR} 의 머지 커밋을 읽지 못했습니다: '${SHA}'"

# 머지 커밋의 트리가 그 버전인가 · 발행 워크플로가 있는가(태그 ref 로 부르므로 그 트리의 파일로 돈다)
git cat-file -e "${SHA}^{commit}" 2>/dev/null || git fetch -q --no-tags origin "$SHA" || die "머지 커밋 ${SHA} 를 받지 못했습니다."
for entry in $(line_packages "$MAJOR"); do
  dir=${entry%%:*}
  v=$(git show "${SHA}:${dir}/pubspec.yaml" | pubspec_version) || die "${SHA:0:9} 에 ${dir}/pubspec.yaml 이 없습니다."
  [[ "$v" == "$VERSION" ]] || die "머지 커밋 ${SHA:0:9} 의 ${dir} 버전이 ${v} 입니다(${VERSION} 이어야 함) — 태그를 만들지 않습니다."
done
git cat-file -e "${SHA}:.github/workflows/${PUBLISH_WORKFLOW}" 2>/dev/null \
  || die "머지 커밋 ${SHA:0:9} 에 .github/workflows/${PUBLISH_WORKFLOW} 가 없습니다 — 태그 ref 로 발행할 수 없습니다(1.x 면 RELEASING.md 의 'release/v1 맞추기')."

TAG_SHA=$(remote_ref "refs/tags/${VERSION}")
if [[ -z "$TAG_SHA" ]]; then
  gh api -X POST "repos/${REPO}/git/refs" -f "ref=refs/tags/${VERSION}" -f "sha=${SHA}" > /dev/null \
    || die "태그 ${VERSION} 를 만들지 못했습니다 — 이 실행을 다시 실행(Re-run)하세요."
  notice "태그 ${VERSION} → ${SHA:0:9} (PR #${PR})"
elif [[ "$TAG_SHA" == "$SHA" ]]; then
  notice "태그 ${VERSION} 가 이미 머지 커밋 ${SHA:0:9} 에 있습니다 — 발행만 다시 부릅니다."
else
  die "태그 ${VERSION} 가 다른 커밋(${TAG_SHA:0:9})에 있습니다(머지 커밋 ${SHA:0:9}) — 어긋난 상태라 발행하지 않습니다. 태그를 확인하세요."
fi

gh workflow run "$PUBLISH_WORKFLOW" --repo "$REPO" --ref "$VERSION" \
  || die "Publish Flutter SDK 를 부르지 못했습니다 — Actions → Publish Flutter SDK → Run workflow 에서 'Use workflow from' 을 태그 ${VERSION} 로 골라 실행하세요."
notice "Publish Flutter SDK 를 태그 ${VERSION} 로 불렀습니다."
summary "### ${VERSION}: 태그 → 발행" "" "- PR #${PR} 머지 커밋 \`${SHA:0:9}\` 에 태그 \`${VERSION}\`" "- Publish Flutter SDK (ref \`${VERSION}\`) 실행"
