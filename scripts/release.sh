#!/usr/bin/env bash
#
# Yield release pipeline — the mechanical half.
#
# Runs everything that is deterministic and failure-prone in one shot:
#   preflight → test → version bump → archive → export → re-sign Sparkle
#   → zip → notarize → staple → re-zip → verify → Sparkle-sign
#
# It deliberately does NOT touch appcast.xml, the git tag, or the GitHub
# release — those need judgment (release notes) and are handled by the
# /release skill after this script prints the edSignature it needs.
#
# Usage:
#   scripts/release.sh 1.4.2          # full release build
#   scripts/release.sh --dry-run      # exercise the machinery, no notarize, no git writes
#   scripts/release.sh 1.4.2 --skip-tests
#
set -euo pipefail

# Run from the repo root no matter where we're invoked from.
cd "$(dirname "$0")/.."

# ---------------------------------------------------------------- config
readonly PROJECT="Yield.xcodeproj"
readonly SCHEME="Yield"
readonly TEAM_ID="7G49Y875S8"
readonly SIGN_ID="Developer ID Application: Jeremy Fields (${TEAM_ID})"
readonly NOTARY_PROFILE="notarytool-profile"

# Pinning derivedDataPath keeps build products out of the shared global
# DerivedData (whose stale leftovers have broken the test step before) and
# makes the Sparkle sign_update tool land at a stable, repo-relative path.
readonly DERIVED="build/derived"
readonly OUT="build/release"
readonly ARCHIVE="${OUT}/Yield.xcarchive"
readonly EXPORT_DIR="${OUT}/export"
readonly APP="${EXPORT_DIR}/Yield.app"
readonly SPARKLE_SIGN="${DERIVED}/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"

# Logs live under the (gitignored) build dir and are deliberately NOT
# cleaned up — when a step fails, the log is the only way to find out why.
readonly LOG_DIR="build/logs"

step() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }
ok()   { printf '\033[0;32m  ✓ %s\033[0m\n' "$*"; }
die()  { printf '\n\033[0;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# Run a command with its output captured. On failure, show the tail of the
# log and stop — a bare `>/dev/null` would abort the release with no clue why.
run() {
  local name="$1"; shift
  local log="${LOG_DIR}/${name}.log"
  if ! "$@" >"$log" 2>&1; then
    printf '\n\033[0;31m  ── last 30 lines of %s ──\033[0m\n' "$log" >&2
    tail -30 "$log" >&2
    die "${name} failed. Full log: ${log}"
  fi
}

current_version() { grep -E '^ *MARKETING_VERSION:' project.yml | sed -E 's/.*"(.*)".*/\1/'; }
current_build()   { grep -E '^ *CURRENT_PROJECT_VERSION:' project.yml | sed -E 's/.*"(.*)".*/\1/'; }

# ------------------------------------------------------------------ args
VERSION=""
DRY_RUN=0
SKIP_TESTS=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    -h|--help)
      sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*)
      echo "unknown flag: $arg" >&2; exit 2 ;;
    *)
      VERSION="$arg" ;;
  esac
done

mkdir -p "$LOG_DIR"

if [[ $DRY_RUN -eq 1 ]]; then
  # Don't silently ignore a version the caller explicitly asked for.
  if [[ -n "$VERSION" && "$VERSION" != "$(current_version)" ]]; then
    die "--dry-run builds the current version ($(current_version)) and never bumps.
Drop the '${VERSION}' argument, or run without --dry-run to actually release it."
  fi
  VERSION="$(current_version)"
  echo "DRY RUN — building ${VERSION}: no git writes, no notarization, no publish."
elif [[ -z "$VERSION" ]]; then
  die "No version given. Usage: scripts/release.sh 1.4.2   (current: $(current_version))"
