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
- ↪️ **Continue today** — picking up yesterday's work? Hover a past day's entry in a project's drawer (or right-click it) and Continue today starts a fresh running timer with the same project, task, and note.
- ✏️ **Entry workflow** — project + task dropdowns grouped by client. Add to any day of the week, not just today. Double-click any entry to edit it, or start a timer with pre-filled hours for catch-up tracking.
- 🔀 **Move time off a runaway timer** — left a timer running through a meeting? Right-click the timer bar, choose Move Time, pick where the time really belongs and how much of it to move, then either keep timing what you were doing or switch the timer to the new task. Time already tracked to that task today merges in automatically. Any of today's entries can start the same flow — hover one in a project's drawer for the Move icon, or right-click it.
- 📅 **Log time from a Google Calendar event** — connect Google Calendar in Settings and a calendar button appears beside + Timer, opening today's schedule as a mini day view: hour grid, a line marking now, overlapping meetings side by side. Events are cached in the background so it opens instantly. Every event carries one-click Start Timer and Add Time actions, and meetings you've logged before auto-select their project + task. Read-only access to your primary calendar — nothing is written back to Google.
- 🏷️ **Notes on the timer bar** — the running (or paused) timer shows its entry's notes right in the bar, kept to one line with the full text on hover. Timers started from a calendar event also carry a calendar glyph and the event's scheduled length ("· 0:30 event"), so meeting timers are recognizable at a glance. In the System theme the glyph is blue and the line ends with when the meeting does ("· until 3:30pm", then "· ended 3:30pm").
- ⭐ **Favorites** — star a project + task combo to save it. Picking a project auto-selects its most-recently-used favorite, a "Favorites" popover next to the project picker gives one-tap selection of any saved combo, and Settings lists every favorite so you can prune. No star? Yield also learns your habits and auto-selects the task you usually log on each project.
- 📣 **External-change notifications** — when a timer is started or stopped from outside Yield (e.g. the Harvest browser extension), a system notification acknowledges the change. Toggle off in Settings → Preferences if you don't want it.

**Visualizations & navigation**

- 🎛️ **Configurable menu bar display** — pick the graphic and the text separately. Styles: the classic monochrome gauge, a budget ring that fills toward the active project's booking, a status capsule that fills like a battery (solid for the share of the booking you've used, an empty outline for what's left), or week bars showing Monday to Friday against your daily target. The colored styles stay monochrome until a timer runs, then turn green, amber near the booking, and red once over it. They also show when a timer is paused (a dashed outline), when a meeting is waiting to be logged (blue), and when Yield can't reach Harvest (dimmed). Text: project tracked vs. booked, current timer vs. day total, current timer vs. project remaining, just the running timer, or time left.
- 📈 **Weekly time chart** — stacked area chart showing hours by project across the week. Click a legend row to isolate a single project, or export the chart as a PNG. In the System theme, hover a day for that day's hours by project.
- 🗂️ **All or Booked** — switch the list between every project you've touched this week and only the ones booked in Forecast. Time tracked on a project with no booking still shows under All, marked as unbooked in the System theme.
- 🔍 **Day-of-week filter** — click a weekday in the header to narrow the list to projects you spent time on (or are booked on) that day; click it again, or the week total, to clear it. With Google Calendar connected, the day's meetings open under its tab (see "A day's meetings at a glance"). In the System theme today's tab is set a weight heavier, so it stays the one that stands out when another day is selected.

**Awareness**

