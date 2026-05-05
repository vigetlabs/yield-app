---
name: test
description: "Run the Yield app's XCTest suite. Use whenever the user wants to run tests, check that tests pass, or verify a change didn't break anything before committing. Reports test counts, failures (with file/line), and total runtime."
---

# Run Yield's tests

Run the full unit-test suite for the Yield macOS app.

## Process

Execute:

```bash
xcodebuild test -project Yield.xcodeproj -scheme Yield -configuration Debug -destination 'platform=macOS'
```

Set the bash timeout to **300000ms (5 minutes)** — the build step plus full test run typically completes well under a minute, but the first build after a clean can take longer.

## Reading the output

A passing run ends with:

```
Test Suite 'All tests' passed at <timestamp>.
	 Executed N tests, with 0 failures (0 unexpected) in <duration> seconds
** TEST SUCCEEDED **
```

A failing run ends with `** TEST FAILED **`. Look for `failed (...)` lines or `error:` markers to find the failing assertion(s) — each one names the test method (e.g. `-[YieldTests.DoubleFormattersTests test_roundedHM_thirtyOneMinutes]`) and the file:line of the failed assertion.

## Reporting

Report:

- Whether tests passed or failed.
- The number of tests executed (from `Executed N tests` line).
- For failures: each failing test's name and the assertion error (file:line + reason). Tail the relevant section of the build output rather than dumping the full log.
- Total runtime.

If tests fail, **stop** — don't try to fix the failure unless the user asked you to. Just report the failure clearly and let the user decide what to do.
