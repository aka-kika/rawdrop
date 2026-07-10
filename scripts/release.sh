#!/usr/bin/env bash
#
# release.sh — build → sign → notarize → staple → publish a RawDrop release.
#
# One command cuts a full public release. Reads the version from project.yml,
# builds a universal Developer ID-signed app, notarizes and staples the DMG,
# then (unless --no-publish) tags and creates the GitHub release with the
# CHANGELOG notes attached.
#
# The notarization password is NEVER stored here. Provide it one of two ways:
#
#   1. Keychain profile (recommended, one-time setup):
#        xcrun notarytool store-credentials rawdrop-notary \
#          --apple-id "iliuchina@icloud.com" --team-id "P5RB3W3D58" \
#          --password "<app-specific-password>"
#      then just run: scripts/release.sh
#
#   2. Environment variables (per run):
#        APPLE_ID="iliuchina@icloud.com" APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
#          scripts/release.sh
#
# Usage:
#   scripts/release.sh                 # full release, prompts before publishing
#   scripts/release.sh --no-publish    # build + notarize + staple, stop before GitHub
#   scripts/release.sh -y              # skip the pre-publish confirmation
#
set -euo pipefail

# ---- config (edit here if the signing identity or repo ever changes) --------
SIGN_IDENTITY="Developer ID Application: Veronica Loren (P5RB3W3D58)"
TEAM_ID="P5RB3W3D58"
APPLE_ID_DEFAULT="iliuchina@icloud.com"
NOTARY_PROFILE="${NOTARY_PROFILE:-rawdrop-notary}"  # keychain profile name
REPO="aka-kika/rawdrop"
SCHEME="RawDrop"
# -----------------------------------------------------------------------------

PUBLISH=1
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --no-publish) PUBLISH=0 ;;
    -y|--yes)     ASSUME_YES=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Run from the repo root regardless of where the script is invoked.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

step() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

# ---- 0. Preconditions -------------------------------------------------------
command -v xcodegen  >/dev/null || die "xcodegen not found (brew install xcodegen)"
command -v create-dmg >/dev/null || die "create-dmg not found (brew install create-dmg)"
security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY" \
  || die "signing identity not in keychain: $SIGN_IDENTITY"

VERSION="$(grep 'MARKETING_VERSION' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
[ -n "$VERSION" ] || die "could not read MARKETING_VERSION from project.yml"
APP="DerivedData/Build/Products/Release/$SCHEME.app"
DMG="dist/$SCHEME-$VERSION.dmg"
TAG="v$VERSION"
step "Releasing $SCHEME $VERSION  (tag $TAG)"

# Warn early if the tag already exists — avoids building then failing at the end.
if [ "$PUBLISH" -eq 1 ] && git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  die "tag $TAG already exists — bump MARKETING_VERSION in project.yml first"
fi

# Resolve notarization credentials up front so we fail before a long build.
NOTARY_ARGS=()
if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
  echo "    notarization: keychain profile '$NOTARY_PROFILE'"
elif [ -n "${APPLE_APP_PASSWORD:-}" ]; then
  NOTARY_ARGS=(--apple-id "${APPLE_ID:-$APPLE_ID_DEFAULT}" --team-id "$TEAM_ID" --password "$APPLE_APP_PASSWORD")
  echo "    notarization: APPLE_APP_PASSWORD env var"
else
  die "no notarization credentials. Set up keychain profile '$NOTARY_PROFILE' (see header) or export APPLE_APP_PASSWORD."
fi

# ---- 1. Generate + build (universal, Developer ID, hardened runtime) ---------
step "Generating Xcode project"
xcodegen generate >/dev/null

step "Building Release (arm64 + x86_64)"
rm -rf DerivedData/Build/Products/Release
xcodebuild -scheme "$SCHEME" -configuration Release -derivedDataPath ./DerivedData \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  build >/dev/null
[ -d "$APP" ] || die "build produced no app at $APP"

# ---- 2. Verify the signed app before we spend time notarizing ---------------
step "Verifying signature"
codesign --verify --strict --verbose=2 "$APP" 2>&1 | tail -1
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "get-task-allow" \
  && die "app still requests get-task-allow — notarization would fail"
lipo -info "$APP/Contents/MacOS/$SCHEME" | grep -q "arm64" \
  && lipo -info "$APP/Contents/MacOS/$SCHEME" | grep -q "x86_64" \
  || die "app is not universal"
echo "    universal, Developer ID, hardened runtime, no get-task-allow ✓"

# ---- 3. Package + sign the DMG ----------------------------------------------
step "Building DMG"
mkdir -p dist
STAGE="$(mktemp -d)/RawDrop"; mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"
rm -f "$DMG"
create-dmg \
  --volname "$SCHEME $VERSION" --window-size 600 340 --icon-size 120 \
  --icon "$SCHEME.app" 150 170 --app-drop-link 450 170 --hide-extension "$SCHEME.app" \
  "$DMG" "$STAGE" >/dev/null 2>&1 || true   # create-dmg exits nonzero on cosmetic warnings
[ -f "$DMG" ] || die "DMG was not created at $DMG"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
echo "    $DMG ($(du -h "$DMG" | cut -f1))"

# ---- 4. Notarize + staple ---------------------------------------------------
step "Submitting to Apple notary (this waits for Apple)"
if ! xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait 2>&1 | tee /tmp/rd-notary.log | tail -3; then
  die "notarytool submit failed"
fi
grep -q "status: Accepted" /tmp/rd-notary.log || {
  SUBID="$(grep -m1 '  id:' /tmp/rd-notary.log | awk '{print $2}')"
  echo "--- notary log ---"; xcrun notarytool log "$SUBID" "${NOTARY_ARGS[@]}" 2>&1 | tail -30
  die "notarization not Accepted"
}
step "Stapling"
xcrun stapler staple "$DMG" >/dev/null
xcrun stapler validate "$DMG" >/dev/null && echo "    stapled ✓"
spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 | grep -i "accepted" \
  && echo "    Gatekeeper: accepted ✓"

# ---- 5. Publish -------------------------------------------------------------
if [ "$PUBLISH" -eq 0 ]; then
  step "Done (--no-publish). Artifact ready: $DMG"
  exit 0
fi

# Extract this version's CHANGELOG section for the release notes.
NOTES="$(awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" {grab=1; next}
  grab && /^## \[/ {exit}
  grab {print}
' CHANGELOG.md)"
[ -n "$NOTES" ] || NOTES="RawDrop $VERSION"

if [ "$ASSUME_YES" -eq 0 ]; then
  echo
  echo "About to publish PUBLIC release $TAG to $REPO with $DMG."
  read -r -p "Proceed? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || die "aborted before publish (artifact left at $DMG)"
fi

step "Tagging + pushing $TAG"
git tag "$TAG"
git push origin "$TAG"

step "Creating GitHub release"
printf '%s\n\n---\nUniversal (Apple Silicon + Intel), signed & notarized. Drag **RawDrop** to **Applications**.\n' "$NOTES" \
  | gh release create "$TAG" "$DMG" --repo "$REPO" --title "$SCHEME $VERSION" --notes-file -

step "Released: https://github.com/$REPO/releases/tag/$TAG"
