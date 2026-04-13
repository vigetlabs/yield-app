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

    private var headerTitle: String {
        let prefix = isEditing ? "Edit time entry" : "New time entry"
        return "\(prefix): \(DateHelpers.displayFormatter.string(from: spentDate))"
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

    private var canLog: Bool {
        canStart && enteredHours > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text(headerTitle)
                    .font(YieldFonts.titleMedium)
                    .foregroundStyle(YieldColors.textPrimary)

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
                    .disabled(!canStart)
                    .opacity(canStart ? 1 : 0.5)
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
            // Initialize spent date: edit mode uses the entry's date, create mode uses
            // the targetDate (from a day-cell click) or today.
            if let entry = editingEntry, let parsed = DateHelpers.dateFormatter.date(from: entry.date) {
                spentDate = parsed
            } else if let target = targetDate {
                spentDate = target
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
            selectedTaskId = id
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
        availableTasks = project.taskAssignments.map { TaskOption(id: $0.task.id, name: $0.task.name) }
        if availableTasks.count == 1 {
            selectedTaskId = availableTasks.first?.id
        }
    }

    private var enteredHours: Double {
        Double(timeHours) + Double(timeMinutes) / 60.0
    }

    private func startTimer() async {
        guard let projectId = selectedProjectId,
              let taskId = selectedTaskId else { return }

        isStarting = true
        await viewModel.startNewTimer(projectId: projectId, taskId: taskId, notes: notes.isEmpty ? nil : notes)
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
