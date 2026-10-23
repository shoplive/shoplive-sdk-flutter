#!/usr/bin/env bash
# [SMV-1723] 버튼(Release Flutter SDK) — <V> 로 버전을 올리는 PR 을 연다. 태그도 발행도 하지 않는다(그건 PR 머지 뒤).
#
#   scripts/release-flutter-prepare.sh <V>      (GITHUB_REPOSITORY · GH_TOKEN · origin 이 있는 main 클론에서)
#
# 순서 — 읽기만 하는 검사를 모두 통과한 뒤에 쓴다(브랜치·PR).
#   1. 이미 나간 버전인가: 태그 <V> · pub.dev 의 <V>(pub.dev 는 같은 버전을 다시 올릴 수 없다)
#   2. 같은 버전의 PR 이 열려 있으면 새로 만들지 않고 PR 빌드만 다시 부른다
#   3. 기준 트리: 3.x = main, 1.x = release/v1(없으면 마지막 1.x 태그에서 만든다)
#   4. 기준 트리의 현재 버전 < <V>
#   5. 네이티브 <V> 가 공개됐는가(Android POM · iOS Release/Package.swift 또는 pod-specs · 네이티브 Release 노트)
#   6. (1.x) release/v1 의 배포 자동화가 main 과 같은가 — 다르면 사람이 맞춘다(GITHUB_TOKEN 은 워크플로 파일을 쓸 수 없다)
#   7. 버전 올리기(release-flutter-bump.sh) → 커밋 → release-flutter/<V> push → PR → PR 빌드(workflow_dispatch)
# 원격 조회가 실패하면 "없음" 으로 읽지 않고 멈춘다.
set -euo pipefail
SRC=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scripts/release-flutter-lib.sh
. "$SRC/scripts/release-flutter-lib.sh"
cd "$SRC"

VERSION=${1:-}
is_semver "$VERSION" || die "버전 형식이 올바르지 않습니다: '${VERSION}' — 접두사 없는 x.y.z (예: 3.0.4 · 1.9.1)."
MAJOR=${VERSION%%.*}
BASE=$(line_base "$MAJOR") || die "${VERSION}: 이 버튼은 3.x(main) · 1.x(release/v1) 만 냅니다."
REPO=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY 가 필요합니다}
# 배포 자동화의 정본은 main 이다. 다른 브랜치에서 누르면 그 브랜치의 스크립트로 PR 을 만들게 된다.
if [[ -n "${GITHUB_REF:-}" && "$GITHUB_REF" != "refs/heads/main" ]]; then
  die "main 에서 실행하세요(지금 ${GITHUB_REF}) — Actions 에서 'Use workflow from: main'."
fi
HEAD_BRANCH="${PR_BRANCH_PREFIX}${VERSION}"
PACKAGES=$(line_packages "$MAJOR")
BOT_NAME="github-actions[bot]"
BOT_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"

# PR 빌드(1단계 CI)를 그 브랜치로 부른다. GITHUB_TOKEN 이 연 PR 은 pull_request 워크플로를 깨우지 않지만(또는 승인 대기),
# workflow_dispatch 는 GITHUB_TOKEN 으로도 돈다. 기준 트리에 pr-build.yml 이 없으면(1.x) 부르지 않고 알린다.
# TODO(SDP-VERIFY): 요확인 — workflow_dispatch 로 돈 PR build 의 체크가 PR 의 Checks 에 붙는지 첫 3.x 릴리스 PR 에서 확인 · 근거 SMV-1723
dispatch_ci() {  # dispatch_ci <commit> — CI_NOTE(PR 본문 한 줄)를 채운다. 부르지 못하면 1.
  if ! git cat-file -e "$1:.github/workflows/${PR_BUILD_WORKFLOW}" 2>/dev/null; then
    warn "${BASE} 트리에는 ${PR_BUILD_WORKFLOW} 가 없어 PR 빌드를 부르지 않았습니다 — example 빌드를 손으로 확인하세요."
    CI_NOTE="이 라인에는 PR build 가 없습니다 — example 앱 Android/iOS 빌드를 손으로 확인한 뒤 머지하세요."
    return 0
  fi
  if gh workflow run "$PR_BUILD_WORKFLOW" --repo "$REPO" --ref "$HEAD_BRANCH"; then
    notice "PR 빌드를 ${HEAD_BRANCH} 로 불렀습니다 — 결과는 PR 의 Checks 와 Actions 탭에서 봅니다."
    CI_NOTE="PR build 를 \`${HEAD_BRANCH}\` 로 실행했습니다(workflow_dispatch). 통과를 보고 머지하세요."
    return 0
  fi
  CI_NOTE="**PR build 를 부르지 못했습니다** — Actions → PR build → Run workflow(브랜치 \`${HEAD_BRANCH}\`)로 돌리고 통과를 본 뒤 머지하세요."
  return 1
}