- 🌴 **Time off** — your Forecast PTO surfaces as a dedicated summary row, and the menu bar icon switches to a moon when you're off for the full day.
- 📝 **Forecast notes** — assignment notes from Forecast surface on project rows; hover the icon to read the full text.
- ⏳ **Next meeting in the menu bar** — with Google Calendar connected, turn on Settings → Calendar → Menu bar meetings and the menu bar item gains a countdown beside the timer graphic: your next meeting and how long until it starts ("AMC kickoff in 1h 22m"), its calendar glyph — a page showing today's date — turning blue as it begins; how long the current one has left, and the next if it follows closely ("1:1 Sam 12m left · next 20m"); and, when a meeting's timer is still running after it, how long ago it ended ("1:1 Sam ended 12m ago"). When meetings overlap, the one that started last is the one named — a standup inside a focus block takes over while it runs, then hands the bar back — and a meeting that starts before the current one ends is always mentioned as next, however far off, so a long block doesn't hide what's coming ("Focus time 2h 40m left · next 40m"). The words stay in the menu bar's own ink so they read on any wallpaper, and on the ring, capsule and week-bars styles a blue dot on the graphic marks a meeting that wants a timer or has one running. Choose Title and time, or Time only to keep titles out of the bar while screen sharing; "Shorten titles to" sets how many characters of a title to keep, in steps of five. Every timed event on your calendar counts, focus blocks included, and so do meetings whose start prompts you've muted; only events you declined are left out. Off by default.
- 🕘 **A day's meetings at a glance** — with Google Calendar connected, selecting a day in the week strip opens a thin timeline under its tab: a pill for each of that day's meetings, placed by the clock. Select Wednesday on a Monday and it's Wednesday's calendar. Today's also tells what's on (solid) from what's coming and what's done (fainter), with a red line marking now. It always covers 9 to 5, stretching for anything earlier or later, and overlapping meetings stack in a second lane. Hover a pill for its title and times; click today's strip to open the day's schedule. An empty day says "No meetings". There's nothing to turn on: without a calendar connected, selecting a day works as it always did.
- 🗓️ **Meeting timer prompts** — when a calendar event starts, Yield nudges you (a notification plus a bar above the timer) to put your timer on it. Open Yield six minutes into the meeting and it offers to start the meeting's timer *and* move those six minutes off whatever was running — your timeline reads as if you'd switched on time. A meeting always lands on today's entry for its task when there is one, with its title added on a new line of the notes, so several 1:1s on one task end up listed in a single entry. If the timer is already running on that task when the next meeting starts, the bar offers Add to Timer instead: one click adds the title and nothing else changes. Mute any recurring meeting permanently ("Don't prompt for meetings like this"), or turn the feature off in Settings.
- ⏰ **Post-meeting reminders** — the bookend to meeting prompts: start a timer from a calendar event and let it run long, and once the meeting's end has passed by your idle threshold Yield notifies you and offers to move the extra minutes to whatever you actually did next. The timer is tied to its meeting by its Harvest entry, and the tie is saved, so pausing and resuming or relaunching Yield mid-meeting doesn't lose it. Stopping the timer or switching to another ends the tie, so time you track to the same entry afterwards is an ordinary timer again. It has its own toggle in Settings.
- ⚠️ **Booked-but-unassigned warning** — booked on a project in Forecast but never added to it in Harvest? The project row flags it, this week and in look-ahead weeks, so you can get access sorted before time needs logging. A Forecast project with no linked Harvest project at all gets a pink marker and an icon that says so — it's booked, but there's nothing to log time against until an admin links it from Forecast.
- 💤 **Idle detection** — when you've been away with a timer running, Yield opens an alert window with options to continue, stop, keep the time, or move the idle minutes to a different timer. (Set the threshold in Settings.)
- 🔔 **Budget notifications** — nudges you when you hit your booked target on a project so you know when to move on. If macOS notifications are turned off for Yield, Settings says so and links to the right pane.
- 🚧 **Outage awareness** — when Harvest or Forecast stops responding, a banner names the service and checks Harvest's status page for you: a confirmed incident shows its name and a link, and if the status page reports nothing wrong, Yield says so, which points to your own connection or sign-in. Timer controls switch off until Harvest is back, and the colored menu bar styles dim so you know the numbers may be stale.
- 🔒 **Locked weeks** — when Harvest has locked a past week from edits, a small lock icon appears next to each weekday in the header strip so you know the week is read-only.

**Polish**

