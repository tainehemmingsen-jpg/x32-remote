#!/bin/bash
# Pushes CI output (logs + screenshots) to the ci-results branch so it can be read with plain git.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/ci-out}"
TMP=$(mktemp -d)
cp -R "$OUT"/. "$TMP"/
echo "${GITHUB_SHA:-local}" > "$TMP/SHA.txt"
date -u > "$TMP/DATE.txt"
cd "$TMP"
git init -q
git config user.name "ci"
git config user.email "ci@users.noreply.github.com"
git checkout -q -b ci-results
git add -A
git commit -q -m "CI results for ${GITHUB_SHA:-local}"
git push -q -f "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" ci-results
echo "published to ci-results"