# ---------------------------------------------------------------------------
# 1. 이미 나간 버전인가
# ---------------------------------------------------------------------------
TAG_SHA=$(remote_ref "refs/tags/${VERSION}")
if [[ -n "$TAG_SHA" ]]; then
  die "태그 ${VERSION} 이 이미 있습니다 — 발행됐거나 발행 중인 버전입니다. 발행이 덜 끝났다면 Publish Flutter SDK 를 태그 ${VERSION} 로 다시 실행하세요(RELEASING.md)."
fi
for entry in $PACKAGES; do
  name=${entry#*:}
  st=$(pub_state "$name" "$VERSION")
  if [[ "$st" == published ]]; then
    die "pub.dev 에 ${name} ${VERSION} 이 이미 있습니다 — pub.dev 는 같은 버전을 다시 올릴 수 없습니다. 다음 버전으로 누르세요."
  fi
done

# ---------------------------------------------------------------------------
# 2. 같은 버전의 PR
# ---------------------------------------------------------------------------
HB_SHA=$(remote_ref "refs/heads/${HEAD_BRANCH}")
if [[ -n "$HB_SHA" ]]; then
  PR_URL=$(gh pr list --repo "$REPO" --head "$HEAD_BRANCH" --state open --json url --jq '.[0].url // ""') \
    || die "열린 PR 을 조회하지 못했습니다 — 다시 누르세요."
  [[ -n "$PR_URL" ]] || die "브랜치 ${HEAD_BRANCH} 가 남아 있는데 열린 PR 이 없습니다 — 닫은 PR 의 브랜치라면 지우고 다시 누르세요."
  notice "${VERSION} 의 PR 이 이미 열려 있습니다: ${PR_URL} — 새로 만들지 않고 PR 빌드만 다시 부릅니다."
  git fetch -q origin "refs/heads/${HEAD_BRANCH}" || die "${HEAD_BRANCH} 를 받지 못했습니다 — 다시 누르세요."
  CI_NOTE=""
  dispatch_ci FETCH_HEAD || die "PR 빌드를 부르지 못했습니다 — Actions → PR build → Run workflow(브랜치 ${HEAD_BRANCH})로 돌리세요."
  summary "### ${VERSION}: 이미 열린 PR ${PR_URL}" "" "${CI_NOTE}"
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. 기준 트리
# ---------------------------------------------------------------------------
git fetch -q --tags --force origin || die "origin 에서 태그를 받지 못했습니다 — 다시 누르세요."
BASE_SHA=$(remote_ref "refs/heads/${BASE}")
CREATE_FROM=""
if [[ -z "$BASE_SHA" ]]; then
  [[ "$MAJOR" == 1 ]] || die "${BASE} 브랜치가 없습니다."
  CREATE_FROM=$(line_tag_max "$MAJOR")
  [[ -n "$CREATE_FROM" ]] || die "${MAJOR}.x 태그가 없어 ${BASE} 를 만들 수 없습니다."
  BASE_SHA=$(git rev-parse "${CREATE_FROM}^{commit}")
  log "기준 브랜치 ${BASE} 없음 — 마지막 ${MAJOR}.x 태그 ${CREATE_FROM} (${BASE_SHA:0:9}) 에서 만듭니다."
else
  git fetch -q origin "+refs/heads/${BASE}:refs/remotes/origin/${BASE}" || die "${BASE} 를 받지 못했습니다 — 다시 누르세요."
  BASE_SHA=$(git rev-parse "refs/remotes/origin/${BASE}^{commit}")
  log "기준 브랜치 ${BASE} @ ${BASE_SHA:0:9}"
fi
WORK=$(mktemp -d)
WT="${WORK}/base"
cleanup() { git -C "$SRC" worktree remove --force "$WT" > /dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT
git worktree add -q --detach "$WT" "$BASE_SHA" || die "기준 트리를 꺼내지 못했습니다."

# ---------------------------------------------------------------------------
# 4. 현재 버전 < V
# ---------------------------------------------------------------------------
[[ -f "${WT}/${LINE_PRIMARY_DIR}/pubspec.yaml" ]] || die "${BASE} 에 ${LINE_PRIMARY_DIR}/pubspec.yaml 이 없습니다."
OLD=$(pubspec_version < "${WT}/${LINE_PRIMARY_DIR}/pubspec.yaml")
is_semver "$OLD" || die "${BASE} 의 ${LINE_PRIMARY_DIR}/pubspec.yaml version 을 읽지 못했습니다: '${OLD}'"
for entry in $PACKAGES; do
  dir=${entry%%:*}
  [[ -f "${WT}/${dir}/pubspec.yaml" ]] || die "${BASE} 에 ${dir}/ 가 없습니다 — ${MAJOR}.x 라인의 트리가 아닙니다."
  v=$(pubspec_version < "${WT}/${dir}/pubspec.yaml")
  [[ "$v" == "$OLD" ]] || die "${BASE} 의 패키지 버전이 서로 다릅니다(${LINE_PRIMARY_DIR} ${OLD} · ${dir} ${v}) — 같은 버전이어야 합니다."
done
[[ "${OLD%%.*}" == "$MAJOR" ]] || die "${BASE} 의 현재 버전은 ${OLD} 입니다 — ${VERSION} 과 라인이 다릅니다."
if [[ "$OLD" == "$VERSION" ]]; then
  die "${BASE} 가 이미 ${VERSION} 입니다. 그 버전의 release PR 이 머지됐는데 태그가 없다면 'Release Flutter SDK on merge' 를 그 PR 번호로 실행하세요(RELEASING.md)."
fi
semver_gt "$VERSION" "$OLD" || die "${VERSION} 은 ${BASE} 의 현재 버전 ${OLD} 보다 높아야 합니다."
PREV=$(line_tag_max "$MAJOR" "$VERSION")
[[ -n "$PREV" ]] || die "${VERSION} 보다 낮은 ${MAJOR}.x 태그가 없어 CHANGELOG 범위를 정할 수 없습니다."
git merge-base --is-ancestor "${PREV}^{commit}" "$BASE_SHA" || die "직전 태그 ${PREV} 가 ${BASE} 에 들어 있지 않습니다 — CHANGELOG 범위를 정할 수 없습니다."
log "현재 ${OLD} → ${VERSION} · CHANGELOG 범위 ${PREV}..${BASE}"

# ---------------------------------------------------------------------------
# 5. 네이티브 V 공개 확인
# ---------------------------------------------------------------------------
MISSING=""
miss() { MISSING="${MISSING}"$'\n'"  - $*"; }
probe() {  # probe <설명> <url> → 404 면 MISSING 에 넣는다
  local code
  code=$(http_get "$2" /dev/null)
  if [[ "$code" == 404 ]]; then miss "$1 — $2"; fi
}
# Android: build.gradle 이 받는 cloud.shoplive 좌표(3.x 는 버전 문자열, 1.x 는 $shoplive_sdk_version)
android_artifacts() {
  GRADLE_OLD=$(re_ver "$OLD") perl -ne '
    print "$1\n" if /implementation\("cloud\.shoplive:([a-z0-9-]+):$ENV{GRADLE_OLD}"\)/;
    print "$1\n" if /implementation "cloud\.shoplive:([a-z0-9-]+):\$shoplive_sdk_version"/;' "$1"
}
NATIVE_LINKS="[Android ${VERSION}](https://github.com/${ANDROID_REPO}/releases/tag/${VERSION}) · [iOS ${VERSION}](https://github.com/${IOS_REPO}/releases/tag/${VERSION})"
probe "Android Release 노트 ${VERSION}" "${GH_API}/repos/${ANDROID_REPO}/releases/tags/${VERSION}"
for entry in $PACKAGES; do
  dir=${entry%%:*}
  arts=$(android_artifacts "${WT}/${dir}/android/build.gradle")
  [[ -n "$arts" ]] || die "${dir}/android/build.gradle 에서 cloud.shoplive 좌표를 읽지 못했습니다 — 파일 모양이 바뀌었습니다."
  for a in $arts; do
    probe "Android ${a}:${VERSION}" "${MAVEN_REPO}/cloud/shoplive/${a}/${VERSION}/${a}-${VERSION}.pom"
  done
done
SUMS=""
if [[ "$MAJOR" == 3 ]]; then
  # iOS 3.x: shoplive-sdk-ios Release <V> 의 zip(pod install 이 받는 것) + 태그 <V> 의 Package.swift checksum(podspec sha256)
  NAMES=""
  for entry in $PACKAGES; do
    dir=${entry%%:*}; name=${entry#*:}
    n=$(perl -ne "print \"\$1\n\" if /^\s*'(\w+)' => '[0-9a-f]{64}',?\s*\$/" "${WT}/${dir}/ios/${name}.podspec")
    [[ -n "$n" ]] || die "${dir}/ios/${name}.podspec 에서 XCFramework 목록을 읽지 못했습니다."
    NAMES="${NAMES} ${n}"
  done
  code=$(http_get "${GH_API}/repos/${IOS_REPO}/releases/tags/${VERSION}" "${WORK}/ios-release.json")
  if [[ "$code" == 404 ]]; then
    miss "iOS Release ${VERSION} — https://github.com/${IOS_REPO}/releases/tag/${VERSION}"
  else
    assets=$(jq -r '.assets[].name' "${WORK}/ios-release.json") || die "iOS Release ${VERSION} 응답을 읽지 못했습니다."
    for n in $NAMES; do
      grep -qxF "${n}.xcframework.zip" <<< "$assets" || miss "iOS Release ${VERSION} 의 ${n}.xcframework.zip"
    done
  fi
  code=$(http_get "${GH_API}/repos/${IOS_REPO}/contents/Package.swift?ref=${VERSION}" "${WORK}/Package.swift" "application/vnd.github.raw")
  if [[ "$code" == 404 ]]; then
    miss "iOS ${IOS_REPO}@${VERSION} 의 Package.swift"
  else
    SUMS="${WORK}/ios-checksums.txt"
    # let <이름> = "<64hex>" 상수와 .binaryTarget(name:, checksum:) 를 묶는다(checksum 이 상수 이름이든 문자열이든).
    perl -e '
      local $/; my $s = <STDIN>; my %c;
      while ($s =~ /\blet\s+(\w+)\s*=\s*"([0-9a-f]{64})"/g) { $c{$1} = $2 }
      my ($v) = $s =~ /\blet\s+sdkVersion\s*=\s*"([^"]*)"/;
      print "#sdkVersion ", (defined $v ? $v : ""), "\n";
      my @chunks = split /\.binaryTarget\s*\(/, $s; shift @chunks;
      for my $b (@chunks) {
        my ($n) = $b =~ /name:\s*"([^"]+)"/ or next;
        my $sum;
        if ($b =~ /checksum:\s*"([0-9a-f]{64})"/) { $sum = $1 } elsif ($b =~ /checksum:\s*(\w+)/) { $sum = $c{$1} }
        print "$n $sum\n" if defined $sum;
      }' < "${WORK}/Package.swift" > "$SUMS"
    sv=$(sed -n 's/^#sdkVersion //p' "$SUMS")
    if [[ -n "$sv" && "$sv" != "$VERSION" ]]; then
      die "${IOS_REPO}@${VERSION} 의 Package.swift sdkVersion 이 ${sv} 입니다 — 태그와 내용이 어긋납니다. iOS 배포를 확인하세요."
    fi
    for n in $NAMES; do
      awk -v n="$n" '$1 == n && $2 ~ /^[0-9a-f]+$/ && length($2) == 64 { f = 1 } END { exit !f }' "$SUMS" \
        || miss "iOS Package.swift@${VERSION} 의 ${n} checksum"
    done
  fi
