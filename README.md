# <img src="app-icon.png" width="32" height="32" alt="Yield app icon" /> Yield

Yield is a macOS menu bar app that brings your [Forecast](https://www.getharvest.com/forecast) bookings and your [Harvest](https://www.getharvest.com/) time entries together in one place. If you use both tools, you know the friction: Forecast tells you what you planned, Harvest tells you what you tracked, and figuring out where you actually stand means flipping between the two all week. Yield does that reconciliation for you and keeps the answer in your menu bar — which projects have hours left, which are over, how today fits into the week — so it's easier to decide what to work on next. When you're ready, you can start or stop a Harvest timer right from the dropdown.

## ⬇️ Get started

**[Download the latest version](https://github.com/vigetlabs/yield-app/releases/latest)**

Unzip, drag Yield to your Applications folder, and launch — it'll take root in your menu bar. Click the gauge icon and hit "Sign in with Harvest"; Yield connects your Forecast data automatically using the same login. Your week's projects, hours, and timers are all right there.

*Requires macOS 14 (Sonoma) or later and a Harvest account with Forecast enabled.*

## ✨ Features

- 🤝 **Harvest + Forecast, side by side** — your logged hours and your booked hours in a single view, so you always know where the week stands.
- ⏱️ **Full-featured time tracker** — start, stop, pause, resume, edit, and delete Harvest timers without leaving the menu bar. A duplicate-timer guard offers to resume an existing entry instead of doubling up.
- 📊 **Color-coded progress bars** — every project shows status at a glance: green when under budget or on track, red when over.
- 📐 **Day-by-day breakdown** — expand any project for a Mon–Fri day grid (weekends join in when worked): each cell is one day scaled against your daily target, flipping green to red at the exact point tracked time crossed the booked budget. Individual time entries sit right below.
- 🔭 **Past and future weeks** — peek ahead at what's booked (expected hours, holidays, your time off, prospective Forecast bookings) or step backward through past weeks for a read-only review.

### And more

**Time tracking**

- ⚡ **Quick actions everywhere** — hover a project row to surface one-click icons: Resume a stopped timer, Quick Start the task you usually track on that project (starred, or simply inferred from habit), or Add Time to open the full form. The running-timer bar has its own hover set — Edit, Move Time, Delete — and every hover action is mirrored in a labeled right-click menu.
- ✏️ **Entry workflow** — project + task dropdowns grouped by client. Add to any day of the week, not just today. Double-click any entry to edit it, or start a timer with pre-filled hours for catch-up tracking.
- 🔀 **Move time off a runaway timer** — left a timer running through a meeting? Right-click the timer bar, choose Move Time, pick where the time really belongs and how much of it to move, then either keep timing what you were doing or switch the timer to the new task. Time already tracked to that task today merges in automatically.
- 📅 **Log time from a Google Calendar event** — connect Google Calendar in Settings and a calendar button appears beside + Timer, opening today's schedule as a mini day view: hour grid, a line marking now, overlapping meetings side by side. Events are cached in the background so it opens instantly. Every event carries one-click Start Timer and Add Time actions, and meetings you've logged before auto-select their project + task. Read-only access to your primary calendar — nothing is written back to Google.
- 🏷️ **Notes on the timer bar** — the running (or paused) timer shows its entry's notes right in the bar, kept to one line with the full text on hover. Timers started from a calendar event also carry a calendar glyph and the event's scheduled length ("· 0:30 event"), so meeting timers are recognizable at a glance.
- ⭐ **Favorites** — star a project + task combo to save it. Picking a project auto-selects its most-recently-used favorite, a "Favorites" popover next to the project picker gives one-tap selection of any saved combo, and Settings lists every favorite so you can prune. No star? Yield also learns your habits and auto-selects the task you usually log on each project.
- 📣 **External-change notifications** — when a timer is started or stopped from outside Yield (e.g. the Harvest browser extension), a system notification acknowledges the change. Toggle off in Settings → Preferences if you don't want it.

**Visualizations & navigation**

- 🎛️ **Configurable menu bar display** — pick what shows next to the icon: project tracked vs. booked, current timer vs. day total, current timer vs. project remaining, or just the running timer. The icon itself rotates as a gauge tied to your progress on the active project.
- 📈 **Weekly time chart** — stacked area chart showing hours by project across the week. Click a legend row to isolate a single project, or export the chart as a PNG.
- 🔍 **Day-of-week filter** — click a weekday in the header to narrow the list to projects you spent time on (or are booked on) that day.

**Awareness**

- 🌴 **Time off** — your Forecast PTO surfaces as a dedicated summary row, and the menu bar icon switches to a moon when you're off for the full day.
- 📝 **Forecast notes** — assignment notes from Forecast surface on project rows; hover the icon to read the full text.
- 🗓️ **Meeting timer prompts** — when a calendar event starts, Yield nudges you (a notification plus a bar above the timer) to put your timer on it. Open Yield six minutes into the meeting and it offers to start the meeting's timer *and* move those six minutes off whatever was running — your timeline reads as if you'd switched on time. Mute any recurring meeting permanently ("Don't prompt for meetings like this"), or turn the feature off in Settings.
- ⏰ **Post-meeting reminders** — the bookend to meeting prompts: start a timer from a calendar event and let it run long, and once the meeting's end has passed by your idle threshold Yield notifies you and offers to move the extra minutes to whatever you actually did next. It stands down on its own if you stop or switch timers, and has its own toggle in Settings.
- ⚠️ **Booked-but-unassigned warning** — booked on a project in Forecast but never added to it in Harvest? The project row flags it, this week and in look-ahead weeks, so you can get access sorted before time needs logging.
- 💤 **Idle detection** — alerts you when you've been idle, with options to continue, stop, keep the time, or move the idle minutes to a different timer.
- 🔔 **Budget notifications** — nudges you when you hit your booked target on a project so you know when to move on.
- 🔒 **Locked weeks** — when Harvest has locked a past week from edits, a small lock icon appears next to each weekday in the header strip so you know the week is read-only.

**Polish**

- 🌗 **Light & dark mode** — pick System, Light, or Dark from Settings. The light palette is tuned for WCAG AA contrast across every accent.

## 🔁 Updates

Yield checks for new versions daily and prompts you to install them. You can also trigger a check anytime from **Settings → Check for Updates**.

## 🔐 Data & privacy

Yield talks to a few services and stores nothing on a server we control:

- **Harvest API** for time entries, timers, projects, tasks, and your account profile.
- **Forecast API** (via the same Harvest OAuth token) for weekly assignments, projects, clients, and time-off blocks.
- **Google Calendar API** (only if you connect it) for today's events on your primary calendar — read-only (`calendar.events.readonly` scope), refreshed in the background every few minutes while connected so the event picker and meeting prompts stay current (cached in memory only), never written back to Google.

Locally on your machine:

- **OAuth access + refresh tokens** (Harvest + Google) are stored in the macOS **Keychain**.
- **Preferences and favorites** (appearance, idle setting, menu-bar display mode, notification toggles, favorited project/task pairs, per-project task-usage history, meeting-title → project/task memory for calendar pre-fill, muted meeting titles) live in **UserDefaults**.
- **Error logs** are written to `~/Library/Logs/Yield/yield.log` (rotated at 256 KB) so you can attach them to bug reports. Nothing in the log leaves your machine unless you upload it yourself.

Yield doesn't include any analytics, telemetry, or crash reporters that phone home.

## 🐞 Reporting issues

Click the 🐞 icon in the bottom-left of the popup to open a pre-filled GitHub issue with your version, macOS version, last error, and last refresh time. Drag the log file (Settings → Reveal Logs in Finder) into the issue if you can.

## 📜 License

MIT — see [LICENSE](LICENSE).
