import SwiftUI

struct NewTimerFormView: View {
    let viewModel: TimeComparisonViewModel
    let editingEntry: TimeEntryInfo?
    let preselectedProjectId: Int?
    let targetDate: Date?
    let onDismiss: () -> Void

    @State private var allProjects: [TimeComparisonViewModel.TimerProjectOption] = []
    @State private var isLoadingProjects = true
    @State private var selectedProjectId: Int?
    @State private var selectedTaskId: Int?
    @State private var notes: String = ""
    @State private var timeHours: Int = 0
    @State private var timeMinutes: Int = 0
    @State private var availableTasks: [TaskOption] = []
    @State private var isStarting = false
    @State private var isLogging = false
    @State private var isSaving = false
    @State private var spentDate: Date = Date()
    @State private var duplicateConfirmEntries: [TimeEntryInfo]?

    init(viewModel: TimeComparisonViewModel, editingEntry: TimeEntryInfo? = nil, preselectedProjectId: Int? = nil, targetDate: Date? = nil, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.editingEntry = editingEntry
        self.preselectedProjectId = preselectedProjectId
        self.targetDate = targetDate
        self.onDismiss = onDismiss
    }

    private var isEditing: Bool { editingEntry != nil }
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
        isEditing ? "Edit time entry:" : "New time entry:"
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
        if isEditing {
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
        selectedProjectId != nil && selectedTaskId != nil && !isStarting && !isLogging
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
                // Project dropdown
                projectPicker

                // Task dropdown
                taskPicker

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
                            .padding(.vertical, 4)
                    }
                    .frame(height: 52)
                    .background(YieldColors.surfaceDefault)
                    .clipShape(RoundedRectangle(cornerRadius: YieldRadius.dropdown))
                    .overlay(
                        RoundedRectangle(cornerRadius: YieldRadius.dropdown)
                            .strokeBorder(YieldColors.border, lineWidth: 1)
                    )