else
  # iOS 1.x: shoplive/pod-specs 의 podspec(앱의 pod install 이 이 spec 리포에서 받는다) + iOS Release 노트
  probe "iOS Release 노트 ${VERSION}" "${GH_API}/repos/${IOS_REPO}/releases/tags/${VERSION}"
  for p in $LINE1_IOS_PODS; do
    probe "iOS pod ${p} ${VERSION}" "${GH_API}/repos/${PODSPECS_REPO}/contents/Specs/${p}/${VERSION}/${p}.podspec"
  done
fi
if [[ -n "$MISSING" ]]; then
  die "네이티브 ${VERSION} 이 아직 공개되지 않았습니다(네이티브 배포가 끝난 뒤 다시 누르세요):${MISSING}"
fi
log "네이티브 ${VERSION} 공개 확인 — ${NATIVE_LINKS}"

# ---------------------------------------------------------------------------
# 6. (1.x) 기준 브랜치 만들기 · 배포 자동화 확인
# ---------------------------------------------------------------------------
if [[ -n "$CREATE_FROM" ]]; then
  gh api -X POST "repos/${REPO}/git/refs" -f "ref=refs/heads/${BASE}" -f "sha=${BASE_SHA}" > /dev/null \
    || die "${BASE} 를 만들지 못했습니다(${CREATE_FROM} ${BASE_SHA:0:9}) — 다시 누르세요."
  notice "${BASE} 를 ${CREATE_FROM} 에서 만들었습니다."
