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
    let onDismiss: () -> Void

    @State private var allProjects: [TimeComparisonViewModel.TimerProjectOption] = []
    @State private var isLoadingProjects = true
    @State private var selectedProjectId: Int?
    @State private var selectedTaskId: Int?
    @State private var notes: String = ""
    @State private var timeHours: Int = 0
    @State private var timeMinutes: Int = 0
    @State private var availableTasks: [TaskOption] = []
    @State private var spentDate: Date = Date()
    @State private var duplicateConfirmEntries: [TimeEntryInfo]?
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

    init(viewModel: TimeComparisonViewModel, editingEntry: TimeEntryInfo? = nil, preselectedProjectId: Int? = nil, targetDate: Date? = nil, idleMove: TimeComparisonViewModel.PendingIdleMove? = nil, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.editingEntry = editingEntry
        self.preselectedProjectId = preselectedProjectId
        self.targetDate = targetDate
        self.idleMove = idleMove
        self.onDismiss = onDismiss
    }

    private var isEditing: Bool { editingEntry != nil }
    private var isIdleMove: Bool { idleMove != nil }
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
        if isEditing || isIdleMove {
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

    var body: some View {
        // The calendar event picker takes over the form's body
        // entirely while open — MenuBarExtra panels can't host
        // sheets or popovers, so an inline swap is the only way
        // to surface secondary UI without breaking the panel's
        // resize/positioning behavior.
        if showCalendarPicker {
            CalendarEventPickerView(
                onSelect: applyCalendarEvent,
                onCancel: { showCalendarPicker = false }
            )
        } else {
            formBody
        }
    }

    private var formBody: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            projectPicker
                            if !resolvedFavorites.isEmpty {
                                favoritesPickerButton
                            }
                        }
                        taskPicker
                    }
                    favoriteButton
                }

                // Notes + Time row
                HStack(spacing: 12) {
                    // Notes field
                    ZStack(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("Notes (optional)")
                                .font(YieldFonts.titleSmall)
                                .foregroundStyle(YieldColors.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        TextEditor(text: $notes)
                            .font(YieldFonts.titleSmall)
                            .foregroundStyle(YieldColors.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }
                    .frame(height: YieldDimensions.inputFieldHeight)
                    .background(YieldColors.surfaceDefault)
                    .yieldBorder()

                    // Manual time entry (HH:MM)
                    TimeInputView(hours: $timeHours, minutes: $timeMinutes)
                }
            }
            .padding(16)

            // Duplicate timer confirmation
            if let entries = duplicateConfirmEntries {
                duplicateConfirmBanner(entries: entries)
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

                    if !isEditing && !isIdleMove {
                        // Calendar picker button hidden until the OAuth
                        // verification + PKCE refactor land. The button
                        // definition (`calendarPickerButton` below) stays
                        // in the codebase so re-enabling is a one-line
                        // change — restore by uncommenting the line below.
                        // calendarPickerButton

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
        .task {
            // Initialize spent date. Priority:
            //   1. Edit mode → entry's own date
            //   2. Idle-move mode → today (idle moves are constrained to today)
            //   3. Explicit targetDate parameter
            //   4. Active weekday filter → pre-fill the filtered day
            //   5. Today (default)
            if let entry = editingEntry, let parsed = DateHelpers.dateFormatter.date(from: entry.date) {
                spentDate = parsed
            } else if isIdleMove {
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
            } else if let projectId = preselectedProjectId,
                      let project = allProjects.first(where: { $0.harvestProjectId == projectId }) {
                // Pre-selected project: populate project and load its tasks
                selectProject(project)
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
    /// two icon affordances feel like a set. Disabled when Google
    /// Calendar isn't connected; tooltip points the user at Settings.
    private var calendarPickerButton: some View {
        let connected = AppState.shared.googleAuthService.isAuthenticated
        return Button {
            showCalendarPicker = true
        } label: {
            Image(systemName: "calendar")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(connected ? YieldColors.textPrimary : YieldColors.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!connected)
        .opacity(connected ? 1 : 0.4)
        .help(connected
            ? "Pick from today's calendar events"
            : "Connect Google Calendar in Settings")
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
        showCalendarPicker = false
    }

    // MARK: - Favorites Pill Row

    private struct ResolvedFavorite: Identifiable {
        let projectId: Int
        let taskId: Int
        let clientName: String?
        let projectName: String
        let taskName: String
        let lastUsedAt: Date

        var id: String { "\(projectId)-\(taskId)" }
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
    /// selector.
    private var favoritesPickerButton: some View {
        DropdownPicker(
            label: "Favorites",
            placeholder: "★ Favorites",
            selectedId: nil,
            isPullDown: true,
            richItems: resolvedFavorites.enumerated().map { index, fav in
                (id: index, attributedTitle: Self.favoriteMenuItemTitle(for: fav))
            },
            showsItemSeparators: true
        ) { index in
            guard resolvedFavorites.indices.contains(index) else { return }
            applyFavorite(resolvedFavorites[index])
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

        // Project line (Client — Project)
        let projectText = ProjectStatus.qualifiedName(client: fav.clientName, project: fav.projectName)
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
            groups: projectGroups,
            selectedId: selectedProjectId
        ) { id in
            if let project = allProjects.first(where: { $0.harvestProjectId == id }) {
                selectProject(project)
            }
        }
    }

    private var projectGroups: [DropdownGroup] {
        let grouped = Dictionary(grouping: allProjects) { $0.clientName ?? "" }
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
                items: sorted.map { ($0.harvestProjectId, $0.projectName) }
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
        isLoadingProjects = false
    }

    private func selectProject(_ project: TimeComparisonViewModel.TimerProjectOption) {
        selectedProjectId = project.harvestProjectId
        selectedTaskId = nil
        duplicateConfirmEntries = nil
        availableTasks = project.taskAssignments.map { TaskOption(id: $0.task.id, name: $0.task.name) }
        // Auto-select preference order:
        //   1. Most-recently-used favorite for this project (covers
        //      both single-favorite and multi-favorite cases)
        //   2. Project's only task, if there's just one
        if let fav = FavoritesStore.shared.mostRecentlyUsedFavorite(forProjectId: project.harvestProjectId),
           availableTasks.contains(where: { $0.id == fav.taskId }) {
            selectTask(fav.taskId)
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
        onDismiss()
        await viewModel.startNewTimer(projectId: projectId, taskId: taskId, hours: hours, notes: notesToSend)
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
    /// its action. Renders the explanation alongside Cancel + Delete
    /// buttons in place of the normal actions row.
    private var deleteConfirmRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The entry will be removed from Harvest. This can't be undone.")
                .font(YieldFonts.dmSans(11))
                .foregroundStyle(YieldColors.textSecondary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") {
                    showDeleteConfirm = false
                }
                .buttonStyle(.yieldBordered)

                Button {
                    showDeleteConfirm = false
                    Task { await deleteEntry() }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.redOutlined)
            }
        }
    }

    // MARK: - Duplicate Confirmation

    private func duplicateConfirmBanner(entries: [TimeEntryInfo]) -> some View {
        let totalHours = entries.reduce(0.0) { $0 + $1.hours }
        let projectName = selectedProject?.projectName ?? "This project"
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
                            onDismiss()
                            Task {
                                await viewModel.toggleEntryTimer(entryId: entryId, isRunning: false)
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