- 🎨 **Two looks** — Settings → Display → Theme. **Editorial** is the original and the default: serif project names, compact rows, Yield's own palette. **System** is an alternative drawn with the Material-X kit: Manrope type, projects grouped under a band per client with each row leading on its logged hours, durations written as 6:30, round icon buttons, and the kit's blue for controls. Status keeps fixed colors (green for the running project, red for over, orange for paused, blue for meeting prompts), so a healthy project never looks like a warning. The timer bar stays in place with an idle state when nothing is running, each weekday in the header gets a small bar against your daily target, and Settings, future weeks, and the timer form follow the same design. Both work in light and dark.
- 🌗 **Light & dark mode** — pick System, Light, or Dark from Settings. The light palette is tuned for WCAG AA contrast across every accent.
- 🎯 **Your week, your numbers** — set your weekly hours target in Settings (40 by default). It sets the daily target that the day grid and the menu bar's week bars are measured against.
- 🧰 **Troubleshooting** — the last section of Settings: Sync Now reloads everything, your calendar included, and shows when Yield last synced; Reveal Logs opens the log folder for a bug report; Reset Preferences puts every setting back to its default while keeping your sign-ins, favorites, and muted meetings; and Forget Remembered Meetings clears which project each meeting title goes to, so Yield asks again.
- 🚀 **Launch at login** — a switch in Settings → Preferences.
- 🔄 **Always current** — Yield refreshes itself: every time you open it, every 30 seconds for the running timer, after anything you do to a timer, and when your Mac wakes or comes back online. There's no refresh button to remember; if a load fails, the error has a Try again.

## 🔁 Updates

Yield checks for new versions daily and prompts you to install them. You can also trigger a check anytime from **Settings → Check for Updates**.

## 🔐 Data & privacy

Yield talks to a few services and stores nothing on a server we control:

- **Harvest API** for time entries, timers, projects, tasks, and your account profile — today's entries and the running timer are polled every 30 seconds while Yield is open; everything else at launch, on a new day, and after your own timer actions.
- **Forecast API** (via the same Harvest OAuth token) for weekly assignments, projects, clients, and time-off blocks.
- **Harvest's status page** (harveststatus.com) — only when a Harvest or Forecast request fails, to tell you whether there's a known incident. No account information is sent.
- **The update feed** — a file on GitHub that lists the latest version, checked daily. Updates themselves download from this repository's releases.
- **Google Calendar API** (only if you connect it) for today's events on your primary calendar, plus those of a day you select in the week strip — read-only (`calendar.events.readonly` scope), re-checked when you open Yield and alongside its own full refreshes (at most once every four minutes) so the event picker, meeting prompts, menu bar countdown and day strip stay current, cached in memory only, never written back to Google.

Locally on your machine:

- **OAuth access + refresh tokens** (Harvest + Google) are stored in the macOS **Keychain**.
- **Preferences and favorites** (appearance, theme, menu bar style and text, weekly hours target, idle setting, notification and calendar toggles, favorited project/task pairs, per-project task-usage history, meeting-title → project/task memory for calendar pre-fill, muted meeting titles, and the title and times of the meeting the current timer was started from) live in **UserDefaults**.
- **Account details that aren't secrets** (your name, your Harvest and Forecast account IDs, your Google account email if connected, and when each token expires) also live in **UserDefaults**, so Settings can show who's signed in.
- **Error logs** are written to `~/Library/Logs/Yield/yield.log` (rotated at 256 KB) so you can attach them to bug reports. Nothing in the log leaves your machine unless you upload it yourself.

Yield doesn't include any analytics, telemetry, or crash reporters that phone home.

## 🐞 Reporting issues

Click the 🐞 icon in the bottom-left of the popup to open a pre-filled GitHub issue with your version, macOS version, last error, and last refresh time. Drag the log file (Settings → Reveal Logs in Finder) into the issue if you can.

## 📜 License

MIT — see [LICENSE](LICENSE).

The bundled typefaces (Newsreader, DM Sans, JetBrains Mono, and Manrope) are each licensed under the [SIL Open Font License](https://openfontlicense.org).