fi
if [[ "$BASE" != main ]]; then
  STALE=""
  for f in $RELEASE_MACHINERY; do
    cmp -s "${SRC}/${f}" "${WT}/${f}" || STALE="${STALE} ${f}"
  done
  if [[ -n "$STALE" ]]; then
    die "${BASE} 의 배포 자동화가 main 과 다릅니다(${STALE# }). 머지·발행은 ${BASE} 의 파일로 돌고, GITHUB_TOKEN 은 워크플로 파일을 push 할 수 없어 사람이 맞춥니다 — RELEASING.md 의 '1.x: release/v1 맞추기' 를 한 뒤 다시 누르세요."
  fi
fi

# ---------------------------------------------------------------------------
# 7. 버전 올리기 → 커밋 → push → PR → PR 빌드
# ---------------------------------------------------------------------------
BUMP_MD="${WORK}/bump.md"
(
  cd "$WT"
  if [[ -n "$SUMS" ]]; then
    bash "${SRC}/scripts/release-flutter-bump.sh" --to "$VERSION" --since "$PREV" --ios-checksums "$SUMS"
  else
    bash "${SRC}/scripts/release-flutter-bump.sh" --to "$VERSION" --since "$PREV"
  fi
) > "$BUMP_MD" || die "버전 올리기에 실패했습니다(위 오류)."
git -C "$WT" add -u
git -C "$WT" -c user.name="$BOT_NAME" -c user.email="$BOT_EMAIL" commit -q \
  -m "Release Flutter SDK ${VERSION}" \
  -m "Shoplive SDK ${VERSION} (Android/iOS) 로 버전을 올린다 — Release Flutter SDK 버튼이 만든 커밋." \
  || die "커밋하지 못했습니다."
