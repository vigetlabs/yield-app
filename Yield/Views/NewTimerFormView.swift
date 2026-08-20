import SwiftUI

struct NewTimerFormView: View {
    let viewModel: TimeComparisonViewModel
    let editingEntry: TimeEntryInfo?
    let preselectedProjectId: Int?
    let targetDate: Date?
    /// When non-nil, the form is being used to relocate idle time from
    /// an existing running timer to another timer on the same day. The
    /// time field is pre-filled with the idle hours, the date is locked
    /// to today, and the action buttons commit the move (rather than
    /// starting a new timer or logging time).
    let idleMove: TimeComparisonViewModel.PendingIdleMove?
    /// When non-nil, the form is moving a user-chosen amount of time off
    /// the banner's current timer onto another task (the left-it-running-
    /// through-a-meeting fix). Date locked to today, the time field
    /// starts empty (the user knows how long the meeting was; the app
    /// doesn't), and the actions commit the move — either keeping the
    /// source timer going or switching the timer to the destination.
    let timerMove: TimeComparisonViewModel.PendingTimerMove?
    let onDismiss: () -> Void

    @State private var allProjects: [TimeComparisonViewModel.TimerProjectOption] = []
    @State private var isLoadingProjects = true
    /// Pre-grouped + sorted version of `allProjects` for the project
    /// dropdown. Built once when `allProjects` loads — the grouping
    /// and per-group sort would otherwise run on every body pass
    /// (each keystroke in any TextField re-renders the form).
    @State private var projectGroupsCache: [DropdownGroup] = []
    @State private var selectedProjectId: Int?
    @State private var selectedTaskId: Int?
    @State private var notes: String = ""
    @State private var timeHours: Int = 0
    @State private var timeMinutes: Int = 0
    @State private var availableTasks: [TaskOption] = []
    @State private var spentDate: Date = Date()
    @State private var duplicateConfirmEntries: [TimeEntryInfo]?
    /// Set when the form opened with a preselected project the user
    /// isn't a Harvest member of, so the picker can't select it. Drives
    /// an explanatory banner instead of a silent empty picker.
    @State private var unselectableProjectName: String?
    @State private var showDeleteConfirm = false
    /// Toggled by the calendar icon next to the time field. When
    /// true the form's body is replaced inline by
    /// `CalendarEventPickerView` (no sheet/popover — MenuBarExtra
    /// can't host either). Selecting an event flips this back to
    /// false and pre-fills the time + notes.
    @State private var showCalendarPicker = false
    /// Set by `applyCalendarEvent` so the save path knows the form's
    /// notes came from a real calendar pick (not a hand-typed entry
    /// that happens to look like a meeting title). Only calendar-
    /// sourced saves get added to `MeetingHistoryStore` — recording
    /// every save would learn from one-off freeform notes too,
    /// which is noisy and not what the user asked for.
    @State private var sourcedFromCalendarPicker = false
    /// The actual event behind `sourcedFromCalendarPicker`, kept so a
    /// running-timer commit can arm the post-meeting overage reminder
    /// (which needs the event's end time, not just its title).
    @State private var sourcedCalendarEvent: CalendarEvent?

    /// Meeting-prompt routing: the meeting whose title prefills notes.
    /// Non-nil also marks the save as meeting-sourced so it records to
    /// `MeetingHistoryStore` — the first-encounter save is what makes
    /// the next prompt's Start Timer instant.
    let meetingEvent: CalendarEvent?
    /// Timer-move mode only: prefill the amount (elapsed-since-meeting-
    /// start when routed from the prompt bar) instead of starting at 0.
    let timerMovePrefillHours: Double?

    init(viewModel: TimeComparisonViewModel, editingEntry: TimeEntryInfo? = nil, preselectedProjectId: Int? = nil, targetDate: Date? = nil, idleMove: TimeComparisonViewModel.PendingIdleMove? = nil, timerMove: TimeComparisonViewModel.PendingTimerMove? = nil, startInCalendarPicker: Bool = false, meetingEvent: CalendarEvent? = nil, timerMovePrefillHours: Double? = nil, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.editingEntry = editingEntry
        self.preselectedProjectId = preselectedProjectId
        self.targetDate = targetDate
        self.idleMove = idleMove
        self.timerMove = timerMove
        self.meetingEvent = meetingEvent
        self.timerMovePrefillHours = timerMovePrefillHours
        // Meeting-sourced saves record to MeetingHistoryStore the same
        // way calendar-picker saves do.
        _sourcedFromCalendarPicker = State(initialValue: meetingEvent != nil)
        _sourcedCalendarEvent = State(initialValue: meetingEvent)
        // Header calendar shortcut: open directly on the event picker
        // rather than making the user tap through the form to reach it.
        _showCalendarPicker = State(initialValue: startInCalendarPicker)
        // Back should return wherever the picker was opened from: the
        // main view for the header shortcut, the form for the in-form
        // calendar icon (which resets this when it opens the picker).
        _pickerOpenedFromMainView = State(initialValue: startInCalendarPicker)
        self.onDismiss = onDismiss
    }

    /// True while the open picker was reached via the header's calendar
    /// shortcut — its Back button then dismisses the whole form back to
    /// the main view instead of stranding the user on a blank form they
    /// never asked for.
    @State private var pickerOpenedFromMainView: Bool = false

    private var isEditing: Bool { editingEntry != nil }
    private var isIdleMove: Bool { idleMove != nil }
    private var isTimerMove: Bool { timerMove != nil }
    private var isSpentDateToday: Bool { Calendar.current.isDateInToday(spentDate) }
    private var spentDateString: String { DateHelpers.dateFormatter.string(from: spentDate) }

    /// "Mon, Apr 21" — used when the spent date isn't today.
    private static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    /// "Apr 21" — day-of-week is replaced by "Today" when applicable.
    private static let headerMonthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private var headerPrefix: String {
        if isEditing { return "Edit time entry:" }
        if isIdleMove { return "Move idle time:" }
        if isTimerMove { return "Move time:" }
        return "New time entry:"
    }

