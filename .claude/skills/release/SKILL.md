---
name: release
description: "Cut a new release of the Yield macOS app. Use this skill whenever the user wants to release, ship, publish, or cut a new version of Yield. Handles the full pipeline: version bump, build, sign, notarize, appcast, GitHub release, and Slack notification."
---

# Release Yield

Cut a new release of the Yield macOS app. The argument is the version number (e.g., `0.9.7`).

**Version argument: $ARGUMENTS**

If `$ARGUMENTS` is empty, read the current `MARKETING_VERSION` from `project.yml` and ask the user what version to release.

## Process

Execute each step in order. If any step fails, stop immediately and report the error — do not continue to subsequent steps.

### 1. Bump Version

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

### 2. Archive & Export

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

### 3. Re-sign Sparkle & Zip

Re-sign Sparkle so it matches the app's identity:
```bash
codesign --force --deep --sign "Developer ID Application: Jeremy Fields (7G49Y875S8)" --options runtime /tmp/YieldExport/Yield.app/Contents/Frameworks/Sparkle.framework
```

Create the zip. This MUST use `COPYFILE_DISABLE=1` and `--norsrc` to strip macOS AppleDouble `._` resource fork files — without this, Gatekeeper rejects the app with "unsealed contents present in the root directory of an embedded framework":
```bash
cd /tmp/YieldExport && COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent Yield.app /tmp/Yield-VERSION.zip
```

### 4. Notarize & Staple

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

### 5. Sparkle Signature

Sign the zip for Sparkle auto-updates:
```bash
/Users/jeremyfields/Sites/yield-app/build/derived/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update /tmp/Yield-VERSION.zip
```

Capture the `sparkle:edSignature="..."` and `length=...` values from the output — these go in the appcast.

### 6. Update Appcast

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

### 7. Push & GitHub Release

```bash
git push origin main
```

Create the GitHub release with the zip attached:
```bash
gh release create vVERSION /tmp/Yield-VERSION.zip --title "vVERSION" --notes "RELEASE_NOTES"
```

The release notes for GitHub should be formatted with markdown headers and bullet points.

The GitHub Actions workflow (`.github/workflows/slack-release-notify.yml`) will automatically post to #yield-app when the release is created — no manual Slack step needed.

## Reminders

- All commit messages must end with `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`
- Use HEREDOC syntax for commit messages to preserve formatting
- The zip MUST use `COPYFILE_DISABLE=1 ditto --norsrc` — never use plain `zip`
- Set timeout to 600000ms for notarization (it can take a few minutes)
- Report the GitHub release URL when done