git -C "$WT" push -q origin "HEAD:refs/heads/${HEAD_BRANCH}" || die "${HEAD_BRANCH} 를 push 하지 못했습니다 — 다시 누르세요."

# PR 빌드는 PR 보다 먼저 부른다(브랜치는 이미 있다) — 결과 한 줄을 본문에 그대로 넣는다.
CI_NOTE=""; CI_FAILED=""
dispatch_ci "$(git -C "$WT" rev-parse HEAD)" || CI_FAILED=1

BODY="${WORK}/pr-body.md"
# shellcheck disable=SC2016  # 아래 printf 의 백틱은 마크다운이다(셸 확장 아님).
{
  printf 'Shoplive Flutter SDK **%s** — `%s` 기준, Release Flutter SDK 버튼이 연 PR 입니다.\n\n' "$VERSION" "$BASE"
  printf -- '- 네이티브 %s: %s (Android POM · iOS ' "$VERSION" "$NATIVE_LINKS"
  if [[ "$MAJOR" == 3 ]]; then printf 'Release zip · Package.swift checksum'; else printf 'pod-specs'; fi
  printf ' 확인함)\n'
  printf -- '- 패키지: %s\n' "$(for e in $PACKAGES; do printf '`%s` ' "${e#*:}"; done)"
  printf -- '- CHANGELOG: 고정 문구 + 네이티브 Release 링크 + `%s` 이후 각 패키지 폴더의 커밋 제목. 고객에게 보이는 글이니 필요하면 이 PR 에서 다듬으세요.\n' "$PREV"
  printf -- '- PR 빌드: %s\n\n' "$CI_NOTE"
  printf '**머지하면** 머지 커밋에 태그 `%s` 가 붙고, Publish Flutter SDK 가 pub.dev 발행(' "$VERSION"
  if [[ "$MAJOR" == 3 ]]; then printf 'shoplive_core → shoplive_player · shoplive_streamer'; else printf 'shoplive_player'; fi
  printf ')과 GitHub Release `%s` 를 합니다. pub.dev 는 같은 버전을 다시 올릴 수 없으니 머지 전에 확인하세요.\n\n' "$VERSION"
  cat "$BUMP_MD"
} > "$BODY"

PR_URL=$(gh pr create --repo "$REPO" --base "$BASE" --head "$HEAD_BRANCH" \
  --title "Release Flutter SDK ${VERSION}" --body-file "$BODY") || {
  # 브랜치만 남으면 다시 눌러도 "열린 PR 없는 브랜치" 로 멈춘다 — 지우고 끝낸다.
  git push -q origin --delete "$HEAD_BRANCH" || warn "브랜치 ${HEAD_BRANCH} 를 지우지 못했습니다 — 지우고 다시 누르세요."
  die "PR 을 열지 못했습니다 — 다시 누르세요."
}
notice "PR: ${PR_URL}"
summary "### Release Flutter SDK ${VERSION}" "" "- PR: ${PR_URL}" "- 기준: \`${BASE}\` (${OLD} → ${VERSION})" "- ${CI_NOTE}"
if [[ -n "$CI_FAILED" ]]; then
  die "PR 은 열었지만 PR 빌드를 부르지 못했습니다 — Actions → PR build → Run workflow(브랜치 ${HEAD_BRANCH})로 돌리세요. 같은 버전으로 버튼을 다시 눌러도 PR 빌드만 다시 부릅니다."
fi