    private func dateLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today, \(Self.headerMonthDayFormatter.string(from: date))"
        }
        return Self.headerDateFormatter.string(from: date)
    }

    /// All seven days of the current week (Mon–Sun), in order.
    private var currentWeekDays: [Date] {
        let weekStart = DateHelpers.currentWeekBounds().start
        let cal = Calendar.current
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// Date pill in the header. In edit mode it's static (the entry's date
    /// can't be moved from here). In create mode it's a menu that lets the
    /// user target any day of the current week.
    @ViewBuilder
    private var dateSelector: some View {
        if isEditing || isIdleMove || isTimerMove {
            Text(dateLabel(for: spentDate))
                .font(YieldFonts.titleMedium)
                .foregroundStyle(YieldColors.textPrimary)
        } else {
            Menu {
                ForEach(currentWeekDays, id: \.self) { day in
                    Button {
                        spentDate = day
                        refreshDuplicateConfirm()
                    } label: {
                        let isSelected = Calendar.current.isDate(day, inSameDayAs: spentDate)
                        if isSelected {
                            Label(dateLabel(for: day), systemImage: "checkmark")
                        } else {
                            Text(dateLabel(for: day))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(dateLabel(for: spentDate))
                        .font(YieldFonts.titleMedium)
                        .foregroundStyle(YieldColors.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(YieldColors.textSecondary)
                }
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    struct TaskOption: Identifiable, Hashable {
        let id: Int
        let name: String
    }

    private var selectedProject: TimeComparisonViewModel.TimerProjectOption? {
        guard let id = selectedProjectId else { return nil }
        return allProjects.first(where: { $0.harvestProjectId == id })
    }

    private var canStart: Bool {
        selectedProjectId != nil && selectedTaskId != nil
    }

    /// Existing entries for the currently selected project + task on the
    /// currently selected spent date. Drives the duplicate-entry warning.
    private var existingEntriesOnSelectedDate: [TimeEntryInfo] {
        guard let projectId = selectedProjectId,
              let taskId = selectedTaskId else { return [] }
        guard let project = viewModel.projectStatuses.first(where: {
            $0.harvestProjectId == projectId
        }) else { return [] }
        return project.timeEntries.filter { $0.date == spentDateString && $0.taskId == taskId }
    }

    private var canLog: Bool {
        canStart && enteredHours > 0
    }

    /// True when the timer-move destination is the very task the time is
    /// being moved from — a no-op that would just churn the entry.
    private var isMoveSelfTarget: Bool {
        guard let move = timerMove else { return false }
        return selectedProjectId == move.sourceProjectId && selectedTaskId == move.sourceTaskId
    }

    /// Timer-move commit gate: a real destination, a positive amount, and
    /// no more than the source timer currently holds. The ceiling is live
    /// (the source keeps ticking under the form), and the commit path
    /// clamps again at commit time.
    private var canMove: Bool {
        guard let move = timerMove else { return false }
        return canStart && enteredHours > 0 && !isMoveSelfTarget
            && enteredHours <= viewModel.timerMoveAvailableHours(move) + 0.0001
    }

    var body: some View {
        // The calendar event picker takes over the form's body
        // entirely while open — MenuBarExtra panels can't host
        // sheets or popovers, so an inline swap is the only way
        // to surface secondary UI without breaking the panel's
        // resize/positioning behavior.
        // ZStack (not Group) so the outgoing and incoming views overlap
        // during the swap instead of stacking — same fix as the panel's
        // top-level container. The picker slides in from the trailing
        // edge like every deeper navigation in the panel; the form
        // cross-fades back in like the main content does. Each
        // `showCalendarPicker` mutation is wrapped in `withAnimation`
        // at its call site — a value-keyed `.animation` modifier alone
        // doesn't propagate to the MenuBarExtra panel's NSPanel resize,
        // so the panel would snap while the views animate.
        ZStack(alignment: .top) {
            if showCalendarPicker {
                CalendarEventPickerView(
                    viewModel: viewModel,
                    onSelect: applyCalendarEvent,
                    onStartTimer: startTimerFromEvent,
                    onCancel: {
                        if pickerOpenedFromMainView {
                            onDismiss()
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCalendarPicker = false
                            }
                        }
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                formBody
                    .transition(.opacity)
            }
        }
        // Setup lives on the Group (not formBody) so projects start
        // loading even when the form opens directly on the calendar
        // picker — `applyCalendarEvent`'s meeting-history auto-select
        // needs `allProjects` populated by the time an event is picked.
        .task {
            // Initialize spent date. Priority:
            //   1. Edit mode → entry's own date
            //   2. Idle-move / timer-move mode → today (moves are
            //      constrained to today — the source timer is today's)
            //   3. Explicit targetDate parameter
            //   4. Active weekday filter → pre-fill the filtered day
            //   5. Today (default)
            if let entry = editingEntry, let parsed = DateHelpers.dateFormatter.date(from: entry.date) {
                spentDate = parsed
            } else if isIdleMove || isTimerMove {
                spentDate = Date()
            } else if let target = targetDate {
                spentDate = target
            } else if let filter = viewModel.dayFilter,
                      let parsed = DateHelpers.dateFormatter.date(from: filter) {
                spentDate = parsed
            }

            // Pre-fill the time field with the idle hours so the user
            // sees the amount being relocated.
            if let move = idleMove {
                (timeHours, timeMinutes) = move.idleHours.roundedHM
            }

            // Meeting-prompt routing: title as notes, and (in timer-move
            // mode) the elapsed-since-start amount ready to move.
            if let meetingEvent, notes.isEmpty, !meetingEvent.summary.isEmpty {
                notes = meetingEvent.summary
            }
            if isTimerMove, let prefill = timerMovePrefillHours {
                (timeHours, timeMinutes) = prefill.roundedHM
            }

            await loadProjects()
            if let entry = editingEntry {
                // Edit mode: populate all fields
                selectedProjectId = entry.harvestProjectId
                notes = entry.notes ?? ""
                (timeHours, timeMinutes) = entry.hours.roundedHM
                if let project = allProjects.first(where: { $0.harvestProjectId == entry.harvestProjectId }) {
                    availableTasks = project.taskAssignments.map { TaskOption(id: $0.task.id, name: $0.task.name) }
                }
                selectedTaskId = entry.taskId
            } else if let projectId = preselectedProjectId {
                if let project = allProjects.first(where: { $0.harvestProjectId == projectId }) {
                    // Pre-selected project: populate project and load its tasks
                    selectProject(project)
                } else {
                    // The project was preselected but isn't in the user's
                    // Harvest assignments — almost always "booked in
                    // Forecast, not a member in Harvest." Surface a clear
                    // explanation instead of silently leaving the picker
                    // empty (the old dead-end). Row quick-actions are
                    // already gated for this state; this guard covers any
                    // remaining path here.
                    unselectableProjectName = viewModel.projectStatuses
                        .first { $0.harvestProjectId == projectId }?
                        .displayName ?? "this project"
                }
            }
        }
    }

    private var formBody: some View {
        // Hoist resolvedFavorites once per body pass — it's read by
        // the isEmpty guard, the popover's `richItems`, the indices
        // check, and the index access. Previously each was a separate
        // recomputation (Dictionary grouping + sort over all favorites)
        // per body, multiplied by the high re-render rate while the
        // user types in any TextField.
        let favorites = resolvedFavorites
        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Text(headerPrefix)
                    .font(YieldFonts.titleMedium)
                    .foregroundStyle(YieldColors.textPrimary)

                dateSelector

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "minus")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Timer")
                            .font(YieldFonts.labelButton)
                    }
                }
                .buttonStyle(.greenFilled)
            }
            .padding(16)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(YieldColors.border)
                    .frame(height: 1)
            }

            // Dropdowns + Notes
            VStack(alignment: .leading, spacing: 12) {
                // Project + task pickers, with the favorite star
                // button floating to the right (toggles favorite for
                // the current selection). When the user has favorites,
                // a "Favorites" button sits inline with the project
                // picker — opens a popover for one-tap selection of a
                // saved combo.
                if let unselectableProjectName {
                    unassignedBanner(projectName: unselectableProjectName)
                }

                if let move = timerMove {
                    moveSourceBanner(move)
                }

                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            projectPicker
                            if !favorites.isEmpty {
                                favoritesPickerButton(favorites: favorites)
                            }
                        }
                        taskPicker
                    }
                    favoriteButton
                }

                // Notes + Time row
                HStack(spacing: 12) {
                    // Notes field — macOS 14's TextField with
                    // axis: .vertical natively handles multi-line
                    // entry with a placeholder, so the previous
                    // ZStack-overlaying-Text trick around TextEditor
                    // (which doesn't support placeholders) collapses
                    // to a single line. `reservesSpace: true` keeps
                    // the row at its 2-line height even when empty
                    // so the surrounding layout doesn't jitter as
                    // the user types.
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2, reservesSpace: true)
                        .font(YieldFonts.titleSmall)
                        .foregroundStyle(YieldColors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(height: YieldDimensions.inputFieldHeight)
                        .background(YieldColors.surfaceDefault)
                        .yieldBorder()

                    // Manual time entry (HH:MM)
                    TimeInputView(hours: $timeHours, minutes: $timeMinutes)
                }
            }
            .padding(16)

            // Duplicate timer confirmation. In timer-move mode this is
            // informational (an existing destination entry gets merged
            // into, matching Harvest's own same-task-same-day behavior)
            // rather than an action fork.
            if let entries = duplicateConfirmEntries {
                if isTimerMove {
                    moveTargetBanner(entries: entries)
                } else {
                    duplicateConfirmBanner(entries: entries)
                }
            }

            // Actions. Swapped for an inline delete-confirmation row
            // when `showDeleteConfirm` is true — system
            // `.confirmationDialog` doesn't work inside MenuBarExtra
            // (the dialog presentation makes the panel resign key,
            // the panel auto-dismisses, and the dialog's button
            // action never fires).
            if showDeleteConfirm {
                deleteConfirmRow
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            } else {
                HStack(spacing: 8) {
                    if isEditing {
                        Button {
                            Task { await saveEntry() }
                        } label: {
                            Text("Save")
                        }
                        .buttonStyle(.greenOutlined)
                        .disabled(!canStart)
                        .opacity(canStart ? 1 : 0.5)
                    } else if isIdleMove {
                        // Idle-move mode: a single primary commit. When a
                        // matching entry already exists, the duplicate banner
                        // disables this so the user makes the explicit
                        // add-or-create choice from the banner.
                        Button {
                            Task { await commitIdleMove() }
                        } label: {
                            Text("Move Time")
                        }
                        .buttonStyle(.greenOutlined)
                        .disabled(!canLog || duplicateConfirmEntries != nil)
                        .opacity(canLog && duplicateConfirmEntries == nil ? 1 : 0.5)
                    } else if let move = timerMove {
                        // Timer-move mode: two commits. Keep = source
                        // stays as it was (running keeps running at the
                        // reduced total); Start = the timer switches to
                        // the destination task. The duplicate banner is
                        // informational here — an existing destination
                        // entry is merged into, so it never blocks.
                        Button {
                            Task { await commitTimerMove(switchTimer: false) }
                        } label: {
                            Text(move.sourceWasRunning ? "Move & Keep Timing" : "Move Time")
                        }
                        .buttonStyle(.greenOutlined)
                        .disabled(!canMove)
                        .opacity(canMove ? 1 : 0.5)

                        Button {
                            Task { await commitTimerMove(switchTimer: true) }
                        } label: {
                            Text("Move & Start Timer")
                        }
                        .buttonStyle(.yieldBordered)
                        .disabled(!canMove)
                        .opacity(canMove ? 1 : 0.5)
                    } else if isSpentDateToday {
                        Button {
                            Task { await startTimer() }
                        } label: {
                            Text("Start Timer")
                        }
                        .buttonStyle(.greenOutlined)
                        .disabled(!canStart || duplicateConfirmEntries != nil)
                        .opacity(canStart && duplicateConfirmEntries == nil ? 1 : 0.5)
                    }

                    Button("Cancel") {
                        onDismiss()
                    }
                    .buttonStyle(.yieldBordered)

                    Spacer()

                    if !isEditing && !isIdleMove && !isTimerMove {
                        if AppState.shared.googleAuthService.isAuthenticated {
                            calendarPickerButton
                        }

                        Button {
                            Task { await logTime() }
                        } label: {
                            Text("Log Time")
                        }
                        .buttonStyle(.yieldBordered)
                        .disabled(!canLog)
                        .opacity(canLog ? 1 : 0.5)
                    } else if isEditing {
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.redOutlined)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Favorite Button

    /// True when the currently selected (project, task) combo is in the
    /// favorites store. Drives the star's filled/empty appearance.
    private var isCurrentSelectionFavorite: Bool {
        guard let projectId = selectedProjectId, let taskId = selectedTaskId else { return false }
        return FavoritesStore.shared.isFavorite(projectId: projectId, taskId: taskId)
    }

    private var favoriteButton: some View {
        let enabled = selectedProjectId != nil && selectedTaskId != nil
        let filled = isCurrentSelectionFavorite
        return Button {
            guard let projectId = selectedProjectId, let taskId = selectedTaskId else { return }
            FavoritesStore.shared.toggle(projectId: projectId, taskId: taskId)
        } label: {
            Image(systemName: filled ? "star.fill" : "star")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(filled ? YieldColors.yellowAccent : YieldColors.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(filled ? "Remove from favorites" : "Add to favorites")
    }

    // MARK: - Calendar Picker Button

    /// 32×32 icon next to `TimeInputView` that opens the Google
    /// Calendar event picker. Mirrors the favorite-star button's
    /// shape exactly (size, weight, hit target, plain style) so the
    /// two icon affordances feel like a set. Hidden entirely (see the
    /// call site) when Google Calendar isn't connected.
    private var calendarPickerButton: some View {
        Button {
            pickerOpenedFromMainView = false
            withAnimation(.easeInOut(duration: 0.2)) {
                showCalendarPicker = true
            }
        } label: {
            Image(systemName: "calendar")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(YieldColors.textPrimary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Pick from today's calendar events")
    }

    /// Apply a selected calendar event to the form's fields. Empty
    /// summary won't clobber existing notes — happens when the user
    /// created a calendar block without a title.
    ///
    /// If the user has previously logged time against a meeting with
    /// the same title (matched case-insensitively, whitespace-trimmed),
    /// auto-select the project + task they used last time. Same shape
    /// as the favorite-auto-select behavior in `selectProject` — the
    /// user can change either field before saving if the suggestion
    /// is wrong.
    private func applyCalendarEvent(_ event: CalendarEvent) {
        let (h, m) = event.durationHours.roundedHM
        timeHours = h
        timeMinutes = m
        if !event.summary.isEmpty {
            notes = event.summary
        }

        if let memory = MeetingHistoryStore.shared.lookup(title: event.summary),
           let project = allProjects.first(where: { $0.harvestProjectId == memory.projectId }),
           project.taskAssignments.contains(where: { $0.task.id == memory.taskId }) {
            // selectProject sets up `availableTasks` and may auto-
            // select the project's favorite task; override with the
            // memory's task afterward so the recall wins.
            selectProject(project)
            selectTask(memory.taskId)
        }

        sourcedFromCalendarPicker = true
        sourcedCalendarEvent = event
        withAnimation(.easeInOut(duration: 0.2)) {
            showCalendarPicker = false
        }
    }

    /// The picker's "Start Timer" quick action. When meeting history
    /// recognizes the event's title, start a running timer on the
    /// remembered project + task immediately — no form stop. Otherwise
    /// land in the form with just the title prefilled (no duration —
    /// a timer runs from now) so the user picks where it belongs; that
    /// save records the pairing, making the next start instant.
    private func startTimerFromEvent(_ event: CalendarEvent) {
        if let memory = MeetingHistoryStore.shared.lookup(title: event.summary),
           isMemoryUsable(memory) {
            MeetingHistoryStore.shared.record(notes: event.summary, projectId: memory.projectId, taskId: memory.taskId)
            viewModel.finalizeMeetingPromptAction(for: event)
            onDismiss()
            Task {
                await viewModel.startNewTimer(
                    projectId: memory.projectId,
                    taskId: memory.taskId,
                    notes: event.summary.isEmpty ? nil : event.summary
                )
                viewModel.noteCalendarSourcedTimer(event: event, projectId: memory.projectId, taskId: memory.taskId)
            }
        } else {
            if !event.summary.isEmpty {
                notes = event.summary
            }
            sourcedFromCalendarPicker = true
            sourcedCalendarEvent = event
            withAnimation(.easeInOut(duration: 0.2)) {
                showCalendarPicker = false
            }
        }
    }

    /// A stored meeting memory is usable unless the loaded project list
    /// disproves it (project gone, task unassigned). While projects are
    /// still loading we trust it — a stale pairing just surfaces the
    /// API error, same as any failed start.
    private func isMemoryUsable(_ memory: (projectId: Int, taskId: Int)) -> Bool {
        guard !allProjects.isEmpty else { return true }
        guard let project = allProjects.first(where: { $0.harvestProjectId == memory.projectId }) else { return false }
        return project.taskAssignments.contains { $0.task.id == memory.taskId }
    }

    // MARK: - Favorites Pill Row

    private struct ResolvedFavorite: Identifiable {
        let projectId: Int
        let taskId: Int
        let clientName: String?
        let projectName: String
        /// Forecast/Harvest project code, prefixed in `displayName`.
        let projectCode: String?
        let taskName: String
        let lastUsedAt: Date

        var id: String { "\(projectId)-\(taskId)" }

        /// Project name with the `[code]` prefix when set.
        var displayName: String {
            ProjectStatus.displayName(code: projectCode, project: projectName)
        }
    }

    /// Favorites resolved against the loaded `allProjects`. Sorted
    /// most-recently-used first so the pill row reads as the user's
    /// "recent quick-picks". Drops favorites whose project the user
    /// no longer has access to since they can't be selected from this
    /// form anyway (the Settings card still surfaces them for cleanup).
    private var resolvedFavorites: [ResolvedFavorite] {
        let projectsById = allProjects.indexed { $0.harvestProjectId }
        return FavoritesStore.shared.favorites
            .compactMap { fav -> ResolvedFavorite? in
                guard let project = projectsById[fav.projectId],
                      let task = project.taskAssignments.first(where: { $0.task.id == fav.taskId })?.task
                else { return nil }
                return ResolvedFavorite(
                    projectId: fav.projectId,
                    taskId: fav.taskId,
                    clientName: project.clientName,
                    projectName: project.projectName,
                    projectCode: project.projectCode,
                    taskName: task.name,
                    lastUsedAt: fav.lastUsedAt
                )
            }
            // Match the project list's sort: alphabetical by client →
            // project → task. The most-recently-used favorite still
            // wins the auto-select inside `selectProject`; this sort
            // only controls how the popover lists the favorites.
            .sorted { a, b in
                let ac = a.clientName ?? ""
                let bc = b.clientName ?? ""
                if ac != bc { return ac.localizedCaseInsensitiveCompare(bc) == .orderedAscending }
                if a.projectName != b.projectName {
                    return a.projectName.localizedCaseInsensitiveCompare(b.projectName) == .orderedAscending
                }
                return a.taskName.localizedCaseInsensitiveCompare(b.taskName) == .orderedAscending
            }
    }

    /// Favorites picker, built on the same `DropdownPicker` /
    /// `NSPopUpButton` machinery as the project and task pickers so it
    /// matches them pixel-for-pixel — same border, background,
    /// chevron, fonts, and (importantly) the same NSMenu-based
    /// dispatch that resizes the MenuBarExtra panel cleanly. Unlike
    /// the project picker we never store a selection: the placeholder
    /// "★ Favorites" stays in the closed state regardless of what the
    /// user picks, so the button reads as a trigger rather than a
    /// selector. Takes the pre-resolved favorites list as a parameter
    /// so the caller can compute it once per body pass instead of
    /// this view recomputing it for each of its four read sites.
    private func favoritesPickerButton(favorites: [ResolvedFavorite]) -> some View {
        DropdownPicker(
            label: "Favorites",
            placeholder: "★ Favorites",
            selectedId: nil,
            isPullDown: true,
            richItems: favorites.enumerated().map { index, fav in
                (id: index, attributedTitle: Self.favoriteMenuItemTitle(for: fav))
            },
            showsItemSeparators: true
        ) { index in
            guard favorites.indices.contains(index) else { return }
            applyFavorite(favorites[index])
        }
        .fixedSize()
    }

    /// Compose a two-line `NSAttributedString` for a favorite menu
    /// item: leading filled-star glyph + project on top, task on
    /// bottom in a smaller secondary-color font. The task line is
    /// indented past the star so it aligns with the project text.
    private static func favoriteMenuItemTitle(for fav: ResolvedFavorite) -> NSAttributedString {
        let titleFont = NSFont(name: "Newsreader-Regular", size: 12) ?? NSFont.systemFont(ofSize: 12)
        let subtitleFont = NSFont(name: "DMSans-Regular", size: 10) ?? NSFont.systemFont(ofSize: 10)
        let result = NSMutableAttributedString()

        // Star icon (text attachment so the line height stays tight).
        let starSize = titleFont.pointSize
        let starConfig = NSImage.SymbolConfiguration(pointSize: starSize, weight: .semibold)
            .applying(.init(paletteColors: [.labelColor]))
        if let starImage = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Favorite")?
            .withSymbolConfiguration(starConfig) {
            starImage.size = NSSize(width: starSize, height: starSize)
            let attachment = NSTextAttachment()
            attachment.image = starImage
            attachment.bounds = NSRect(x: 0, y: -1, width: starSize, height: starSize)
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: "  ", attributes: [.font: titleFont]))
        }

        // Project line (Client — [code] Project)
        let projectText = ProjectStatus.qualifiedName(client: fav.clientName, project: fav.displayName)
        result.append(NSAttributedString(
            string: "\(projectText)\n",
            attributes: [
                .font: titleFont,
                .foregroundColor: NSColor.labelColor,
            ]
        ))

        // Task line — leading spaces approximate the star + gap so
        // the task name aligns under the project text.
        result.append(NSAttributedString(
            string: "    \(fav.taskName)",
            attributes: [
                .font: subtitleFont,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))

        return result
    }

    /// Apply a favorite to the form: select the project (loading its
    /// tasks) and force the favorited task — the existing
    /// `selectProject` auto-selects the most-recently-used favorite
    /// for the project, but here we want THIS favorite specifically.
    private func applyFavorite(_ fav: ResolvedFavorite) {
        guard let project = allProjects.first(where: { $0.harvestProjectId == fav.projectId }) else { return }
        selectedProjectId = project.harvestProjectId
        availableTasks = project.taskAssignments.map { TaskOption(id: $0.task.id, name: $0.task.name) }
        duplicateConfirmEntries = nil
        selectTask(fav.taskId)
    }

    // MARK: - Project Picker

    private var projectPicker: some View {
        DropdownPicker(
            label: "PROJECT",
            placeholder: "Select a project",
            isLoading: isLoadingProjects,
            groups: projectGroupsCache,
            selectedId: selectedProjectId
        ) { id in
            if let project = allProjects.first(where: { $0.harvestProjectId == id }) {
                selectProject(project)
            }
        }
    }

    /// Compute the project dropdown's grouped + sorted shape from
    /// the raw project list. Called once at load time and cached in
    /// `projectGroupsCache`; never read from the view body.
    private static func buildProjectGroups(
        from projects: [TimeComparisonViewModel.TimerProjectOption]
    ) -> [DropdownGroup] {
        let grouped = Dictionary(grouping: projects) { $0.clientName ?? "" }
        let sortedKeys = grouped.keys.sorted { a, b in
            if a.isEmpty { return false }
            if b.isEmpty { return true }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        return sortedKeys.compactMap { key in
            guard let projects = grouped[key] else { return nil }
            let sorted = projects.sorted { $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending }
            return DropdownGroup(
                label: key.isEmpty ? nil : key,
                items: sorted.map { ($0.harvestProjectId, $0.displayName) }
            )
        }
    }

    // MARK: - Task Picker

    private var taskPicker: some View {
        DropdownPicker(
            label: "TASK",
            placeholder: selectedProjectId == nil ? "Select a project first..." : "Select a task",
            isLoading: false,
            items: availableTasks.map { ($0.id, $0.name) },
            selectedId: selectedTaskId,
            isDisabled: selectedProjectId == nil,
            favoritedIds: favoritedTaskIds
        ) { id in
            selectTask(id)
        }
        .opacity(selectedProjectId == nil ? 0.5 : 1)
    }

    /// Task ids favorited under the currently-selected project. The
    /// dropdown lights a star next to each so favorites are surfaced
    /// inline with the rest of the task list.
    private var favoritedTaskIds: Set<Int> {
        guard let projectId = selectedProjectId else { return [] }
        return Set(
            FavoritesStore.shared.favorites
                .filter { $0.projectId == projectId }
                .map { $0.taskId }
        )
    }

    // MARK: - Actions

    private func loadProjects() async {
        isLoadingProjects = true
        do {
            allProjects = try await viewModel.fetchAllProjects()
        } catch {
            allProjects = []
        }
        projectGroupsCache = Self.buildProjectGroups(from: allProjects)
        isLoadingProjects = false
    }

    private func selectProject(_ project: TimeComparisonViewModel.TimerProjectOption) {
        selectedProjectId = project.harvestProjectId
        selectedTaskId = nil
        duplicateConfirmEntries = nil
        availableTasks = project.taskAssignments.map { TaskOption(id: $0.task.id, name: $0.task.name) }
        // Auto-select preference order:
        //   1. Most-recently-used hard favorite for this project (explicit
        //      user intent; covers single- and multi-favorite cases).
        //   2. Soft favorite — the task the user tends to log on this
        //      project lately (recency-weighted frequency). Fills the gap
        //      when nothing's been explicitly starred.
        //   3. Project's only task, if there's just one.
        // Each candidate is guarded against staleness (the stored task may
        // have since been unassigned from the project).
        if let fav = FavoritesStore.shared.mostRecentlyUsedFavorite(forProjectId: project.harvestProjectId),
           availableTasks.contains(where: { $0.id == fav.taskId }) {
            selectTask(fav.taskId)
        } else if let softTaskId = ProjectTaskHistoryStore.shared.bestTask(forProjectId: project.harvestProjectId),
                  availableTasks.contains(where: { $0.id == softTaskId }) {
            selectTask(softTaskId)
        } else if let onlyTask = availableTasks.first, availableTasks.count == 1 {
            selectTask(onlyTask.id)
        }
    }

    private func selectTask(_ taskId: Int) {
        selectedTaskId = taskId
        refreshDuplicateConfirm()
    }

    /// Re-evaluate whether the duplicate-entry banner should be shown for
    /// the current (project, task, date) tuple. Called whenever any of
    /// those change.
    private func refreshDuplicateConfirm() {
        let existing = existingEntriesOnSelectedDate
        withAnimation(.easeInOut(duration: 0.15)) {
            duplicateConfirmEntries = existing.isEmpty ? nil : existing
        }
    }

    private var enteredHours: Double {
        Double(timeHours) + Double(timeMinutes) / 60.0
    }

    // The save / start / log paths dismiss the form *before* awaiting
    // the API round-trip. SwiftUI removes the form view immediately so
    // the user is back on the main panel; the in-flight request keeps
    // running, and the panel header's existing progress indicator
    // (driven by `viewModel.isLoading` via the `await refresh()` inside
    // each viewModel method) shows that work is happening. Errors land
    // in `viewModel.errorMessage`, which the panel renders.

    private func startTimer() async {
        guard let projectId = selectedProjectId,
              let taskId = selectedTaskId else { return }

        let hours = enteredHours > 0 ? enteredHours : nil
        let notesToSend = notes.isEmpty ? nil : notes
        FavoritesStore.shared.markUsed(projectId: projectId, taskId: taskId)
        if sourcedFromCalendarPicker {
            MeetingHistoryStore.shared.record(notes: notes, projectId: projectId, taskId: taskId)
        }
        if let event = sourcedCalendarEvent {
            viewModel.finalizeMeetingPromptAction(for: event)
        }
        onDismiss()
        await viewModel.startNewTimer(projectId: projectId, taskId: taskId, hours: hours, notes: notesToSend)
        // Arm the post-meeting overage reminder — after the start, so
        // the reminder's next tick sees the timer actually running.
        if let event = sourcedCalendarEvent {
            viewModel.noteCalendarSourcedTimer(event: event, projectId: projectId, taskId: taskId)
        }
    }

    private func logTime() async {
        guard let projectId = selectedProjectId,
              let taskId = selectedTaskId else { return }
        guard enteredHours > 0 else { return }

        let hours = enteredHours
        let notesToSend = notes.isEmpty ? nil : notes
        let date = spentDateString
        FavoritesStore.shared.markUsed(projectId: projectId, taskId: taskId)
        if sourcedFromCalendarPicker {
            MeetingHistoryStore.shared.record(notes: notes, projectId: projectId, taskId: taskId)
        }
        if let event = sourcedCalendarEvent {
            viewModel.finalizeMeetingPromptAction(for: event)
        }
        onDismiss()
        await viewModel.logTimeEntry(
            projectId: projectId,
            taskId: taskId,
            hours: hours,
            notes: notesToSend,
            spentDate: date
        )
    }

    private func saveEntry() async {
        guard let entry = editingEntry,
              let projectId = selectedProjectId,
              let taskId = selectedTaskId else { return }
        let hours = enteredHours > 0 ? enteredHours : entry.hours
        // Only send notes if the user changed them, to avoid unintentionally clearing
        let notesToSend = notes != (entry.notes ?? "") ? notes : entry.notes ?? ""

        FavoritesStore.shared.markUsed(projectId: projectId, taskId: taskId)
        if sourcedFromCalendarPicker {
            MeetingHistoryStore.shared.record(notes: notes, projectId: projectId, taskId: taskId)
        }
        if let event = sourcedCalendarEvent {
            viewModel.finalizeMeetingPromptAction(for: event)
        }
        onDismiss()
        await viewModel.updateExistingEntry(
            entryId: entry.id,
            projectId: projectId,
            taskId: taskId,
            hours: hours,
            notes: notesToSend
        )
    }

    private func deleteEntry() async {
        guard let entry = editingEntry else { return }
        onDismiss()
        await viewModel.deleteTimeEntry(entryId: entry.id)
    }

    /// Commit the timer-move flow. The view model resolves whether the
    /// destination is an existing today entry (merge) or a new one
    /// (create), adjusts the source, and starts/keeps whichever timer
    /// `switchTimer` says should run.
    private func commitTimerMove(switchTimer: Bool) async {
        guard let move = timerMove,
              let projectId = selectedProjectId,
              let taskId = selectedTaskId else { return }
        let hours = enteredHours
        let notesToSend = notes.isEmpty ? nil : notes
        FavoritesStore.shared.markUsed(projectId: projectId, taskId: taskId)
        // Meeting-sourced moves (the prompt bar's first-encounter path)
        // train the title → (project, task) memory like the other
        // calendar-sourced saves.
        if sourcedFromCalendarPicker {
            MeetingHistoryStore.shared.record(notes: notes, projectId: projectId, taskId: taskId)
        }
        if let event = sourcedCalendarEvent {
            viewModel.finalizeMeetingPromptAction(for: event)
        }
        onDismiss()
        await viewModel.commitTimerMove(
            move,
            projectId: projectId,
            taskId: taskId,
            hoursToMove: hours,
            notes: notesToSend,
            switchTimer: switchTimer
        )
        // Only the switch shape leaves the destination timer running —
        // that's the one worth watching for post-meeting overage.
        if switchTimer, let event = sourcedCalendarEvent {
            viewModel.noteCalendarSourcedTimer(event: event, projectId: projectId, taskId: taskId)
        }
    }

    /// Commit the idle-move flow with a brand-new entry on the chosen
    /// project/task. The duplicate banner short-circuits this path
    /// when an existing entry would be a better target.
    private func commitIdleMove() async {
        guard let move = idleMove,
              let projectId = selectedProjectId,
              let taskId = selectedTaskId else { return }
        let notesToSend = notes.isEmpty ? nil : notes
        onDismiss()
        await viewModel.idleMoveCreateNew(
            move,
            projectId: projectId,
            taskId: taskId,
            notes: notesToSend
        )
    }

    // MARK: - Delete Confirmation

    /// Inline replacement for the system `.confirmationDialog` —
    /// MenuBarExtra panels can't host system dialogs without losing
    /// key state, which causes the dialog to dismiss without firing
    /// its action. See `InlineConfirmationRow` for the shared shape.
    private var deleteConfirmRow: some View {
        InlineConfirmationRow(
            message: "Delete this entry from Harvest?",
            confirmLabel: "Delete",
            confirmSystemImage: "trash",
            onCancel: { showDeleteConfirm = false },
            onConfirm: {
                showDeleteConfirm = false
                Task { await deleteEntry() }
            }
        )
    }

    // MARK: - Duplicate Confirmation

    /// Shown when the form opened on a project the user is booked on in
    /// Forecast but isn't a member of in Harvest — Harvest won't accept
    /// a time entry until an admin adds them. Replaces the old silent
    /// dead-end (empty picker, nothing selectable, no explanation).
    private func unassignedBanner(projectName: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 11))
                .foregroundStyle(YieldStatusColors.warning)
            Text("You're booked on \(projectName) in Forecast but aren't a member of it in Harvest, so it can't be selected here. Ask a project admin to add you in Harvest, then try again.")
                .font(YieldFonts.dmSans(11))
                .foregroundStyle(YieldColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(YieldStatusColors.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.card))
    }

    /// Compact context line for timer-move mode: where the time is
    /// coming from and how much is on that timer right now. The total
    /// is live — `elapsedOffset` on the observable view model ticks
    /// every minute, so the line keeps counting under the open form.
    private func moveSourceBanner(_ move: TimeComparisonViewModel.PendingTimerMove) -> some View {
        let available = viewModel.timerMoveAvailableHours(move)
        let (h, m) = available.roundedHM
        return HStack(spacing: 6) {
            Image(systemName: "arrow.turn.up.right")
                .font(.system(size: 11))
                .foregroundStyle(YieldColors.textSecondary)
            Text("From \(move.sourceProjectName) / \(move.sourceTaskName) — \(h):\(String(format: "%02d", m)) on the timer")
                .font(YieldFonts.dmSans(11))
                .foregroundStyle(YieldColors.textSecondary)
                .lineLimit(1)
        }
    }

    /// Timer-move replacement for `duplicateConfirmBanner` — informational
    /// rather than an action fork. Two cases: the picked task already has
    /// time today (fine — the move merges into it), or the picked task IS
    /// the source timer (blocked; `canMove` disables the commit buttons).
    private func moveTargetBanner(entries: [TimeEntryInfo]) -> some View {
        let totalHours = entries.reduce(0.0) { $0 + $1.hours }
        let projectName = selectedProject?.displayName ?? "This project"
        let taskName = entries.first?.taskName ?? "this task"
        let (h, m) = totalHours.roundedHM
        let timeStr = "\(h)h \(String(format: "%02d", m))m"
        let message = isMoveSelfTarget
            ? "That's the timer you're moving time from — pick a different task."
            : "\(projectName) / \(taskName) already has \(timeStr) today. The moved time will be added to that entry."

        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: isMoveSelfTarget ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.system(size: 10))
                .foregroundStyle(isMoveSelfTarget ? YieldColors.yellowAccent : YieldColors.textSecondary)
                .padding(.top, 1)
            Text(message)
                .font(YieldFonts.dmSans(11))
                .foregroundStyle(YieldColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(isMoveSelfTarget ? YieldColors.yellowFaint : YieldColors.surfaceDefault)
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.dropdown))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.opacity)
    }

    private func duplicateConfirmBanner(entries: [TimeEntryInfo]) -> some View {
        let totalHours = entries.reduce(0.0) { $0 + $1.hours }
        let projectName = selectedProject?.displayName ?? "This project"
        let taskName = entries.first?.taskName ?? "this task"
        let hasRunning = entries.contains(where: { $0.isRunning })
        let (h, m) = totalHours.roundedHM
        let timeStr = "\(h)h \(String(format: "%02d", m))m"
        let label = "\(projectName) / \(taskName)"
        let dayPhrase = isSpentDateToday
            ? "today"
            : "on \(Self.headerDateFormatter.string(from: spentDate))"
        let message = hasRunning
            ? "\(label) has a timer running (\(timeStr) \(dayPhrase))."
            : "\(label) already has \(timeStr) logged \(dayPhrase)."

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(YieldColors.yellowAccent)
                Text(message)
                    .font(YieldFonts.dmSans(11))
                    .foregroundStyle(YieldColors.textPrimary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if isIdleMove {
                    // Idle-move mode: merge into the existing entry by
                    // adding the idle hours, rather than resuming a
                    // timer or creating a duplicate.
                    Button {
                        let mostRecent = entries.max(by: { ($0.id) < ($1.id) })
                        guard let move = idleMove, let entryId = mostRecent?.id else { return }
                        onDismiss()
                        Task {
                            await viewModel.idleMoveAddToExisting(move, entryId: entryId)
                        }
                    } label: {
                        Text("Add to existing")
                    }
                    .buttonStyle(.greenOutlined)

                    Button {
                        Task { await commitIdleMove() }
                    } label: {
                        Text("New entry")
                    }
                    .buttonStyle(.yieldBordered)
                } else {
                    // Resume the most recent entry — only when no timer is already running
                    if !hasRunning {
                        Button {
                            let mostRecent = entries.max(by: { ($0.id) < ($1.id) })
                            guard let entryId = mostRecent?.id else { return }
                            // Resuming is as much a commit as Start
                            // Timer — a calendar-sourced resume still
                            // trains the meeting memory and arms the
                            // banner indicator + post-meeting reminder.
                            if sourcedFromCalendarPicker, let projectId = selectedProjectId, let taskId = selectedTaskId {
                                MeetingHistoryStore.shared.record(notes: notes, projectId: projectId, taskId: taskId)
                            }
                            if let event = sourcedCalendarEvent {
                                viewModel.finalizeMeetingPromptAction(for: event)
                            }
                            onDismiss()
                            Task {
                                await viewModel.toggleEntryTimer(entryId: entryId, isRunning: false)
                                if let event = sourcedCalendarEvent,
                                   let projectId = selectedProjectId,
                                   let taskId = selectedTaskId {
                                    viewModel.noteCalendarSourcedTimer(event: event, projectId: projectId, taskId: taskId)
                                }
                            }
                        } label: {
                            Text("Resume existing")
                        }
                        .buttonStyle(.greenOutlined)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            duplicateConfirmEntries = nil
                        }
                    } label: {
                        Text("New entry")
                    }
                    .buttonStyle(.yieldBordered)
                }

                Button {
                    onDismiss()
                } label: {
                    Text("Cancel")
                }
                .buttonStyle(.yieldBordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(YieldColors.yellowFaint)
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.dropdown))
        .overlay(
            RoundedRectangle(cornerRadius: YieldRadius.dropdown)
                .strokeBorder(YieldColors.yellowAccent.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.opacity)
    }
}

// MARK: - Time Input

/// Single-field time input that accepts either `H:MM` or decimal-hours
/// formats and reformats to `H:MM` on commit. Mirrors Harvest's web
/// behavior so a paste of `1.5` lands as `1:30`. Keeps its external
/// API as separate `hours` and `minutes` `Int` bindings so the parent
/// form's save/start logic doesn't have to change.
private struct TimeInputView: View {
    @Binding var hours: Int
    @Binding var minutes: Int

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("0:00", text: $text)
            .font(YieldFonts.jetBrainsMono(16, weight: .medium))
            .foregroundStyle(YieldColors.textPrimary)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .frame(width: 64)
            .focused($focused)
            .onSubmit { commit() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: YieldDimensions.inputFieldHeight)
            .background(YieldColors.surfaceDefault)
            .yieldBorder()
            .fixedSize(horizontal: true, vertical: false)
            .onAppear { text = Self.format(hours: hours, minutes: minutes) }
            // Push parseable text into the bindings on every keystroke
            // so the parent form sees the latest values even if the
            // user clicks Save without first blurring the field — only
            // commit (focus loss / submit) reformats the text back to
            // canonical `H:MM`, so partial inputs like `1:` or `1.`
            // don't get rewritten while the user is mid-edit.
            .onChange(of: text) { _, newText in
                guard focused, let (h, m) = Self.parse(newText) else { return }
                if hours != h { hours = h }
                if minutes != m { minutes = m }
            }
            // Edit-mode populate happens via the parent form's `.task`,
            // which runs after this view's `onAppear` — so without these
            // observers the field stays at the initial "0:00" even when
            // bindings get filled in moments later. The `text != ...`
            // guard keeps the also-fires-during-commit() path a no-op.
            .onChange(of: hours) { _, _ in
                guard !focused else { return }
                let formatted = Self.format(hours: hours, minutes: minutes)
                if text != formatted { text = formatted }
            }
            .onChange(of: minutes) { _, _ in
                guard !focused else { return }
                let formatted = Self.format(hours: hours, minutes: minutes)
                if text != formatted { text = formatted }
            }
    }

    private func commit() {
        if let (h, m) = Self.parse(text) {
            hours = h
            minutes = m
            text = Self.format(hours: h, minutes: m)
        } else {
            // Unparseable — restore the display from the last good values.
            text = Self.format(hours: hours, minutes: minutes)
        }
    }

    static func format(hours: Int, minutes: Int) -> String {
        "\(hours):\(String(format: "%02d", minutes))"
    }

    /// Parse a time entry. Accepts:
    ///   `H:MM`   →  literal hours/minutes
    ///   `H.MM` or `H,MM`  →  decimal hours (1.5 → 1h30m)
    ///   bare integer       →  whole hours (1 → 1h00m)
    /// Returns nil if the string is non-empty and unparseable; empty
    /// string returns (0, 0). Hours capped at 99, minutes at 59.
    static func parse(_ raw: String) -> (Int, Int)? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return (0, 0) }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let hStr = parts[0].trimmingCharacters(in: .whitespaces)
            let mStr = parts[1].trimmingCharacters(in: .whitespaces)
            let h = hStr.isEmpty ? 0 : Int(hStr)
            let m = mStr.isEmpty ? 0 : Int(mStr)
            guard let h, let m, h >= 0, m >= 0 else { return nil }
            return (min(h, 99), min(m, 59))
        }

        // Decimal hours — accept comma or period as the separator.
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let decimal = Double(normalized), decimal >= 0 else { return nil }
        let totalMinutes = Int((decimal * 60).rounded())
        return (min(totalMinutes / 60, 99), totalMinutes % 60)
    }
}