                    // Manual time entry (HH:MM)
                    TimeInputView(hours: $timeHours, minutes: $timeMinutes)
                }
            }
            .padding(16)

            // Duplicate timer confirmation
            if let entries = duplicateConfirmEntries {
                duplicateConfirmBanner(entries: entries)
            }

            // Actions
            HStack(spacing: 8) {
                if isEditing {
                    Button {
                        Task { await saveEntry() }
                    } label: {
                        Text("Save")
                    }
                    .buttonStyle(.greenOutlined)
                    .disabled(!canStart || isSaving)
                    .opacity(canStart && !isSaving ? 1 : 0.5)
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

                if !isEditing {
                    Button {
                        Task { await logTime() }
                    } label: {
                        Text("Log Time")
                    }
                    .buttonStyle(.yieldBordered)
                    .disabled(!canLog)
                    .opacity(canLog ? 1 : 0.5)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Spacer()
        }
        .task {
            // Initialize spent date. Priority:
            //   1. Edit mode → entry's own date
            //   2. Explicit targetDate parameter
            //   3. Active weekday filter → pre-fill the filtered day
            //   4. Today (default)
            if let entry = editingEntry, let parsed = DateHelpers.dateFormatter.date(from: entry.date) {
                spentDate = parsed
            } else if let target = targetDate {
                spentDate = target
            } else if let filter = viewModel.dayFilter,
                      let parsed = DateHelpers.dateFormatter.date(from: filter) {
                spentDate = parsed
            }

            await loadProjects()
            if let entry = editingEntry {
                // Edit mode: populate all fields
                selectedProjectId = entry.harvestProjectId
                notes = entry.notes ?? ""
                timeHours = Int(entry.hours)
                timeMinutes = Int((entry.hours - Double(Int(entry.hours))) * 60)
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
            isDisabled: selectedProjectId == nil
        ) { id in
            selectTask(id)
        }
        .opacity(selectedProjectId == nil ? 0.5 : 1)
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
        if let onlyTask = availableTasks.first, availableTasks.count == 1 {
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

    private func startTimer() async {
        guard let projectId = selectedProjectId,
              let taskId = selectedTaskId else { return }

        isStarting = true
        let hours = enteredHours > 0 ? enteredHours : nil
        await viewModel.startNewTimer(projectId: projectId, taskId: taskId, hours: hours, notes: notes.isEmpty ? nil : notes)
        isStarting = false
        onDismiss()
    }

    private func logTime() async {
        guard let projectId = selectedProjectId,
              let taskId = selectedTaskId else { return }
        guard enteredHours > 0 else { return }

        isLogging = true
        await viewModel.logTimeEntry(
            projectId: projectId,
            taskId: taskId,
            hours: enteredHours,
            notes: notes.isEmpty ? nil : notes,
            spentDate: spentDateString
        )
        isLogging = false
        onDismiss()
    }

    private func saveEntry() async {
        guard let entry = editingEntry,
              let taskId = selectedTaskId else { return }
        let hours = enteredHours > 0 ? enteredHours : entry.hours
        // Only send notes if the user changed them, to avoid unintentionally clearing
        let notesToSend = notes != (entry.notes ?? "") ? notes : entry.notes ?? ""

        isSaving = true
        await viewModel.updateExistingEntry(
            entryId: entry.id,
            taskId: taskId,
            hours: hours,
            notes: notesToSend
        )
        isSaving = false
        onDismiss()
    }

    // MARK: - Duplicate Confirmation

    private func duplicateConfirmBanner(entries: [TimeEntryInfo]) -> some View {
        let totalHours = entries.reduce(0.0) { $0 + $1.hours }
        let projectName = selectedProject?.projectName ?? "This project"
        let taskName = entries.first?.taskName ?? "this task"
        let hasRunning = entries.contains(where: { $0.isRunning })
        let h = Int(totalHours)
        let m = Int((totalHours - Double(h)) * 60)
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
                // Resume the most recent entry — only when no timer is already running
                if !hasRunning {
                    Button {
                        let mostRecent = entries.max(by: { ($0.id) < ($1.id) })
                        guard let entryId = mostRecent?.id else { return }
                        Task {
                            isStarting = true
                            await viewModel.toggleEntryTimer(entryId: entryId, isRunning: false)
                            isStarting = false
                            onDismiss()
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

// MARK: - Time Input (HH:MM)

private struct TimeInputView: View {
    @Binding var hours: Int
    @Binding var minutes: Int

    @State private var hoursText: String = "0"
    @State private var minutesText: String = "00"
    @FocusState private var hoursFocused: Bool
    @FocusState private var minutesFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Hours field
            TextField("0", text: $hoursText)
                .font(YieldFonts.monoMedium)
                .foregroundStyle(YieldColors.textPrimary)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 24)
                .focused($hoursFocused)
                .onChange(of: hoursText) { _, newValue in
                    let filtered = String(newValue.filter { $0.isNumber }.prefix(2))
                    if filtered != newValue { hoursText = filtered }
                    hours = min(Int(filtered) ?? 0, 99)
                }
                .onChange(of: hoursFocused) { _, focused in
                    if !focused {
                        // Format on blur: strip leading zeros but keep at least "0"
                        hoursText = "\(hours)"
                    }
                }

            Text(":")
                .font(YieldFonts.monoMedium)
                .foregroundStyle(YieldColors.textSecondary)

            // Minutes field
            TextField("00", text: $minutesText)
                .font(YieldFonts.monoMedium)
                .foregroundStyle(YieldColors.textPrimary)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.leading)
                .frame(width: 24)
                .focused($minutesFocused)
                .onChange(of: minutesText) { _, newValue in
                    let filtered = String(newValue.filter { $0.isNumber }.prefix(2))
                    if filtered != newValue { minutesText = filtered }
                    let val = Int(filtered) ?? 0
                    minutes = min(val, 59)
                }
                .onChange(of: minutesFocused) { _, focused in
                    if !focused {
                        // Pad to 2 digits on blur
                        minutesText = String(format: "%02d", minutes)
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 52)
        .background(YieldColors.surfaceDefault)
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.dropdown))
        .overlay(
            RoundedRectangle(cornerRadius: YieldRadius.dropdown)
                .strokeBorder(YieldColors.border, lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            hoursText = "\(hours)"
            minutesText = String(format: "%02d", minutes)
        }
        .onChange(of: hours) { _, newValue in
            if !hoursFocused {
                hoursText = "\(newValue)"
            }
        }
        .onChange(of: minutes) { _, newValue in
            if !minutesFocused {
                minutesText = String(format: "%02d", newValue)
            }
        }
    }
}
