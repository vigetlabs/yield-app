import Foundation

/// Which projects the weekly chart draws in their own colour, in what
/// order, and which fold into a neutral "Other".
///
/// Projects are ordered by the week's hours, most first, so the project
/// you spend the week on takes the first colour — not whichever sorts
/// first alphabetically, which painted the same project the same
/// colour every week whatever it was. Ties go by name. Past the
/// palette's last slot, projects fold into one "Other" series: a hue is
/// never generated or reused.
///
/// The order is worked out from the whole week, so isolating a project
/// (which zeroes the others' hours for display) repaints nothing.
struct ChartSeriesPlan: Equatable {
    struct Project: Equatable, Identifiable {
        let id: Int
        /// The chart's identity for the series (`ChartPoint.projectName`).
        let name: String
        /// What the legend calls it: the project's name without its code.
        var label: String
        /// The client, under the label in the legend. For "Other", how
        /// many projects it holds.
        var client: String?
        /// The week's total.
        var hours: Double
    }

    static let otherId = -1
    static let otherName = "Other"

    /// One row per colour, in slot order: `projects[i]` takes slot `i`.
    /// "Other", when there is one, comes last.
    let projects: [Project]
    /// Ids of the projects drawn as part of "Other".
    let folded: Set<Int>

    init(points: [TimeComparisonViewModel.ChartPoint], slotCount: Int) {
        var hours: [Int: Double] = [:]
        var names: [Int: String] = [:]
        var labels: [Int: String] = [:]
        var clients: [Int: String] = [:]
        for point in points {
            hours[point.projectId, default: 0] += point.hours
            names[point.projectId] = names[point.projectId] ?? point.projectName
            labels[point.projectId] = labels[point.projectId] ?? point.projectLabel
            clients[point.projectId] = clients[point.projectId] ?? point.clientName
        }
        let ordered = hours.keys.sorted { a, b in
            if hours[a]! != hours[b]! { return hours[a]! > hours[b]! }
            let byName = names[a]!.localizedCaseInsensitiveCompare(names[b]!)
            if byName != .orderedSame { return byName == .orderedAscending }
            return a < b
        }
        .map { Project(id: $0, name: names[$0]!, label: labels[$0] ?? names[$0]!, client: clients[$0], hours: hours[$0]!) }

        let slots = max(slotCount, 0)
        if ordered.count > slots {
            let rest = ordered.dropFirst(slots)
            let other = Project(
                id: Self.otherId, name: Self.otherName, label: Self.otherName,
                client: "\(rest.count) projects", hours: rest.reduce(0) { $0 + $1.hours }
            )
            projects = Array(ordered.prefix(slots)) + [other]
            folded = Set(rest.map(\.id))
        } else {
            projects = ordered
            folded = []
        }
    }

    /// `points` ready to draw: each folded project's hours re-keyed onto
    /// "Other", and the whole list in slot order. Swift Charts stacks
    /// series in the order their points arrive, so this puts slot 1 at
    /// the baseline and makes every pair of touching bands a pair of
    /// neighbouring slots — the pairs the palettes are validated on.
    /// Alphabetical data order would stack, say, slot 6 against slot 8.
    func points(_ points: [TimeComparisonViewModel.ChartPoint]) -> [TimeComparisonViewModel.ChartPoint] {
        let rank = Dictionary(uniqueKeysWithValues: projects.enumerated().map { ($1.id, $0) })
        let drawn = points.map { p in
            folded.contains(p.projectId)
                ? TimeComparisonViewModel.ChartPoint(
                    id: p.id, projectId: Self.otherId, projectName: Self.otherName,
                    date: p.date, dayLabel: p.dayLabel, hours: p.hours
                )
                : p
        }
        // Stable, so each series keeps its days in their order.
        return drawn.enumerated()
            .sorted { a, b in
                let ra = rank[a.element.projectId] ?? .max, rb = rank[b.element.projectId] ?? .max
                return ra != rb ? ra < rb : a.offset < b.offset
            }
            .map(\.element)
    }
}

// MARK: - Band separators

extension ChartSeriesPlan {
    /// Where one stacked band's top edge is on one day.
    struct Edge: Identifiable {
        let id: String
        let projectName: String
        let dayLabel: String
        /// Hours from the baseline to this band's top: its own hours plus
        /// every band stacked beneath it.
        let top: Double
    }

    /// The top edge of every band, per day, for the thin separator drawn
    /// along it. Swift Charts stacks areas but not lines, so the running
    /// total is worked out here — in the order `points` arrives, which
    /// is the stack's order (see `points(_:)`). A band with no hours on
    /// a day has its edge on the band beneath, so the line still only
    /// ever falls between colours.
    static func edges(_ points: [TimeComparisonViewModel.ChartPoint]) -> [Edge] {
        var running: [String: Double] = [:]
        return points.map { p in
            running[p.date, default: 0] += p.hours
            return Edge(id: "edge-\(p.id)", projectName: p.projectName, dayLabel: p.dayLabel, top: running[p.date]!)
        }
    }

    /// The separator: a hairline in the panel's own background colour —
    /// a light line on light, a dark one on dark — so two neighbouring
    /// bands of similar depth still read as two.
    static let separatorWidth: CGFloat = 1
}
