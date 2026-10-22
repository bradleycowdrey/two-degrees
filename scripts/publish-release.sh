#!/usr/bin/env bash
# CI: publishes dist/*.dmg and dist/*.sha256 as release $1 at commit $2, with this version's section of
# CHANGELOG.md as the notes. $3 = "signed" when the app is signed and notarized. Never replaces a
# published version's files: bump VERSION to release new code.
set -euo pipefail
TAG="$1"; SHA="$2"; SIGNED="${3:-}"
if gh release view "$TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  echo "Release $TAG already exists; not overwriting it."
  exit 0
fi
CHANGES="$(awk -v v="## [${TAG##*v}]" 'index($0, v) == 1 {on=1; next} on && /^## \[/ {exit} on' CHANGELOG.md)"
if [[ "$SIGNED" == "signed" ]]; then
  OPEN=" It's signed and notarized by Apple, so it opens like any other app."
else
  OPEN=" First launch: right-click Two Degrees, then Open."
fi
printf '%s\n\n%s\n' "${CHANGES:-See CHANGELOG.md for what changed.}" \
  "**Install:** download the DMG, open it and drag Two Degrees into Applications.$OPEN For a widget: right-click the desktop, choose Edit Widgets and search for Two Degrees. Made by Bradley Cowdrey · bradcowdrey.com" > "$RUNNER_TEMP/notes.md"
ls -l dist/*.dmg dist/*.sha256
create() {
  gh release create "$TAG" dist/*.dmg dist/*.sha256 \
    --repo "$GITHUB_REPOSITORY" --target "$1" --latest \
    --title "Two Degrees ${TAG##*v}" \
    --notes-file "$RUNNER_TEMP/notes.md" 2>&1
}
# GitHub won't let the workflow token create a tag whose .github/workflows differ from the default
# branch's (HTTP 403). Then tag the default branch instead, but only if everything outside CI (.github,
# scripts) is identical to the built commit, so the tag holds exactly the app that was built and notarized.
if ! OUT="$(create "$SHA")"; then
  HEAD_SHA="$(git rev-parse HEAD)"
  if [[ "$OUT" == *"HTTP 403"* ]] && git diff --quiet "$SHA" "$HEAD_SHA" -- . ':!.github' ':!scripts'; then
    echo "$OUT"
    echo "Tagging $TAG on $HEAD_SHA: only CI files differ from $SHA."
    OUT="$(create "$HEAD_SHA")" || { echo "::error::Couldn't publish $TAG:%0A${OUT//$'\n'/%0A}"; exit 1; }
  else
    echo "::error::Couldn't publish $TAG:%0A${OUT//$'\n'/%0A}%0AIf this is a 403, push the tag yourself (git push origin $SHA:refs/tags/$TAG) and run Finish release again."
    exit 1
  fi
fi
echo "$OUT"
