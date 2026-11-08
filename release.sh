#!/bin/bash
# Mac release: ./release.sh X.Y.Z notes.md
# notes.md holds the "What's new" bullets. The previous release's APK and
# "What you need"/"Install" sections carry over. DRY=1 skips every push/publish
# and restores the tracked files afterwards.
set -euo pipefail
cd "$(dirname "$0")"

V=${1:?usage: release.sh X.Y.Z notes.md}
NOTES=${2:?usage: release.sh X.Y.Z notes.md}
[[ $V =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "bad version: $V" >&2; exit 1; }
[ -f "$NOTES" ] || { echo "no notes file: $NOTES" >&2; exit 1; }

REPO=ike-V/Dirian
TAP=ike-V/dirian
TAPDIR=${TAPDIR:-$HOME/Projects/homebrew-dirian}
CASK=$TAPDIR/Casks/dirian.rb
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

run() { if [ -n "${DRY:-}" ]; then echo "DRY: $*"; else "$@"; fi; }

die() { echo "$1" >&2; [ -n "${DRY:-}" ] || exit 1; }

[ "$(git branch --show-current)" = main ] || die "not on main"
[ -z "$(git status --porcelain --untracked-files=no)" ] || die "Dirian repo not clean"
[ -z "$(git -C "$TAPDIR" status --porcelain --untracked-files=no)" ] || die "tap repo not clean"
git fetch -q
[ "$(git rev-parse HEAD)" = "$(git rev-parse '@{u}')" ] || die "main differs from origin"
if gh release view "v$V" --repo $REPO >/dev/null 2>&1; then echo "v$V already exists" >&2; exit 1; fi

W=$(mktemp -d)
PREV=$(gh release list --repo $REPO --json tagName,isLatest --jq '.[]|select(.isLatest)|.tagName')
echo "==> Previous release $PREV"
gh release download "$PREV" --repo $REPO --pattern 'Dirian-for-Android-*.apk' --dir "$W"
APK=$(cd "$W" && ls Dirian-for-Android-*.apk | sort -V | tail -1)
APK_SHA=$(shasum -a 256 "$W/$APK" | cut -d' ' -f1)
APK_VER=${APK#Dirian-for-Android-}; APK_VER=${APK_VER%.apk}

{
  echo "## What's new"; echo
  cat "$NOTES"
  echo "- Dirian for Android $APK_VER, unchanged release. SHA-256: \`$APK_SHA\`"
  echo
  gh release view "$PREV" --repo $REPO --json body --jq .body | sed -n '/^## What you need/,$p'
} > "$W/notes.md"

echo "==> Release notes for v$V:"; echo; cat "$W/notes.md"; echo
if [ -z "${DRY:-}" ] && [ -z "${YES:-}" ]; then
  [ -t 0 ] || { echo "no terminal to confirm on; set YES=1 to skip the prompt" >&2; exit 1; }
  read -r -p "Publish v$V with these notes? [y/N] " ANSWER
  [ "$ANSWER" = y ] || { echo "aborted, nothing pushed"; exit 1; }
fi

echo "==> Bumping to $V"
sed -i '' -E "/CFBundleShortVersionString/{n;s|<string>[^<]*</string>|<string>$V</string>|;}" Resources/Info.plist
sed -i '' -E "s#releases/tag/v[0-9.]+#releases/tag/v$V#; s#\[v[0-9.]+ release\]#[v$V release]#" README.md
run git add Resources/Info.plist README.md
run git commit -q -m "Dirian $V"
run git push -q

echo "==> Building"
./build.sh
ditto -c -k --keepParent Dirian.app "$W/Dirian-$V.zip"
SHA=$(shasum -a 256 "$W/Dirian-$V.zip" | cut -d' ' -f1)

echo "==> Publishing v$V"
run gh release create "v$V" "$W/Dirian-$V.zip" "$W/$APK" --repo $REPO --title "Dirian $V" --notes-file "$W/notes.md"
if [ -z "${DRY:-}" ]; then
  mkdir "$W/check"
  gh release download "v$V" --repo $REPO --pattern "Dirian-$V.zip" --dir "$W/check"
  [ "$(shasum -a 256 "$W/check/Dirian-$V.zip" | cut -d' ' -f1)" = "$SHA" ] || { echo "downloaded zip hash differs" >&2; exit 1; }
  echo "Downloaded zip matches $SHA"
fi

echo "==> Updating cask"
sed -i '' -E "s/^  version \".*\"/  version \"$V\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
if [ -z "${DRY:-}" ]; then
  WAS_TAPPED=$(brew tap | grep -c -x -i "$TAP" || true)
  [ "$WAS_TAPPED" = 0 ] && brew tap $TAP
  cp "$CASK" "$(brew --repository $TAP)/Casks/dirian.rb"
  brew fetch --cask --force $TAP/dirian
  brew audit --cask --online $TAP/dirian
  git -C "$TAPDIR" add Casks/dirian.rb
  git -C "$TAPDIR" commit -q -m "Update Dirian to $V"
  git -C "$TAPDIR" push -q
  brew untap $TAP && brew tap $TAP
  brew audit --cask --online $TAP/dirian
  [ "$WAS_TAPPED" = 0 ] && brew untap $TAP
fi

if [ -n "${DRY:-}" ]; then
  echo "==> DRY: notes would be:"; cat "$W/notes.md"
  git diff --stat; git -C "$TAPDIR" diff --stat
  git checkout -- Resources/Info.plist README.md
  git -C "$TAPDIR" checkout -- Casks/dirian.rb
  ./build.sh >/dev/null
fi
rm -rf "$W"
echo "==> Done: Dirian $V"
