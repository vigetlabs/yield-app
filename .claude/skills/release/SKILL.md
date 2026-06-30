---
name: release
description: "Cut a new release of the Yield macOS app. Use this skill whenever the user wants to release, ship, publish, or cut a new version of Yield. Handles the full pipeline: version bump, build, sign, notarize, appcast, GitHub release, and Slack notification."
---

# Release Yield

Cut a new release of the Yield macOS app. The argument is the version number (e.g., `0.9.7`).

**Version argument: $ARGUMENTS**

If `$ARGUMENTS` is empty, read the current `MARKETING_VERSION` from `project.yml` and ask the user what version to release.

## Execution discipline (read first)

This pipeline is a long run of repetitive shell + edit steps, which makes it easy to slip into *describing* a command instead of *running* it. Two rules:

1. **Every step is a real tool call** — an actual `Bash` or `Edit` invocation, never command text pasted into your reply. If you catch yourself writing out a command in prose or a code fence as if it ran, stop: it did not run. Re-issue it as a genuine tool call.
2. **Confirm each step produced a tool result before moving on.** If a step yields no output/result, you emitted it as text rather than executing it — redo it as a tool call. Don't advance the pipeline on an assumed result; every command here has observable output (test summary, `** ARCHIVE SUCCEEDED **`, notarization `status: Accepted`, a commit hash, a release URL). No output = it didn't happen.

## Known account-level snag: notarization 403

If `notarytool submit` fails with `HTTP status code: 403. A required agreement is missing or has expired`, this is **not** a build problem — Apple has a pending legal agreement that freezes notarization. Tell the user to sign in at developer.apple.com/account (as Account Holder for team 7G49Y875S8), accept any pending agreement banner (usually the Apple Developer Program License Agreement; also check App Store Connect → Agreements, Tax, and Banking), and that membership isn't lapsed. Acceptance can take a few minutes to propagate. The archive/signed app/zip remain valid in `/tmp` — just re-run from the notarization step once they confirm. Don't tight-loop the endpoint; retry on the user's go-ahead.

## Process

Execute each step in order. If any step fails, stop immediately and report the error — do not continue to subsequent steps.

### 1. Run Tests

Run the full test suite *before* bumping version or building anything. If any test fails, stop the release immediately — surface the failing test names and don't continue. The release shouldn't take a single further step until tests are green.

```bash
xcodebuild test -project Yield.xcodeproj -scheme Yield -configuration Debug -destination 'platform=macOS'
```

A passing run ends with `** TEST SUCCEEDED **`. Anything else is a failure.

### 2. Bump Version

In `project.yml`, update:
- `MARKETING_VERSION` to the new version (`$ARGUMENTS`)
- `CURRENT_PROJECT_VERSION` — increment by 1 from its current value

Then regenerate the Xcode project:

```bash
xcodegen generate
```

Commit the version bump:

```bash
git add project.yml Yield.xcodeproj/project.pbxproj Yield/Info.plist
```

Commit message: `Bump version to VERSION (build N)`

### 3. Archive & Export

Archive:
```bash
xcodebuild -project Yield.xcodeproj -scheme Yield -configuration Release archive -archivePath /tmp/Yield.xcarchive
```

Create an export options plist at `/tmp/export-options.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>7G49Y875S8</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
```

Export:
```bash
xcodebuild -exportArchive -archivePath /tmp/Yield.xcarchive -exportPath /tmp/YieldExport -exportOptionsPlist /tmp/export-options.plist
```

### 4. Re-sign Sparkle & Zip

Re-sign Sparkle so it matches the app's identity:
```bash
codesign --force --deep --sign "Developer ID Application: Jeremy Fields (7G49Y875S8)" --options runtime /tmp/YieldExport/Yield.app/Contents/Frameworks/Sparkle.framework
```

Create the zip. This MUST use `COPYFILE_DISABLE=1` and `--norsrc` to strip macOS AppleDouble `._` resource fork files — without this, Gatekeeper rejects the app with "unsealed contents present in the root directory of an embedded framework":
```bash
cd /tmp/YieldExport && COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent Yield.app /tmp/Yield-VERSION.zip
```

### 5. Notarize & Staple

Submit for notarization (this takes 1-3 minutes):
```bash
xcrun notarytool submit /tmp/Yield-VERSION.zip --keychain-profile "notarytool-profile" --wait
```

If notarization fails with "No Keychain password item found", tell the user to run:
```
xcrun notarytool store-credentials "notarytool-profile" --apple-id EMAIL --team-id 7G49Y875S8
```

Staple the ticket to the app:
```bash
xcrun stapler staple /tmp/YieldExport/Yield.app
```

Re-zip the stapled app (replaces the previous zip):
```bash
cd /tmp/YieldExport && rm -f /tmp/Yield-VERSION.zip && COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent Yield.app /tmp/Yield-VERSION.zip
```

### 6. Sparkle Signature

Sign the zip for Sparkle auto-updates:
```bash
/Users/jeremyfields/Sites/yield-app/build/derived/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update /tmp/Yield-VERSION.zip
```

Capture the `sparkle:edSignature="..."` and `length=...` values from the output — these go in the appcast.

### 7. Update Appcast

Generate release notes from commits since the last tag:
```bash
git log $(git describe --tags --abbrev=0)..HEAD --oneline
```

Add a new `<item>` at the TOP of the `<channel>` in `appcast.xml` (after `<title>Yield Updates</title>`), using the version, build number, edSignature, length, and release notes.

Commit:
```bash
git add appcast.xml
```

Commit message: `Update appcast for vVERSION`

### 8. Push, Tag & GitHub Release

Push commits, then create and push the tag *before* creating the release. This ensures the tag exists on the correct commit when GitHub fires the `published` event (otherwise the Slack notification workflow may not trigger):

```bash
git push origin main
git tag vVERSION
git push origin vVERSION
```

Create the GitHub release pointing at the existing tag:
```bash
gh release create vVERSION /tmp/Yield-VERSION.zip --title "vVERSION" --notes "RELEASE_NOTES" --verify-tag
```

The release notes for GitHub should be formatted with markdown headers and bullet points. Do NOT append a "Generated with Claude Code" line to release notes — keep them attribution-free.

The GitHub Actions workflow (`.github/workflows/slack-release-notify.yml`) will automatically post to #yield-app when the release is created — no manual Slack step needed.

## Reminders

- All commit messages must end with `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`
- Use HEREDOC syntax for commit messages to preserve formatting
- The zip MUST use `COPYFILE_DISABLE=1 ditto --norsrc` — never use plain `zip`
- Set timeout to 600000ms for notarization (it can take a few minutes)
- Report the GitHub release URL when done
