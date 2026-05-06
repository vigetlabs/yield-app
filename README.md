# <img src="app-icon.png" width="32" height="32" alt="Yield app icon" /> Yield

Know what you've sown and what's left to reap. Yield sits in your macOS menu bar and shows how your logged hours in [Harvest](https://www.getharvest.com/) stack up against your booked hours in [Forecast](https://www.getharvest.com/forecast) — so you always know where your week stands.

## ⬇️ Download

**[Download the latest version](https://github.com/vigetlabs/yield-app/releases/latest)**

Unzip, drag Yield to your Applications folder, and launch. It'll take root in your menu bar. Sign in with your Harvest account and you're ready to go.

*Requires macOS 14 (Sonoma) or later and a Harvest account with Forecast enabled.*

## ✨ Features

- 📊 **At-a-glance weekly overview** — every project with color-coded progress bars showing logged vs. booked hours. Green when under budget, red when over.
- 🎛️ **Configurable menu bar display** — pick what shows next to the icon: tracked vs. booked for the running project, current timer vs. today's total, or just the running timer. The icon itself rotates as a gauge tied to your progress on the active project.
- 📈 **Weekly time chart** — stacked area chart showing hours by project across the week. Click a legend row to isolate a single project, or export the chart as a PNG.
- 📐 **Day-by-day breakdown** — expand any project to see a segmented bar of its daily contribution to the week, alongside its individual time entries.
- 🔍 **Day-of-week filter** — click a weekday in the header to narrow the list to projects you spent time on (or are booked on) that day.
- 🔭 **Look-ahead** — see what's still ahead this week: expected hours per day, company holidays, your scheduled time off, and prospective Forecast bookings that aren't tied to a Harvest project yet.
- 🌴 **Time off awareness** — your Forecast PTO surfaces as a dedicated summary row, and the menu bar icon switches to a moon when you're off for the full day.
- ◀ ▶ **Week navigation** — step backward through past weeks (read-only, with full drawers and the day-by-day bar) or forward to see what's booked next, with a "This Week" pill to jump back.
- ⏱️ **Live timer controls** — start, stop, pause, and resume Harvest timers without leaving the menu bar. A duplicate-timer guard offers to resume an existing entry on the same project instead of doubling up.
- ✏️ **Create & edit time entries** — log time with project and task dropdowns grouped by client. Edit (or double-click to edit) and delete entries inline. Start a timer with pre-filled hours for catch-up tracking.
- ⭐ **Favorites** — star a project + task combo to save it. Picking a project auto-selects its most-recently-used favorite, a "Favorites" popover next to the project picker gives one-tap selection of any saved combo, and Settings lists every favorite so you can prune.
- 📅 **Log time to any day** — add entries to any day in the current week, not just today.
- 📝 **Forecast notes** — assignment notes from Forecast surface on project rows; hover the icon to read the full text.
- 💤 **Idle detection** — alerts you when you've been idle, with options to continue, stop, keep the time, or move the idle minutes to a different timer.
- 🔔 **Budget notifications** — nudges you when you hit your booked target on a project so you know when to move on.
- 📣 **External-change HUD** — when a timer is started or stopped from outside Yield (e.g. the Harvest browser extension), a small panel pops below the menu bar icon to acknowledge the change.
- 🌗 **Light & dark mode** — pick System, Light, or Dark from Settings. The light palette is tuned for WCAG AA contrast across every accent.

## 🚜 Getting started

1. **Launch Yield** — look for the gauge icon in your menu bar
2. **Sign in with Harvest** — click the icon and hit "Sign in with Harvest." This connects your Forecast data automatically.
3. **That's it.** Your week's projects, hours, and timers are all right there.

## 🔁 Updates

Yield checks for new versions daily and prompts you to install them. You can also trigger a check anytime from **Settings → Check for Updates**.

## 🔐 Data & privacy

Yield talks to two services and stores nothing on a server we control:

- **Harvest API** for time entries, timers, projects, tasks, and your account profile.
- **Forecast API** (via the same Harvest OAuth token) for weekly assignments, projects, clients, and time-off blocks.

Locally on your machine:

- **OAuth access + refresh tokens** are stored in the macOS **Keychain**.
- **Preferences and favorites** (appearance, idle setting, menu-bar display mode, favorited project/task pairs) live in **UserDefaults**.
- **Error logs** are written to `~/Library/Logs/Yield/yield.log` (rotated at 256 KB) so you can attach them to bug reports. Nothing in the log leaves your machine unless you upload it yourself.

Yield doesn't include any analytics, telemetry, or crash reporters that phone home.

## 🐞 Reporting issues

Click the 🐞 icon in the bottom-left of the popup to open a pre-filled GitHub issue with your version, macOS version, last error, and last refresh time. Drag the log file (Settings → Reveal Logs in Finder) into the issue if you can.

If something is on fire and you need a fast turnaround, drop it in the `#yield-app` Slack channel — patch releases ship within a day.

---

For development info, see [CONTRIBUTING.md](CONTRIBUTING.md).
