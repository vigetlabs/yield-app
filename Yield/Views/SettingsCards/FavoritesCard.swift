import SwiftUI

/// Per-favorite shortcut entries surfaced as a removable list.
struct FavoritesCard: View {
    let allProjects: [TimeComparisonViewModel.TimerProjectOption]
    let isLoadingProjects: Bool

    /// Read directly so a favorite toggle elsewhere only invalidates
    /// this card.
    private let favoritesStore: FavoritesStore = FavoritesStore.shared

    var body: some View {
        // Hoist once per body pass — read at the loading guard, the
        // empty guard, the ForEach, and the separator-skip check.
        // Previously each was a separate Dictionary-index + sort
        // recomputation across the full favorites list.
        let favorites = resolvedFavorites
        return VStack(alignment: .leading, spacing: 0) {
            SettingsCardSectionHeader("Favorites")

            if isLoadingProjects && favorites.isEmpty {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                        .tint(YieldColors.textSecondary)
                    Text("Loading…")
                        .font(YieldFonts.dmSans(11))
                        .foregroundStyle(YieldColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else if favorites.isEmpty {
                Text("No favorites yet. Add one from the new/edit timer screen.")
                    .font(YieldFonts.dmSans(11))
                    .foregroundStyle(YieldColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                // Cap the list at ~3 rows of height with a partial 4th
                // row peeking, so 4+ favorites trigger scrolling.
                // `fixedSize(vertical: true)` lets the scroll view
                // shrink to its content's natural height when there
                // are few favorites — the cap only kicks in once the
                // list would overflow.
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(favorites.enumerated()), id: \.element.id) { index, fav in
                            favoriteRow(fav)
                            if index < favorites.count - 1 {
                                Rectangle()
                                    .fill(YieldColors.border)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: 160)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .yieldCard()
    }

    // MARK: - Row

    private func favoriteRow(_ fav: FavoriteEntry) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 10))
                .foregroundStyle(YieldColors.textSecondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(ProjectStatus.qualifiedName(client: fav.clientName, project: fav.displayName))
                    .font(YieldFonts.dmSans(11, weight: .medium))
                    .foregroundStyle(YieldColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(fav.taskName)
                    .font(YieldFonts.dmSans(10))
                    .foregroundStyle(YieldColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Button {
                favoritesStore.remove(projectId: fav.projectId, taskId: fav.taskId)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(YieldColors.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove favorite")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Resolution

    /// Display row for a single favorite, used to populate the
    /// favorites card. Resolved at render time from `allProjects`.
    private struct FavoriteEntry: Identifiable {
        let projectId: Int
        let taskId: Int
        let clientName: String?
        let projectName: String
        let projectCode: String?
        let taskName: String

        var id: String { "\(projectId)-\(taskId)" }

        /// Project name with the `[code]` prefix when set.
        var displayName: String {
            ProjectStatus.displayName(code: projectCode, project: projectName)
        }
    }

    /// Resolved favorites sorted alphabetically by client → project → task,
    /// with unresolved (project no longer accessible to the user) entries
    /// pushed to the bottom under a generic name so they're still removable.
    private var resolvedFavorites: [FavoriteEntry] {
        let projectsById = allProjects.indexed { $0.harvestProjectId }
        let entries: [FavoriteEntry] = favoritesStore.favorites.map { fav in
            let project = projectsById[fav.projectId]
            let task = project?.taskAssignments.first(where: { $0.task.id == fav.taskId })?.task
            return FavoriteEntry(
                projectId: fav.projectId,
                taskId: fav.taskId,
                clientName: project?.clientName,
                projectName: project?.projectName ?? "Unknown project",
                projectCode: project?.projectCode,
                taskName: task?.name ?? "Unknown task"
            )
        }
        return entries.sorted { a, b in
            // Resolved (has a real project) first, then alphabetical.
            let aResolved = a.projectName != "Unknown project"
            let bResolved = b.projectName != "Unknown project"
            if aResolved != bResolved { return aResolved }
            let ac = a.clientName ?? ""
            let bc = b.clientName ?? ""
            if ac != bc { return ac.localizedCaseInsensitiveCompare(bc) == .orderedAscending }
            if a.projectName != b.projectName {
                return a.projectName.localizedCaseInsensitiveCompare(b.projectName) == .orderedAscending
            }
            return a.taskName.localizedCaseInsensitiveCompare(b.taskName) == .orderedAscending
        }
    }
}
