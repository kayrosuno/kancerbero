#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/version.sh"

REMOTE="${GITHUB_REMOTE:-github}"
APP="$(kancerbero_require_release_app "$ROOT")"
kancerbero_read_app_version "$APP"
SRC="$ROOT/build/updates/appcast.xml"
WT="$ROOT/build/gh-pages"

if [[ ! -f "$SRC" ]]; then
    echo "missing $SRC; run scripts/generate-appcast.sh first" >&2
    exit 1
fi

git -C "$ROOT" fetch "$REMOTE" --tags >/dev/null 2>&1 || true
rm -rf "$WT"

if git -C "$ROOT" show-ref --verify --quiet refs/heads/gh-pages; then
    git -C "$ROOT" worktree add --force "$WT" gh-pages
elif git -C "$ROOT" show-ref --verify --quiet "refs/remotes/$REMOTE/gh-pages"; then
    git -C "$ROOT" worktree add --force -B gh-pages "$WT" "$REMOTE/gh-pages"
else
    # Older Git versions lack `worktree add --orphan`; create the branch in a
    # throwaway clone and let the worktree track it.
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    git clone --quiet --no-checkout "$(git -C "$ROOT" remote get-url "$REMOTE")" "$TMP"
    git -C "$TMP" checkout --orphan gh-pages >/dev/null 2>&1
    git -C "$TMP" rm -rf . >/dev/null 2>&1 || true
    git -C "$TMP" commit --allow-empty -m "appcast: initialize gh-pages" >/dev/null
    git -C "$TMP" push --quiet origin gh-pages
    git -C "$ROOT" fetch "$REMOTE" gh-pages >/dev/null 2>&1
    git -C "$ROOT" worktree add --force -B gh-pages "$WT" "$REMOTE/gh-pages"
fi

cp "$SRC" "$WT/appcast.xml"
touch "$WT/.nojekyll"
git -C "$WT" add appcast.xml .nojekyll
git -C "$WT" commit -m "appcast: $VERSION ($BUILD)"
git -C "$WT" push "$REMOTE" gh-pages
git -C "$ROOT" worktree remove --force "$WT"

echo "appcast published: https://kayrosuno.github.io/kancerbero/appcast.xml"