elif [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die "Version must look like 1.4.2 (got: ${VERSION})"
fi

# ------------------------------------------------------------- preflight
# Fail in seconds on a missing prerequisite rather than three minutes into
# an archive.
step "Preflight"

command -v xcodegen >/dev/null || die "xcodegen not found — brew install xcodegen"
xcode-select -p >/dev/null     || die "No Xcode toolchain selected (xcode-select -p)"
ok "xcodegen + Xcode toolchain"

security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_ID" \
  || die "Signing identity not in keychain: ${SIGN_ID}"
ok "Signing identity present"

if [[ $DRY_RUN -eq 0 ]]; then
  # Cheapest call that proves the stored notary credential still works.
  # A missing profile or a lapsed/blocked account fails here, before the build.
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "notarytool profile '${NOTARY_PROFILE}' missing or rejected.

If this is a 403 'required agreement is missing or has expired', it is an
account-level block, not a build problem: sign in at developer.apple.com/account
as Account Holder for team ${TEAM_ID}, accept the pending agreement (usually the
Apple Developer Program License Agreement; also check App Store Connect →
Agreements, Tax, and Banking), wait a few minutes, and re-run.

Otherwise store the credential:
  xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" --apple-id EMAIL --team-id ${TEAM_ID}"
  ok "Notary credential accepted"

  git diff --quiet && git diff --cached --quiet \
    || die "Working tree is dirty — commit or stash before releasing."
  ok "Working tree clean"
fi

# ----------------------------------------------------------------- tests
# Unsigned: these are pure-logic XCTests with no entitlement-dependent
# behavior, so code signing buys nothing and only adds a flaky keychain
# dependency to the very first step of the release.
if [[ $SKIP_TESTS -eq 0 ]]; then
  step "Tests (unsigned)"
  # Deliberately NOT `xcodebuild | grep ... || true` + PIPESTATUS: running
  # `true` resets PIPESTATUS, so a failing suite would report success and
  # sail straight into a release. Branch on the exit status directly.
  if xcodebuild test \
      -project "$PROJECT" -scheme "$SCHEME" \
      -configuration Debug -destination 'platform=macOS' \
      -derivedDataPath "$DERIVED" \
      CODE_SIGNING_ALLOWED=NO \
      >"${LOG_DIR}/test.log" 2>&1
  then
    grep -E 'Executed [0-9]+ tests' "${LOG_DIR}/test.log" | tail -1 | sed 's/^[[:space:]]*/  /'
    ok "All tests passed"
  else
    printf '\n\033[0;31m  ── failures ──\033[0m\n' >&2
    grep -E 'error:|failed|Executed [0-9]+ tests|\*\* TEST' "${LOG_DIR}/test.log" \
      | tail -20 | sed 's/^/  /' >&2 || true
    die "Tests failed — release stopped. Full log: ${LOG_DIR}/test.log"
  fi
else
  step "Tests SKIPPED (--skip-tests)"
fi

# --------------------------------------------------------- version bump
# Idempotent: re-running after a mid-pipeline failure (e.g. a notarization
# 403) must not double-bump the build number.
if [[ $DRY_RUN -eq 0 ]]; then
  if [[ "$(current_version)" == "$VERSION" ]]; then
    step "Version already ${VERSION} (build $(current_build)) — skipping bump"
  else
    NEXT_BUILD=$(( $(current_build) + 1 ))
    step "Bump to ${VERSION} (build ${NEXT_BUILD})"
    sed -E -i '' "s/^( *MARKETING_VERSION: ).*/\1\"${VERSION}\"/"          project.yml
    sed -E -i '' "s/^( *CURRENT_PROJECT_VERSION: ).*/\1\"${NEXT_BUILD}\"/" project.yml
    run xcodegen xcodegen generate
    git add project.yml Yield.xcodeproj/project.pbxproj Yield/Info.plist
    git commit -q -m "Bump version to ${VERSION} (build ${NEXT_BUILD})

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
    ok "Committed $(git rev-parse --short HEAD)"
  fi
else
  run xcodegen xcodegen generate
fi

readonly BUILD_NUM="$(current_build)"
# Absolute — ditto runs from inside the export dir, and a relative path
# there would have to hop back up an implementation-detail number of levels.
readonly ZIP="${PWD}/build/Yield-${VERSION}.zip"

# ------------------------------------------------------- archive & export
step "Archive (Release)"
rm -rf "$OUT"
mkdir -p "$OUT"
run archive xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -archivePath "$ARCHIVE" \
  archive
ok "Archived"

step "Export (developer-id)"
cat > "${OUT}/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>            <string>developer-id</string>
    <key>teamID</key>            <string>${TEAM_ID}</string>
    <key>signingStyle</key>      <string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
PLIST
run export xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "${OUT}/ExportOptions.plist"
ok "Exported to ${APP}"

# --------------------------------------------------------- sparkle & zip
# Sparkle ships pre-signed by its own authors; re-sign it under our identity
# so the whole bundle traces to one Developer ID.
step "Re-sign Sparkle"
run sparkle-resign codesign --force --deep --sign "$SIGN_ID" --options runtime \
  "${APP}/Contents/Frameworks/Sparkle.framework"
ok "Sparkle re-signed"

# COPYFILE_DISABLE=1 + --norsrc strip AppleDouble "._" files. Without them,
# Gatekeeper rejects the app with "unsealed contents present in the root
# directory of an embedded framework" even though notarization passes.
zip_app() {
  rm -f "$ZIP"
  ( cd "$EXPORT_DIR" && COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent Yield.app "$ZIP" )
}

step "Zip"
zip_app
ok "$(basename "$ZIP") ($(stat -f%z "$ZIP") bytes)"

# ------------------------------------------------- notarize, staple, verify
if [[ $DRY_RUN -eq 1 ]]; then
  step "DRY RUN — skipping notarize/staple/verify"
  run codesign-verify codesign --verify --deep --strict --verbose=2 "$APP"
  ok "Code signature valid (not notarized — dry run)"
else
  step "Notarize (1–3 min)"
  # Capture the status explicitly: notarytool can exit non-zero, and it can
  # also exit zero with a non-Accepted status. Both must stop the release.
  notary_status=0
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait \
    >"${LOG_DIR}/notarize.log" 2>&1 || notary_status=$?
  sed 's/^/  /' "${LOG_DIR}/notarize.log"
  if [[ $notary_status -ne 0 ]] || ! grep -q "status: Accepted" "${LOG_DIR}/notarize.log"; then
    die "Notarization did not return Accepted. Full log: ${LOG_DIR}/notarize.log"
  fi
  ok "Notarization Accepted"

  step "Staple"
  run staple xcrun stapler staple "$APP"
  ok "Ticket stapled"

  step "Re-zip stapled app"
  zip_app
  ok "$(basename "$ZIP") ($(stat -f%z "$ZIP") bytes)"

  # Gate: a build Gatekeeper would reject must never reach the release.
  step "Verify (Gatekeeper)"
  run stapler-validate xcrun stapler validate "$APP"
  # Capture rather than `spctl | grep -q`: grep -q exits on first match and
  # SIGPIPEs the upstream, which under `pipefail` reports a false failure on
  # a perfectly good build — and this gate runs *after* notarization.
  spctl_out="$(spctl -a -vvv -t exec "$APP" 2>&1 || true)"
  printf '%s\n' "$spctl_out" | sed 's/^/  /'
  grep -q "accepted" <<<"$spctl_out" || die "spctl rejected the app — do not publish."
  ok "Gatekeeper: accepted, Notarized Developer ID"
fi

# -------------------------------------------------------- sparkle signature
step "Sparkle signature"
[[ -x "$SPARKLE_SIGN" ]] || die "sign_update not found at ${SPARKLE_SIGN}"
SIG_LINE="$("$SPARKLE_SIGN" "$ZIP")"
ok "Signed for Sparkle"

# ------------------------------------------------------------------ done
cat <<SUMMARY

$(printf '\033[1;32m━━ Build ready ━━\033[0m')

  version   ${VERSION}  (build ${BUILD_NUM})
  zip       ${ZIP}
  appcast   ${SIG_LINE}

SUMMARY

if [[ $DRY_RUN -eq 1 ]]; then
  echo "Dry run — nothing committed, nothing notarized, nothing published."
else
  cat <<'NEXT'
Next (handled by the /release skill):
  1. Add an <item> to appcast.xml using the version/build/edSignature/length above
  2. git add appcast.xml && git commit -m "Update appcast for vX.Y.Z"
  3. git push origin main && git tag vX.Y.Z && git push origin vX.Y.Z
  4. gh release create vX.Y.Z <zip> --title "vX.Y.Z" --notes "..." --verify-tag
NEXT
fi
