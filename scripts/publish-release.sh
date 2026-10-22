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
# On failure, gh's message goes into the error annotation, which can be read without the log.
if ! OUT="$(gh release create "$TAG" dist/*.dmg dist/*.sha256 \
  --repo "$GITHUB_REPOSITORY" --target "$SHA" --latest \
  --title "Two Degrees ${TAG##*v}" \
  --notes-file "$RUNNER_TEMP/notes.md" 2>&1)"; then
  echo "::error::Couldn't publish $TAG:%0A${OUT//$'\n'/%0A}"
  exit 1
fi
echo "$OUT"
