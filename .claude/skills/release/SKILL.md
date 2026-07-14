---
name: release
description: "Cut a new release of the Yield macOS app. Use this skill whenever the user wants to release, ship, publish, or cut a new version of Yield. Handles the full pipeline: version bump, build, sign, notarize, appcast, GitHub release, and Slack notification."
---

# Release Yield

Cut a new release of the Yield macOS app. The argument is the version number (e.g., `1.4.2`).

**Version argument: $ARGUMENTS**

If `$ARGUMENTS` is empty, read the current `MARKETING_VERSION` from `project.yml` and ask the user what version to release.

## How this works

The mechanical, failure-prone half of the pipeline lives in **`scripts/release.sh`** — a single `set -euo pipefail` script that runs:

> preflight → test (unsigned) → version bump + commit → archive → export → re-sign Sparkle → zip → notarize → staple → re-zip → verify (Gatekeeper) → Sparkle-sign

It halts on the first failure, so there's no such thing as a half-applied release. Your job is the **judgment half**: release notes, the appcast entry, and the GitHub release.

Do **not** hand-run the archive/notarize/staple/sign steps. They're in the script. Run the script.

## Process

### 1. Run the build

```bash
./scripts/release.sh VERSION
```

This takes a few minutes (notarization alone is 1–3). Use a generous timeout (600000ms).

On success it prints:

```
━━ Build ready ━━
  version   1.4.2  (build 61)
  zip       /path/to/build/Yield-1.4.2.zip
  appcast   sparkle:edSignature="..." length="..."
```

Capture the **version**, **build number**, **zip path**, **edSignature**, and **length** — the appcast needs all five.

If the script exits non-zero, stop and report the error. It fails loudly and specifically; don't work around it by running the underlying commands by hand. Cases it already explains in its own error output:

- **Dirty working tree** → commit or stash first.
- **Tests failed** → fix them; the release doesn't proceed.
- **Notarization 403 / "required agreement is missing or has expired"** → account-level block, *not* a build problem. The user must sign in at developer.apple.com/account (Account Holder, team 7G49Y875S8), accept the pending agreement (usually the Apple Developer Program License Agreement; also check App Store Connect → Agreements, Tax, and Banking), wait a few minutes, then re-run. Don't tight-loop the endpoint.

Re-running after a mid-pipeline failure is safe: the version bump is idempotent (it won't double-bump the build number), and `--skip-tests` skips a suite you already know is green.

### 2. Write release notes

```bash
git log $(git describe --tags --abbrev=0)..HEAD --oneline
```

Group the user-facing changes; skip internal churn (version bumps, skill/doc edits, refactors with no visible effect). Write for someone who *uses* Yield, not someone who wrote it: lead with what changed for them and why it matters. Match the voice of the existing entries in `appcast.xml`.

### 3. Update the appcast

Add a new `<item>` at the **top** of the `<channel>` in `appcast.xml` (right after `<title>Yield Updates</title>`), using the version, build number, edSignature, and length from step 1:

```xml
    <item>
      <title>Version X.Y.Z</title>
      <sparkle:version>BUILD</sparkle:version>
      <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <ul>
          <li><strong>Headline.</strong> What changed and why it matters.</li>
        </ul>
      ]]></description>
      <enclosure
        url="https://github.com/vigetlabs/yield-app/releases/download/vX.Y.Z/Yield-X.Y.Z.zip"
        sparkle:edSignature="..."
        length="..."
        type="application/octet-stream"/>
    </item>
```

The `edSignature` and `length` **must** match the zip you're about to upload, or Sparkle auto-updates will reject it.

Commit:

```bash
git add appcast.xml
git commit -m "Update appcast for vX.Y.Z"
```

### 4. Push, tag & release

Push commits, then create and push the tag *before* creating the release — this ensures the tag exists on the correct commit when GitHub fires the `published` event (otherwise the Slack notification workflow may not trigger):

```bash
git push origin main
git tag vX.Y.Z
git push origin vX.Y.Z
gh release create vX.Y.Z <zip-path-from-step-1> --title "vX.Y.Z" --notes "RELEASE_NOTES" --verify-tag
```

Format the GitHub notes with markdown headers and bullets. Keep them attribution-free — no "Generated with Claude Code" line.

The `.github/workflows/slack-release-notify.yml` workflow posts to #yield-app automatically when the release is created. No manual Slack step.

### 5. Report

Give the user the release URL. Notarization and Gatekeeper acceptance were already gated by the script — if you got past step 1, the build is good.

## Reminders

- Commit messages end with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`; use HEREDOC syntax to preserve formatting.
- `scripts/release.sh --dry-run` exercises the whole build/sign/zip path with no git writes, no notarization, and no publish. Use it to validate changes to the script itself.
- The script owns every signing/zip invariant (the `COPYFILE_DISABLE=1 ditto --norsrc` AppleDouble strip that Gatekeeper requires, the Sparkle re-sign, the pinned `derivedDataPath`). If you're about to type `codesign`, `ditto`, `notarytool`, or `xcodebuild` during a release — stop. That's the script's job.
